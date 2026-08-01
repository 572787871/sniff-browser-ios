import AVFoundation
import CommonCrypto
import Foundation

struct HLSDownloadPlan: Sendable {
    let taskID: UUID
    let fileName: String
}

@MainActor
protocol HLSAssetDownloadServiceDelegate: AnyObject {
    func hlsDownloadDidStart(taskID: UUID)
    func hlsDownload(
        taskID: UUID,
        progress: Double,
        receivedBytes: Int64
    )
    func hlsDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile)
    func hlsDownloadDidFail(taskID: UUID, error: Error)
    func hlsDownloadDidPause(taskID: UUID)
    func hlsDownloadDidCancel(taskID: UUID)
}

/// Downloads a finite HLS playlist as its declared media segments,
/// then joins them in playlist order. fMP4 playlists become a local `.mp4`
/// (initialization segment followed by media fragments); MPEG-TS playlists are
/// exported to an iOS-compatible `.mp4` after joining. Standard identity-key
/// AES-128 segments are decrypted using the key and IV declared by the playlist.
/// SAMPLE-AES, FairPlay and other
/// DRM formats remain unsupported. The service deliberately does not treat the
/// `.m3u8` text file or an individual fragment as the finished video.
final class HLSAssetDownloadService: NSObject {
    // Kept so old background-session callbacks are completed safely after an
    // upgrade from the AVAssetDownloadURLSession implementation.
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
        configuration.httpMaximumConnectionsPerHost = 4
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
        try validateDownloadable(playlist)
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
                let stored = try await self.downloadAndMerge(
                    taskID: taskID,
                    context: context,
                    playlist: playlist,
                    plan: plan
                )
                self.lock.withLock { self.workers[taskID] = nil }
                await MainActor.run { [weak self] in
                    self?.delegate?.hlsDownloadDidFinish(
                        taskID: taskID,
                        storedFile: stored
                    )
                }
            } catch is CancellationError {
                self.lock.withLock { self.workers[taskID] = nil }
            } catch {
                let shouldSuppress = self.lock.withLock { () -> Bool in
                    self.workers[taskID] = nil
                    return self.intentionallyStoppedIDs.contains(taskID)
                }
                guard !shouldSuppress else { return }
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
        // Segment work is checkpointed on disk. There is no system background
        // URLSession task to claim; DownloadCenter will put persisted active
        // records back into its waiting queue and restart them safely.
        completion([])
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func finalizeLegacyTransportStream(
        at sourceURL: URL,
        preferredFileName: String
    ) async throws -> StoredDownloadFile {
        let workDirectory = storage.applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("LegacyHLSFinalization", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let outputURL = workDirectory.appendingPathComponent("finalized.mp4")
        try await exportTransportStream(at: sourceURL, to: outputURL)
        let baseName = (FileNameSanitizer.sanitize(preferredFileName) as NSString)
            .deletingPathExtension
        let stored = try storage.storeDownloadedFile(
            from: outputURL,
            preferredFileName: "\(baseName.isEmpty ? "HLS 视频" : baseName).mp4",
            resourceType: .hls
        )
        try? FileManager.default.removeItem(at: sourceURL)
        return stored
    }

    private func resolveMediaPlaylist(
        context: DownloadRequestContext,
        maximumDepth: Int = 3
    ) async throws -> HLSMediaPlaylist {
        var url = context.targetURL
        for _ in 0..<maximumDepth {
            let text = try await fetchPlaylist(url: url, context: context)
            switch try parser.parse(text, sourceURL: url) {
            case let .media(playlist):
                try validateDownloadable(playlist)
                return playlist
            case let .master(variants):
                guard let selected = variants.max(by: { lhs, rhs in
                    let leftBandwidth = lhs.bandwidth ?? 0
                    let rightBandwidth = rhs.bandwidth ?? 0
                    if leftBandwidth != rightBandwidth {
                        return leftBandwidth < rightBandwidth
                    }
                    return (lhs.height ?? 0) < (rhs.height ?? 0)
                }) else {
                    throw DownloadCenterError.invalidHLSPlaylist
                }
                url = selected.url
            }
        }
        throw DownloadCenterError.invalidHLSPlaylist
    }

    private func validateDownloadable(_ playlist: HLSMediaPlaylist) throws {
        guard playlist.isEndList else {
            throw DownloadCenterError.liveHLSUnsupported
        }
        guard !playlist.hasUnsupportedEncryption else {
            throw DownloadCenterError.protectedMediaUnsupported
        }
    }

    private func fetchPlaylist(
        url: URL,
        context: DownloadRequestContext
    ) async throws -> String {
        var request = request(for: url, context: context)
        request.setValue(
            "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)
        guard data.count <= 5_000_000,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("#EXTM3U")
        else { throw DownloadCenterError.invalidHLSPlaylist }
        return text
    }

    private func downloadAndMerge(
        taskID: UUID,
        context: DownloadRequestContext,
        playlist: HLSMediaPlaylist,
        plan: HLSDownloadPlan
    ) async throws -> StoredDownloadFile {
        let workDirectory = try makeWorkDirectory(taskID: taskID)
        let allSegments = ([playlist.initializationSegment].compactMap { $0 }) + playlist.segments
        let total = allSegments.count
        guard total > 0 else { throw DownloadCenterError.invalidHLSPlaylist }
        let encryptionKeys = try await fetchEncryptionKeys(
            for: allSegments,
            context: context
        )

        var completed = 0
        var receivedBytes: Int64 = 0
        let batchSize = min(max(DownloadPreferences().maximumConcurrentDownloads, 1), 5)
        var startIndex = 0
        while startIndex < total {
            try Task.checkCancellation()
            let endIndex = min(startIndex + batchSize, total)
            try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                for index in startIndex..<endIndex {
                    let target = segmentFileURL(in: workDirectory, index: index)
                    if let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 0 {
                        completed += 1
                        receivedBytes += Int64(size)
                        continue
                    }
                    let segment = allSegments[index]
                    group.addTask { [weak self] in
                        guard let self else { throw CancellationError() }
                        let data = try await self.downloadSegment(
                            segment,
                            context: context,
                            encryptionKeys: encryptionKeys,
                            ordinal: index + 1
                        )
                        return (index, data)
                    }
                }
                for try await (index, data) in group {
                    try Task.checkCancellation()
                    try data.write(
                        to: segmentFileURL(in: workDirectory, index: index),
                        options: .atomic
                    )
                    completed += 1
                    receivedBytes += Int64(data.count)
                }
            }
            // Publish once per bounded batch. This is frequent enough for a
            // smooth speed display without sending a UI update for every
            // fragment or racing mutable counters across actor boundaries.
            let reportedProgress = Double(completed) / Double(total)
            let reportedBytes = receivedBytes
            await MainActor.run { [weak self] in
                self?.delegate?.hlsDownload(
                    taskID: taskID,
                    progress: reportedProgress,
                    receivedBytes: reportedBytes
                )
            }
            startIndex = endIndex
        }

        try Task.checkCancellation()
        let mergedURL = workDirectory.appendingPathComponent(
            "merged.\(playlist.mergedSegmentFileExtension)"
        )
        try mergeSegments(count: total, in: workDirectory, destination: mergedURL)
        let finalizedURL = try await finalizeMergedMedia(
            at: mergedURL,
            playlist: playlist,
            workDirectory: workDirectory
        )
        let baseName = (FileNameSanitizer.sanitize(plan.fileName) as NSString)
            .deletingPathExtension
        let finalName = "\(baseName.isEmpty ? "HLS 视频" : baseName).\(playlist.outputFileExtension)"
        let stored = try storage.storeDownloadedFile(
            from: finalizedURL,
            preferredFileName: finalName,
            resourceType: .hls
        )
        try? FileManager.default.removeItem(at: workDirectory)
        lock.withLock {
            contexts[taskID] = nil
            intentionallyStoppedIDs.remove(taskID)
        }
        return stored
    }

    private func finalizeMergedMedia(
        at mergedURL: URL,
        playlist: HLSMediaPlaylist,
        workDirectory: URL
    ) async throws -> URL {
        guard playlist.requiresTransportStreamExport else { return mergedURL }
        let outputURL = workDirectory.appendingPathComponent("finalized.mp4")
        try await exportTransportStream(at: mergedURL, to: outputURL)
        return outputURL
    }

    private func exportTransportStream(at sourceURL: URL, to outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(
            url: sourceURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        for preset in presets {
            try Task.checkCancellation()
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset),
                  exporter.supportedFileTypes.contains(.mp4)
            else { continue }
            try? FileManager.default.removeItem(at: outputURL)
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = false
            let succeeded = await export(exporter)
            if succeeded,
               let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 0 {
                return
            }
        }
        // AVAssetExportSession does not reliably accept every long MPEG-TS
        // program even when AVPlayer can inspect its H.264/AAC tracks. Fall
        // back to a native sample-level remux: compressed samples are copied
        // into an MPEG-4 container without changing their media content.
        if try await remuxTransportStream(asset: asset, to: outputURL) {
            return
        }
        throw DownloadCenterError.hlsFinalizationFailed
    }

    private func export(_ exporter: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume(returning: exporter.status == .completed)
            }
        }
    }

    private func remuxTransportStream(
        asset: AVURLAsset,
        to outputURL: URL
    ) async throws -> Bool {
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let tracks = Array(videoTracks.prefix(1)) + Array(audioTracks.prefix(1))
        guard !videoTracks.isEmpty, !tracks.isEmpty else { return false }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        var pumps: [HLSRemuxTrackPump] = []
        for (index, track) in tracks.enumerated() {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let formatDescriptions = try await track.load(.formatDescriptions)
            let input = AVAssetWriterInput(
                mediaType: track.mediaType,
                outputSettings: nil,
                sourceFormatHint: formatDescriptions.first
            )
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { return false }
            reader.add(output)
            writer.add(input)
            pumps.append(HLSRemuxTrackPump(
                input: input,
                output: output,
                queueLabel: "com.example.SniffBrowser.hls-remux.\(index)"
            ))
        }

        guard writer.startWriting(), reader.startReading() else { return false }
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        pumps.forEach { $0.start(reader: reader, group: group) }
        let succeeded = await withCheckedContinuation { continuation in
            group.notify(queue: DispatchQueue.global(qos: .utility)) {
                guard reader.status == .completed else {
                    writer.cancelWriting()
                    continuation.resume(returning: false)
                    return
                }
                writer.finishWriting {
                    continuation.resume(returning: writer.status == .completed)
                }
            }
        }
        guard succeeded,
              let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0
        else { return false }
        return true
    }

    private func downloadSegment(
        _ segment: HLSSegment,
        context: DownloadRequestContext,
        encryptionKeys: [URL: Data],
        ordinal: Int
    ) async throws -> Data {
        var lastError: Error = DownloadCenterError.hlsSegmentFailed(ordinal)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                var request = request(for: segment.url, context: context)
                request.setValue("video/*,audio/*,application/octet-stream,*/*;q=0.5", forHTTPHeaderField: "Accept")
                if let range = segment.byteRange {
                    request.setValue(range.headerValue, forHTTPHeaderField: "Range")
                }
                let (data, response) = try await session.data(for: request)
                try validateHTTP(response)
                try DownloadResponseValidator.validate(
                    response: response,
                    filePrefix: Data(data.prefix(256))
                )
                guard !data.isEmpty else {
                    throw DownloadCenterError.hlsSegmentFailed(ordinal)
                }
                guard let encryption = segment.encryption else { return data }
                guard let key = encryptionKeys[encryption.keyURL] else {
                    throw DownloadCenterError.invalidHLSKey
                }
                let iv = encryption.initializationVector
                    ?? Self.initializationVector(mediaSequence: segment.mediaSequence)
                return try Self.decryptAES128CBC(data: data, key: key, iv: iv)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(
                        for: .milliseconds(Int64(350 * (attempt + 1)))
                    )
                }
            }
        }
        if let centerError = lastError as? DownloadCenterError {
            throw centerError
        }
        throw DownloadCenterError.hlsSegmentFailed(ordinal)
    }

    private func fetchEncryptionKeys(
        for segments: [HLSSegment],
        context: DownloadRequestContext
    ) async throws -> [URL: Data] {
        let urls = Set(segments.compactMap { $0.encryption?.keyURL })
        guard !urls.isEmpty else { return [:] }
        var keys: [URL: Data] = [:]
        for url in urls {
            try Task.checkCancellation()
            var keyRequest = request(for: url, context: context)
            keyRequest.setValue("application/octet-stream,*/*;q=0.5", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: keyRequest)
            try validateHTTP(response)
            guard data.count == kCCKeySizeAES128 else {
                throw DownloadCenterError.invalidHLSKey
            }
            keys[url] = data
        }
        return keys
    }

    private static func initializationVector(mediaSequence: Int64) -> Data {
        var bytes = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var value = UInt64(max(mediaSequence, 0))
        for index in 0..<MemoryLayout<UInt64>.size {
            bytes[bytes.count - 1 - index] = UInt8(value & 0xff)
            value >>= 8
        }
        return Data(bytes)
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
        let outputCapacity = output.count
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
                            outputCapacity,
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

    private func request(for url: URL, context: DownloadRequestContext) -> URLRequest {
        var request = context.makeRequest(
            allowsCellularAccess: DownloadPreferences().allowsCellularDownloads
        )
        request.url = url
        request.timeoutInterval = 45
        if url.host?.caseInsensitiveCompare(context.targetURL.host ?? "") != .orderedSame {
            request.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { return }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw DownloadCenterError.signedURLExpired
            }
            throw DownloadCenterError.serverRejected(response.statusCode)
        }
    }

    private func makeWorkDirectory(taskID: UUID) throws -> URL {
        let root = storage.applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("HLSWork", isDirectory: true)
        let directory = root.appendingPathComponent(taskID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeWorkDirectory(taskID: UUID) {
        let directory = storage.applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("HLSWork", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private func segmentFileURL(in directory: URL, index: Int) -> URL {
        directory.appendingPathComponent(String(format: "%08d.part", index))
    }

    private func mergeSegments(count: Int, in directory: URL, destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination)
        else { throw DownloadCenterError.hlsMergeFailed }
        defer { try? output.close() }
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                let inputURL = segmentFileURL(in: directory, index: index)
                let input = try FileHandle(forReadingFrom: inputURL)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                }
            }
            try output.synchronize()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DownloadCenterError.hlsMergeFailed
        }
    }
}

private final class HLSRemuxTrackPump {
    private let input: AVAssetWriterInput
    private let output: AVAssetReaderTrackOutput
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var didFinish = false

    init(
        input: AVAssetWriterInput,
        output: AVAssetReaderTrackOutput,
        queueLabel: String
    ) {
        self.input = input
        self.output = output
        queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func start(reader: AVAssetReader, group: DispatchGroup) {
        group.enter()
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    finish(group: group)
                    return
                }
                guard input.append(sample) else {
                    reader.cancelReading()
                    input.markAsFinished()
                    finish(group: group)
                    return
                }
            }
        }
    }

    private func finish(group: DispatchGroup) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        group.leave()
    }
}
