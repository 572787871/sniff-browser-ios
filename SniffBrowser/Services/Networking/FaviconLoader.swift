import CryptoKit
import UIKit

/// Loads web page favicons once and serves them from a local memory + disk
/// cache afterwards, so favorites lists do not re-download the same icon
/// every time they appear.
final class FaviconLoader {
    static let shared = FaviconLoader()

    static let maximumNetworkBytes = 2 * 1_024 * 1_024

    private static let defaultMemoryLimit = 8 * 1_024 * 1_024
    private static let defaultDiskLimit: Int64 = 20 * 1_024 * 1_024

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let ioQueue = DispatchQueue(
        label: "com.example.SniffBrowser.favicon-cache",
        qos: .utility
    )
    private let lock = NSLock()
    private var pending: [String: [UUID: (UIImage?) -> Void]] = [:]
    private let directoryURL: URL
    private let diskLimit: Int64
    private let maximumNetworkBytes: Int

    init(
        directoryURL: URL? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
        memoryLimit: Int = FaviconLoader.defaultMemoryLimit,
        diskLimit: Int64 = FaviconLoader.defaultDiskLimit,
        maximumNetworkBytes: Int = FaviconLoader.maximumNetworkBytes
    ) {
        memoryCache.totalCostLimit = memoryLimit
        self.session = URLSession(configuration: sessionConfiguration)
        self.diskLimit = diskLimit
        self.maximumNetworkBytes = maximumNetworkBytes
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        self.directoryURL = directoryURL ?? caches.appendingPathComponent(
            "Favicons",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    /// Loads the favicon at `url`, resolving from memory, then disk, then the
    /// network. Returns a request ID that can be passed to `cancel` when the
    /// caller is reused or deallocated. The completion is always called on the
    /// main queue and may deliver `nil` when no icon could be produced.
    @discardableResult
    func load(url: URL, completion: @escaping (UIImage?) -> Void) -> UUID {
        let key = Self.cacheKey(for: url)

        if let image = memoryCache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(image) }
            return UUID()
        }

        let requestID = UUID()
        lock.lock()
        if var callbacks = pending[key] {
            callbacks[requestID] = completion
            pending[key] = callbacks
            lock.unlock()
            return requestID
        }
        pending[key] = [requestID: completion]
        lock.unlock()

        ioQueue.async { [weak self] in
            guard let self else { return }
            let fileURL = self.fileURL(forKey: key)
            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data),
               image.size.width > 0,
               image.size.height > 0 {
                self.memoryCache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: data.count
                )
                self.finish(key: key, image: image)
                return
            }
            self.startNetwork(url: url, key: key)
        }
        return requestID
    }

    /// Removes the callback for `requestID` so a stale cell reuse or a
    /// deallocated view cannot overwrite newer content.
    func cancel(url: URL, requestID: UUID) {
        let key = Self.cacheKey(for: url)
        lock.lock()
        guard var callbacks = pending[key] else {
            lock.unlock()
            return
        }
        callbacks.removeValue(forKey: requestID)
        if callbacks.isEmpty {
            pending[key] = nil
        } else {
            pending[key] = callbacks
        }
        lock.unlock()
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        ioQueue.async { [directoryURL] in
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
    }

    /// Stable cache key for a favicon URL. Derived from the URL itself so the
    /// same icon is shared by every list that references it.
    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves the best favicon URL for a site, preferring Google's favicon
    /// service and falling back to the conventional `/favicon.ico` location.
    static func faviconURL(for siteURL: URL) -> URL? {
        guard let host = siteURL.host, !host.isEmpty else { return nil }
        if let encoded = host.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ),
           let googleFavicon = URL(
            string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=64"
           ) {
            return googleFavicon
        }
        var components = URLComponents()
        components.scheme = siteURL.scheme ?? "https"
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }

    private func startNetwork(url: URL, key: String) {
        lock.lock()
        guard pending[key] != nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard error == nil,
                  let data,
                  data.count <= self.maximumNetworkBytes,
                  let image = UIImage(data: data),
                  image.size.width > 0,
                  image.size.height > 0
            else {
                self.finish(key: key, image: nil)
                return
            }
            self.memoryCache.setObject(
                image,
                forKey: key as NSString,
                cost: data.count
            )
            self.ioQueue.async { [weak self] in
                guard let self else { return }
                try? data.write(to: self.fileURL(forKey: key), options: .atomic)
                Self.trim(directoryURL: self.directoryURL, limit: self.diskLimit)
            }
            self.finish(key: key, image: image)
        }
        task.resume()
    }

    private func finish(key: String, image: UIImage?) {
        let callbacks = lock.withLock { () -> [(UIImage?) -> Void] in
            guard let values = pending.removeValue(forKey: key)?.values else {
                return []
            }
            return Array(values)
        }
        DispatchQueue.main.async {
            callbacks.forEach { $0(image) }
        }
    }

    private func fileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(key)
    }

    private static func trim(directoryURL: URL, limit: Int64) {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries: [(URL, Int64, Date)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { return nil }
            return (
                url,
                Int64(values.fileSize ?? 0),
                values.contentModificationDate ?? .distantPast
            )
        }
        var size = entries.reduce(Int64(0)) { $0 + $1.1 }
        guard size > limit else { return }
        entries.sort { $0.2 < $1.2 }
        for entry in entries where size > limit {
            try? FileManager.default.removeItem(at: entry.0)
            size -= entry.1
        }
    }
}
