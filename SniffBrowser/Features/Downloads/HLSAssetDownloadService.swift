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
        else { throw DownloadCenterError.liveHLSUnsupported }
    }
}

struct HLSDownloadPlan: Sendable {
    let taskID: UUID
    let fileName: String
    let thumbnailURL: URL?

    init(taskID: UUID, fileName: String, thumbnailURL: URL? = nil) {
        self.taskID = taskID
        self.fileName = fileName
        self.thumbnailURL = thumbnailURL
    }
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

/// Downloads a finite RFC 8216 stream using the same in-memory request context
/// as the webpage, decrypts ordinary identity-key AES-128 fragments, and writes
/// a self-contained local HLS video package. Keeping the original media
/// fragments avoids the invalid "concatenate TS and rename it MP4" path and
/// lets AVPlayer decode the original codec through a loopback HTTP origin.
final class HLSAssetDownloadService: NSObject {
    // Kept for compatibility with background callbacks created by older builds.
    static let sessionIdentifier = "com.example.SniffBrowser.background.hls"

    weak var delegate: HLSAssetDownloadServiceDelegate?

    private let storage: DownloadFileStorage
    private let parser = HLSPlaylistParser()
    private let lock = NSLock()
    private let session: URLSession
    private var plans: [UUID: HLSDownloadPlan] = [:]
    private var contexts: [UUID: DownloadRequestContext] = [:]
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var intentionallyStoppedIDs: Set<UUID> = []

    init(storage: DownloadFileStorage) {
        self.storage = storage
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 5
        configuration.allowsCellularAccess = DownloadPreferences().allowsCellularDownloads
        session = URLSession(configuration: configuration)
        super.init()
    }

    func register(plan: HLSDownloadPlan) {
        lock.withLock { plans[plan.taskID] = plan }
    }

    func validate(context: DownloadRequestContext) async throws {
        _ = try await resolveMediaPlaylist(context: context)
    }

    func start(
        taskID: UUID,
        context: DownloadRequestContext,
        title: String
    ) async throws {
        try Task.checkCancellation()
        let playlist = try await resolveMediaPlaylist(context: context)
        let plan = lock.withLock { plans[taskID] }
            ?? HLSDownloadPlan(taskID: taskID, fileName: title)
        lock.withLock {
            plans[taskID] = plan
            contexts[taskID] = context
            intentionallyStoppedIDs.remove(taskID)
            workers[taskID]?.cancel()
        }
        await MainActor.run { [weak self] in
            self?.delegate?.hlsDownloadDidStart(taskID: taskID)
        }
        let worker = Task { [weak self] in
            guard let self else { return }
            do {
                let stored = try await self.downloadPackage(
                    taskID: taskID,
                    context: context,
                    playlist: playlist,
                    plan: plan
                )
                self.lock.withLock {
                    self.workers[taskID] = nil
                    self.contexts[taskID] = nil
                    self.intentionallyStoppedIDs.remove(taskID)
                }
                await MainActor.run { [weak self] in
                    self?.delegate?.hlsDownloadDidFinish(
                        taskID: taskID,
                        storedFile: stored
                    )
                }
            } catch is CancellationError {
                self.lock.withLock { self.workers[taskID] = nil }
            } catch {
                let suppress = self.lock.withLock { () -> Bool in
                    self.workers[taskID] = nil
                    return self.intentionallyStoppedIDs.contains(taskID)
                }
                guard !suppress else { return }
                await MainActor.run { [weak self] in
                    self?.delegate?.hlsDownloadDidFail(taskID: taskID, error: error)
                }
            }
        }
        lock.withLock { workers[taskID] = worker }
    }

    func pause(taskID: UUID) {
        let worker = lock.withLock { () -> Task<Void, Never>? in
            intentionallyStoppedIDs.insert(taskID)
            return workers.removeValue(forKey: taskID)
        }
        worker?.cancel()
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownloadDidPause(taskID: taskID)
        }
    }

    func resume(taskID: UUID) throws {
        let values = lock.withLock { (plans[taskID], contexts[taskID], workers[taskID]) }
        guard values.2 == nil, let plan = values.0, let context = values.1 else {
            throw DownloadCenterError.taskUnavailable
        }
        Task { [weak self] in
            do {
                try await self?.start(
                    taskID: taskID,
                    context: context,
                    title: plan.fileName
                )
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    self?.delegate?.hlsDownloadDidFail(taskID: taskID, error: error)
                }
            }
        }
    }

    func cancel(taskID: UUID) {
        let worker = lock.withLock { () -> Task<Void, Never>? in
            intentionallyStoppedIDs.insert(taskID)
            contexts[taskID] = nil
            return workers.removeValue(forKey: taskID)
        }
        worker?.cancel()
        removeWorkDirectory(taskID: taskID)
        Task { @MainActor [weak self] in
            self?.delegate?.hlsDownloadDidCancel(taskID: taskID)
        }
    }

    func restoreSystemTasks(completion: @escaping ([UUID]) -> Void) {
        // Segment checkpoints are ordinary sandbox files. DownloadCenter moves
        // interrupted records back to waiting; a fresh webpage context is still
        // required when a signed URL has expired.
        completion([])
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func resolveMediaPlaylist(
        context: DownloadRequestContext,
        maximumDepth: Int = 4
    ) async throws -> HLSMediaPlaylist {
        var url = context.targetURL
        for _ in 0..<maximumDepth {
            try Task.checkCancellation()
            let fetched = try await fetchPlaylist(url: url, context: context)
            // Relative variant, key and segment URLs are relative to the final
            // playlist URL after redirects, not necessarily to the sniffed URL.
            switch try parser.parse(fetched.text, sourceURL: fetched.finalURL) {
            case let .media(playlist):
                guard playlist.isEndList else {
                    throw DownloadCenterError.liveHLSUnsupported
                }
                guard !playlist.hasUnsupportedEncryption else {
                    throw DownloadCenterError.protectedMediaUnsupported
                }
                return playlist
            case let .master(variants):
                guard let selected = variants.max(by: { lhs, rhs in
                    let left = lhs.bandwidth ?? 0
                    let right = rhs.bandwidth ?? 0
                    return left == right
                        ? (lhs.height ?? 0) < (rhs.height ?? 0)
                        : left < right
                }) else { throw DownloadCenterError.invalidHLSPlaylist }
                url = selected.url
            }
        }
        throw DownloadCenterError.invalidHLSPlaylist
    }

    private func fetchPlaylist(
        url: URL,
        context: DownloadRequestContext
    ) async throws -> FetchedPlaylist {
        var request = request(for: url, context: context)
        request.setValue(
            "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        guard data.count <= 5_000_000,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("#EXTM3U")
        else { throw DownloadCenterError.invalidHLSPlaylist }
        return FetchedPlaylist(
            text: text,
            finalURL: response.url ?? url
        )
    }

    private func downloadPackage(
        taskID: UUID,
        context: DownloadRequestContext,
        playlist: HLSMediaPlaylist,
        plan: HLSDownloadPlan
    ) async throws -> StoredDownloadFile {
        let workDirectory = try makeWorkDirectory(taskID: taskID)
        let mediaDirectory = workDirectory.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaDirectory,
            withIntermediateDirectories: true
        )
        let orderedSegments = ([playlist.initializationSegment].compactMap { $0 })
            + playlist.segments
        guard !orderedSegments.isEmpty else {
            throw DownloadCenterError.invalidHLSPlaylist
        }
        let keys = try await fetchEncryptionKeys(
            for: orderedSegments,
            context: context
        )
        let initCount = playlist.initializationSegment == nil ? 0 : 1
        let batchSize = min(max(DownloadPreferences().maximumConcurrentDownloads, 1), 5)
        var completed = 0
        var receivedBytes: Int64 = 0
        var start = 0

        while start < orderedSegments.count {
            try Task.checkCancellation()
            let end = min(start + batchSize, orderedSegments.count)
            try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                for index in start..<end {
                    let destination = segmentFileURL(
                        index: index,
                        initCount: initCount,
                        playlist: playlist,
                        directory: mediaDirectory
                    )
                    if let size = try? destination.resourceValues(
                        forKeys: [.fileSizeKey]
                    ).fileSize, size > 0 {
                        completed += 1
                        receivedBytes += Int64(size)
                        continue
                    }
                    let segment = orderedSegments[index]
                    group.addTask { [weak self] in
                        guard let self else { throw CancellationError() }
                        let data = try await self.downloadSegment(
                            segment,
                            context: context,
                            encryptionKeys: keys,
                            ordinal: index + 1
                        )
                        try data.write(to: destination, options: .atomic)
                        return (index, data.count)
                    }
                }
                for try await (_, byteCount) in group {
                    completed += 1
                    receivedBytes += Int64(byteCount)
                    let progress = Double(completed) / Double(orderedSegments.count)
                    let bytes = receivedBytes
                    await MainActor.run { [weak self] in
                        self?.delegate?.hlsDownload(
                            taskID: taskID,
                            progress: progress,
                            receivedBytes: bytes
                        )
                    }
                }
            }
            start = end
        }

        try writeLocalPlaylist(
            playlist,
            initCount: initCount,
            to: workDirectory.appendingPathComponent("index.m3u8")
        )
        if let thumbnailURL = plan.thumbnailURL {
            try? await savePoster(
                from: thumbnailURL,
                context: context,
                to: workDirectory.appendingPathComponent("poster.jpg")
            )
        }
        let metadata = HLSVideoPackageMetadata(
            title: plan.fileName,
            sourceHost: context.pageURL?.host ?? context.targetURL.host,
            duration: playlist.segments.compactMap(\.duration).reduce(0, +),
            createdAt: Date()
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(
                to: workDirectory.appendingPathComponent("metadata.json"),
                options: .atomic
            )
        }
        let stored = try storage.storeHLSVideoPackage(
            from: workDirectory,
            preferredFileName: plan.fileName
        )
        return stored
    }

    private func fetchEncryptionKeys(
        for segments: [HLSSegment],
        context: DownloadRequestContext
    ) async throws -> [URL: Data] {
        let urls = Set(segments.compactMap { $0.encryption?.keyURL })
        var result: [URL: Data] = [:]
        for url in urls {
            try Task.checkCancellation()
            let (data, response) = try await session.data(
                for: request(for: url, context: context)
            )
            try validateHTTP(response, data: data)
            guard data.count == kCCKeySizeAES128 else {
                throw DownloadCenterError.invalidHLSKey
            }
            result[url] = data
        }
        return result
    }

    private func downloadSegment(
        _ segment: HLSSegment,
        context: DownloadRequestContext,
        encryptionKeys: [URL: Data],
        ordinal: Int
    ) async throws -> Data {
        var lastError: Error = DownloadCenterError.hlsSegmentFailed(ordinal)
        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                var request = request(for: segment.url, context: context)
                if let range = segment.byteRange {
                    request.setValue(range.headerValue, forHTTPHeaderField: "Range")
                }
                let (responseData, response) = try await session.data(for: request)
                try validateHTTP(response, data: responseData)
                var data = responseData
                if let range = segment.byteRange,
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    let offset = Int(range.offset ?? 0)
                    let length = Int(range.length)
                    guard offset >= 0, length > 0,
                          responseData.count >= offset + length
                    else { throw DownloadCenterError.hlsSegmentFailed(ordinal) }
                    data = responseData.subdata(in: offset..<(offset + length))
                }
                if let encryption = segment.encryption {
                    guard let key = encryptionKeys[encryption.keyURL] else {
                        throw DownloadCenterError.invalidHLSKey
                    }
                    data = try Self.decryptAES128CBC(
                        data: data,
                        key: key,
                        iv: encryption.initializationVector
                            ?? Self.sequenceInitializationVector(segment.mediaSequence)
                    )
                }
                guard !data.isEmpty else {
                    throw DownloadCenterError.hlsSegmentFailed(ordinal)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                }
            }
        }
        if lastError is DownloadCenterError { throw lastError }
        throw DownloadCenterError.hlsSegmentFailed(ordinal)
    }

    private func writeLocalPlaylist(
        _ playlist: HLSMediaPlaylist,
        initCount: Int,
        to url: URL
    ) throws {
        let maximumDuration = playlist.segments.compactMap(\.duration).max() ?? 10
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:\(playlist.initializationSegment == nil ? 3 : 7)",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-TARGETDURATION:\(max(Int(ceil(maximumDuration)), 1))",
            "#EXT-X-MEDIA-SEQUENCE:0"
        ]
        if playlist.initializationSegment != nil {
            lines.append("#EXT-X-MAP:URI=\"media/init.mp4\"")
        }
        for (index, segment) in playlist.segments.enumerated() {
            if segment.discontinuityBefore { lines.append("#EXT-X-DISCONTINUITY") }
            lines.append(String(format: "#EXTINF:%.6f,", segment.duration ?? 0))
            lines.append("media/\(mediaFileName(index: index + initCount, initCount: initCount, playlist: playlist))")
        }
        lines.append("#EXT-X-ENDLIST")
        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private func segmentFileURL(
        index: Int,
        initCount: Int,
        playlist: HLSMediaPlaylist,
        directory: URL
    ) -> URL {
        directory.appendingPathComponent(
            mediaFileName(index: index, initCount: initCount, playlist: playlist)
        )
    }

    private func mediaFileName(
        index: Int,
        initCount: Int,
        playlist: HLSMediaPlaylist
    ) -> String {
        if initCount == 1, index == 0 { return "init.mp4" }
        let mediaIndex = index - initCount
        let original = playlist.segments[max(mediaIndex, 0)].url.pathExtension.lowercased()
        let fallback = playlist.initializationSegment == nil ? "ts" : "m4s"
        let allowed = ["ts", "m4s", "mp4", "aac", "m4a", "webvtt", "vtt"]
        let ext = allowed.contains(original) ? original : fallback
        return String(format: "segment-%06d.%@", mediaIndex, ext)
    }

    private func savePoster(
        from url: URL,
        context: DownloadRequestContext,
        to destination: URL
    ) async throws {
        var request = request(for: url, context: context)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        guard data.count <= 5_000_000,
              let mimeType = response.mimeType?.lowercased(),
              mimeType.hasPrefix("image/")
        else { return }
        try data.write(to: destination, options: .atomic)
    }

    private func request(
        for url: URL,
        context: DownloadRequestContext
    ) -> URLRequest {
        var request = context.makeRequest(
            for: url,
            allowsCellularAccess: DownloadPreferences().allowsCellularDownloads
        )
        request.timeoutInterval = 30
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DownloadCenterError.invalidURL
        }
        guard (200..<300).contains(http.statusCode) else {
            if [401, 403, 410].contains(http.statusCode) {
                throw DownloadCenterError.signedURLExpired
            }
            throw DownloadCenterError.serverRejected(http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""
        if contentType.contains("text/html"),
           Data(data.prefix(512)).containsHTMLDocumentMarker {
            throw DownloadCenterError.unexpectedHTML
        }
    }

    private func makeWorkDirectory(taskID: UUID) throws -> URL {
        let root = storage.applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("HLSWork", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(taskID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeWorkDirectory(taskID: UUID) {
        let url = storage.applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("HLSWork", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    static func decryptAES128CBC(data: Data, key: Data, iv: Data) throws -> Data {
        guard !data.isEmpty,
              key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128
        else { throw DownloadCenterError.hlsDecryptionFailed }
        if let decrypted = crypt(data: data, key: key, iv: iv, options: CCOptions(kCCOptionPKCS7Padding)) {
            return decrypted
        }
        // A few encoders emit block-aligned AES-CBC without a terminal padding
        // block. Accept that standards-adjacent form without weakening DRM checks.
        if data.count.isMultiple(of: kCCBlockSizeAES128),
           let decrypted = crypt(data: data, key: key, iv: iv, options: 0) {
            return decrypted
        }
        throw DownloadCenterError.hlsDecryptionFailed
    }

    private static func crypt(
        data: Data,
        key: Data,
        iv: Data,
        options: CCOptions
    ) -> Data? {
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
                            options,
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
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func sequenceInitializationVector(_ sequence: Int64) -> Data {
        var result = Data(repeating: 0, count: kCCBlockSizeAES128)
        var value = UInt64(bitPattern: sequence).bigEndian
        withUnsafeBytes(of: &value) { bytes in
            result.replaceSubrange(8..<16, with: bytes)
        }
        return result
    }
}

private struct HLSVideoPackageMetadata: Codable {
    let title: String
    let sourceHost: String?
    let duration: TimeInterval
    let createdAt: Date
}

private struct FetchedPlaylist {
    let text: String
    let finalURL: URL
}

private extension Data {
    var containsHTMLDocumentMarker: Bool {
        guard let value = String(data: self, encoding: .utf8)?.lowercased() else {
            return false
        }
        return value.contains("<!doctype html") || value.contains("<html")
    }
}
