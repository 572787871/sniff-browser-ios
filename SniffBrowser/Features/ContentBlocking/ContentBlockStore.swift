import Foundation

/// 内容拦截中心的本地 JSON 存储（延续项目 Application Support 原子写习惯）。
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
            .appendingPathComponent("ContentBlockingCenter", isDirectory: true)
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

/// 过滤器管理：官方规则列表元数据与启用状态。
@MainActor
final class FilterRuleManager {
    static let officialLists: [FilterListMeta] = [
        FilterListMeta(
            sourceKey: "2",
            name: "AdGuard Base",
            details: "EasyList + AdGuard English，全球主流站点广告过滤基础规则",
            author: "AdGuard",
            license: "GPL-3.0",
            version: "2.4.81.60",
            updatedAt: nil,
            ruleCount: 21_403,
            isEnabled: true,
            sortOrder: 0,
            category: .ads
        ),
        FilterListMeta(
            sourceKey: "3",
            name: "EasyPrivacy",
            details: "阻止追踪器、统计脚本与用户画像收集",
            author: "EasyList",
            license: "CC BY-SA 3.0",
            version: "1.0",
            updatedAt: nil,
            ruleCount: 8_421,
            isEnabled: true,
            sortOrder: 1,
            category: .privacy
        ),
        FilterListMeta(
            sourceKey: "4",
            name: "社交媒体过滤",
            details: "隐藏社交分享按钮、评论组件与推荐内容",
            author: "AdGuard",
            license: "GPL-3.0",
            version: "1.0",
            updatedAt: nil,
            ruleCount: 5_203,
            isEnabled: true,
            sortOrder: 2,
            category: .social
        ),
        FilterListMeta(
            sourceKey: "11",
            name: "AdGuard Mobile",
            details: "移动端网站专用广告规则",
            author: "AdGuard",
            license: "GPL-3.0",
            version: "1.3.12",
            updatedAt: nil,
            ruleCount: 6_205,
            isEnabled: true,
            sortOrder: 3,
            category: .ads
        ),
        FilterListMeta(
            sourceKey: "14",
            name: "AdBlock Warning Removal",
            details: "隐藏反广告拦截提示（含 Annoyances 系列）",
            author: "AdGuard",
            license: "GPL-3.0",
            version: "1.2.4",
            updatedAt: nil,
            ruleCount: 512,
            isEnabled: true,
            sortOrder: 4,
            category: .ads
        ),
        FilterListMeta(
            sourceKey: "224",
            name: "Chinese Filter",
            details: "EasyList China + AdGuard Chinese，中文网站广告与元素隐藏",
            author: "AdGuard",
            license: "GPL-3.0",
            version: "2.1.63.4",
            updatedAt: nil,
            ruleCount: 6_020,
            isEnabled: true,
            sortOrder: 5,
            category: .ads
        ),
    ]

    private let store: ContentBlockStore
    private let preferences = BrowserPreferences()
    private var lists: [FilterListMeta]

    init(store: ContentBlockStore) {
        self.store = store
        let saved = store.load([FilterListMeta].self, fileName: "filterLists.json")
        if let saved, !saved.isEmpty {
            var merged = saved
            for official in Self.officialLists
            where !merged.contains(where: { $0.sourceKey == official.sourceKey }) {
                merged.append(official)
            }
            lists = merged.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            lists = Self.officialLists
        }
    }

    func allLists() -> [FilterListMeta] {
        lists.sorted { $0.sortOrder < $1.sortOrder }
    }

    func lists(in category: FilterCategory) -> [FilterListMeta] {
        allLists().filter { $0.category == category }
    }

    func enabledSourceKeys() -> [String] {
        lists.filter(\.isEnabled).map(\.sourceKey)
    }

    func setEnabled(_ enabled: Bool, for sourceKey: String) {
        guard let index = lists.firstIndex(where: { $0.sourceKey == sourceKey }) else {
            return
        }
        lists[index].isEnabled = enabled
        persist()
    }

    func updateMetadata(sourceKey: String, version: String, ruleCount: Int, updatedAt: Date) {
        guard let index = lists.firstIndex(where: { $0.sourceKey == sourceKey }) else {
            return
        }
        lists[index].version = version
        lists[index].ruleCount = ruleCount
        lists[index].updatedAt = updatedAt
        persist()
    }

    func moveList(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        for index in lists.indices {
            lists[index].sortOrder = index
        }
        persist()
    }

    private func persist() {
        store.save(lists, fileName: "filterLists.json")
    }
}

/// 自定义规则管理。
@MainActor
final class CustomRuleManager {
    private let store: ContentBlockStore
    private var rules: [CustomRule]

    init(store: ContentBlockStore) {
        self.store = store
        rules = store.load([CustomRule].self, fileName: "customRules.json") ?? []
    }

    func allRules() -> [CustomRule] {
        rules.sorted { $0.sortOrder < $1.sortOrder }
    }

    func searchRules(query: String) -> [CustomRule] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allRules() }
        return allRules().filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.content.localizedCaseInsensitiveContains(trimmed)
        }
    }

    @discardableResult
    func addRule(_ rule: CustomRule) -> CustomRule {
        var rule = rule
        rule.sortOrder = rules.count
        rules.append(rule)
        persist()
        return rule
    }

    func updateRule(_ rule: CustomRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        reindex()
        persist()
    }

    func batchDelete(_ ids: [UUID]) {
        rules.removeAll { ids.contains($0.id) }
        reindex()
        persist()
    }

    func batchToggle(_ ids: [UUID], enabled: Bool) {
        for index in rules.indices where ids.contains(rules[index].id) {
            rules[index].isEnabled = enabled
        }
        persist()
    }

    func toggleFavorite(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isFavorite.toggle()
        persist()
    }

    @discardableResult
    func duplicateRule(id: UUID) -> CustomRule? {
        guard let source = rules.first(where: { $0.id == id }) else { return nil }
        let copy = CustomRule(
            name: source.name + " 副本",
            content: source.content,
            type: source.type,
            isEnabled: source.isEnabled,
            sortOrder: rules.count
        )
        rules.append(copy)
        persist()
        return copy
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        reindex()
        persist()
    }

    func recordHit(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].hitCount += 1
        rules[index].lastHitAt = Date()
        persist()
    }

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(allRules())
    }

    func importJSON(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode([CustomRule].self, from: data),
              !imported.isEmpty
        else {
            return false
        }
        for rule in imported {
            addRule(rule)
        }
        return true
    }

    private func reindex() {
        for index in rules.indices {
            rules[index].sortOrder = index
        }
    }

    private func persist() {
        store.save(rules, fileName: "customRules.json")
    }
}

/// 白名单管理：支持域名、子域名、通配符与正则。
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

    func searchPatterns(query: String) -> [WhitelistPattern] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allPatterns() }
        return patterns.filter { $0.pattern.localizedCaseInsensitiveContains(trimmed) }
    }

    func addPattern(_ pattern: WhitelistPattern) {
        patterns.append(pattern)
        persist()
    }

    func deletePattern(id: UUID) {
        patterns.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else { return }
        patterns[index].isEnabled = enabled
        persist()
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
        guard let imported = try? JSONDecoder().decode([WhitelistPattern].self, from: data) else {
            return false
        }
        patterns.append(contentsOf: imported)
        persist()
        return true
    }

    private func persist() {
        store.save(patterns, fileName: "whitelist.json")
    }
}

/// 性能统计：可观察数据（规则数/过滤器数）为真实值；拦截次数、流量、
/// 提速受 WebKit 公开 API 限制无法精确统计，按 0 存储并在 UI 显示说明。
@MainActor
final class StatisticsManager {
    private let store: ContentBlockStore
    private var record: StatsRecord

    init(store: ContentBlockStore) {
        self.store = store
        record = store.load(StatsRecord.self, fileName: "stats.json") ?? .empty
    }

    func current() -> StatsRecord {
        if record.dayKey != Self.todayKey() {
            record.dayKey = Self.todayKey()
            record.todayBlocked = 0
            persist()
        }
        return record
    }

    func updateRuleCount(_ count: Int, filterCount: Int) {
        record.ruleCount = count
        record.filterCount = filterCount
        persist()
    }

    func recordBlockedRequest() {
        if record.dayKey != Self.todayKey() {
            record.dayKey = Self.todayKey()
            record.todayBlocked = 0
        }
        record.todayBlocked += 1
        record.totalBlocked += 1
        persist()
    }

    func resetAll() {
        record = StatsRecord(
            todayBlocked: 0,
            totalBlocked: 0,
            savedTrafficMB: 0,
            averageSpeedUpPercent: 0,
            ruleCount: record.ruleCount,
            filterCount: record.filterCount,
            dayKey: Self.todayKey()
        )
        persist()
    }

    private func persist() {
        store.save(record, fileName: "stats.json")
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

/// 请求日志：只记录 WKNavigationDelegate 可观察的主框架导航。
@MainActor
final class RequestLogManager {
    private let store: ContentBlockStore
    private var entries: [RequestLogEntry]
    private let maxEntries = 2_000

    init(store: ContentBlockStore) {
        self.store = store
        entries = store.load([RequestLogEntry].self, fileName: "requestLog.json") ?? []
    }

    func allEntries() -> [RequestLogEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    func addEntry(_ entry: RequestLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        store.save(entries, fileName: "requestLog.json")
    }
}

/// 内容拦截中心门面：汇总各管理器并与 ContentBlockerService 协作。
@MainActor
final class ContentBlockManager {
    static let shared = ContentBlockManager()

    let filterManager: FilterRuleManager
    let customManager: CustomRuleManager
    let whitelistManager: WhitelistManager
    let statisticsManager: StatisticsManager
    let logManager: RequestLogManager

    private let store = ContentBlockStore()
    private var schedule: UpdateSchedule
    private var developerMode: Bool

    private init() {
        filterManager = FilterRuleManager(store: store)
        customManager = CustomRuleManager(store: store)
        whitelistManager = WhitelistManager(store: store)
        statisticsManager = StatisticsManager(store: store)
        logManager = RequestLogManager(store: store)
        schedule = store.load(UpdateSchedule.self, fileName: "schedule.json") ?? .fiveDays
        developerMode = store.load(Bool.self, fileName: "developerMode.json") ?? false
    }

    var updateSchedule: UpdateSchedule {
        schedule
    }

    func setUpdateSchedule(_ value: UpdateSchedule) {
        schedule = value
        store.save(value, fileName: "schedule.json")
    }

    var isDeveloperMode: Bool {
        developerMode
    }

    func setDeveloperMode(_ enabled: Bool) {
        developerMode = enabled
        store.save(enabled, fileName: "developerMode.json")
    }

    func restoreDefaults() {
        for fileName in [
            "filterLists.json",
            "customRules.json",
            "whitelist.json",
            "schedule.json",
            "developerMode.json",
        ] {
            store.remove(fileName: fileName)
        }
    }

    func exportCustomRulesJSON() -> Data? {
        customManager.exportJSON()
    }

    func importCustomRulesJSON(_ data: Data) -> Bool {
        customManager.importJSON(data)
    }
}
