import AVFoundation
import UIKit

@MainActor
final class RemoteMediaThumbnailLoader {
    static let shared = RemoteMediaThumbnailLoader()

    private struct HLSFrameWork {
        let id: UUID
        let task: Task<UIImage?, Never>
    }

    private final class Operation {
        var task: Task<Void, Never>?
        var imageGenerator: AVAssetImageGenerator?
        var isCancelled = false
        var isFinished = false
        var remainingFrameRequests = 0

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            task?.cancel()
            task = nil
            imageGenerator?.cancelAllCGImageGeneration()
            imageGenerator = nil
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private var pendingHLSFrames: [String: HLSFrameWork] = [:]

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func load(
        resource: DetectedResource,
        context: DownloadRequestContext,
        targetPixelSize: CGSize,
        allowsSharedCache: Bool,
        completion: @escaping (UIImage?) -> Void
    ) -> ResourceThumbnailToken {
        let key = cacheKey(
            resource: resource,
            targetPixelSize: targetPixelSize,
            allowsSharedCache: allowsSharedCache
        )
        if let image = cache.object(forKey: key as NSString) {
            completion(image)
            return ResourceThumbnailToken(cancellation: {})
        }

        let operation = Operation()
        operation.task = Task { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else {
                return
            }
            if allowsSharedCache,
               let image = await self.persistedImage(
                key: key,
                targetPixelSize: targetPixelSize
               ) {
                guard !Task.isCancelled, !operation.isCancelled else {
                    return
                }
                self.store(image, key: key)
                operation.isFinished = true
                completion(image)
                return
            }
            // HLS 先直接交给正式 FFmpeg 引擎。此前先走回环代理，代理
            // 请求尚未准备好时所有卡片都会落到同一个占位图。直接取帧仍
            // 携带网页 UA/Referer，但明确不跨 CDN 传播 Cookie/Authorization。
            if resource.resourceType == .hls,
               let image = await self.coalescedHLSFrame(
                workKey: key,
                cacheKey: key,
                allowsDiskCache: allowsSharedCache,
                sourceURL: resource.canonicalURL,
                requestHeaders: Self.safeRemoteFrameHeaders(
                    context: context,
                    url: resource.canonicalURL
                ),
                targetPixelSize: targetPixelSize,
                resourceURL: resource.canonicalURL
               ) {
                guard !Task.isCancelled, !operation.isCancelled else {
                    return
                }
                operation.isFinished = true
                completion(image)
                return
            }
            let asset: AVURLAsset
            do {
                let kind: RemoteMediaPlaybackKind = resource.resourceType == .hls
                    ? .hls
                    : .direct
                let playbackURL = try await RemoteHLSPlaybackServer.shared
                    .playbackURL(context: context, kind: kind)
                guard !Task.isCancelled, !operation.isCancelled else {
                    return
                }
                if resource.resourceType == .hls,
                   let image = await self.coalescedHLSFrame(
                    workKey: "\(key)|proxy",
                    cacheKey: key,
                    allowsDiskCache: allowsSharedCache,
                    sourceURL: playbackURL,
                    requestHeaders: [:],
                    targetPixelSize: targetPixelSize,
                    resourceURL: resource.canonicalURL
                   ) {
                    guard !Task.isCancelled, !operation.isCancelled else {
                        return
                    }
                    operation.isFinished = true
                    completion(image)
                    return
                }
                asset = AVURLAsset(url: playbackURL)
            } catch {
                guard !operation.isCancelled else { return }
                AppLogger(.sniffer).debug(
                    "视频预览代理创建失败 type=\(resource.resourceType.rawValue) url=\(resource.canonicalURL.absoluteString) error=\(error.localizedDescription)"
                )
                completion(nil)
                return
            }

            do {
                guard try await asset.load(.isPlayable) else {
                    throw RemoteHLSPlaybackServerError.invalidResponse
                }
            } catch {
                guard !operation.isCancelled else { return }
                AppLogger(.sniffer).debug(
                    "视频预览资源不可播放 type=\(resource.resourceType.rawValue) url=\(resource.canonicalURL.absoluteString) error=\(error.localizedDescription)"
                )
                completion(nil)
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = targetPixelSize
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            operation.imageGenerator = generator
            let loadedDuration = try? await asset.load(.duration)
            let duration = resource.duration.flatMap {
                $0.isFinite && $0 > 0 ? $0 : nil
            } ?? loadedDuration.flatMap {
                let value = $0.seconds
                return value.isFinite && value > 0 ? value : nil
            }
            let preferredSeconds = duration.map {
                min(max($0 * 0.03, 0.35), 3)
            } ?? 0.75
            let candidateSeconds = Self.frameCandidateSeconds(
                preferred: preferredSeconds,
                duration: duration
            )
            let times = candidateSeconds.map {
                NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
            }
            operation.remainingFrameRequests = times.count
            generator.generateCGImagesAsynchronously(
                forTimes: times
            ) { [weak self, weak operation] requestedTime, cgImage, _, result, error in
                Task { @MainActor in
                    guard let self,
                          let operation,
                          !operation.isCancelled,
                          !operation.isFinished
                    else { return }
                    operation.remainingFrameRequests -= 1
                    guard result == .succeeded, let cgImage else {
                        guard operation.remainingFrameRequests == 0 else {
                            return
                        }
                        operation.isFinished = true
                        operation.imageGenerator = nil
                        AppLogger(.sniffer).debug(
                            "视频预览取帧失败 type=\(resource.resourceType.rawValue) candidates=\(candidateSeconds) lastTime=\(requestedTime.seconds) url=\(resource.canonicalURL.absoluteString) error=\(error?.localizedDescription ?? "unknown")"
                        )
                        completion(nil)
                        return
                    }
                    operation.isFinished = true
                    operation.imageGenerator = nil
                    generator.cancelAllCGImageGeneration()
                    let image = UIImage(cgImage: cgImage)
                    self.persist(
                        image,
                        key: key,
                        allowsDiskCache: allowsSharedCache
                    )
                    completion(image)
                }
            }
        }
        return ResourceThumbnailToken {
            Task { @MainActor in operation.cancel() }
        }
    }

    /// Returns an already generated frame without resolving WebKit cookies or
    /// opening the media URL again. Normal-tab frames survive sheet recreation,
    /// memory warnings and app background/foreground cycles through the shared
    /// thumbnail disk cache. Private-tab frames remain memory-only.
    func cachedImage(
        resource: DetectedResource,
        targetPixelSize: CGSize,
        allowsSharedCache: Bool
    ) async -> UIImage? {
        let key = cacheKey(
            resource: resource,
            targetPixelSize: targetPixelSize,
            allowsSharedCache: allowsSharedCache
        )
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        guard allowsSharedCache,
              let image = await persistedImage(
                key: key,
                targetPixelSize: targetPixelSize
              )
        else { return nil }
        store(image, key: key)
        return image
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
        pendingHLSFrames.values.forEach { $0.task.cancel() }
        pendingHLSFrames.removeAll()
    }

    /// Signed HLS URLs for the same playlist are often discovered once from
    /// the player config and again from pre/post-roll requests. They must keep
    /// their original URL for playback/download, but thumbnail extraction can
    /// safely share one short-lived task for the same playlist path.
    private func coalescedHLSFrame(
        workKey: String,
        cacheKey: String,
        allowsDiskCache: Bool,
        sourceURL: URL,
        requestHeaders: [String: String],
        targetPixelSize: CGSize,
        resourceURL: URL
    ) async -> UIImage? {
        if let pending = pendingHLSFrames[workKey] {
            return await pending.task.value
        }
        let workID = UUID()
        let task: Task<UIImage?, Never> = Task { [weak self] in
            guard let self else { return nil }
            let image = await self.generateHLSFrame(
                sourceURL: sourceURL,
                requestHeaders: requestHeaders,
                targetPixelSize: targetPixelSize,
                resourceURL: resourceURL
            )
            if let image {
                // Persist inside the shared work item. A table cell can be
                // reused while FFmpeg is still extracting the frame; the
                // completed cover must not be discarded with that cell.
                self.persist(
                    image,
                    key: cacheKey,
                    allowsDiskCache: allowsDiskCache
                )
            }
            return image
        }
        pendingHLSFrames[workKey] = HLSFrameWork(id: workID, task: task)
        let image = await task.value
        if pendingHLSFrames[workKey]?.id == workID {
            pendingHLSFrames.removeValue(forKey: workKey)
        }
        return image
    }

    private func generateHLSFrame(
        sourceURL: URL,
        requestHeaders: [String: String],
        targetPixelSize: CGSize,
        resourceURL: URL
    ) async -> UIImage? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sniff-preview-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do {
            try await FFmpegProcessorProvider.current.generateThumbnail(
                from: sourceURL,
                output: outputURL,
                requestHeaders: requestHeaders
            )
            try Task.checkCancellation()
            guard let image = UIImage(contentsOfFile: outputURL.path) else {
                return nil
            }
            return image.preparingThumbnail(of: targetPixelSize) ?? image
        } catch {
            guard !Task.isCancelled else { return nil }
            AppLogger(.sniffer).debug(
                "HLS 视频预览 FFmpeg 取帧失败 url=\(resourceURL.absoluteString) error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    private static func safeRemoteFrameHeaders(
        context: DownloadRequestContext,
        url: URL
    ) -> [String: String] {
        let requestHeaders = context.makeRequest(for: url).allHTTPHeaderFields ?? [:]
        let allowedNames = Set([
            "accept",
            "accept-language",
            "origin",
            "referer",
            "user-agent"
        ])
        return requestHeaders.reduce(into: [:]) { result, pair in
            guard allowedNames.contains(pair.key.lowercased()) else { return }
            result[pair.key] = pair.value
        }
    }

    private func store(_ image: UIImage, key: String) {
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: Int(
                image.size.width * image.size.height
                    * image.scale * image.scale * 4
            )
        )
    }

    private func persist(
        _ image: UIImage,
        key: String,
        allowsDiskCache: Bool
    ) {
        store(image, key: key)
        guard allowsDiskCache,
              let data = image.jpegData(compressionQuality: 0.82)
        else { return }
        ResourceThumbnailCache.shared.writeDisk(
            data,
            key: Self.persistedCacheKey(for: key)
        )
    }

    private func persistedImage(
        key: String,
        targetPixelSize: CGSize
    ) async -> UIImage? {
        let data: Data? = await withCheckedContinuation { continuation in
            ResourceThumbnailCache.shared.readDisk(
                key: Self.persistedCacheKey(for: key)
            ) { data in
                continuation.resume(returning: data)
            }
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        return image.preparingThumbnail(of: targetPixelSize) ?? image
    }

    private static func persistedCacheKey(for value: String) -> String {
        // ResourceThumbnailCache stores keys as file names. A stable FNV-1a
        // digest avoids URL path separators and remains valid across launches.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "media-\(String(hash, radix: 16)).jpg"
    }

    /// HLS manifests can expose their track metadata later than direct files.
    /// Let AVAssetImageGenerator probe a few early key-frame positions instead
    /// of rejecting the stream before frame extraction has started.
    private static func frameCandidateSeconds(
        preferred: TimeInterval,
        duration: TimeInterval?
    ) -> [TimeInterval] {
        let upperBound = duration.map { max(0.05, $0 - 0.05) }
        let raw = [preferred, 0.1, 1.5]
        var result: [TimeInterval] = []
        for value in raw {
            let bounded = min(max(value, 0.05), upperBound ?? value)
            guard !result.contains(where: { abs($0 - bounded) < 0.01 }) else {
                continue
            }
            result.append(bounded)
        }
        return result
    }

    private func cacheKey(
        resource: DetectedResource,
        targetPixelSize: CGSize,
        allowsSharedCache: Bool
    ) -> String {
        let namespace = allowsSharedCache
            ? "normal"
            : "private:\(resource.tabID.uuidString)"
        return [
            namespace,
            Self.previewIdentity(for: resource.canonicalURL),
            "\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))"
        ].joined(separator: "|")
    }

    static func previewIdentity(for url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.fragment = nil
        components.host = components.host?.lowercased()
        if let queryItems = components.queryItems {
            let retained = queryItems.filter { item in
                let name = item.name.lowercased()
                return !Self.volatileSignatureQueryNames.contains(name)
                    && !name.hasPrefix("x-amz-")
                    && !name.hasPrefix("x-oss-")
            }
            components.queryItems = retained.isEmpty ? nil : retained
        }
        return components.string ?? url.absoluteString
    }

    private static let volatileSignatureQueryNames: Set<String> = [
        "access_token", "auth", "auth_key", "authkey", "expires",
        "expiration", "key-pair-id", "policy", "sig", "signature", "token"
    ]
}
