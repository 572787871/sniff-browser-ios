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
    private var suppressedCompletionIDs: Set<UUID> = []
    private var finishedIDs: Set<UUID> = []
    private var backgroundCompletionHandler: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = DownloadPreferences().allowsCellularDownloads
        configuration.httpMaximumConnectionsPerHost = DownloadPreferences()
            .maximumConcurrentDownloads
        let queue = OperationQueue()
        queue.name = "com.example.SniffBrowser.file-download-delegate"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    init(storage: DownloadFileStorage) {
        self.storage = storage
        super.init()
    }

    func register(plan: FileDownloadPlan) {
        lock.withLock { plans[plan.taskID] = plan }
    }

    func start(taskID: UUID, request: URLRequest) {
        let task = session.downloadTask(with: request)
        task.taskDescription = taskID.uuidString
        lock.withLock { systemTasks[taskID] = task }
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
            self.lock.withLock { self.systemTasks[taskID] = nil }
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
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : nil
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
            let stored = try storage.storeDownloadedFile(
                from: location,
                preferredFileName: plan.fileName,
                resourceType: plan.resourceType
            )
            lock.withLock {
                finishedIDs.insert(id)
                systemTasks[id] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.fileDownloadDidFinish(taskID: id, storedFile: stored)
            }
        } catch {
            lock.withLock {
                finishedIDs.insert(id)
                systemTasks[id] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.fileDownloadDidFail(taskID: id, error: error)
            }
        }
    }
}

extension BackgroundFileDownloadService: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = taskID(for: task) else { return }
        let shouldSuppress = lock.withLock { () -> Bool in
            if finishedIDs.remove(id) != nil { return true }
            if suppressedCompletionIDs.remove(id) != nil { return true }
            systemTasks[id] = nil
            return false
        }
        guard !shouldSuppress, let error else { return }
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
