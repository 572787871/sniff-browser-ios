@preconcurrency import AVFoundation
import CommonCrypto
import Foundation

enum HLSDownloadEligibility {
    static func validate(
        isPlayable: Bool,
        durationSeconds: Double,
        isDurationIndefinite: Bool
    ) throws {
        guard isPlayable else { throw DownloadCenterError.invalidURL }
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

/// Uses AVFoundation's system HLS download pipeline. The completed item is a
/// system-owned offline video package that AVPlayer opens directly; it is not
/// exposed as an MPEG-2 transport stream and it does not depend on a fragile
/// post-download TS-to-MP4 export.
final class HLSAssetDownloadService: NSObject {
    static let sessionIdentifier = "com.example.SniffBrowser.background.hls"

    weak var delegate: HLSAssetDownloadServiceDelegate?

    private let storage: DownloadFileStorage
    private let playlistParser = HLSPlaylistParser()
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
        try await validatePlaylist(context: context)
        try await validate(asset: makeAsset(context: context))
    }

    func start(
        taskID: UUID,
        context: DownloadRequestContext,
        title: String
    ) async throws {
        try Task.checkCancellation()
        try await validatePlaylist(context: context)
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
        let duration = try await asset.load(.duration)
        try HLSDownloadEligibility.validate(
            isPlayable: isPlayable,
            durationSeconds: duration.seconds,
            isDurationIndefinite: duration.isIndefinite
        )
    }

    /// Some servers use ordinary RFC 8216 identity-key AES-128. AVFoundation
    /// may report such a stream as protected even though it can legally save
    /// and play it. Inspect the public playlist tags instead: accept identity
    /// AES-128 and reject only unsupported encryption such as SAMPLE-AES or
    /// FairPlay key formats.
    private func validatePlaylist(
        context: DownloadRequestContext,
        maximumDepth: Int = 3
    ) async throws {
        var url = context.targetURL
        for _ in 0..<maximumDepth {
            try Task.checkCancellation()
            let text = try await fetchPlaylist(at: url, context: context)
            switch try playlistParser.parse(text, sourceURL: url) {
            case let .media(playlist):
                guard playlist.isEndList else {
                    throw DownloadCenterError.liveHLSUnsupported
                }
                guard !playlist.hasUnsupportedEncryption else {
                    throw DownloadCenterError.protectedMediaUnsupported
                }
                return
            case let .master(variants):
                guard let preferred = variants.max(by: { lhs, rhs in
                    let leftBandwidth = lhs.bandwidth ?? 0
                    let rightBandwidth = rhs.bandwidth ?? 0
                    if leftBandwidth != rightBandwidth {
                        return leftBandwidth < rightBandwidth
                    }
                    return (lhs.height ?? 0) < (rhs.height ?? 0)
                }) else {
                    throw DownloadCenterError.invalidHLSPlaylist
                }
                url = preferred.url
            }
        }
        throw DownloadCenterError.invalidHLSPlaylist
    }

    private func fetchPlaylist(
        at url: URL,
        context: DownloadRequestContext
    ) async throws -> String {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.allowsCellularAccess = DownloadPreferences().allowsCellularDownloads
        request.httpShouldHandleCookies = false
        context.headers.forEach {
            if $0.key.caseInsensitiveCompare("Cookie") != .orderedSame
                || url.host?.caseInsensitiveCompare(context.targetURL.host ?? "") == .orderedSame {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
        }
        request.setValue(
            "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 5_000_000,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("#EXTM3U")
        else {
            throw DownloadCenterError.invalidHLSPlaylist
        }
        return text
    }

    private func taskID(for task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }

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
