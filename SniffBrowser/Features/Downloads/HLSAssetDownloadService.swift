@preconcurrency import AVFoundation
import CommonCrypto
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
    func hlsDownload(taskID: UUID, progress: Double, receivedBytes: Int64)
    func hlsDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile)
    func hlsDownloadDidFail(taskID: UUID, error: Error)
    func hlsDownloadDidPause(taskID: UUID)
    func hlsDownloadDidCancel(taskID: UUID)
}

/// Uses AVFoundation's system HLS download pipeline so the completed asset is
/// directly consumable by AVPlayer. The system-owned asset package must remain
/// at the URL supplied by AVAssetDownloadURLSession; it is not renamed to `.ts`
/// or exposed as a concatenated transport stream.
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
        try await validate(asset: makeAsset(context: context))
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
        try HLSDownloadEligibility.validate(
            isPlayable: isPlayable,
            isProtected: isProtected,
            durationSeconds: duration.seconds,
            isDurationIndefinite: duration.isIndefinite
        )
    }

    private func taskID(for task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }

    // Retained as a tested utility for a future standards-compliant custom
    // segment pipeline. The active download path above deliberately delegates
    // HLS packaging and playback compatibility to AVFoundation.
    static func decryptAES128CBC(
        data: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        guard !data.isEmpty,
              key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128
        else { throw DownloadCenterError.hlsDecryptionFailed }

        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            capacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw DownloadCenterError.hlsDecryptionFailed
        }
        output.removeSubrange(outputLength..<output.count)
        return output
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
            self?.delegate?.hlsDownload(
                taskID: id,
                progress: progress,
                receivedBytes: 0
            )
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
