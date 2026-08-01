import ImageIO
import UIKit

struct ResourceThumbnailRequest {
    let resourceID: UUID
    let tabID: UUID
    let request: URLRequest
    let targetPixelSize: CGSize
    let allowsDiskCache: Bool
}

protocol ResourceThumbnailLoading: AnyObject {
    @discardableResult
    func load(
        _ request: ResourceThumbnailRequest,
        completion: @escaping (UIImage?) -> Void
    ) -> ResourceThumbnailToken
    func clearMemoryCache()
    func cancelRequests(for tabID: UUID)
}

final class ResourceThumbnailToken {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        lock.lock()
        let action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }

    deinit { cancel() }
}

final class ResourceThumbnailCache {
    static let shared = ResourceThumbnailCache()

    private let memory = NSCache<NSString, UIImage>()
    private let privateKeyLock = NSLock()
    private var privateKeysByTab: [UUID: Set<String>] = [:]
    private let ioQueue = DispatchQueue(
        label: "com.example.SniffBrowser.thumbnail-cache",
        qos: .utility
    )
    private let directoryURL: URL
    private let diskLimit: Int64

    init(
        directoryURL: URL? = nil,
        memoryLimit: Int = 32 * 1_024 * 1_024,
        diskLimit: Int64 = 50 * 1_024 * 1_024
    ) {
        memory.totalCostLimit = memoryLimit
        self.diskLimit = diskLimit
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directoryURL = directoryURL ?? caches.appendingPathComponent(
            "ResourceThumbnails",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    func image(forKey key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    func storeInMemory(
        _ image: UIImage,
        key: String,
        byteCount: Int,
        privateTabID: UUID? = nil
    ) {
        memory.setObject(image, forKey: key as NSString, cost: byteCount)
        if let privateTabID {
            privateKeyLock.withLock {
                privateKeysByTab[privateTabID, default: []].insert(key)
            }
        }
    }

    func readDisk(key: String, completion: @escaping (Data?) -> Void) {
        ioQueue.async { [directoryURL] in
            completion(try? Data(contentsOf: directoryURL.appendingPathComponent(key)))
        }
    }

    func writeDisk(_ data: Data, key: String) {
        ioQueue.async { [directoryURL, diskLimit] in
            let destination = directoryURL.appendingPathComponent(key)
            try? data.write(to: destination, options: .atomic)
            Self.trim(directoryURL: directoryURL, limit: diskLimit)
        }
    }

    func clearMemory() {
        memory.removeAllObjects()
        privateKeyLock.withLock { privateKeysByTab.removeAll() }
    }

    func removePrivateMemory(for tabID: UUID) {
        let keys = privateKeyLock.withLock {
            privateKeysByTab.removeValue(forKey: tabID) ?? []
        }
        keys.forEach { memory.removeObject(forKey: $0 as NSString) }
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
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
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

final class ResourceThumbnailLoader: NSObject, ResourceThumbnailLoading {
    static let shared = ResourceThumbnailLoader()
    static let maximumNetworkBytes = 5 * 1_024 * 1_024

    private struct CompletionEntry {
        let id: UUID
        let callback: (UIImage?) -> Void
    }

    private final class PendingRequest {
        let tabID: UUID
        var callbacks: [CompletionEntry]
        var task: URLSessionDataTask?

        init(tabID: UUID, callbacks: [CompletionEntry]) {
            self.tabID = tabID
            self.callbacks = callbacks
        }
    }

    private final class NetworkTransfer {
        let key: String
        let request: ResourceThumbnailRequest
        var data = Data()

        init(key: String, request: ResourceThumbnailRequest) {
            self.key = key
            self.request = request
        }
    }

    private let cache: ResourceThumbnailCache
    private let maximumNetworkBytes: Int
    private let sessionConfiguration: URLSessionConfiguration
    private let lock = NSLock()
    private var pending: [String: PendingRequest] = [:]
    private var transfers: [Int: NetworkTransfer] = [:]
    private let decodeQueue = DispatchQueue(
        label: "com.example.SniffBrowser.thumbnail-decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private lazy var session: URLSession = {
        let configuration = sessionConfiguration
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 4
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.example.SniffBrowser.thumbnail-network"
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
    }()

    init(
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        cache: ResourceThumbnailCache = .shared,
        maximumNetworkBytes: Int = ResourceThumbnailLoader.maximumNetworkBytes
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.cache = cache
        self.maximumNetworkBytes = maximumNetworkBytes
        super.init()
    }

    @discardableResult
    func load(
        _ request: ResourceThumbnailRequest,
        completion: @escaping (UIImage?) -> Void
    ) -> ResourceThumbnailToken {
        let key = cacheKey(for: request)
        if let image = cache.image(forKey: key) {
            DispatchQueue.main.async { completion(image) }
            return ResourceThumbnailToken(cancellation: {})
        }

        let callbackID = UUID()
        let token = ResourceThumbnailToken { [weak self] in
            self?.cancel(key: key, callbackID: callbackID)
        }
        let entry = CompletionEntry(id: callbackID, callback: completion)

        lock.lock()
        if let existing = pending[key] {
            existing.callbacks.append(entry)
            lock.unlock()
            return token
        }
        pending[key] = PendingRequest(tabID: request.tabID, callbacks: [entry])
        lock.unlock()

        if request.allowsDiskCache {
            cache.readDisk(key: key) { [weak self] data in
                guard let self else { return }
                if let data,
                   let image = self.downsample(data, targetPixelSize: request.targetPixelSize) {
                    self.cache.storeInMemory(
                        image,
                        key: key,
                        byteCount: data.count,
                        privateTabID: request.allowsDiskCache ? nil : request.tabID
                    )
                    self.finish(key: key, image: image)
                } else {
                    self.startNetwork(request, key: key)
                }
            }
        } else {
            startNetwork(request, key: key)
        }
        return token
    }

    func clearMemoryCache() { cache.clearMemory() }

    func cancelRequests(for tabID: UUID) {
        let tasks: [URLSessionDataTask] = lock.withLock {
            let keys = pending.compactMap { key, value in
                value.tabID == tabID ? key : nil
            }
            return keys.compactMap { key in
                pending.removeValue(forKey: key)?.task
            }
        }
        tasks.forEach { $0.cancel() }
        cache.removePrivateMemory(for: tabID)
    }

    private func startNetwork(_ thumbnailRequest: ResourceThumbnailRequest, key: String) {
        lock.lock()
        guard let pendingRequest = pending[key], pendingRequest.task == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        var request = thumbnailRequest.request
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        lock.lock()
        if let pendingRequest = pending[key] {
            pendingRequest.task = task
            transfers[task.taskIdentifier] = NetworkTransfer(
                key: key,
                request: thumbnailRequest
            )
            lock.unlock()
            task.resume()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    private func finish(key: String, image: UIImage?) {
        lock.lock()
        let callbacks = pending.removeValue(forKey: key)?.callbacks ?? []
        lock.unlock()
        DispatchQueue.main.async {
            callbacks.forEach { $0.callback(image) }
        }
    }

    private func cancel(key: String, callbackID: UUID) {
        lock.lock()
        guard let item = pending[key] else {
            lock.unlock()
            return
        }
        item.callbacks.removeAll { $0.id == callbackID }
        if item.callbacks.isEmpty {
            item.task?.cancel()
            pending[key] = nil
        }
        lock.unlock()
    }

    private func downsample(_ data: Data, targetPixelSize: CGSize) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        let maxDimension = max(targetPixelSize.width, targetPixelSize.height)
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxDimension))
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    private func cacheKey(for request: ResourceThumbnailRequest) -> String {
        // Private-tab thumbnails use a resource-scoped namespace. This keeps an
        // authenticated image discovered in an incognito tab from joining a
        // normal-tab pending request or being reused by the normal disk cache.
        let namespace = request.allowsDiskCache
            ? "normal"
            : "private:\(request.tabID.uuidString):\(request.resourceID.uuidString)"
        let size = request.targetPixelSize
        let value = "\(namespace)|\(request.request.url?.absoluteString ?? "missing")|\(Int(size.width))x\(Int(size.height))"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

extension ResourceThumbnailLoader: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(maximumNetworkBytes)
        else {
            let key = lock.withLock {
                transfers.removeValue(forKey: dataTask.taskIdentifier)?.key
            }
            completionHandler(.cancel)
            if let key { finish(key: key, image: nil) }
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let rejectedKey: String? = lock.withLock {
            guard let transfer = transfers[dataTask.taskIdentifier] else {
                return nil
            }
            guard transfer.data.count <= maximumNetworkBytes - data.count else {
                transfers.removeValue(forKey: dataTask.taskIdentifier)
                return transfer.key
            }
            transfer.data.append(data)
            return nil
        }
        if let rejectedKey {
            dataTask.cancel()
            finish(key: rejectedKey, image: nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let transfer = lock.withLock({
            transfers.removeValue(forKey: task.taskIdentifier)
        }) else { return }
        guard error == nil else {
            finish(key: transfer.key, image: nil)
            return
        }
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = self.downsample(
                transfer.data,
                targetPixelSize: transfer.request.targetPixelSize
            )
            if let image {
                self.cache.storeInMemory(
                    image,
                    key: transfer.key,
                    byteCount: transfer.data.count,
                    privateTabID: transfer.request.allowsDiskCache
                        ? nil
                        : transfer.request.tabID
                )
                if transfer.request.allowsDiskCache {
                    self.cache.writeDisk(transfer.data, key: transfer.key)
                }
            }
            self.finish(key: transfer.key, image: image)
        }
    }
}
