import UIKit
import WebKit

@MainActor
protocol TabSnapshotProviding: AnyObject {
    func captureAndStore(tab: BrowserTab) async -> UIImage?
    func loadSnapshot(for tabID: UUID) async -> UIImage?
    func removeSnapshot(for tabID: UUID)
}

@MainActor
final class TabSnapshotService: TabSnapshotProviding {
    private let directoryURL: URL

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let cachesURL = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directoryURL = cachesURL
                .appendingPathComponent("TabSnapshots", isDirectory: true)
        }
    }

    func captureAndStore(tab: BrowserTab) async -> UIImage? {
        guard let webView = tab.webView else {
            return tab.snapshot
        }

        let configuration = WKSnapshotConfiguration()
        if webView.bounds.width > 0 {
            configuration.snapshotWidth = NSNumber(
                value: Double(min(webView.bounds.width, 360))
            )
        }
        let image: UIImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return tab.snapshot }

        if !tab.isPrivate,
           let data = image.jpegData(compressionQuality: 0.78) {
            let directoryURL = directoryURL
            let fileURL = snapshotURL(for: tab.id)
            await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    AppLogger(.browser).error(
                        "标签页快照缓存写入失败：\(error.localizedDescription)"
                    )
                }
            }.value
        }
        return image
    }

    func loadSnapshot(for tabID: UUID) async -> UIImage? {
        let fileURL = snapshotURL(for: tabID)
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }.value
        return data.flatMap(UIImage.init(data:))
    }

    func removeSnapshot(for tabID: UUID) {
        try? FileManager.default.removeItem(at: snapshotURL(for: tabID))
    }

    private func snapshotURL(for tabID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(tabID.uuidString)
            .appendingPathExtension("jpg")
    }
}
