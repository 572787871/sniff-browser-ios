import AVFoundation
import UIKit

/// Bounds remote frame extraction independently from the number of visible or
/// recently reused cells. AVFoundation and the loopback proxy both allocate
/// sizeable media buffers; starting one probe per discovered video can push a
/// resource-heavy page over an iPhone's memory budget.
private actor RemoteMediaPreviewPermitPool {
    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            available = min(limit, available + 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// AVAssetImageGenerator can call back from multiple queues and may never
/// deliver a terminal callback for a malformed remote stream. This one-shot
/// request owns the continuation, accepts the first valid frame, and enforces
/// a hard timeout without allowing a late callback to resume twice.
private final class RemoteMediaFrameRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let generator: AVAssetImageGenerator
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var remainingAttempts: Int
    private var result: UIImage?
    private var isFinished = false

    init(generator: AVAssetImageGenerator, attemptCount: Int) {
        self.generator = generator
        remainingAttempts = max(1, attemptCount)
    }

    func attach(_ continuation: CheckedContinuation<UIImage?, Never>) {
        let completedResult: UIImage?
        lock.lock()
        if isFinished {
            completedResult = result
        } else {
            self.continuation = continuation
            lock.unlock()
            return
        }
        lock.unlock()
        continuation.resume(returning: completedResult)
    }

    func receive(_ image: UIImage?) {
        var continuationToResume: CheckedContinuation<UIImage?, Never>?
        var finalImage: UIImage?
        var shouldFinish = false
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        if let image {
            result = image
            finalImage = image
            isFinished = true
        } else {
            remainingAttempts -= 1
            if remainingAttempts <= 0 {
                isFinished = true
            }
        }
        if isFinished {
            shouldFinish = true
            continuationToResume = continuation
            continuation = nil
        }
        lock.unlock()
        guard shouldFinish else { return }
        generator.cancelAllCGImageGeneration()
        continuationToResume?.resume(returning: finalImage)
    }

    func cancel() {
        var continuationToResume: CheckedContinuation<UIImage?, Never>?
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuationToResume = continuation
        continuation = nil
        lock.unlock()
        generator.cancelAllCGImageGeneration()
        continuationToResume?.resume(returning: nil)
    }
}

@MainActor
final class RemoteMediaThumbnailLoader {
    static let shared = RemoteMediaThumbnailLoader()

    /// A media frame belongs to a resource, not to a particular table cell.
    /// Cells are routinely reused when a sheet is resized or the app returns
    /// from the background. Keeping one shared work item prevents those view
    /// lifecycle events from starting the same remote probe again.
    private final class MediaWork {
        let tabID: UUID
        let task: Task<UIImage?, Never>
        var callbacks: [UUID: (UIImage?) -> Void] = [:]

        init(tabID: UUID, task: Task<UIImage?, Never>) {
            self.tabID = tabID
            self.task = task
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private let previewPermits = RemoteMediaPreviewPermitPool(limit: 1)
    private var pendingWork: [String: MediaWork] = [:]
    private var privateMemoryKeysByTab: [UUID: Set<String>] = [:]

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
        let storageKey = cacheKey(
            resource: resource,
            targetPixelSize: targetPixelSize,
            allowsSharedCache: allowsSharedCache
        )
        if let image = cache.object(forKey: storageKey as NSString) {
            completion(image)
            return ResourceThumbnailToken(cancellation: {})
        }

        // The disk/memory cache may be shared by normal tabs, but an in-flight
        // request must not be shared across tabs: the first tab's cookies,
        // Referer and signed URL context would otherwise determine the second
        // tab's frame. Scope only the active work by tab ID.
        let workKey = Self.previewWorkIdentity(
            tabID: resource.tabID,
            cacheKey: storageKey
        )
        let callbackID = UUID()
        let work: MediaWork
        if let existing = pendingWork[workKey] {
            work = existing
        } else {
            let task = Task { [weak self] () -> UIImage? in
                guard let self else { return nil }
                await self.previewPermits.acquire()
                guard !Task.isCancelled else {
                    await self.previewPermits.release()
                    return nil
                }
                let image: UIImage?
                if allowsSharedCache,
                   let persisted = await self.persistedImage(
                    key: storageKey,
                    targetPixelSize: targetPixelSize
                ) {
                    self.store(persisted, key: storageKey)
                    image = persisted
                } else {
                    image = await self.generatePreview(
                        resource: resource,
                        context: context,
                        targetPixelSize: targetPixelSize
                    )
                }
                await self.previewPermits.release()
                return image
            }
            work = MediaWork(tabID: resource.tabID, task: task)
            pendingWork[workKey] = work
            observeCompletion(
                workKey: workKey,
                cacheKey: storageKey,
                work: work,
                allowsSharedCache: allowsSharedCache
            )
        }
        work.callbacks[callbackID] = completion

        // Cancelling a cell subscription must not cancel the shared remote
        // probe. Another visible cell, a recreated sheet, or the next run loop
        // may still need the exact same frame.
        return ResourceThumbnailToken { [weak self, weak work] in
            Task { @MainActor in
                guard self != nil, let work else { return }
                work.callbacks[callbackID] = nil
            }
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
        privateMemoryKeysByTab.removeAll()
        // A memory warning is a hard pressure signal. Completed normal-tab
        // frames remain in the bounded disk cache, while unfinished probes are
        // cancelled so the app does not get jetsam-killed after opening the
        // resource sheet on a media-heavy page.
        let workItems = Array(pendingWork.values)
        pendingWork.removeAll()
        workItems.forEach { work in
            let callbacks = Array(work.callbacks.values)
            work.callbacks.removeAll()
            work.task.cancel()
            callbacks.forEach { $0(nil) }
        }
    }

    /// Called only when a tab is actually closed. Leaving the resource sheet,
    /// reusing a cell, or receiving a memory warning must not cross this
    /// privacy/lifecycle boundary.
    func cancelRequests(for tabID: UUID) {
        let keys = pendingWork.compactMap { key, work in
            work.tabID == tabID ? key : nil
        }
        keys.forEach { key in
            guard let work = pendingWork.removeValue(forKey: key) else { return }
            work.callbacks.removeAll()
            work.task.cancel()
        }
        let privateKeys = privateMemoryKeysByTab.removeValue(forKey: tabID) ?? []
        privateKeys.forEach { cache.removeObject(forKey: $0 as NSString) }
    }

    private func observeCompletion(
        workKey: String,
        cacheKey: String,
        work: MediaWork,
        allowsSharedCache: Bool
    ) {
        Task { @MainActor [weak self, weak work] in
            guard let self, let work else { return }
            let image = await work.task.value
            if let image {
                self.persist(
                    image,
                    key: cacheKey,
                    allowsDiskCache: allowsSharedCache,
                    privateTabID: allowsSharedCache ? nil : work.tabID
                )
            }
            guard self.pendingWork[workKey] === work else { return }
            self.pendingWork.removeValue(forKey: workKey)
            let callbacks = Array(work.callbacks.values)
            work.callbacks.removeAll()
            callbacks.forEach { $0(image) }
        }
    }

    private func generatePreview(
        resource: DetectedResource,
        context: DownloadRequestContext,
        targetPixelSize: CGSize
    ) async -> UIImage? {
        let kind: RemoteMediaPlaybackKind = resource.resourceType == .hls
            ? .hls
            : .direct
        var proxyURL: URL?
        do {
            proxyURL = try await RemoteHLSPlaybackServer.shared
                .playbackURL(context: context, kind: kind)
        } catch {
            AppLogger(.sniffer).debug(
                "视频预览代理创建失败 type=\(resource.resourceType.rawValue) url=\(resource.canonicalURL.absoluteString) error=\(error.localizedDescription)"
            )
        }

        // AVFoundation is usually the fastest path for the first visible
        // frame and keeps malformed remote media outside the native FFmpeg C
        // decoder. Do not wait for `isPlayable` or a complete duration probe:
        // both can take several seconds on a signed HLS origin.
        if let proxyURL,
           let image = await generateAVAssetFrame(
            from: proxyURL,
            targetPixelSize: targetPixelSize
           ) {
            return image
        }

        // Never pass an untrusted remote playlist/segment into the native
        // FFmpeg C decoder from a scrolling list. Downloaded local files still
        // use the established FFmpeg pipeline; remote previews are isolated
        // behind AVFoundation and the bounded loopback proxy only.
        return nil
    }

    private func generateAVAssetFrame(
        from url: URL,
        targetPixelSize: CGSize
    ) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetPixelSize
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let requestedTimes = [0.1, 0.8, 2.0].map {
            NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
        }
        let request = RemoteMediaFrameRequest(
            generator: generator,
            attemptCount: requestedTimes.count
        )
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.attach(continuation)
                generator.generateCGImagesAsynchronously(
                    forTimes: requestedTimes
                ) { _, cgImage, _, result, _ in
                    request.receive(
                        result == .succeeded
                            ? cgImage.map { UIImage(cgImage: $0) }
                            : nil
                    )
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + 8
                ) {
                    request.cancel()
                }
            }
        } onCancel: {
            request.cancel()
        }
        guard let image else { return nil }
        return image.preparingThumbnail(of: targetPixelSize) ?? image
    }

    private func store(
        _ image: UIImage,
        key: String,
        privateTabID: UUID? = nil
    ) {
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: Int(
                image.size.width * image.size.height
                    * image.scale * image.scale * 4
            )
        )
        if let privateTabID {
            privateMemoryKeysByTab[privateTabID, default: []].insert(key)
        }
    }

    private func persist(
        _ image: UIImage,
        key: String,
        allowsDiskCache: Bool,
        privateTabID: UUID?
    ) {
        store(image, key: key, privateTabID: privateTabID)
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

    /// Cache identity can be shared for normal tabs, while active work must
    /// remain isolated to the tab whose request context created it.
    static func previewWorkIdentity(tabID: UUID, cacheKey: String) -> String {
        tabID.uuidString + "|" + cacheKey
    }

    private static let volatileSignatureQueryNames: Set<String> = [
        "access_token", "auth", "auth_key", "authkey", "expires",
        "expiration", "key-pair-id", "policy", "sig", "signature", "token"
    ]
}
