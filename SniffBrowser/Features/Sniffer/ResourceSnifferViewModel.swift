import Foundation

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
            self.resolveHLSMetadataIfNeeded(in: snapshot.resources)
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
        if !state.activationState.isEnabled {
            try await service.enableSniffing(for: state.tabID)
            return
        }
        _ = try await service.scanResources(for: state.tabID)
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

    func thumbnailRequest(for url: URL) async -> URLRequest {
        await requestContextProvider(url).makeRequest(
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
        resource: DetectedResource
    ) async throws -> DownloadCreationResult {
        let context = await requestContextProvider(resource.canonicalURL)
        return try await downloadCenter.createDownload(
            resource: resource,
            context: context
        )
    }

    private func resolveHLSMetadataIfNeeded(
        in resources: [DetectedResource]
    ) {
        for resource in resources where resource.resourceType == .hls {
            let url = resource.canonicalURL
            guard !attemptedHLSMetadataURLs.contains(url),
                  hlsMetadataTasks[url] == nil
            else { continue }
            attemptedHLSMetadataURLs.insert(url)
            hlsMetadataTasks[url] = Task { [weak self] in
                guard let self else { return }
                defer { self.hlsMetadataTasks[url] = nil }
                let context = await self.requestContextProvider(url)
                do {
                    let enriched = try await self.hlsMetadataResolver.resolve(
                        resource: resource,
                        context: context
                    )
                    guard !Task.isCancelled else { return }
                    self.store.upsert([enriched], tabID: resource.tabID)
                } catch is CancellationError {
                    return
                } catch {
                    // Metadata is supplemental. A failure must not hide a
                    // resource that the established downloader can still use.
                }
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
