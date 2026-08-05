import WebKit

extension Notification.Name {
    static let contentBlockerDidChange =
        Notification.Name("com.sniffbrowser.contentBlockerDidChange")
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
    static let rulesUpdateURLs = [
        URL(
            string: "https://filters.adtidy.org/extension/safari/filters/2_optimized.txt"
        )!,
        URL(
            string: "https://filters.adtidy.org/extension/safari/filters/224_optimized.txt"
        )!,
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

    private(set) var isReady = false
    private(set) var ruleCount = 0
    private(set) var lastLoadError: String?
    private(set) var updatedAt: Date?
    private(set) var filterVersion: String?
    private(set) var isUpdating = false

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
        return preferences.contentBlockingWhitelist.contains(host.lowercased())
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

    /// 下载并安装最新过滤规则。成功后立即重新应用并通知页面重载。
    func updateRules() async throws {
        guard !isUpdating else {
            throw ContentBlockerUpdateError.alreadyUpdating
        }
        isUpdating = true
        defer { isUpdating = false }

        do {
            var filterTexts: [String] = []
            var versions: [String] = []
            for url in Self.rulesUpdateURLs {
                let text = try await downloadFilterText(from: url)
                filterTexts.append(text)
                if let version = ContentBlockerRuleBuilder.filterVersion(from: text) {
                    versions.append(version)
                }
            }
            guard let jsonData = ContentBlockerRuleBuilder.chunkedJSONData(
                from: filterTexts
            ),
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
            postChange()
        } catch let error as ContentBlockerUpdateError {
            throw error
        } catch {
            throw ContentBlockerUpdateError.invalidResponse
        }
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
        let (data, response) = try await URLSession.shared.data(
            from: url
        )
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

    private func loadMetadata() -> RuleMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(RuleMetadata.self, from: data)
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: .contentBlockerDidChange,
            object: self
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
