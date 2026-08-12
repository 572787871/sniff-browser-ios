import ImageIO
import UIKit
import WebKit

struct ResourceThumbnailRequest {
    let resourceID: UUID
    let tabID: UUID
    let request: URLRequest
    let targetPixelSize: CGSize
    let allowsDiskCache: Bool
    let inlineData: Data?

    init(
        resourceID: UUID,
        tabID: UUID,
        request: URLRequest,
        targetPixelSize: CGSize,
        allowsDiskCache: Bool,
        inlineData: Data? = nil
    ) {
        self.resourceID = resourceID
        self.tabID = tabID
        self.request = request
        self.targetPixelSize = targetPixelSize
        self.allowsDiskCache = allowsDiskCache
        self.inlineData = inlineData
    }
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

    func clearAll() {
        clearMemory()
        ioQueue.async { [directoryURL] in
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
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
        var responseStatusCode: Int?
        var responseMIMEType: String?
        var responseURL: URL?

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
    private var svgRenderers: [String: SVGThumbnailRenderer] = [:]
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

        if let data = request.inlineData ?? Self.dataURLData(from: request.request.url) {
            return loadInline(
                data: data,
                request: request,
                key: key,
                completion: completion
            )
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

    func clearCache() { cache.clearAll() }

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
        request.setValue(
            "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
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

    private func loadInline(
        data: Data,
        request: ResourceThumbnailRequest,
        key: String,
        completion: @escaping (UIImage?) -> Void
    ) -> ResourceThumbnailToken {
        let cancelled = LockedFlag()
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let mimeType = request.request.value(forHTTPHeaderField: "Content-Type")
                ?? request.request.url.flatMap(Self.dataURLMIME)
            if Self.isSVG(data: data, mimeType: mimeType) {
                self.startInlineSVGRenderer(
                    data: data,
                    targetPixelSize: request.targetPixelSize,
                    key: key,
                    request: request,
                    cancelled: cancelled,
                    completion: completion
                )
                return
            }
            let image = self.decodeImage(
                data,
                mimeType: mimeType,
                targetPixelSize: request.targetPixelSize
            )
            if let image {
                self.cache.storeInMemory(
                    image,
                    key: key,
                    byteCount: data.count,
                    privateTabID: request.allowsDiskCache ? nil : request.tabID
                )
                if request.allowsDiskCache, !Self.isSVG(data: data) {
                    self.cache.writeDisk(data, key: key)
                }
            }
            DispatchQueue.main.async {
                guard !cancelled.value else { return }
                completion(image)
            }
        }
        return ResourceThumbnailToken { cancelled.value = true }
    }

    private func startInlineSVGRenderer(
        data: Data,
        targetPixelSize: CGSize,
        key: String,
        request: ResourceThumbnailRequest,
        cancelled: LockedFlag,
        completion: @escaping (UIImage?) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !cancelled.value else { return }
            let renderer = SVGThumbnailRenderer(
                data: data,
                targetPixelSize: targetPixelSize
            ) { [weak self] image in
                guard let self else { return }
                self.svgRenderers[key] = nil
                guard !cancelled.value else { return }
                if let image {
                    self.cacheImage(
                        image,
                        rawData: data,
                        key: key,
                        request: request
                    )
                }
                completion(image)
            }
            self.svgRenderers[key] = renderer
        }
    }

    private func decodeImage(
        _ data: Data,
        mimeType: String?,
        targetPixelSize: CGSize
    ) -> UIImage? {
        guard Self.isSupportedImagePayload(
            data: data,
            mimeType: mimeType
        ) else {
            return nil
        }
        if Self.isSVG(data: data, mimeType: mimeType) {
            // SVG is rendered by SVGThumbnailRenderer on the main thread after
            // a network response has been validated. ImageIO has no SVG decoder
            // on iOS, so returning nil here lets the caller use that path.
            return nil
        }
        return downsample(data, targetPixelSize: targetPixelSize)
    }

    private func startSVGRenderer(
        data: Data,
        targetPixelSize: CGSize,
        key: String,
        request: ResourceThumbnailRequest
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let renderer = SVGThumbnailRenderer(
                data: data,
                targetPixelSize: targetPixelSize
            ) { [weak self] image in
                guard let self else { return }
                self.svgRenderers[key] = nil
                if let image {
                    self.cacheImage(
                        image,
                        rawData: data,
                        key: key,
                        request: request
                    )
                }
                self.finish(key: key, image: image)
            }
            self.svgRenderers[key] = renderer
        }
    }

    private static func dataURLData(from url: URL?) -> Data? {
        guard let url, url.scheme?.lowercased() == "data" else { return nil }
        let raw = url.absoluteString
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let header = String(raw[..<comma]).lowercased()
        let payload = String(raw[raw.index(after: comma)...])
        if header.contains(";base64") {
            return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    private static func dataURLMIME(from url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "data" else { return nil }
        let raw = url.absoluteString
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let header = String(raw[..<comma])
        return header
            .dropFirst(5)
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)
    }

    private static func isSVG(
        data: Data,
        mimeType: String? = nil
    ) -> Bool {
        let mime = mimeType.flatMap { value in
            value.split(separator: ";", maxSplits: 1)
                .first
                .map(String.init)
        }?.lowercased()
        if mime == "image/svg+xml" { return true }
        let prefixData = Data(data.prefix(512))
        guard let prefix = String(
            data: prefixData,
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return false }
        return prefix.hasPrefix("<?xml") && prefix.contains("<svg")
            || prefix.hasPrefix("<svg")
    }

    private static func isSupportedImagePayload(
        data: Data,
        mimeType: String?
    ) -> Bool {
        guard !data.isEmpty else { return false }
        let mime = mimeType.flatMap { value in
            value.split(separator: ";", maxSplits: 1)
                .first
                .map(String.init)
        }?.lowercased()
        if mime == "text/html" || mime == "application/json" {
            return false
        }
        if isSVG(data: data, mimeType: mime) { return true }
        return CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) != nil
    }

    private func cacheImage(
        _ image: UIImage,
        rawData: Data,
        key: String,
        request: ResourceThumbnailRequest
    ) {
        cache.storeInMemory(
            image,
            key: key,
            byteCount: rawData.count,
            privateTabID: request.allowsDiskCache ? nil : request.tabID
        )
        // SVG is rasterized by WebKit, so persist the rendered thumbnail rather
        // than the original XML (which ImageIO cannot decode on iOS).
        if request.allowsDiskCache,
           let pngData = image.pngData() {
            cache.writeDisk(pngData, key: key)
        }
    }

    private func cacheKey(for request: ResourceThumbnailRequest) -> String {
        // Private-tab thumbnails use a resource-scoped namespace. This keeps an
        // authenticated image discovered in an incognito tab from joining a
        // normal-tab pending request or being reused by the normal disk cache.
        let namespace = request.allowsDiskCache
            ? "normal"
            : "private:\(request.tabID.uuidString):\(request.resourceID.uuidString)"
        let size = request.targetPixelSize
        let requestContext = request.request.allHTTPHeaderFields?
            .filter { key, _ in
                ["referer", "cookie", "user-agent"].contains(key.lowercased())
            }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key.lowercased())=\($0.value)" }
            .joined(separator: "&") ?? ""
        let value = "\(namespace)|\(request.request.url?.absoluteString ?? "missing")|\(requestContext)|\(Int(size.width))x\(Int(size.height))"
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
            AppLogger(.sniffer).debug(
                "图片缩略图请求失败 status=\((response as? HTTPURLResponse)?.statusCode ?? -1) mime=\(response.mimeType ?? "unknown") url=\(response.url?.absoluteString ?? "missing")"
            )
            let key = lock.withLock {
                transfers.removeValue(forKey: dataTask.taskIdentifier)?.key
            }
            completionHandler(.cancel)
            if let key { finish(key: key, image: nil) }
            return
        }
        lock.withLock {
            transfers[dataTask.taskIdentifier]?.responseStatusCode = http.statusCode
            transfers[dataTask.taskIdentifier]?.responseMIMEType = response.mimeType
            transfers[dataTask.taskIdentifier]?.responseURL = response.url
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
            AppLogger(.sniffer).debug(
                "图片缩略图网络失败 error=\(error?.localizedDescription ?? "unknown") url=\(transfer.request.request.url?.absoluteString ?? "missing")"
            )
            finish(key: transfer.key, image: nil)
            return
        }
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = self.decodeImage(
                transfer.data,
                mimeType: transfer.responseMIMEType,
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
                self.finish(key: transfer.key, image: image)
            } else if Self.isSVG(
                data: transfer.data,
                mimeType: transfer.responseMIMEType
            ) {
                self.startSVGRenderer(
                    data: transfer.data,
                    targetPixelSize: transfer.request.targetPixelSize,
                    key: transfer.key,
                    request: transfer.request
                )
            } else {
                AppLogger(.sniffer).debug(
                    "图片缩略图解码失败 status=\(transfer.responseStatusCode.map(String.init) ?? "unknown") mime=\(transfer.responseMIMEType ?? "unknown") bytes=\(transfer.data.count) url=\((transfer.responseURL ?? transfer.request.request.url)?.absoluteString ?? "missing")"
                )
                self.finish(key: transfer.key, image: nil)
            }
        }
    }
}

private final class LockedFlag {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class SVGThumbnailRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let completion: (UIImage?) -> Void
    private var didFinish = false

    init(
        data: Data,
        targetPixelSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let size = CGSize(
            width: max(1, min(targetPixelSize.width, 1_024)),
            height: max(1, min(targetPixelSize.height, 1_024))
        )
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        let base64 = data.base64EncodedString()
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}img{display:block;width:100%;height:100%;object-fit:contain}</style>
        <img src="data:image/svg+xml;base64,\(base64)">
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didFinish else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            self?.finish(image)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(nil)
    }

    private func finish(_ image: UIImage?) {
        guard !didFinish else { return }
        didFinish = true
        webView.navigationDelegate = nil
        completion(image)
    }
}

@MainActor
enum WebViewBlobImageDataLoader {
    static func load(url: URL, in webView: WKWebView) async -> Data? {
        guard url.scheme?.lowercased() == "blob",
              let encodedURL = try? JSONSerialization.data(
                withJSONObject: url.absoluteString
              ),
              let urlLiteral = String(data: encodedURL, encoding: .utf8)
        else { return nil }
        let script = """
        (async () => {
          try {
            const response = await fetch(\(urlLiteral));
            if (!response.ok) return null;
            const buffer = await response.arrayBuffer();
            if (buffer.byteLength > 5 * 1024 * 1024) return null;
            const bytes = new Uint8Array(buffer);
            let binary = "";
            const chunk = 0x8000;
            for (let i = 0; i < bytes.length; i += chunk) {
              binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
            }
            return btoa(binary);
          } catch (_) { return null; }
        })();
        """
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, _ in
                guard let base64 = value as? String,
                      let data = Data(base64Encoded: base64)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
