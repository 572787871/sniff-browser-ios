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
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State
    private let store: TabResourceStore
    private let service: ResourceSniffingService
    private let requestContextProvider: RequestContextProvider
    private let downloadCenter: DownloadCenter
    private var observationToken: UUID?

    init(
        tabID: UUID,
        pageTitle: String?,
        pageURL: URL?,
        isPrivate: Bool,
        store: TabResourceStore,
        service: ResourceSniffingService,
        downloadCenter: DownloadCenter,
        requestContextProvider: @escaping RequestContextProvider
    ) {
        self.store = store
        self.service = service
        self.downloadCenter = downloadCenter
        self.requestContextProvider = requestContextProvider
        state = State(
            tabID: tabID,
            pageTitle: pageTitle.nilIfBlank ?? "新标签页",
            pageURL: pageURL,
            isPrivate: isPrivate,
            resources: store.resources(for: tabID),
            scanState: store.snapshot(for: tabID).scanState,
            lastScanAt: store.snapshot(for: tabID).lastScanAt,
            errorMessage: store.snapshot(for: tabID).errorMessage,
            activationState: store.snapshot(for: tabID).activationState
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
                activationState: snapshot.activationState
            )
            self.onStateChange?(self.state)
        }
    }

    func stop() {
        store.removeObserver(observationToken)
        observationToken = nil
    }

    func refresh() async throws {
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
        service.resetResources(for: state.tabID)
    }

    func thumbnailRequest(for resource: DetectedResource) async -> URLRequest {
        await requestContextProvider(resource.canonicalURL).makeRequest(
            cachePolicy: .returnCacheDataElseLoad
        )
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
