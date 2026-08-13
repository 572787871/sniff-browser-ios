import AVFoundation
import UIKit

@MainActor
final class RemoteMediaThumbnailLoader {
    static let shared = RemoteMediaThumbnailLoader()

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
        if allowsSharedCache,
           let image = cache.object(forKey: key as NSString) {
            completion(image)
            return ResourceThumbnailToken(cancellation: {})
        }

        let operation = Operation()
        operation.task = Task { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else {
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
                   let image = await self.generateHLSFrame(
                    playbackURL: playbackURL,
                    targetPixelSize: targetPixelSize,
                    resourceURL: resource.canonicalURL
                   ) {
                    guard !Task.isCancelled, !operation.isCancelled else {
                        return
                    }
                    operation.isFinished = true
                    if allowsSharedCache {
                        self.store(image, key: key)
                    }
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
                    if allowsSharedCache {
                        self.store(image, key: key)
                    }
                    completion(image)
                }
            }
        }
        return ResourceThumbnailToken {
            Task { @MainActor in operation.cancel() }
        }
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    private func generateHLSFrame(
        playbackURL: URL,
        targetPixelSize: CGSize,
        resourceURL: URL
    ) async -> UIImage? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sniff-preview-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do {
            try await FFmpegProcessorProvider.current.generateThumbnail(
                from: playbackURL,
                output: outputURL
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
            resource.canonicalURL.absoluteString,
            "\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))"
        ].joined(separator: "|")
    }
}
