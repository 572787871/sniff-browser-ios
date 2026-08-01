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
        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.uiImage
            if let image {
                self?.cache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: Int(image.size.width * image.size.height * 4)
                )
            }
            DispatchQueue.main.async { completion(image) }
        }
        return FileThumbnailToken { [weak generator] in
            generator?.cancel(request)
        }
    }

    func clearMemory() {
        cache.removeAllObjects()
    }
}
