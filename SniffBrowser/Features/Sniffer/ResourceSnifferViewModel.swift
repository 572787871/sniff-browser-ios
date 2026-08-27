import Foundation

private actor HLSMetadataPermitPool {
    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available = min(limit, available + 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class ResourceSnifferViewModel {
    typealias RequestContextProvider = @MainActor (URL) async -> DownloadRequestContext
    struct State: Equatable {
        let tabID: UUID
        let pageTitle: String
        let pageURL: URL?
        let isPrivate: Bool
        let resources: [DetectedResource]
        let scanState: ResourceScanState
        let lastScanAt: Date?
        let errorMessage: String?
        let activationState: SniffingActivationState
        let hasStarted: Bool
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State
    private let store: TabResourceStore
    private let service: ResourceSniffingService
    private let requestContextProvider: RequestContextProvider
    private let blobImageDataProvider: @MainActor (URL) async -> Data?
    private let downloadCenter: DownloadCenter
    private let hlsMetadataResolver = HLSResourceMetadataResolver()
    private let hlsMetadataPermits = HLSMetadataPermitPool(limit: 2)
    private var observationToken: UUID?
    private var hlsMetadataTasks: [URL: Task<Void, Never>] = [:]
    private var attemptedHLSMetadataURLs: Set<URL> = []

    init(
        tabID: UUID,
        pageTitle: String?,
        pageURL: URL?,
        isPrivate: Bool,
        store: TabResourceStore,
        service: ResourceSniffingService,
        downloadCenter: DownloadCenter,
        requestContextProvider: @escaping RequestContextProvider,
        blobImageDataProvider: @escaping @MainActor (URL) async -> Data?
    ) {
        self.store = store
        self.service = service
        self.downloadCenter = downloadCenter
        self.requestContextProvider = requestContextProvider
        self.blobImageDataProvider = blobImageDataProvider
        let snapshot = store.snapshot(for: tabID)
        state = State(
            tabID: tabID,
            pageTitle: pageTitle.nilIfBlank ?? "新标签页",
            pageURL: pageURL,
            isPrivate: isPrivate,
            resources: snapshot.resources,
            scanState: snapshot.scanState,
            lastScanAt: snapshot.lastScanAt,
            errorMessage: snapshot.errorMessage,
            activationState: snapshot.activationState,
            hasStarted: snapshot.hasStarted
        )
    }

    func start() {
        guard observationToken == nil else {
            onStateChange?(state)
            return
        }
        observationToken = store.observe(tabID: state.tabID) {
            [weak self] snapshot in
            guard let self else { return }
            self.state = State(
                tabID: snapshot.tabID,
                pageTitle: self.state.pageTitle,
                pageURL: self.state.pageURL,
                isPrivate: self.state.isPrivate,
                resources: snapshot.resources,
                scanState: snapshot.scanState,
                lastScanAt: snapshot.lastScanAt,
                errorMessage: snapshot.errorMessage,
                activationState: snapshot.activationState,
                hasStarted: snapshot.hasStarted
            )
            self.onStateChange?(self.state)
            // Opening the panel must not trigger follow-up network work. HLS
            // metadata resolution is part of an active sniffing session only.
            if snapshot.activationState == .active {
                self.resolveHLSMetadataIfNeeded(in: snapshot.resources)
            }
        }
    }

    func stop() {
        store.removeObserver(observationToken)
        observationToken = nil
        hlsMetadataTasks.values.forEach { $0.cancel() }
        hlsMetadataTasks.removeAll()
    }

    func refresh() async throws {
        attemptedHLSMetadataURLs.removeAll()
        store.resetHLSMetadataResolutionClaims(tabID: state.tabID)
        if !state.activationState.isEnabled {
            try await service.enableSniffing(for: state.tabID)
            return
        }
        _ = try await service.scanResources(for: state.tabID)
    }

    /// Starts detection only after an explicit user action. The service's
    /// activation path performs one bounded manual scan as part of enabling
    /// the page bridge, so resources that were loaded before the panel opened
    /// are still eligible without reloading the WKWebView.
    func startSniffing() async throws {
        try await activateIfNeeded()
    }

    func activateIfNeeded() async throws {
        guard !state.activationState.isEnabled else { return }
        try await service.enableSniffing(for: state.tabID)
    }

    func disable() async {
        await service.disableSniffing(for: state.tabID)
    }

    func clearResults() {
        hlsMetadataTasks.values.forEach { $0.cancel() }
        hlsMetadataTasks.removeAll()
        attemptedHLSMetadataURLs.removeAll()
        service.resetResources(for: state.tabID)
    }

    var presentationState: ResourceSnifferPresentationState {
        store.presentationState(for: state.tabID)
    }

    func updatePresentationState(
        _ presentationState: ResourceSnifferPresentationState
    ) {
        store.updatePresentationState(
            presentationState,
            for: state.tabID
        )
    }

    func thumbnailRequest(for url: URL) async -> URLRequest {
        if url.scheme?.lowercased() == "data" {
            return URLRequest(url: url)
        }
        return await requestContextProvider(url).makeRequest(
            cachePolicy: .returnCacheDataElseLoad
        )
    }

    func thumbnailData(for url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "blob" else { return nil }
        return await blobImageDataProvider(url)
    }

    func requestContext(for resource: DetectedResource) async -> DownloadRequestContext {
        await requestContextProvider(resource.canonicalURL)
    }

    func startDownload(
        resource: DetectedResource,
        previewImageData: Data? = nil
    ) async throws -> DownloadCreationResult {
        let context = await requestContextProvider(resource.canonicalURL)
        return try await downloadCenter.createDownload(
            resource: resource,
            context: context,
            previewImageData: previewImageData
        )
    }

    private func resolveHLSMetadataIfNeeded(
        in resources: [DetectedResource]
    ) {
        for resource in resources where resource.resourceType == .hls {
            let url = resource.canonicalURL
            guard !attemptedHLSMetadataURLs.contains(url),
                  hlsMetadataTasks[url] == nil,
                  store.claimHLSMetadataResolution(
                    tabID: resource.tabID,
                    url: url
                  )
            else { continue }
            attemptedHLSMetadataURLs.insert(url)
            hlsMetadataTasks[url] = Task { [weak self] in
                guard let self else { return }
                defer { self.hlsMetadataTasks[url] = nil }
                await self.hlsMetadataPermits.acquire()
                guard !Task.isCancelled else {
                    await self.hlsMetadataPermits.release()
                    return
                }
                let context = await self.requestContextProvider(url)
                let enriched: DetectedResource?
                do {
                    enriched = try await self.hlsMetadataResolver.resolve(
                        resource: resource,
                        context: context
                    )
                } catch is CancellationError {
                    enriched = nil
                } catch {
                    // Metadata is supplemental. A failure must not hide a
                    // resource that the established downloader can still use.
                    enriched = nil
                }
                await self.hlsMetadataPermits.release()
                guard !Task.isCancelled, let enriched else { return }
                self.store.upsert([enriched], tabID: resource.tabID)
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let rawValue = self else {
            return nil
        }
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
