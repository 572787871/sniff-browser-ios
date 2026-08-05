import WebKit

extension Notification.Name {
    static let contentBlockerDidChange =
        Notification.Name("com.sniffbrowser.contentBlockerDidChange")
}

/// 广告过滤服务：把内置规则编译成 `WKContentRuleList`，并按标签页与
/// 白名单决定是否应用到对应 WebView。
@MainActor
final class ContentBlockerService {
    static let shared = ContentBlockerService()

    private struct RuleChunk {
        let identifier: String
        let ruleList: WKContentRuleList
        let ruleCount: Int
    }

    private let preferences = BrowserPreferences()
    private let ruleListStore = WKContentRuleListStore.default()
    private let chunkSize = 100
    private var chunks: [RuleChunk] = []
    private var addedRuleListsByTab: [UUID: Set<String>] = [:]
    private var loadTask: Task<Void, Never>?

    private(set) var isReady = false
    private(set) var bundledRuleCount = 0
    private(set) var lastLoadError: String?

    var isEnabled: Bool {
        preferences.contentBlockingEnabled
    }

    var whitelistedHosts: [String] {
        preferences.contentBlockingWhitelist
    }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.loadBundledRules()
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

    private func loadBundledRules() async {
        guard let url = Bundle.main.url(
            forResource: "content-blocker-rules",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data),
        let rules = object as? [[String: Any]],
        !rules.isEmpty
        else {
            lastLoadError = "无法读取内置广告过滤规则。"
            return
        }

        bundledRuleCount = rules.count
        var compiledChunks: [RuleChunk] = []
        let chunkCount = Int(
            ceil(Double(rules.count) / Double(chunkSize))
        )
        for index in 0..<chunkCount {
            let slice = Array(
                rules.dropFirst(index * chunkSize).prefix(chunkSize)
            )
            guard let jsonData = try? JSONSerialization.data(withJSONObject: slice),
                  let jsonString = String(data: jsonData, encoding: .utf8)
            else {
                continue
            }
            let identifier = "com.sniffbrowser.adblock.\(index)"
            if let ruleList = await compile(jsonString, identifier: identifier) {
                compiledChunks.append(
                    RuleChunk(
                        identifier: identifier,
                        ruleList: ruleList,
                        ruleCount: slice.count
                    )
                )
            }
        }
        chunks = compiledChunks
        isReady = true
        if chunks.isEmpty {
            lastLoadError = "内置广告过滤规则编译失败。"
        }
        postChange()
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

    private func postChange() {
        NotificationCenter.default.post(
            name: .contentBlockerDidChange,
            object: self
        )
    }
}
