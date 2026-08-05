import Foundation

extension Notification.Name {
    static let historyItemsDidChange =
        Notification.Name("com.sniffbrowser.historyItemsDidChange")
}

final class HistoryService {
    static let shared = HistoryService()
    static let changeCountUserInfoKey = "count"

    /// 同一网址在短时间内重复访问（如刷新）时，
    /// 更新最近一条记录而不是不断新增重复条目。
    static let duplicateVisitWindow: TimeInterval = 30

    private let repository: HistoryRepositoryProtocol
    private let notificationCenter: NotificationCenter
    private let now: () -> Date

    init(
        repository: HistoryRepositoryProtocol = HistoryRepository(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func allEntries() throws -> [HistoryItem] {
        try repository.allItems().sorted {
            if $0.visitedAt == $1.visitedAt {
                return $0.url.absoluteString < $1.url.absoluteString
            }
            return $0.visitedAt > $1.visitedAt
        }
    }

    func count() throws -> Int {
        try repository.allItems().count
    }

    @discardableResult
    func recordVisit(title: String?, url: URL?) throws -> HistoryItem? {
        guard let normalizedURL = HistoryURLNormalizer.normalize(url),
              let host = normalizedURL.host
        else {
            return nil
        }
        let date = now()
        let fallbackTitle = host
        let entries = try repository.allItems()
        let latest = entries.max(by: { $0.visitedAt < $1.visitedAt })

        if let latest,
           latest.url == normalizedURL,
           date.timeIntervalSince(latest.visitedAt) <= Self.duplicateVisitWindow {
            let updatedItem = HistoryItem(
                id: latest.id,
                title: normalizedTitle(title, fallback: fallbackTitle),
                url: normalizedURL,
                host: host,
                visitedAt: date
            )
            let savedItem = try repository.save(updatedItem)
            postChange()
            return savedItem
        }

        let item = HistoryItem(
            title: normalizedTitle(title, fallback: fallbackTitle),
            url: normalizedURL,
            host: host,
            visitedAt: date
        )
        let savedItem = try repository.save(item)
        postChange()
        return savedItem
    }

    @discardableResult
    func removeEntry(id: UUID) throws -> HistoryItem? {
        let removedItem = try repository.delete(id: id)
        if removedItem != nil {
            postChange()
        }
        return removedItem
    }

    func clearAll() throws {
        try repository.deleteAll()
        postChange()
    }

    @discardableResult
    func observeChanges(
        using handler: @escaping () -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: .historyItemsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    func removeChangeObserver(_ observer: NSObjectProtocol) {
        notificationCenter.removeObserver(observer)
    }

    private func postChange() {
        var userInfo: [AnyHashable: Any]?
        if let updatedCount = try? count() {
            userInfo = [Self.changeCountUserInfoKey: updatedCount]
        }
        notificationCenter.post(
            name: .historyItemsDidChange,
            object: self,
            userInfo: userInfo
        )
    }

    private func normalizedTitle(_ title: String?, fallback: String) -> String {
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallback : trimmedTitle
    }
}
