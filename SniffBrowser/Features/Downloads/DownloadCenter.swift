import Foundation

extension Notification.Name {
    static let downloadTasksDidChange = Notification.Name(
        "com.example.SniffBrowser.downloadTasksDidChange"
    )
}

@MainActor
final class DownloadCenter: DownloadManaging {
    static let shared = DownloadCenter()

    private(set) var tasks: [DownloadTaskModel] = []
    var onTasksChanged: (() -> Void)?

    private let repository: DownloadRepository
    private let storage: DownloadFileStorage
    private let preferences: DownloadPreferences
    private let fileService: BackgroundFileDownloadService
    private let hlsService: HLSAssetDownloadService
    private let notificationService: DownloadNotificationService
    private var requestContexts: [UUID: DownloadRequestContext] = [:]
    private var progressAggregators: [UUID: DownloadProgressAggregator] = [:]
    private var lastProgressEmissionDates: [UUID: Date] = [:]
    private var hlsPreparationTasks: [UUID: Task<Void, Never>] = [:]
    private var persistenceTask: Task<Void, Never>?
    private var didLoad = false
    private var isReloading = false
    private var reloadWaiters: [CheckedContinuation<Void, Never>] = []
    private var preferenceObserver: NSObjectProtocol?

    init(
        repository: DownloadRepository = DownloadRepository(),
        storage: DownloadFileStorage = DownloadFileStorage(),
        preferences: DownloadPreferences = DownloadPreferences()
    ) {
        self.repository = repository
        self.storage = storage
        self.preferences = preferences
        fileService = BackgroundFileDownloadService(storage: storage)
        fileService.ensureSession()
        hlsService = HLSAssetDownloadService(storage: storage)
        notificationService = DownloadNotificationService(preferences: preferences)
        fileService.delegate = self
        hlsService.delegate = self
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .downloadPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleWaitingTasks()
            }
        }
    }

    deinit {
        persistenceTask?.cancel()
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
    }

    func reloadTasks() async {
        guard !didLoad else {
            publish()
            return
        }
        if isReloading {
            await withCheckedContinuation { continuation in
                reloadWaiters.append(continuation)
            }
            return
        }
        isReloading = true
        do {
            storage.migrateLegacyLayoutIfNeeded()
            tasks = try await repository.load()
            for index in tasks.indices {
                if let path = tasks[index].destinationRelativePath {
                    let migrated = storage.migratedRelativePath(path)
                    if migrated != path {
                        tasks[index].destinationRelativePath = migrated
                    }
                }
                if let thumbnail = tasks[index].thumbnailLocalPath {
                    let migrated = storage.migratedThumbnailPath(thumbnail)
                    if migrated != thumbnail {
                        tasks[index].thumbnailLocalPath = migrated
                    }
                }
            }
            repairMissingFiles()
            registerPlansForPersistedTasks()
            let regularIDs = await restoredRegularTaskIDs()
            let hlsIDs = await restoredHLSTaskIDs()
            let restoredIDs = Set(regularIDs + hlsIDs)
            for index in tasks.indices where tasks[index].state.isInProgress {
                tasks[index].state = restoredIDs.contains(tasks[index].id)
                    ? .downloading
                    : .waiting
                tasks[index].updatedAt = Date()
            }
            finishReload()
            publish()
            persist(immediately: true)
            MediaPipeline.shared.sweepLeftoverWorkDirectories(
                activeTaskIDs: Set(tasks.map(\.id))
            )
            resumeInterruptedProcessing()
            scheduleWaitingTasks()
        } catch {
            tasks = []
            finishReload()
            publish()
        }
    }

    func createDownload(
        resource: DetectedResource,
        context: DownloadRequestContext
    ) async throws -> DownloadCreationResult {
        if !didLoad {
            await reloadTasks()
        }
        guard let scheme = resource.canonicalURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            if resource.canonicalURL.scheme?.lowercased() == "blob" {
                throw DownloadCenterError.unsupportedBlob
            }
            throw DownloadCenterError.invalidURL
        }
        // A playlist is often served as text/plain and the lightweight sniffer
        // cannot determine encryption from response metadata alone. Let the
        // HLS parser inspect the real manifest instead of incorrectly labeling
        // every such stream as protected before download creation.
        guard resource.isPotentiallyDownloadable || resource.resourceType == .hls else {
            throw DownloadCenterError.invalidURL
        }

        if let existing = existingDownloadResult(for: resource.canonicalURL) {
            return existing
        }

        let kind: DownloadKind = resource.resourceType == .hls
            ? .hlsAsset
            : .regularFile
        // Do not fetch an HLS playlist inside the user-triggered creation
        // transaction. Playlist redirects and signed CDN URLs can take several
        // seconds to resolve, which previously kept the resource sheet waiting
        // before it could confirm that the task was queued. The task is now
        // registered immediately; `start(_:)` performs playlist validation in
        // the existing asynchronous preparing phase and reports a real failure
        // on the task if the stream is invalid, live, expired, or protected.
        let fileName = preferredFileName(for: resource, kind: kind)
        let model = DownloadTaskModel(
            resourceID: resource.id,
            sourceURL: resource.canonicalURL,
            thumbnailURL: resource.resourceType == .image
                ? resource.canonicalURL
                : resource.thumbnailURL,
            fileName: fileName,
            fileExtension: resource.fileExtension,
            resourceType: resource.resourceType,
            downloadKind: kind,
            expectedSize: kind == .hlsAsset ? nil : resource.estimatedSize
        )
        tasks.append(model)
        requestContexts[model.id] = context
        registerPlan(for: model)
        publish()
        persist(immediately: true)
        scheduleWaitingTasks()
        return .created(model.id)
    }

    func pauseTask(id: UUID) async throws {
        guard let index = index(for: id) else {
            throw DownloadCenterError.taskUnavailable
        }
        switch tasks[index].state {
        case .waiting, .retrying:
            updateTask(id: id) { task in
                task.state = .paused
                task.speedBytesPerSecond = nil
                task.estimatedRemainingTime = nil
            }
            scheduleWaitingTasks()
        case .preparing:
            if tasks[index].downloadKind == .regularFile {
                fileService.pause(taskID: id)
            } else {
                hlsPreparationTasks[id]?.cancel()
                hlsPreparationTasks[id] = nil
                updateTask(id: id) { task in
                    task.state = .paused
                    task.speedBytesPerSecond = nil
                    task.estimatedRemainingTime = nil
                }
                scheduleWaitingTasks()
            }
        case .downloading:
            if tasks[index].downloadKind == .regularFile {
                fileService.pause(taskID: id)
            } else {
                hlsService.pause(taskID: id)
            }
        default:
            return
        }
    }

    func resumeTask(id: UUID) async throws {
        guard let index = index(for: id), tasks[index].state == .paused else {
            throw DownloadCenterError.taskUnavailable
        }
        let model = tasks[index]
        if model.downloadKind == .regularFile,
           model.resumeDataRelativePath != nil,
           storage.loadResumeData(relativePath: model.resumeDataRelativePath) == nil {
            throw DownloadCenterError.resumeDataInvalid
        }
        updateTask(id: id) { task in
            task.state = .waiting
            task.errorCode = nil
            task.errorDescription = nil
        }
        scheduleWaitingTasks()
    }

    func restartTaskFromBeginning(id: UUID) async throws {
        guard index(for: id) != nil else {
            throw DownloadCenterError.taskUnavailable
        }
        storage.removeResumeData(relativePath: task(id: id)?.resumeDataRelativePath)
        updateTask(id: id) { task in
            task.state = .waiting
            task.downloadedSize = 0
            task.progressFraction = nil
            task.resumeDataRelativePath = nil
            task.errorCode = nil
            task.errorDescription = nil
        }
        scheduleWaitingTasks()
    }

    func cancelTask(id: UUID) async throws {
        guard let model = task(id: id) else {
            throw DownloadCenterError.taskUnavailable
        }
        hlsPreparationTasks[id]?.cancel()
        hlsPreparationTasks[id] = nil
        if model.downloadKind == .regularFile {
            fileService.cancel(taskID: id)
        } else {
            hlsService.cancel(taskID: id)
        }
        storage.removeResumeData(relativePath: model.resumeDataRelativePath)
        updateTask(id: id) { task in
            task.state = .cancelled
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = nil
            task.resumeDataRelativePath = nil
        }
        scheduleWaitingTasks()
    }

    func retryTask(id: UUID) async throws {
        guard let index = index(for: id),
              [.failed, .cancelled].contains(tasks[index].state)
        else { throw DownloadCenterError.taskUnavailable }
        updateTask(id: id) { task in
            task.state = .waiting
            task.downloadedSize = 0
            task.progressFraction = nil
            task.errorCode = nil
            task.errorDescription = nil
            task.retryCount += 1
        }
        scheduleWaitingTasks()
    }

    func deleteTask(id: UUID, deleteFile: Bool) async throws {
        guard let model = task(id: id) else { return }
        if model.state == .completed, !deleteFile {
            updateTask(id: id) { task in
                task.isHiddenFromDownloadHistory = true
            }
            return
        }
        if model.state.isInProgress || model.state == .waiting || model.state == .paused {
            if model.downloadKind == .regularFile {
                fileService.cancel(taskID: id)
            } else {
                hlsService.cancel(taskID: id)
            }
        }
        if deleteFile {
            try storage.removeFile(relativePath: model.destinationRelativePath)
        }
        storage.removeResumeData(relativePath: model.resumeDataRelativePath)
        tasks.removeAll { $0.id == id }
        requestContexts[id] = nil
        progressAggregators[id] = nil
        lastProgressEmissionDates[id] = nil
        hlsPreparationTasks[id]?.cancel()
        hlsPreparationTasks[id] = nil
        publish()
        persist(immediately: true)
        scheduleWaitingTasks()
    }

    func fileURL(for taskID: UUID) -> URL? {
        storage.fileURL(relativePath: task(id: taskID)?.destinationRelativePath)
    }

    func thumbnailFileURL(for taskID: UUID) -> URL? {
        storage.fileURL(relativePath: task(id: taskID)?.thumbnailLocalPath)
    }

    func renameCompletedTask(id: UUID, to requestedName: String) throws {
        guard let model = task(id: id), model.state == .completed else {
            throw DownloadCenterError.taskUnavailable
        }
        let extensionName = (model.fileName as NSString).pathExtension
        var safeName = FileNameSanitizer.sanitize(requestedName)
        if (safeName as NSString).pathExtension.isEmpty, !extensionName.isEmpty {
            safeName += ".\(extensionName)"
        }
        guard !safeName.isEmpty else { throw DownloadCenterError.fileOperationFailed }
        if model.downloadKind == .hlsAsset,
           model.destinationRelativePath?.hasPrefix("Container/") == true {
            // Preserve rename behavior for legacy AVFoundation asset packages
            // created before the segmented HLS implementation.
            updateTask(id: id) { task in task.fileName = safeName }
            return
        }
        let stored = try storage.renameFile(
            relativePath: model.destinationRelativePath,
            preferredFileName: safeName
        )
        updateTask(id: id) { task in
            task.fileName = stored.fileURL.lastPathComponent
            task.destinationRelativePath = stored.relativePath
        }
    }

    func handleBackgroundEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let isKnownSession: Bool
        switch identifier {
        case BackgroundFileDownloadService.sessionIdentifier:
            fileService.setBackgroundCompletionHandler(completionHandler)
            isKnownSession = true
        case HLSAssetDownloadService.sessionIdentifier:
            hlsService.setBackgroundCompletionHandler(completionHandler)
            isKnownSession = true
        default:
            completionHandler()
            isKnownSession = false
        }
        guard isKnownSession else { return }

        // Register persisted task plans before recreating either background
        // session. A completion callback may arrive as soon as the session is
        // recreated, and it needs the plan to choose and validate its target.
        Task { [weak self] in
            await self?.reloadTasks()
        }
    }

    private func scheduleWaitingTasks() {
        let activeCount = tasks.lazy.filter { $0.state.isInProgress }.count
        var remainingSlots = max(0, preferences.maximumConcurrentDownloads - activeCount)
        guard remainingSlots > 0 else { return }

        for model in tasks where model.state == .waiting && remainingSlots > 0 {
            remainingSlots -= 1
            start(model)
        }
    }

    private func start(_ model: DownloadTaskModel) {
        let context = requestContexts[model.id] ?? DownloadRequestContext(
            targetURL: model.sourceURL,
            pageURL: nil,
            headers: [:]
        )
        updateTask(id: model.id) { task in
            task.state = .preparing
            task.startedAt = task.startedAt ?? Date()
            task.errorCode = nil
            task.errorDescription = nil
        }
        if model.downloadKind == .regularFile {
            if model.resumeDataRelativePath != nil {
                do {
                    try fileService.resume(
                        taskID: model.id,
                        resumeDataRelativePath: model.resumeDataRelativePath
                    )
                } catch {
                    storage.removeResumeData(relativePath: model.resumeDataRelativePath)
                    updateTask(id: model.id) { task in
                        task.state = .failed
                        task.resumeDataRelativePath = nil
                        task.speedBytesPerSecond = nil
                        task.estimatedRemainingTime = nil
                        task.errorCode = String(describing: type(of: error))
                        task.errorDescription = DownloadErrorMapper.message(for: error)
                    }
                    scheduleWaitingTasks()
                }
            } else {
                var request = context.makeRequest(
                    allowsCellularAccess: preferences.allowsCellularDownloads
                )
                request.setValue(
                    acceptHeader(for: model.resourceType),
                    forHTTPHeaderField: "Accept"
                )
                fileService.start(
                    taskID: model.id,
                    request: request
                )
            }
        } else {
            do {
                try hlsService.resume(taskID: model.id)
                return
            } catch {
                // A fresh request context is required after process relaunch or
                // when a signed manifest has expired. The segment checkpoints
                // remain reusable once the page supplies that context again.
            }
            let preparationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.hlsService.start(
                        taskID: model.id,
                        context: context,
                        title: model.fileName
                    )
                } catch is CancellationError {
                    return
                } catch {
                    self.failTask(id: model.id, error: error)
                }
                self.hlsPreparationTasks[model.id] = nil
            }
            hlsPreparationTasks[model.id] = preparationTask
        }
    }

    private func acceptHeader(for resourceType: ResourceType) -> String {
        switch resourceType {
        case .video: return "video/*,application/octet-stream;q=0.9,*/*;q=0.8"
        case .audio: return "audio/*,application/octet-stream;q=0.9,*/*;q=0.8"
        case .image: return "image/avif,image/webp,image/*,*/*;q=0.8"
        case .document: return "application/pdf,text/plain,*/*;q=0.8"
        case .subtitle: return "text/vtt,text/plain,*/*;q=0.8"
        case .archive, .other: return "application/octet-stream,*/*;q=0.8"
        case .hls: return "application/vnd.apple.mpegurl,*/*;q=0.8"
        }
    }

    private func preferredFileName(
        for resource: DetectedResource,
        kind: DownloadKind
    ) -> String {
        var name = FileNameSanitizer.sanitize(resource.fileName)
        if name.isEmpty { name = "下载资源" }
        if kind == .hlsAsset {
            var base = (name as NSString).deletingPathExtension
            let opaqueCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF-_ ")
            let looksOpaque = base.count >= 32
                && base.unicodeScalars.allSatisfy { opaqueCharacters.contains($0) }
            let genericNames: Set<String> = [
                "master", "index", "playlist", "video", "stream", "hls"
            ]
            if (looksOpaque || genericNames.contains(base.lowercased())),
               let pageTitle = resource.sourcePageTitle {
                let readableTitle = FileNameSanitizer.sanitize(pageTitle)
                if !readableTitle.isEmpty { base = readableTitle }
            }
            if let quality = HLSQualityLabel.make(
                width: resource.width,
                height: resource.height,
                bitrate: resource.bitrate
            ), !base.lowercased().contains(quality.lowercased()) {
                base += " - \(quality)"
            }
            return base.isEmpty ? "下载视频" : base
        }
        if (name as NSString).pathExtension.isEmpty,
           let fileExtension = resource.fileExtension,
           !fileExtension.isEmpty {
            name += ".\(fileExtension)"
        }
        return name
    }

    private func existingDownloadResult(
        for sourceURL: URL
    ) -> DownloadCreationResult? {
        guard let existing = tasks.first(where: {
            $0.sourceURL == sourceURL
                && $0.state != .failed
                && $0.state != .cancelled
        }) else { return nil }
        return existing.state == .completed
            ? .fileAlreadyExists(existing.id)
            : .alreadyDownloading(existing.id)
    }

    private func task(id: UUID) -> DownloadTaskModel? {
        tasks.first { $0.id == id }
    }

    private func index(for id: UUID) -> Int? {
        tasks.firstIndex { $0.id == id }
    }

    private func updateTask(
        id: UUID,
        immediatePersistence: Bool = true,
        _ mutation: (inout DownloadTaskModel) -> Void
    ) {
        guard let index = index(for: id) else { return }
        mutation(&tasks[index])
        tasks[index].updatedAt = Date()
        publish()
        persist(immediately: immediatePersistence)
    }

    private func updateProgressTask(
        id: UUID,
        now: Date = Date(),
        _ mutation: (inout DownloadTaskModel) -> Void
    ) {
        guard let index = index(for: id) else { return }
        mutation(&tasks[index])
        tasks[index].updatedAt = now

        // URLSession and AVFoundation may report dozens of progress callbacks
        // per second. Keep the in-memory model current while limiting observer
        // and persistence work to roughly 6 Hz.
        let lastEmission = lastProgressEmissionDates[id] ?? .distantPast
        guard now.timeIntervalSince(lastEmission) >= 0.16 else { return }
        lastProgressEmissionDates[id] = now
        publish()
        persist(immediately: false)
    }

    private func failTask(id: UUID, error: Error) {
        guard let existing = task(id: id) else { return }
        if preferences.automaticRetryEnabled, existing.retryCount < 2 {
            updateTask(id: id) { task in
                task.state = .retrying
                task.retryCount += 1
                task.errorCode = String(describing: type(of: error))
                task.errorDescription = DownloadErrorMapper.message(for: error)
            }
            updateTask(id: id) { $0.state = .waiting }
            scheduleWaitingTasks()
            return
        }
        updateTask(id: id) { task in
            task.state = .failed
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = nil
            task.errorCode = String(describing: type(of: error))
            task.errorDescription = DownloadErrorMapper.message(for: error)
        }
        scheduleWaitingTasks()
    }

    private func finishTask(id: UUID, storedFile: StoredDownloadFile) {
        updateTask(id: id) { task in
            task.state = .completed
            task.downloadedSize = storedFile.byteCount ?? task.expectedSize ?? task.downloadedSize
            task.expectedSize = storedFile.byteCount ?? task.expectedSize
            task.progressFraction = 1
            task.destinationRelativePath = storedFile.relativePath
            if task.downloadKind != .hlsAsset,
               !storedFile.relativePath.hasPrefix("Container/") {
                task.fileName = storedFile.fileURL.lastPathComponent
                task.fileExtension = storedFile.fileURL.pathExtension.lowercased()
            }
            task.completedAt = Date()
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = 0
            task.errorCode = nil
            task.errorDescription = nil
        }
        if let model = task(id: id) {
            notificationService.notifyCompleted(fileName: model.fileName, taskID: id)
            runPipelinePostProcessing(
                id: id,
                sourceURL: storedFile.fileURL,
                resourceType: model.resourceType,
                fileName: model.fileName
            )
        }
        requestContexts[id] = nil
        progressAggregators[id] = nil
        lastProgressEmissionDates[id] = nil
        hlsPreparationTasks[id] = nil
        scheduleWaitingTasks()
    }

    /// 视频类任务完成后，后台统一走 Media Pipeline 生成最终文件并清理缓存。
    private func runPipelinePostProcessing(
        id: UUID,
        sourceURL: URL,
        resourceType: ResourceType,
        fileName: String
    ) {
        guard [.video, .hls, .audio].contains(resourceType) else {
            return
        }
        let preferredType: MediaType
        switch resourceType {
        case .hls: preferredType = .hls
        case .audio: preferredType = .audio
        default: preferredType = .unknown
        }
        Task { [weak self] in
            guard let self else { return }
            let final = await MediaPipeline.shared.postProcess(
                taskID: id,
                sourceURL: sourceURL,
                preferredType: preferredType,
                fileName: fileName
            )
            guard let final else { return }
            self.updateTask(id: id) { task in
                task.fileName = final.fileName
                task.fileExtension = final.url.pathExtension.lowercased()
                task.destinationRelativePath = "Videos/\(final.url.lastPathComponent)"
                task.thumbnailLocalPath = final.thumbnailLocalPath
                task.mediaDuration = final.info.duration
                task.mediaWidth = final.info.width
                task.mediaHeight = final.info.height
                task.mediaBitrate = final.info.estimatedBitrate
            }
            self.persist(immediately: true)
            self.publish()
        }
    }

    /// 启动恢复：完成但尚未进入 Videos 的视频任务，自动继续媒体处理。
    private func resumeInterruptedProcessing() {
        for model in tasks where model.state == .completed
            && [.video, .hls, .audio].contains(model.resourceType)
            && !(model.destinationRelativePath?.hasPrefix("Videos/") ?? false) {
            guard let url = storage.fileURL(relativePath: model.destinationRelativePath) else {
                continue
            }
            runPipelinePostProcessing(
                id: model.id,
                sourceURL: url,
                resourceType: model.resourceType,
                fileName: model.fileName
            )
        }
    }

    private func registerPlan(for model: DownloadTaskModel) {
        if model.downloadKind == .regularFile {
            fileService.register(plan: FileDownloadPlan(
                taskID: model.id,
                fileName: model.fileName,
                resourceType: model.resourceType
            ))
        } else {
            hlsService.register(plan: HLSDownloadPlan(
                taskID: model.id,
                fileName: model.fileName,
                thumbnailURL: model.thumbnailURL
            ))
        }
    }

    private func registerPlansForPersistedTasks() {
        tasks.forEach(registerPlan)
    }

    private func repairMissingFiles() {
        for index in tasks.indices where tasks[index].state == .completed {
            guard storage.fileURL(
                relativePath: tasks[index].destinationRelativePath
            ) == nil else { continue }
            tasks[index].state = .failed
            tasks[index].errorDescription = "本地文件已不存在。"
            tasks[index].destinationRelativePath = nil
        }
    }

    private func restoredRegularTaskIDs() async -> [UUID] {
        await withCheckedContinuation { continuation in
            fileService.restoreSystemTasks { continuation.resume(returning: $0) }
        }
    }

    private func restoredHLSTaskIDs() async -> [UUID] {
        await withCheckedContinuation { continuation in
            hlsService.restoreSystemTasks { continuation.resume(returning: $0) }
        }
    }

    private func persist(immediately: Bool) {
        persistenceTask?.cancel()
        let snapshot = tasks
        persistenceTask = Task { [repository] in
            if !immediately {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
            try? await repository.save(snapshot)
        }
    }

    private func publish() {
        onTasksChanged?()
        NotificationCenter.default.post(name: .downloadTasksDidChange, object: self)
    }

    private func finishReload() {
        didLoad = true
        isReloading = false
        let waiters = reloadWaiters
        reloadWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }
}

extension DownloadCenter: BackgroundFileDownloadServiceDelegate {
    func fileDownloadDidStart(taskID: UUID) {
        updateTask(id: taskID) { task in
            task.state = .downloading
            task.startedAt = task.startedAt ?? Date()
        }
    }

    func fileDownloadDidPause(taskID: UUID, resumeDataRelativePath: String?) {
        updateTask(id: taskID) { task in
            task.state = .paused
            task.resumeDataRelativePath = resumeDataRelativePath
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = nil
        }
        scheduleWaitingTasks()
    }

    func fileDownload(
        taskID: UUID,
        didUpdate receivedBytes: Int64,
        expectedBytes: Int64?
    ) {
        var aggregator = progressAggregators[taskID] ?? DownloadProgressAggregator()
        let sample = aggregator.update(
            receivedBytes: receivedBytes,
            expectedBytes: expectedBytes
        )
        progressAggregators[taskID] = aggregator
        updateProgressTask(id: taskID) { task in
            task.state = .downloading
            task.downloadedSize = sample.receivedBytes
            task.expectedSize = sample.expectedBytes ?? task.expectedSize
            task.speedBytesPerSecond = sample.speedBytesPerSecond
            task.estimatedRemainingTime = sample.estimatedRemainingTime
        }
    }

    func fileDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile) {
        finishTask(id: taskID, storedFile: storedFile)
    }

    func fileDownloadDidFail(taskID: UUID, error: Error) {
        failTask(id: taskID, error: error)
    }

    func fileDownloadDidCancel(taskID: UUID) {
        guard task(id: taskID)?.state != .cancelled else { return }
        updateTask(id: taskID) { $0.state = .cancelled }
        scheduleWaitingTasks()
    }
}

extension DownloadCenter: HLSAssetDownloadServiceDelegate {
    func hlsDownloadDidStart(taskID: UUID) {
        updateTask(id: taskID) { $0.state = .downloading }
    }

    func hlsDownload(
        taskID: UUID,
        progress: Double,
        receivedBytes: Int64
    ) {
        var aggregator = progressAggregators[taskID] ?? DownloadProgressAggregator()
        let sample = aggregator.update(
            receivedBytes: receivedBytes,
            expectedBytes: nil
        )
        progressAggregators[taskID] = aggregator
        updateProgressTask(id: taskID) { task in
            task.state = .downloading
            task.progressFraction = progress
            task.downloadedSize = sample.receivedBytes
            task.speedBytesPerSecond = sample.speedBytesPerSecond
            // HLS playlists generally do not publish segment byte totals. Keep
            // total size and ETA unknown instead of presenting an estimate as
            // authoritative; finishTask writes the exact merged file size.
            task.estimatedRemainingTime = nil
        }
    }

    func hlsDownloadDidFinish(taskID: UUID, storedFile: StoredDownloadFile) {
        finishTask(id: taskID, storedFile: storedFile)
    }

    func hlsDownloadDidFail(taskID: UUID, error: Error) {
        failTask(id: taskID, error: error)
    }

    func hlsDownloadDidPause(taskID: UUID) {
        updateTask(id: taskID) { task in
            task.state = .paused
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = nil
        }
        scheduleWaitingTasks()
    }

    func hlsDownloadDidCancel(taskID: UUID) {
        guard task(id: taskID)?.state != .cancelled else { return }
        updateTask(id: taskID) { task in
            task.state = .cancelled
            task.speedBytesPerSecond = nil
            task.estimatedRemainingTime = nil
        }
        scheduleWaitingTasks()
    }
}

enum DownloadErrorMapper {
    static func message(for error: Error) -> String {
        if let error = error as? DownloadCenterError {
            return error.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "网络连接已断开。"
            case .timedOut: return "下载请求超时，请稍后重试。"
            case .networkConnectionLost: return "下载连接中断，已保留可恢复的数据。"
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "无法连接资源服务器，请返回网页重新识别后重试。"
            case .cancelled: return "下载已取消。"
            default: return "下载失败，请检查网络后重试。"
            }
        }
        return "下载失败，请稍后重试。"
    }
}
