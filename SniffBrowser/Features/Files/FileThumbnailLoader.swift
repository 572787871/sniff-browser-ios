import AVFoundation
import QuickLookThumbnailing
import UIKit

final class FileThumbnailToken {
    private let cancellation: () -> Void
    private var isCancelled = false

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation()
    }

    deinit { cancel() }
}

final class FileThumbnailLoader {
    static let shared = FileThumbnailLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let generator = QLThumbnailGenerator.shared

    private init() {
        cache.countLimit = 150
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func load(
        fileURL: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) -> FileThumbnailToken {
        let key = "\(fileURL.path)|\(Int(size.width))x\(Int(size.height))@\(scale)"
        if let image = cache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(image) }
            return FileThumbnailToken(cancellation: {})
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        let operation = FileThumbnailOperation()
        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard operation.isActive else { return }
            let image = representation?.uiImage
            if let image {
                self?.store(image, key: key)
                DispatchQueue.main.async { completion(image) }
                return
            }
            guard Self.isVideoFile(fileURL) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.generateVideoFrame(
                fileURL: fileURL,
                size: size,
                scale: scale,
                key: key,
                operation: operation,
                completion: completion
            )
        }
        return FileThumbnailToken { [weak generator] in
            operation.cancel()
            generator?.cancel(request)
        }
    }

    func clearMemory() {
        cache.removeAllObjects()
    }

    private func generateVideoFrame(
        fileURL: URL,
        size: CGSize,
        scale: CGFloat,
        key: String,
        operation: FileThumbnailOperation,
        completion: @escaping (UIImage?) -> Void
    ) {
        let asset = AVURLAsset(url: fileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
        imageGenerator.requestedTimeToleranceAfter = .positiveInfinity
        guard operation.install(imageGenerator) else { return }
        let requestedTime = CMTime(seconds: 0.5, preferredTimescale: 600)
        imageGenerator.generateCGImagesAsynchronously(
            forTimes: [NSValue(time: requestedTime)]
        ) { [weak self] _, cgImage, _, result, _ in
            guard operation.isActive else { return }
            guard result == .succeeded, let cgImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image = UIImage(cgImage: cgImage)
            self?.store(image, key: key)
            DispatchQueue.main.async { completion(image) }
        }
    }

    private func store(_ image: UIImage, key: String) {
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        )
    }

    private static func isVideoFile(_ url: URL) -> Bool {
        ["mp4", "m4v", "mov", "movpkg", "m3u8"].contains(
            url.pathExtension.lowercased()
        )
    }
}

private final class FileThumbnailOperation {
    private let lock = NSLock()
    private var isCancelled = false
    private var imageGenerator: AVAssetImageGenerator?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled
    }

    func install(_ generator: AVAssetImageGenerator) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else {
            generator.cancelAllCGImageGeneration()
            return false
        }
        imageGenerator = generator
        return true
    }

    func cancel() {
        let generator: AVAssetImageGenerator?
        lock.lock()
        isCancelled = true
        generator = imageGenerator
        imageGenerator = nil
        lock.unlock()
        generator?.cancelAllCGImageGeneration()
    }
}
