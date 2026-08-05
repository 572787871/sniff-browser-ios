import Foundation

protocol HistoryRepositoryProtocol: AnyObject {
    func allItems() throws -> [HistoryItem]

    @discardableResult
    func save(_ item: HistoryItem) throws -> HistoryItem

    @discardableResult
    func delete(id: UUID) throws -> HistoryItem?

    func deleteAll() throws
}

enum HistoryRepositoryError: LocalizedError {
    case invalidURL
    case invalidStoredItem
    case readFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "该网页地址无法记录。"
        case .invalidStoredItem:
            return "历史记录数据已损坏，暂时无法读取。"
        case let .readFailed(error):
            return "读取历史记录失败：\(error.localizedDescription)"
        case let .writeFailed(error):
            return "保存历史记录失败：\(error.localizedDescription)"
        }
    }
}

enum HistoryURLNormalizer {
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

final class HistoryRepository: HistoryRepositoryProtocol {
    private let fileManager: FileManager
    private let fileURL: URL
    private let lock = NSLock()
    private var cachedItems: [HistoryItem]?

    convenience init(fileManager: FileManager = .default) {
        let applicationSupportDirectory =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let fileURL = applicationSupportDirectory
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
        self.init(fileURL: fileURL, fileManager: fileManager)
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func allItems() throws -> [HistoryItem] {
        try withLock {
            try loadItemsLocked()
        }
    }

    @discardableResult
    func save(_ item: HistoryItem) throws -> HistoryItem {
        guard let normalizedURL = HistoryURLNormalizer.normalize(item.url),
              let host = normalizedURL.host
        else {
            throw HistoryRepositoryError.invalidURL
        }

        return try withLock {
            var items = try loadItemsLocked()
            let savedItem = HistoryItem(
                id: item.id,
                title: normalizedTitle(item.title, fallback: host),
                url: normalizedURL,
                host: host,
                visitedAt: item.visitedAt
            )
            if let existingIndex = items.firstIndex(where: { $0.id == savedItem.id }) {
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
    func delete(id: UUID) throws -> HistoryItem? {
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

    func deleteAll() throws {
        try withLock {
            let items: [HistoryItem] = []
            try persistLocked(items)
            cachedItems = items
        }
    }

    private func loadItemsLocked() throws -> [HistoryItem] {
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
            throw HistoryRepositoryError.readFailed(error)
        }

        let decodedItems: [HistoryItem]
        do {
            decodedItems = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            throw HistoryRepositoryError.readFailed(error)
        }

        var uniqueItems: [UUID: HistoryItem] = [:]
        for item in decodedItems {
            guard let normalizedURL = HistoryURLNormalizer.normalize(item.url),
                  let host = normalizedURL.host
            else {
                throw HistoryRepositoryError.invalidStoredItem
            }
            let normalizedItem = HistoryItem(
                id: item.id,
                title: normalizedTitle(item.title, fallback: host),
                url: normalizedURL,
                host: host,
                visitedAt: item.visitedAt
            )
            if let existing = uniqueItems[item.id],
               existing.visitedAt >= normalizedItem.visitedAt {
                continue
            }
            uniqueItems[item.id] = normalizedItem
        }

        let items = Array(uniqueItems.values)
        cachedItems = items
        return items
    }

    private func persistLocked(_ items: [HistoryItem]) throws {
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
            throw HistoryRepositoryError.writeFailed(error)
        }
    }

    private func normalizedTitle(_ title: String, fallback: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallback : trimmedTitle
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
