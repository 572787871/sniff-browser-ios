import WebKit

extension Notification.Name {
    static let contentBlockerDidChange =
        Notification.Name("com.sniffbrowser.contentBlockerDidChange")
}

extension ContentBlockerService {
    /// 通知 userInfo 中控制是否重载当前页面的键。
    static let reloadActivePageUserInfoKey = "reloadActivePage"
}

enum ContentBlockerUpdateError: LocalizedError {
    case alreadyUpdating
    case invalidResponse
    case invalidFilter
    case compileFailed

    var errorDescription: String? {
        switch self {
        case .alreadyUpdating:
            return "过滤规则正在更新中，请稍候。"
        case .invalidResponse:
            return "无法下载最新过滤规则，请检查网络后重试。"
        case .invalidFilter:
            return "下载的过滤规则无法解析。"
        case .compileFailed:
            return "最新过滤规则编译失败，已保留当前规则。"
        }
    }
}

/// 广告过滤服务：加载内置或已下载的规则，编译成 `WKContentRuleList`，
/// 并按标签页与白名单决定是否应用到对应 WebView；支持手动更新规则。
@MainActor
final class ContentBlockerService {
    static let shared = ContentBlockerService()
    /// AdGuard 优化版规则源（Safari 格式）。
    static let sourceDefinitions: [(key: String, url: URL)] = [
        ("2", URL(string: "https://filters.adtidy.org/extension/safari/filters/2_optimized.txt")!),
        ("3", URL(string: "https://filters.adtidy.org/extension/safari/filters/3_optimized.txt")!),
        ("4", URL(string: "https://filters.adtidy.org/extension/safari/filters/4_optimized.txt")!),
        ("11", URL(string: "https://filters.adtidy.org/extension/safari/filters/11_optimized.txt")!),
        ("14", URL(string: "https://filters.adtidy.org/extension/safari/filters/14_optimized.txt")!),
        ("224", URL(string: "https://filters.adtidy.org/extension/safari/filters/224_optimized.txt")!),
    ]
    /// Safari 端点不可用时的备用源（AdGuard iOS 原始列表）。
    static let iosFilterURLs: [String: URL] = [
        "2": URL(string: "https://filters.adtidy.org/ios/filters/2.txt")!,
        "3": URL(string: "https://filters.adtidy.org/ios/filters/3.txt")!,
        "4": URL(string: "https://filters.adtidy.org/ios/filters/4.txt")!,
        "11": URL(string: "https://filters.adtidy.org/ios/filters/11.txt")!,
        "14": URL(string: "https://filters.adtidy.org/ios/filters/14.txt")!,
        "224": URL(string: "https://filters.adtidy.org/ios/filters/224.txt")!,
    ]
    static let primaryIdentifier = "com.sniffbrowser.adblock"

    private struct RuleChunk {
        let identifier: String
        let ruleList: WKContentRuleList
        let ruleCount: Int
    }

    private struct RuleMetadata: Codable {
        let updatedAt: Date
        let version: String
        let ruleCount: Int
    }

    private let preferences = BrowserPreferences()
    private let ruleListStore = WKContentRuleListStore.default()
    private let chunkSize = 2_000
    private let fileManager = FileManager.default
    private var chunks: [RuleChunk] = []
    private var cosmeticRules: [(domains: [String]?, selector: String)] = []
    private var addedRuleListsByTab: [UUID: Set<String>] = [:]
    private var loadTask: Task<Void, Never>?

    private lazy var supportDirectory: URL = {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("ContentBlocker", isDirectory: true)
    }()

    private var downloadedRulesURL: URL {
        supportDirectory.appendingPathComponent(
            "content-blocker-rules.json",
            isDirectory: false
        )
    }

    private var metadataURL: URL {
        supportDirectory.appendingPathComponent(
            "rules-metadata.json",
            isDirectory: false
        )
    }

    private var sourcesDirectory: URL {
        supportDirectory.appendingPathComponent("sources", isDirectory: true)
    }

    private(set) var isReady = false
    private(set) var ruleCount = 0
    private(set) var lastLoadError: String?
    private(set) var updatedAt: Date?
    private(set) var filterVersion: String?
    private(set) var isUpdating = false
    private static let maxGlobalCountSelectors = 350

    var isEnabled: Bool {
        preferences.contentBlockingEnabled
    }

    var whitelistedHosts: [String] {
        preferences.contentBlockingWhitelist
    }

    var updateDescription: String {
        if isUpdating {
            return "正在更新…"
        }
        if let updatedAt {
            return "上次更新：\(Self.dateFormatter.string(from: updatedAt)) · \(ruleCount) 条规则"
        }
        return "使用内置规则 · \(ruleCount) 条规则"
    }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.loadRules()
        }
    }

    func setEnabled(_ enabled: Bool) {
        preferences.contentBlockingEnabled = enabled
        postChange()
    }

    func isWhitelisted(_ host: String?) -> Bool {
        guard let host else { return false }
        if preferences.contentBlockingWhitelist.contains(host.lowercased()) {
            return true
        }
        return ContentBlockManager.shared.whitelistManager.matches(host)
    }

    func setWhitelisted(_ whitelisted: Bool, host: String) {
        let normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        var list = preferences.contentBlockingWhitelist
        if whitelisted {
            if !list.contains(normalized) {
                list.append(normalized)
            }
        } else {
            list.removeAll { $0 == normalized }
        }
        preferences.contentBlockingWhitelist = list
        postChange()
    }

    func forgetTab(_ id: UUID) {
        addedRuleListsByTab.removeValue(forKey: id)
    }

    /// 当前页面 host 对应的元素隐藏选择器：站点限定选择器全量 + 全局选择器上限内。
    func cosmeticSelectors(for host: String?) -> [String] {
        let hostScoped = cosmeticRules.compactMap { rule -> String? in
            guard let domains = rule.domains else { return nil }
            return matches(host: host, domains: domains) ? rule.selector : nil
        }
        let global = cosmeticRules
            .filter { $0.domains == nil }
            .prefix(Self.maxGlobalCountSelectors)
            .map(\.selector)
        return Array(Set(hostScoped + global))
    }

    private func matches(host: String?, domains: [String]) -> Bool {
        guard let host else { return false }
        let normalized = host.lowercased()
        return domains.contains { domain in
            let domain = domain.lowercased()
            return normalized == domain || normalized.hasSuffix("." + domain)
        }
    }

    /// 按当前开关与白名单状态，在 WebView 上添加或移除规则。
    /// 返回 true 表示规则集合发生了变化，调用方通常需要重载页面。
    @discardableResult
    func applyRules(
        to webView: WKWebView,
        tabID: UUID,
        host: String?
    ) -> Bool {
        loadIfNeeded()
        guard isReady else { return false }

        let shouldBlock = isEnabled && !isWhitelisted(host)
        let controller = webView.configuration.userContentController
        var added = addedRuleListsByTab[tabID] ?? []
        var changed = false
        let availableIdentifiers = Set(chunks.map(\.identifier))

        if shouldBlock {
            for chunk in chunks where !added.contains(chunk.identifier) {
                controller.add(chunk.ruleList)
                added.insert(chunk.identifier)
                changed = true
            }
        } else {
            for identifier in added where availableIdentifiers.contains(identifier) {
                if let ruleList = chunks.first(where: { $0.identifier == identifier })?
                    .ruleList {
                    controller.remove(ruleList)
                }
                added.remove(identifier)
                changed = true
            }
        }
        addedRuleListsByTab[tabID] = added
        return changed
    }

    /// 下载全部官方规则源并缓存，再按启用的规则子集编译。
    /// 成功后立即重新应用；`reloadPages` 为 false 时（后台自动更新）不重载当前页面。
    func updateRules(reloadPages: Bool = true) async throws {
        guard !isUpdating else {
            throw ContentBlockerUpdateError.alreadyUpdating
        }
        isUpdating = true
        defer { isUpdating = false }

        do {
            var versions: [String] = []
            for definition in Self.sourceDefinitions {
                // 单个规则源失败不中断整体更新，成功编译启用子集即可。
                if let text = try? await downloadSourceText(for: definition) {
                    cacheSourceText(text, key: definition.key)
                    if let version = ContentBlockerRuleBuilder.filterVersion(from: text) {
                        versions.append("\(definition.key):\(version)")
                    }
                }
            }
            guard !versions.isEmpty else {
                throw ContentBlockerUpdateError.invalidResponse
            }
            try await rebuildRules(reloadPages: reloadPages, versions: versions)
        } catch let error as ContentBlockerUpdateError {
            throw error
        } catch {
            throw ContentBlockerUpdateError.invalidResponse
        }
    }

    /// 从缓存的启用规则源、启用的自定义规则与白名单重建规则。
    func rebuildRules(reloadPages: Bool = true) async throws {
        var versions: [String] = []
        for definition in Self.sourceDefinitions {
            if let text = cachedSourceText(key: definition.key),
               let version = ContentBlockerRuleBuilder.filterVersion(from: text) {
                versions.append("\(definition.key):\(version)")
            }
        }
        try await rebuildRules(reloadPages: reloadPages, versions: versions)
    }

    private func rebuildRules(reloadPages: Bool, versions: [String]) async throws {
        let enabledKeys = Set(ContentBlockManager.shared.filterManager.enabledSourceKeys())
        var texts: [String] = []
        for definition in Self.sourceDefinitions where enabledKeys.contains(definition.key) {
            if let text = cachedSourceText(key: definition.key) {
                texts.append(text)
            }
        }
        texts.append(contentsOf: customRuleTexts())
        texts.append(contentsOf: whitelistExceptionTexts())

        guard !texts.isEmpty,
              let jsonData = ContentBlockerRuleBuilder.chunkedJSONData(from: texts),
              let chunks = parseRuleChunks(from: jsonData),
              !chunks.isEmpty
        else {
            throw ContentBlockerUpdateError.invalidFilter
        }
        let compiledChunks = await compileChunks(
            chunks: chunks,
            primaryIdentifier: Self.primaryIdentifier
        )
        guard !compiledChunks.isEmpty else {
            throw ContentBlockerUpdateError.compileFailed
        }

        self.chunks = compiledChunks
        ruleCount = chunks.reduce(0) { $0 + $1.count }
        ContentBlockManager.shared.statisticsManager.updateRuleCount(
            ruleCount,
            filterCount: enabledKeys.count
        )
        updatedAt = Date()
        filterVersion = versions.joined(separator: " / ")
        lastLoadError = nil
        isReady = true
        persistDownloadedRules(
            jsonData,
            metadata: RuleMetadata(
                updatedAt: updatedAt ?? Date(),
                version: filterVersion ?? "",
                ruleCount: ruleCount
            )
        )
        postChange(reloadActivePage: reloadPages)
    }

    private func loadRules() async {
        if let metadata = loadMetadata(),
           let data = try? Data(contentsOf: downloadedRulesURL) {
            updatedAt = metadata.updatedAt
            filterVersion = metadata.version.isEmpty ? nil : metadata.version
            await installRules(
                data: data,
                fallbackError: "无法读取已下载的广告过滤规则。"
            )
            if isReady { return }
        }

        guard let url = Bundle.main.url(
            forResource: "content-blocker-rules",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url)
        else {
            lastLoadError = "无法读取内置广告过滤规则。"
            return
        }
        updatedAt = nil
        filterVersion = nil
        await installRules(
            data: data,
            fallbackError: "无法读取内置广告过滤规则。"
        )
    }

    private func installRules(data: Data, fallbackError: String) async {
        guard let chunks = parseRuleChunks(from: data), !chunks.isEmpty
        else {
            lastLoadError = fallbackError
            return
        }
        ruleCount = chunks.reduce(0) { $0 + $1.count }
        ContentBlockManager.shared.statisticsManager.updateRuleCount(
            ruleCount,
            filterCount: ContentBlockManager.shared.filterManager.enabledSourceKeys().count
        )
        let compiledChunks = await compileChunks(
            chunks: chunks,
            primaryIdentifier: Self.primaryIdentifier
        )
        self.chunks = compiledChunks
        isReady = !self.chunks.isEmpty
        if self.chunks.isEmpty {
            lastLoadError = "广告过滤规则编译失败。"
        }
        postChange()
    }

    private func parseRuleChunks(from data: Data) -> [[[String: Any]]]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let chunks = object as? [[[String: Any]]],
              !chunks.isEmpty
        else {
            return nil
        }
        return chunks
    }

    /// 把多个规则分块各自编译为独立的 WKContentRuleList。
    /// 某个分块仍超限编译失败时，再按 `chunkSize` 子分块兜底。
    private func compileChunks(
        chunks: [[[String: Any]]],
        primaryIdentifier: String
    ) async -> [RuleChunk] {
        var compiledChunks: [RuleChunk] = []
        collectCosmeticRules(from: chunks)
        for (index, rules) in chunks.enumerated() {
            guard let chunkData = try? JSONSerialization.data(
                withJSONObject: rules
            ),
            let jsonString = String(data: chunkData, encoding: .utf8)
            else {
                continue
            }
            let identifier = "\(primaryIdentifier).list.\(index)"
            if let ruleList = await compile(
                jsonString,
                identifier: identifier
            ) {
                compiledChunks.append(
                    RuleChunk(
                        identifier: identifier,
                        ruleList: ruleList,
                        ruleCount: rules.count
                    )
                )
            } else {
                compiledChunks.append(
                    contentsOf: await compileFallbackChunks(
                        rules: rules,
                        baseIdentifier: identifier
                    )
                )
            }
        }
        return compiledChunks
    }

    private func collectCosmeticRules(from chunks: [[[String: Any]]]) {
        var collected: [(domains: [String]?, selector: String)] = []
        for chunk in chunks {
            for rule in chunk {
                guard let action = rule["action"] as? [String: Any],
                      action["type"] as? String == "css-display-none",
                      let selector = action["selector"] as? String
                else {
                    continue
                }
                let domains = (rule["trigger"] as? [String: Any])?["if-domain"] as? [String]
                collected.append((domains: domains, selector: selector))
            }
        }
        cosmeticRules = collected
    }

    private func compileFallbackChunks(
        rules: [[String: Any]],
        baseIdentifier: String
    ) async -> [RuleChunk] {
        var compiledChunks: [RuleChunk] = []
        let chunkCount = Int(ceil(Double(rules.count) / Double(chunkSize)))
        for index in 0..<chunkCount {
            let slice = Array(
                rules.dropFirst(index * chunkSize).prefix(chunkSize)
            )
            guard let sliceData = try? JSONSerialization.data(
                withJSONObject: slice
            ),
                  let sliceString = String(data: sliceData, encoding: .utf8)
            else {
                continue
            }
            let identifier = "\(baseIdentifier).chunk.\(index)"
            if let ruleList = await compile(
                sliceString,
                identifier: identifier
            ) {
                compiledChunks.append(
                    RuleChunk(
                        identifier: identifier,
                        ruleList: ruleList,
                        ruleCount: slice.count
                    )
                )
            }
        }
        return compiledChunks
    }

    private func downloadFilterText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            throw ContentBlockerUpdateError.invalidResponse
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ContentBlockerUpdateError.invalidFilter
        }
        return text
    }

    private func downloadSourceText(
        for definition: (key: String, url: URL)
    ) async throws -> String {
        do {
            return try await downloadFilterText(from: definition.url)
        } catch {
            if let fallback = Self.iosFilterURLs[definition.key] {
                return try await downloadFilterText(from: fallback)
            }
            throw error
        }
    }

    private func compile(
        _ json: String,
        identifier: String
    ) async -> WKContentRuleList? {
        guard let ruleListStore else { return nil }
        return await withCheckedContinuation { continuation in
            ruleListStore.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    private func persistDownloadedRules(
        _ jsonData: Data,
        metadata: RuleMetadata
    ) {
        try? fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try? jsonData.write(to: downloadedRulesURL, options: .atomic)
        if let metadataData = try? JSONEncoder().encode(metadata) {
            try? metadataData.write(to: metadataURL, options: .atomic)
        }
    }

    private func cacheSourceText(_ text: String, key: String) {
        try? fileManager.createDirectory(
            at: sourcesDirectory,
            withIntermediateDirectories: true
        )
        let url = sourcesDirectory.appendingPathComponent(
            "\(key).txt",
            isDirectory: false
        )
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func cachedSourceText(key: String) -> String? {
        let url = sourcesDirectory.appendingPathComponent(
            "\(key).txt",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 清除已下载的规则源与编译产物，回到内置规则。
    func clearSourceCache() async {
        try? fileManager.removeItem(at: sourcesDirectory)
        try? fileManager.removeItem(at: downloadedRulesURL)
        try? fileManager.removeItem(at: metadataURL)
        chunks = []
        isReady = false
        await loadRules()
    }

    /// 启用的自定义规则直接作为 AdGuard 语法文本参与编译。
    private func customRuleTexts() -> [String] {
        ContentBlockManager.shared.customManager.allRules()
            .filter { $0.isEnabled }
            .compactMap { rule -> String? in
                let content = rule.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                return content
            }
    }

    /// 白名单的域名/子域名模式转成例外规则；通配符与正则由 applyRules 运行时匹配。
    private func whitelistExceptionTexts() -> [String] {
        ContentBlockManager.shared.whitelistManager.allPatterns()
            .filter { $0.isEnabled }
            .compactMap { pattern -> String? in
                switch pattern.matchType {
                case .domain, .subdomain:
                    let domain = pattern.pattern
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    guard !domain.isEmpty else { return nil }
                    return "@@||\(domain)^"
                case .wildcard, .regex:
                    return nil
                }
            }
    }

    private func loadMetadata() -> RuleMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(RuleMetadata.self, from: data)
    }

    private func postChange(reloadActivePage: Bool = true) {
        NotificationCenter.default.post(
            name: .contentBlockerDidChange,
            object: self,
            userInfo: [Self.reloadActivePageUserInfoKey: reloadActivePage]
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
