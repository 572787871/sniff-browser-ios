import Foundation

@MainActor
final class ResourceSnifferViewModel {
    struct State: Equatable {
        let tabID: UUID
        let pageTitle: String
        let pageURL: URL?
        let isPrivate: Bool
        let resources: [DetectedResource]
        let scanState: ResourceScanState
        let lastScanAt: Date?
        let errorMessage: String?
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State
    private let store: TabResourceStore
    private let service: ResourceSniffingService
    private var observationToken: UUID?

    init(
        tabID: UUID,
        pageTitle: String?,
        pageURL: URL?,
        isPrivate: Bool,
        store: TabResourceStore,
        service: ResourceSniffingService
    ) {
        self.store = store
        self.service = service
        state = State(
            tabID: tabID,
            pageTitle: pageTitle.nilIfBlank ?? "新标签页",
            pageURL: pageURL,
            isPrivate: isPrivate,
            resources: store.resources(for: tabID),
            scanState: store.snapshot(for: tabID).scanState,
            lastScanAt: store.snapshot(for: tabID).lastScanAt,
            errorMessage: store.snapshot(for: tabID).errorMessage
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
                errorMessage: snapshot.errorMessage
            )
            self.onStateChange?(self.state)
        }
    }

    func stop() {
        store.removeObserver(observationToken)
        observationToken = nil
    }

    func refresh() async throws {
        _ = try await service.scanResources(for: state.tabID)
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
