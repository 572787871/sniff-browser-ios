import Foundation

enum DownloadResponseValidator {
    static func validate(
        response: URLResponse?,
        filePrefix: Data?
    ) throws {
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw DownloadCenterError.signedURLExpired
            }
            throw DownloadCenterError.serverRejected(response.statusCode)
        }
        let mime = response?.mimeType?.lowercased() ?? ""
        if mime == "text/html" || mime == "application/xhtml+xml" {
            throw DownloadCenterError.unexpectedHTML
        }
        if let filePrefix,
           let text = String(data: filePrefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           text.hasPrefix("<!doctype html") || text.hasPrefix("<html") {
            throw DownloadCenterError.unexpectedHTML
        }
    }
}

struct FileDownloadPlan: Sendable {
    let taskID: UUID
    let fileName: String
    let resourceType: ResourceType
}

enum FileDownloadTransportPolicy {
    static func shouldRetryInForeground(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .cancelled, .badURL, .unsupportedURL,
             .userAuthenticationRequired, .userCancelledAuthentication,
             .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return false
        default:
            return true
        }
    }
}

@MainActor
protocol BackgroundFileDownloadServiceDelegate: AnyObject {
    func fileDownloadDidStart(taskID: UUID)
    func fileDownloadDidPause(taskID: UUID, resumeDataRelativePath: String?)
    func fileDownload(
        taskID: UUID,
        didUpdate receivedBytes: Int64,
        expectedBytes: Int64?
    )
    func fileDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile)
    func fileDownloadDidFail(taskID: UUID, error: Error)
    func fileDownloadDidCancel(taskID: UUID)
}

final class BackgroundFileDownloadService: NSObject {
    static let sessionIdentifier = "com.example.SniffBrowser.background.files"

    weak var delegate: BackgroundFileDownloadServiceDelegate?

    private let storage: DownloadFileStorage
    private let lock = NSLock()
    private var plans: [UUID: FileDownloadPlan] = [:]
    private var systemTasks: [UUID: URLSessionDownloadTask] = [:]
    private var originalRequests: [UUID: URLRequest] = [:]

    private var suppressedCompletionIDs: Set<UUID> = []
    private var finishedIDs: Set<UUID> = []
    private var backgroundCompletionHandler: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 6
        let queue = OperationQueue()
        queue.name = "com.example.SniffBrowser.file-download-delegate"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()


    init(storage: DownloadFileStorage) {
        self.storage = storage
        super.init()
    }

    func ensureSession() {
        _ = session
    }

    func register(plan: FileDownloadPlan) {
        lock.withLock { plans[plan.taskID] = plan }
    }

    func start(
        taskID: UUID,
        request: URLRequest
    ) {
        let task = session.downloadTask(with: request)
        task.taskDescription = taskID.uuidString
        lock.withLock {
            originalRequests[taskID] = request
            systemTasks[taskID] = task
        }
        task.resume()
        Task { @MainActor [weak self] in
            self?.delegate?.fileDownloadDidStart(taskID: taskID)
        }
    }

    func pause(taskID: UUID) {
        guard let task = lock.withLock({ systemTasks[taskID] }) else { return }
        lock.withLock { suppressedCompletionIDs.insert(taskID) }
        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self else { return }
            let relativePath = data.flatMap {
                try? self.storage.saveResumeData($0, taskID: taskID)
            }
            self.lock.withLock {
                self.systemTasks[taskID] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.fileDownloadDidPause(
                    taskID: taskID,
                    resumeDataRelativePath: relativePath
                )
            }
        })
    }

    func resume(taskID: UUID, resumeDataRelativePath: String?) throws {
        guard let data = storage.loadResumeData(relativePath: resumeDataRelativePath)
        else { throw DownloadCenterError.resumeDataInvalid }
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = taskID.uuidString
        lock.withLock {
            suppressedCompletionIDs.remove(taskID)
            systemTasks[taskID] = task
        }
        task.resume()
        Task { @MainActor [weak self] in
            self?.delegate?.fileDownloadDidStart(taskID: taskID)
        }
    }

    func cancel(taskID: UUID) {
        let task = lock.withLock { () -> URLSessionDownloadTask? in
            suppressedCompletionIDs.insert(taskID)
            originalRequests[taskID] = nil
            return systemTasks.removeValue(forKey: taskID)
        }
        task?.cancel()
        Task { @MainActor [weak self] in
            self?.delegate?.fileDownloadDidCancel(taskID: taskID)
        }
    }

    func restoreSystemTasks(completion: @escaping ([UUID]) -> Void) {
        session.getAllTasks { [weak self] tasks in
            guard let self else {
                completion([])
                return
            }
            var ids: [UUID] = []
            self.lock.withLock {
                for case let task as URLSessionDownloadTask in tasks {
                    guard let value = task.taskDescription,
                          let id = UUID(uuidString: value)
                    else { continue }
                    self.systemTasks[id] = task
                    ids.append(id)
                }
            }
            completion(ids)
        }
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        lock.withLock { backgroundCompletionHandler = completionHandler }
    }

    private func taskID(for task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }

    private func validate(task: URLSessionDownloadTask, fileURL: URL) throws {
        var prefix: Data?
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? handle.close() }
            prefix = try? handle.read(upToCount: 256)
        }
        try DownloadResponseValidator.validate(
            response: task.response,
            filePrefix: prefix
        )
    }
}

extension BackgroundFileDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = taskID(for: downloadTask) else { return }
        var expected: Int64? = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : nil
        // Fallback: try to get content length from HTTP response headers
        if expected == nil,
           let response = downloadTask.response as? HTTPURLResponse {
            // Case-insensitive lookup for Content-Length
            for (key, value) in response.allHeaderFields {
                guard let keyStr = key as? String,
                      keyStr.lowercased() == "content-length",
                      let valueStr = value as? String,
                      let length = Int64(valueStr),
                      length > 0 else { continue }
                expected = length
                break
            }
        }
        Task { @MainActor [weak self] in
            self?.delegate?.fileDownload(
                taskID: id,
                didUpdate: totalBytesWritten,
                expectedBytes: expected
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = taskID(for: downloadTask),
              let plan = lock.withLock({ plans[id] })
        else { return }
        do {
            try validate(task: downloadTask, fileURL: location)
            // 许多图片/资源 URL 不带扩展名，但响应头带真实 MIME。
            // 文件名缺少扩展名时按 MIME 补上，保证文件可预览、可分享。
            let fileName = Self.fileNameWithFallbackExtension(
                plan.fileName,
                mimeType: downloadTask.response?.mimeType
            )
            var stored = try storage.storeDownloadedFile(
                from: location,
                preferredFileName: fileName,
                resourceType: plan.resourceType
            )
            // 部分图床对图片做 AES 加密防盗链：解密后替换为可用图片。
            if plan.resourceType == .image,
               let raw = try? Data(contentsOf: stored.fileURL),
               let decrypted = ImageProtection.decryptedImageData(
                   from: raw,
                   sourceHost: downloadTask.originalRequest?.url?.host
               ),
               (try? decrypted.write(to: stored.fileURL, options: .atomic)) != nil {
                stored = storage.storedFile(for: stored.fileURL)
            }
            lock.withLock {
                finishedIDs.insert(id)
                systemTasks[id] = nil
                originalRequests[id] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.fileDownloadDidFinish(taskID: id, storedFile: stored)
            }
        } catch {
            lock.withLock {
                finishedIDs.insert(id)
                systemTasks[id] = nil
                originalRequests[id] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.fileDownloadDidFail(taskID: id, error: error)
            }
        }
    }
}

extension BackgroundFileDownloadService {
    static func fileNameWithFallbackExtension(
        _ name: String,
        mimeType: String?
    ) -> String {
        guard (name as NSString).pathExtension.isEmpty,
              let mimeType,
              let ext = preferredExtension(forMIMEType: mimeType)
        else { return name }
        return name + "." + ext
    }

    static func preferredExtension(forMIMEType mimeType: String) -> String? {
        let mime = mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/avif": return "avif"
        case "image/heic", "image/heif": return "heic"
        case "image/svg+xml": return "svg"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "audio/mpeg": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
        case "audio/wav", "audio/x-wav": return "wav"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "application/zip": return "zip"
        default: return nil
        }
    }
}

extension BackgroundFileDownloadService: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        redirectedRequest.httpShouldHandleCookies = false
        let originalRequest = task.originalRequest
        for header in ["User-Agent", "Referer", "Accept", "Accept-Language"] {
            if redirectedRequest.value(forHTTPHeaderField: header) == nil,
               let value = originalRequest?.value(forHTTPHeaderField: header) {
                redirectedRequest.setValue(value, forHTTPHeaderField: header)
            }
        }
        // A WebKit Cookie header is safe to retain only for redirects that stay
        // on the exact host. Never forward authenticated cookies to another CDN.
        if request.url?.host?.caseInsensitiveCompare(
            originalRequest?.url?.host ?? ""
        ) == .orderedSame,
        redirectedRequest.value(forHTTPHeaderField: "Cookie") == nil,
        let cookie = originalRequest?.value(forHTTPHeaderField: "Cookie") {
            redirectedRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = taskID(for: task) else { return }
        let suppress = lock.withLock { () -> Bool in
            if finishedIDs.remove(id) != nil { return true }
            if suppressedCompletionIDs.remove(id) != nil { return true }
            systemTasks[id] = nil
            return false
        }
        guard !suppress else { return }
        guard let error else { return }
        lock.withLock {
            originalRequests[id] = nil
        }
        Task { @MainActor [weak self] in
            self?.delegate?.fileDownloadDidFail(taskID: id, error: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (() -> Void)? in
            defer { backgroundCompletionHandler = nil }
            return backgroundCompletionHandler
        }
        DispatchQueue.main.async { completion?() }
    }
}
