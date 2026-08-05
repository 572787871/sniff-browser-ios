import Foundation

/// 内容拦截中心的本地 JSON 存储。
final class ContentBlockStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        directoryURL = applicationSupport
            .appendingPathComponent("ContentBlocking", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load<T: Decodable>(_ type: T.Type, fileName: String) -> T? {
        guard let data = try? Data(contentsOf: url(fileName)) else {
            return nil
        }
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, fileName: String) {
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(fileName), options: .atomic)
    }

    func remove(fileName: String) {
        try? fileManager.removeItem(at: url(fileName))
    }

    private func url(_ fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }
}

/// 内置规则列表管理。
@MainActor
final class FilterRuleManager {
    static let officialLists: [FilterListMeta] = [
        FilterListMeta(
            sourceKey: "2",
            name: "AdGuard Base",
            details: "全球主流站点广告过滤基础规则",
            ruleCount: 21_403,
            isEnabled: true,
            sortOrder: 0
        ),
        FilterListMeta(
            sourceKey: "3",
            name: "EasyPrivacy",
            details: "阻止追踪器与统计脚本",
            ruleCount: 8_421,
            isEnabled: true,
            sortOrder: 1
        ),
        FilterListMeta(
            sourceKey: "4",
            name: "社交媒体过滤",
            details: "隐藏分享与社交组件",
            ruleCount: 5_203,
            isEnabled: true,
            sortOrder: 2
        ),
        FilterListMeta(
            sourceKey: "11",
            name: "AdGuard Mobile",
            details: "移动端网站广告规则",
            ruleCount: 6_205,
            isEnabled: true,
            sortOrder: 3
        ),
        FilterListMeta(
            sourceKey: "14",
            name: "AdBlock Warning Removal",
            details: "隐藏反广告拦截提示",
            ruleCount: 512,
            isEnabled: true,
            sortOrder: 4
        ),
        FilterListMeta(
            sourceKey: "224",
            name: "Chinese Filter",
            details: "中文网站广告与元素隐藏",
            ruleCount: 6_020,
            isEnabled: true,
            sortOrder: 5
        ),
    ]

    private let store: ContentBlockStore
    private var lists: [FilterListMeta]

    init(store: ContentBlockStore) {
        self.store = store
        let saved = store.load([FilterListMeta].self, fileName: "filterLists.json")
        if let saved, !saved.isEmpty {
            lists = saved.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            lists = Self.officialLists
        }
    }

    func allLists() -> [FilterListMeta] {
        lists.sorted { $0.sortOrder < $1.sortOrder }
    }

    func enabledSourceKeys() -> [String] {
        lists.filter(\.isEnabled).map(\.sourceKey)
    }

    func setEnabled(_ enabled: Bool, for sourceKey: String) {
        guard let index = lists.firstIndex(where: { $0.sourceKey == sourceKey }) else {
            return
        }
        lists[index].isEnabled = enabled
        store.save(lists, fileName: "filterLists.json")
    }

    func updateRuleCount(sourceKey: String, count: Int) {
        guard let index = lists.firstIndex(where: { $0.sourceKey == sourceKey }) else {
            return
        }
        lists[index].ruleCount = count
        store.save(lists, fileName: "filterLists.json")
    }

    func restoreDefaults() {
        lists = Self.officialLists
        store.save(lists, fileName: "filterLists.json")
    }
}

/// 导入的自定义规则管理。
@MainActor
final class CustomRuleManager {
    private let store: ContentBlockStore
    private var rules: [CustomRule]

    init(store: ContentBlockStore) {
        self.store = store
        rules = store.load([CustomRule].self, fileName: "customRules.json") ?? []
    }

    func allRules() -> [CustomRule] {
        rules
    }

    @discardableResult
    func addRule(_ rule: CustomRule) -> CustomRule {
        rules.append(rule)
        store.save(rules, fileName: "customRules.json")
        return rule
    }

    func importLines(_ lines: [String]) -> Int {
        var imported = 0
        for line in lines {
            let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty,
                  !content.hasPrefix("!"),
                  !content.hasPrefix("[")
            else {
                continue
            }
            addRule(CustomRule(content: content))
            imported += 1
        }
        return imported
    }

    func importJSON(_ data: Data) -> Int {
        if let rules = try? JSONDecoder().decode([CustomRule].self, from: data) {
            for rule in rules {
                addRule(rule)
            }
            return rules.count
        }
        if let strings = try? JSONDecoder().decode([String].self, from: data) {
            return importLines(strings)
        }
        return 0
    }

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(rules)
    }

    func clear() {
        rules = []
        store.save(rules, fileName: "customRules.json")
    }
}

/// 白名单管理。
@MainActor
final class WhitelistManager {
    private let store: ContentBlockStore
    private var patterns: [WhitelistPattern]

    init(store: ContentBlockStore) {
        self.store = store
        patterns = store.load([WhitelistPattern].self, fileName: "whitelist.json") ?? []
    }

    func allPatterns() -> [WhitelistPattern] {
        patterns
    }

    func addPattern(_ pattern: WhitelistPattern) {
        patterns.append(pattern)
        store.save(patterns, fileName: "whitelist.json")
    }

    func deletePattern(id: UUID) {
        patterns.removeAll { $0.id == id }
        store.save(patterns, fileName: "whitelist.json")
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else { return }
        patterns[index].isEnabled = enabled
        store.save(patterns, fileName: "whitelist.json")
    }

    func matches(_ host: String?) -> Bool {
        guard let host else { return false }
        let normalized = host.lowercased()
        return patterns.contains { pattern in
            guard pattern.isEnabled else { return false }
            switch pattern.matchType {
            case .domain:
                return normalized == pattern.pattern.lowercased()
            case .subdomain:
                let domain = pattern.pattern.lowercased()
                return normalized == domain || normalized.hasSuffix("." + domain)
            case .wildcard:
                let regex = NSRegularExpression.escapedPattern(
                    for: pattern.pattern.lowercased()
                )
                    .replacingOccurrences(of: "\\*", with: ".*")
                return normalized.range(
                    of: "^\(regex)$",
                    options: .regularExpression
                ) != nil
            case .regex:
                return normalized.range(
                    of: pattern.pattern,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            }
        }
    }

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(patterns)
    }

    func importJSON(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(
            [WhitelistPattern].self,
            from: data
        ) else {
            return false
        }
        patterns.append(contentsOf: imported)
        store.save(patterns, fileName: "whitelist.json")
        return true
    }

    func clear() {
        patterns = []
        store.save(patterns, fileName: "whitelist.json")
    }
}

/// 内容拦截门面。
@MainActor
final class ContentBlockManager {
    static let shared = ContentBlockManager()

    let filterManager: FilterRuleManager
    let customManager: CustomRuleManager
    let whitelistManager: WhitelistManager

    private init() {
        let store = ContentBlockStore()
        filterManager = FilterRuleManager(store: store)
        customManager = CustomRuleManager(store: store)
        whitelistManager = WhitelistManager(store: store)
    }
}
