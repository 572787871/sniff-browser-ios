import Foundation

protocol FavoriteRepositoryProtocol: AnyObject {
    func allItems() throws -> [FavoriteItem]
    func item(for url: URL) throws -> FavoriteItem?

    @discardableResult
    func save(_ item: FavoriteItem) throws -> FavoriteItem

    @discardableResult
    func delete(id: UUID) throws -> FavoriteItem?

    @discardableResult
    func delete(url: URL) throws -> FavoriteItem?
}

enum FavoriteRepositoryError: LocalizedError {
    case invalidURL
    case invalidStoredItem
    case readFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "该网页地址无法收藏。"
        case .invalidStoredItem:
            return "收藏数据已损坏，暂时无法读取。"
        case let .readFailed(error):
            return "读取收藏失败：\(error.localizedDescription)"
        case let .writeFailed(error):
            return "保存收藏失败：\(error.localizedDescription)"
        }
    }
}

enum FavoriteURLNormalizer {
    static func normalize(_ url: URL?) -> URL? {
        guard let url,
              var components = URLComponents(
                url: url.standardized,
                resolvingAgainstBaseURL: false
              ),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let rawHost = components.host?.lowercased()
        else {
            return nil
        }

        let normalizedHost = rawHost.hasSuffix(".")
            ? String(rawHost.dropLast())
            : rawHost
        guard !normalizedHost.isEmpty,
              !normalizedHost.hasPrefix("."),
              !normalizedHost.hasSuffix("."),
              !normalizedHost.contains("..")
        else {
            return nil
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return nil
        }

        components.scheme = scheme
        components.host = normalizedHost
        components.fragment = nil

        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }

        guard let normalized = components.url,
              normalized.host?.isEmpty == false
        else {
            return nil
        }
        return normalized
    }
}

final class FavoriteRepository: FavoriteRepositoryProtocol {
    private let fileManager: FileManager
    private let fileURL: URL
    private let lock = NSLock()
    private var cachedItems: [FavoriteItem]?

    convenience init(fileManager: FileManager = .default) {
        let applicationSupportDirectory =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let fileURL = applicationSupportDirectory
            .appendingPathComponent("Favorites", isDirectory: true)
            .appendingPathComponent("favorites.json", isDirectory: false)
        self.init(fileURL: fileURL, fileManager: fileManager)
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func allItems() throws -> [FavoriteItem] {
        try withLock {
            try loadItemsLocked()
        }
    }

    func item(for url: URL) throws -> FavoriteItem? {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            return nil
        }
        return try withLock {
            try loadItemsLocked().first { $0.url == normalizedURL }
        }
    }

    @discardableResult
    func save(_ item: FavoriteItem) throws -> FavoriteItem {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(item.url),
              let host = normalizedURL.host
        else {
            throw FavoriteRepositoryError.invalidURL
        }

        return try withLock {
            var items = try loadItemsLocked()
            let existingIndex = items.firstIndex { $0.url == normalizedURL }
            let existing = existingIndex.map { items[$0] }
            let savedItem = FavoriteItem(
                id: existing?.id ?? item.id,
                title: normalizedTitle(item.title, fallback: host),
                url: normalizedURL,
                host: host,
                createdAt: existing?.createdAt ?? item.createdAt,
                updatedAt: max(
                    item.updatedAt,
                    existing?.updatedAt ?? item.createdAt
                ),
                faviconURL: validFaviconURL(item.faviconURL) ?? existing?.faviconURL
            )

            if let existingIndex {
                items[existingIndex] = savedItem
            } else {
                items.append(savedItem)
            }
            try persistLocked(items)
            cachedItems = items
            return savedItem
        }
    }

    @discardableResult
    func delete(id: UUID) throws -> FavoriteItem? {
        try withLock {
            var items = try loadItemsLocked()
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let removedItem = items.remove(at: index)
            try persistLocked(items)
            cachedItems = items
            return removedItem
        }
    }

    @discardableResult
    func delete(url: URL) throws -> FavoriteItem? {
        guard let normalizedURL = FavoriteURLNormalizer.normalize(url) else {
            return nil
        }
        return try withLock {
            var items = try loadItemsLocked()
            guard let index = items.firstIndex(where: { $0.url == normalizedURL }) else {
                return nil
            }
            let removedItem = items.remove(at: index)
            try persistLocked(items)
            cachedItems = items
            return removedItem
        }
    }

    private func loadItemsLocked() throws -> [FavoriteItem] {
        if let cachedItems {
            return cachedItems
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedItems = []
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw FavoriteRepositoryError.readFailed(error)
        }

        let decodedItems: [FavoriteItem]
        do {
            decodedItems = try JSONDecoder().decode([FavoriteItem].self, from: data)
        } catch {
            throw FavoriteRepositoryError.readFailed(error)
        }

        var uniqueItems: [URL: FavoriteItem] = [:]
        for item in decodedItems {
            guard let normalizedURL = FavoriteURLNormalizer.normalize(item.url),
                  let host = normalizedURL.host
            else {
                throw FavoriteRepositoryError.invalidStoredItem
            }
            let normalizedItem = FavoriteItem(
                id: item.id,
                title: normalizedTitle(item.title, fallback: host),
                url: normalizedURL,
                host: host,
                createdAt: item.createdAt,
                updatedAt: max(item.updatedAt, item.createdAt),
                faviconURL: validFaviconURL(item.faviconURL)
            )
            if let existing = uniqueItems[normalizedURL],
               existing.updatedAt >= normalizedItem.updatedAt {
                continue
            }
            uniqueItems[normalizedURL] = normalizedItem
        }

        let items = Array(uniqueItems.values)
        cachedItems = items
        return items
    }

    private func persistLocked(_ items: [FavoriteItem]) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FavoriteRepositoryError.writeFailed(error)
        }
    }

    private func normalizedTitle(_ title: String, fallback: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallback : trimmedTitle
    }

    private func validFaviconURL(_ url: URL?) -> URL? {
        FavoriteURLNormalizer.normalize(url)
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
