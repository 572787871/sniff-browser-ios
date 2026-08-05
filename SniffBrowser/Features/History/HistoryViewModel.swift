import Foundation

struct HistoryDaySection: Equatable, Sendable {
    let title: String
    let items: [HistoryItem]
}

struct HistoryViewState: Equatable, Sendable {
    let sections: [HistoryDaySection]
    let totalCount: Int
    let searchQuery: String

    static let empty = HistoryViewState(
        sections: [],
        totalCount: 0,
        searchQuery: ""
    )

    var isFiltering: Bool {
        !searchQuery.isEmpty
    }
}

@MainActor
final class HistoryViewModel {
    private(set) var state = HistoryViewState.empty {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((HistoryViewState) -> Void)?
    var onError: ((Error) -> Void)?

    private let service: HistoryService
    private var allItems: [HistoryItem] = []
    private var changeObserver: NSObjectProtocol?

    init(service: HistoryService = .shared) {
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
            allItems = try service.allEntries()
            publishState()
        } catch {
            onError?(error)
        }
    }

    func updateSearchQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.searchQuery != trimmedQuery else { return }
        state = HistoryViewState(
            sections: sections(matching: trimmedQuery),
            totalCount: allItems.count,
            searchQuery: trimmedQuery
        )
    }

    @discardableResult
    func remove(_ item: HistoryItem) -> Bool {
        do {
            let removedItem = try service.removeEntry(id: item.id)
            allItems = try service.allEntries()
            publishState()
            return removedItem != nil
        } catch {
            onError?(error)
            return false
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        do {
            try service.clearAll()
            allItems = []
            publishState()
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    private func publishState() {
        state = HistoryViewState(
            sections: sections(matching: state.searchQuery),
            totalCount: allItems.count,
            searchQuery: state.searchQuery
        )
    }

    private func sections(matching query: String) -> [HistoryDaySection] {
        let entries = query.isEmpty ? allItems : allItems.filter { item in
            let normalizedQuery = searchable(query)
            return searchable(item.title).contains(normalizedQuery)
                || searchable(item.host).contains(normalizedQuery)
                || searchable(item.url.absoluteString).contains(normalizedQuery)
        }
        guard !entries.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ) ?? today

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy年M月d日"

        let grouped = Dictionary(grouping: entries) { item -> String in
            let startOfDay = calendar.startOfDay(for: item.visitedAt)
            if startOfDay == today {
                return "今天"
            }
            if startOfDay == yesterday {
                return "昨天"
            }
            return dateFormatter.string(from: item.visitedAt)
        }
        return grouped.keys
            .sorted { lhs, rhs in
                let lhsStart = calendar.startOfDay(for: grouped[lhs]?.first?.visitedAt ?? now)
                let rhsStart = calendar.startOfDay(for: grouped[rhs]?.first?.visitedAt ?? now)
                return lhsStart > rhsStart
            }
            .map { dayTitle in
                HistoryDaySection(
                    title: dayTitle,
                    items: grouped[dayTitle] ?? []
                )
            }
    }

    private func searchable(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
