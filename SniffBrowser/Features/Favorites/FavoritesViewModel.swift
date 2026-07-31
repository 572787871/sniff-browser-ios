import Foundation

struct FavoritesViewState: Equatable, Sendable {
    let items: [FavoriteItem]
    let totalCount: Int
    let searchQuery: String

    static let empty = FavoritesViewState(
        items: [],
        totalCount: 0,
        searchQuery: ""
    )

    var isFiltering: Bool {
        !searchQuery.isEmpty
    }
}

@MainActor
final class FavoritesViewModel {
    private(set) var state = FavoritesViewState.empty {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((FavoritesViewState) -> Void)?
    var onError: ((Error) -> Void)?

    private let service: FavoriteService
    private var allItems: [FavoriteItem] = []
    private var changeObserver: NSObjectProtocol?

    init(service: FavoriteService = .shared) {
        self.service = service
        changeObserver = service.observeChanges { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        if let changeObserver {
            service.removeChangeObserver(changeObserver)
        }
    }

    func reload() {
        do {
            allItems = try service.allFavorites()
            publishState()
        } catch {
            onError?(error)
        }
    }

    func updateSearchQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.searchQuery != trimmedQuery else { return }
        state = FavoritesViewState(
            items: filteredItems(matching: trimmedQuery),
            totalCount: allItems.count,
            searchQuery: trimmedQuery
        )
    }

    @discardableResult
    func remove(_ item: FavoriteItem) -> Bool {
        do {
            let removedItem = try service.removeFavorite(id: item.id)
            allItems = try service.allFavorites()
            publishState()
            return removedItem != nil
        } catch {
            onError?(error)
            return false
        }
    }

    private func publishState() {
        state = FavoritesViewState(
            items: filteredItems(matching: state.searchQuery),
            totalCount: allItems.count,
            searchQuery: state.searchQuery
        )
    }

    private func filteredItems(matching query: String) -> [FavoriteItem] {
        guard !query.isEmpty else { return allItems }
        let normalizedQuery = searchable(query)
        return allItems.filter { item in
            searchable(item.title).contains(normalizedQuery)
                || searchable(item.host).contains(normalizedQuery)
                || searchable(item.url.absoluteString).contains(normalizedQuery)
        }
    }

    private func searchable(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
