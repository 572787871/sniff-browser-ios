import Foundation

extension Notification.Name {
    static let favoriteItemsDidChange =
        Notification.Name("com.sniffbrowser.favoriteItemsDidChange")
}

struct FavoriteActionState: Equatable, Sendable {
    let isEnabled: Bool
    let isFavorite: Bool

    var title: String {
        isFavorite ? "取消收藏" : "添加收藏"
    }

    var systemImageName: String {
        isFavorite ? "star.fill" : "star"
    }
}

enum FavoriteToggleResult: Equatable, Sendable {
    case added(FavoriteItem)
    case removed(FavoriteItem)
}

enum FavoriteServiceError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "当前页面无法收藏。"
    }
}

final class FavoriteService {
    static let shared = FavoriteService()
    static let changeCountUserInfoKey = "count"

    private let repository: FavoriteRepositoryProtocol
    private let notificationCenter: NotificationCenter
    private let now: () -> Date

    init(
        repository: FavoriteRepositoryProtocol = FavoriteRepository(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func allFavorites() throws -> [FavoriteItem] {
        try repository.allItems().sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func count() throws -> Int {
        try repository.allItems().count
    }

    func isFavorite(_ url: URL?) throws -> Bool {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            return false
        }
        return try repository.item(for: normalizedURL) != nil
    }

    func actionState(for url: URL?) throws -> FavoriteActionState {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            return FavoriteActionState(isEnabled: false, isFavorite: false)
        }
        return FavoriteActionState(
            isEnabled: true,
            isFavorite: try repository.item(for: normalizedURL) != nil
        )
    }

    @discardableResult
    func addFavorite(
        title: String?,
        url: URL?,
        faviconURL: URL? = nil
    ) throws -> FavoriteItem {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url),
              let host = normalizedURL.host
        else {
            throw FavoriteServiceError.invalidURL
        }
        let date = now()
        let item = FavoriteItem(
            title: title ?? host,
            url: normalizedURL,
            host: host,
            createdAt: date,
            updatedAt: date,
            faviconURL: faviconURL
        )
        let savedItem = try repository.save(item)
        postChange()
        return savedItem
    }

    @discardableResult
    func removeFavorite(for url: URL?) throws -> FavoriteItem? {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            throw FavoriteServiceError.invalidURL
        }
        let removedItem = try repository.delete(url: normalizedURL)
        if removedItem != nil {
            postChange()
        }
        return removedItem
    }

    @discardableResult
    func removeFavorite(id: UUID) throws -> FavoriteItem? {
        let removedItem = try repository.delete(id: id)
        if removedItem != nil {
            postChange()
        }
        return removedItem
    }

    @discardableResult
    func restoreFavorite(_ item: FavoriteItem) throws -> FavoriteItem {
        let restoredItem = try repository.save(item)
        postChange()
        return restoredItem
    }

    @discardableResult
    func toggleFavorite(
        title: String?,
        url: URL?,
        faviconURL: URL? = nil
    ) throws -> FavoriteToggleResult {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            throw FavoriteServiceError.invalidURL
        }
        if let removedItem = try repository.delete(url: normalizedURL) {
            postChange()
            return .removed(removedItem)
        }
        return .added(
            try addFavorite(
                title: title,
                url: normalizedURL,
                faviconURL: faviconURL
            )
        )
    }

    @discardableResult
    func observeChanges(
        using handler: @escaping () -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: .favoriteItemsDidChange,
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
            name: .favoriteItemsDidChange,
            object: self,
            userInfo: userInfo
        )
    }
}
