import AVFoundation
import UIKit

@MainActor
final class RemoteMediaThumbnailLoader {
    static let shared = RemoteMediaThumbnailLoader()

    private final class Operation {
        var task: Task<Void, Never>?
        var imageGenerator: AVAssetImageGenerator?
        var isCancelled = false

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
                let videoTracks = try await asset.loadTracks(
                    withMediaType: .video
                )
                guard !videoTracks.isEmpty else {
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
            let seconds = duration.map {
                min(max($0 * 0.03, 0.35), 3)
            } ?? 0.75
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            generator.generateCGImagesAsynchronously(
                forTimes: [NSValue(time: time)]
            ) { [weak self, weak operation] _, cgImage, _, result, error in
                Task { @MainActor in
                    guard let self,
                          let operation,
                          !operation.isCancelled
                    else { return }
                    operation.imageGenerator = nil
                    guard result == .succeeded, let cgImage else {
                        AppLogger(.sniffer).debug(
                            "视频预览取帧失败 type=\(resource.resourceType.rawValue) time=\(seconds) url=\(resource.canonicalURL.absoluteString) error=\(error?.localizedDescription ?? "unknown")"
                        )
                        completion(nil)
                        return
                    }
                    let image = UIImage(cgImage: cgImage)
                    if allowsSharedCache {
                        self.cache.setObject(
                            image,
                            forKey: key as NSString,
                            cost: Int(
                                image.size.width * image.size.height
                                    * image.scale * image.scale * 4
                            )
                        )
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
