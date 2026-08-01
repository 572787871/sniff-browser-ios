import AVFoundation
import Foundation

enum HLSDownloadEligibility {
    static func validate(
        isPlayable: Bool,
        isProtected: Bool,
        durationSeconds: Double,
        isDurationIndefinite: Bool
    ) throws {
        guard isPlayable else { throw DownloadCenterError.invalidURL }
        guard !isProtected else {
            throw DownloadCenterError.protectedMediaUnsupported
        }
        guard !isDurationIndefinite,
              durationSeconds.isFinite,
              durationSeconds > 0
        else {
            throw DownloadCenterError.liveHLSUnsupported
        }
    }
}

struct HLSDownloadPlan: Sendable {
    let taskID: UUID
    let fileName: String
}

@MainActor
protocol HLSAssetDownloadServiceDelegate: AnyObject {
    func hlsDownloadDidStart(taskID: UUID)
    func hlsDownload(taskID: UUID, progress: Double)
    func hlsDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile)
    func hlsDownloadDidFail(taskID: UUID, error: Error)
    func hlsDownloadDidPause(taskID: UUID)
    func hlsDownloadDidCancel(taskID: UUID)
}

final class HLSAssetDownloadService: NSObject {
    static let sessionIdentifier = "com.example.SniffBrowser.background.hls"

    weak var delegate: HLSAssetDownloadServiceDelegate?

    private let storage: DownloadFileStorage
    private let lock = NSLock()
    private var plans: [UUID: HLSDownloadPlan] = [:]
    private var systemTasks: [UUID: AVAssetDownloadTask] = [:]
    private var suppressedCompletionIDs: Set<UUID> = []
    private var finishedIDs: Set<UUID> = []
    private var backgroundCompletionHandler: (() -> Void)?
    private lazy var session: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = DownloadPreferences().allowsCellularDownloads
        let queue = OperationQueue()
        queue.name = "com.example.SniffBrowser.hls-download-delegate"
        queue.maxConcurrentOperationCount = 1
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: queue
        )
    }()

    init(storage: DownloadFileStorage) {
        self.storage = storage
        super.init()
    }

    func register(plan: HLSDownloadPlan) {
        lock.withLock { plans[plan.taskID] = plan }
    }

    func validate(context: DownloadRequestContext) async throws {
        let asset = makeAsset(context: context)
        try await validate(asset: asset)
    }

    func start(
        taskID: UUID,
        context: DownloadRequestContext,
        title: String
    ) async throws {
        try Task.checkCancellation()
        let asset = makeAsset(context: context)
        try await validate(asset: asset)
        try Task.checkCancellation()
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: title,
            assetArtworkData: nil,
            options: nil
        ) else { throw DownloadCenterError.invalidURL }
        task.taskDescription = taskID.uuidString
        lock.withLock { systemTasks[taskID] = task }
        task.resume()
        await MainActor.run { [weak self] in
            self?.delegate?.hlsDownloadDidStart(taskID: taskID)
        }
    }

    private func makeAsset(context: DownloadRequestContext) -> AVURLAsset {
        AVURLAsset(
            url: context.targetURL,
            options: context.assetOptions(
                allowsCellularAccess: DownloadPreferences().allowsCellularDownloads
            )
        )
    }

    private func validate(asset: AVURLAsset) async throws {
        let isPlayable = try await asset.load(.isPlayable)
        try Task.checkCancellation()
        let isProtected = try await asset.load(.hasProtectedContent)
        try Task.checkCancellation()
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        try HLSDownloadEligibility.validate(
            isPlayable: isPlayable,
            isProtected: isProtected,
            durationSeconds: seconds,
            isDurationIndefinite: duration.isIndefinite
        )
    }

    func pause(taskID: UUID) {
        guard let task = lock.withLock({ systemTasks[taskID] }) else { return }
        task.suspend()
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownloadDidPause(taskID: taskID)
        }
    }

    func resume(taskID: UUID) throws {
        guard let task = lock.withLock({ systemTasks[taskID] }) else {
            throw DownloadCenterError.taskUnavailable
        }
        task.resume()
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownloadDidStart(taskID: taskID)
        }
    }

    func cancel(taskID: UUID) {
        let task = lock.withLock { () -> AVAssetDownloadTask? in
            suppressedCompletionIDs.insert(taskID)
            return systemTasks.removeValue(forKey: taskID)
        }
        task?.cancel()
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownloadDidCancel(taskID: taskID)
        }
    }

    func restoreSystemTasks(completion: @escaping ([UUID]) -> Void) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { completion([]); return }
            var ids: [UUID] = []
            self.lock.withLock {
                for case let task as AVAssetDownloadTask in tasks {
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
}

extension HLSAssetDownloadService: AVAssetDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = taskID(for: assetDownloadTask) else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.reduce(0.0) {
            $0 + $1.timeRangeValue.duration.seconds
        }
        let progress = expected > 0 && expected.isFinite
            ? min(max(loaded / expected, 0), 1)
            : 0
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownload(taskID: id, progress: progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = taskID(for: assetDownloadTask),
              let plan = lock.withLock({ plans[id] })
        else { return }
        do {
            let stored = try storage.storeHLSAssetPackage(
                from: location,
                preferredFileName: plan.fileName
            )
            lock.withLock {
                finishedIDs.insert(id)
                systemTasks[id] = nil
            }
            Task { @MainActor [weak self] in
                self?.delegate?.hlsDownloadDidFinish(taskID: id, storedFile: stored)
            }
        } catch {
            lock.withLock { finishedIDs.insert(id) }
            Task { @MainActor [weak self] in
                self?.delegate?.hlsDownloadDidFail(taskID: id, error: error)
            }
        }
    }

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
            self?.delegate?.hlsDownloadDidFail(taskID: id, error: error)
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
