import Foundation

/// 把 AdGuard/EasyList 风格的过滤器文本转换为 WKContentRuleList 规则 JSON。
///
/// WebKit 内容拦截的正则不支持 `|` 交替、环视与反向引用，且每个规则列表
/// 最多 50,000 条。这里只保留整域拦截、简单元素隐藏与整域例外，
/// 一条规则对应一个域名/选择器，与 scripts/build-content-blocker.py 一致。
enum ContentBlockerRuleBuilder {
    /// 单个 WKContentRuleList 分块上限，与 scripts/build-content-blocker.py 保持一致。
    static let maxRulesPerChunk = 45_000

    private static let resourceTypes = [
        "image",
        "style-sheet",
        "script",
        "font",
        "raw",
        "media",
        "popup",
        "ping",
    ]

    private static let safeSelectorCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "0123456789#._->+~[]=\"'^*$ ,"
    )

    static func buildJSONData(from filterTexts: [String]) -> Data? {
        guard let rules = buildRules(from: filterTexts), !rules.isEmpty else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: rules)
    }

    /// 与内置规则一致的多分块 JSON：`[[rule...], [rule...]]`，
    /// 每个分块可单独编译为 WKContentRuleList，突破单列表 50k 上限。
    static func chunkedJSONData(from filterTexts: [String]) -> Data? {
        guard let rules = buildRules(from: filterTexts), !rules.isEmpty else {
            return nil
        }
        var chunks: [[[String: Any]]] = []
        var current: [[String: Any]] = []
        var currentBytes = 0
        let maxBytesPerChunk = 8 * 1024 * 1024
        for rule in rules {
            let ruleBytes = (
                try? JSONSerialization.data(withJSONObject: rule)
            )?.count ?? 0
            if !current.isEmpty,
               current.count >= maxRulesPerChunk
                || currentBytes + ruleBytes > maxBytesPerChunk {
                chunks.append(current)
                current = []
                currentBytes = 0
            }
            current.append(rule)
            currentBytes += ruleBytes
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return try? JSONSerialization.data(withJSONObject: chunks)
    }

    private static func buildRules(from filterTexts: [String]) -> [[String: Any]]? {
        var hostBlocks: Set<String> = []
        var cosmetics: [(domains: [String]?, selector: String)] = []
        var exceptionHosts: Set<String> = []

        for filterText in filterTexts {
            parse(
                filterText,
                hostBlocks: &hostBlocks,
                cosmetics: &cosmetics,
                exceptionHosts: &exceptionHosts
            )
        }
        guard !hostBlocks.isEmpty || !cosmetics.isEmpty else { return nil }

        var rules: [[String: Any]] = []
        for domain in hostBlocks.subtracting(exceptionHosts).sorted() {
            rules.append(hostRule(for: domain, action: "block"))
        }
        for (domains, selector) in cosmetics {
            for part in selector.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard isValidSelector(trimmed) else { continue }
                rules.append(cosmeticRule(domains: domains, selector: trimmed))
            }
        }
        for domain in exceptionHosts.sorted() {
            rules.append(hostRule(for: domain, action: "ignore-previous-rules"))
        }
        return rules
    }

    static func filterVersion(from filterText: String) -> String? {
        for rawLine in filterText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("! Version:") else { continue }
            return line
                .dropFirst("! Version:".count)
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parse(
        _ filterText: String,
        hostBlocks: inout Set<String>,
        cosmetics: inout [(domains: [String]?, selector: String)],
        exceptionHosts: inout Set<String>
    ) {
        for rawLine in filterText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("!"),
                  !line.hasPrefix("[")
            else {
                continue
            }
            if line.contains("$") || line.contains("~") || line.contains("*") {
                continue
            }
            if line.hasPrefix("#@#") || line.hasPrefix("#?#") {
                continue
            }
            if line.hasPrefix("@@") {
                if let host = plainHost(from: String(line.dropFirst(4))) {
                    exceptionHosts.insert(host)
                }
                continue
            }
            if line.hasPrefix("||") {
                if let host = plainHost(from: String(line.dropFirst(2))) {
                    hostBlocks.insert(host)
                }
                continue
            }
            if let range = line.range(of: "##") {
                let head = String(line[..<range.lowerBound])
                let selector = String(line[range.upperBound...])
                if head.isEmpty {
                    if isValidSelector(selector) {
                        cosmetics.append((nil, selector))
                    }
                    continue
                }
                guard !head.hasSuffix("."),
                      !head.hasPrefix("."),
                      !head.contains("#")
                else {
                    continue
                }
                let domains = head
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if domains.allSatisfy({ isValidDomain($0) }),
                   isValidSelector(selector) {
                    cosmetics.append((domains, selector))
                }
            }
        }
    }

    private static func plainHost(from line: String) -> String? {
        guard line.hasSuffix("^") else { return nil }
        let host = String(line.dropLast()).lowercased()
        return isValidDomain(host) ? host : nil
    }

    private static func isValidDomain(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.range(
                of: "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$",
                options: .regularExpression
              ) != nil,
              host.contains("."),
              !host.contains(".."),
              !host.hasPrefix("."),
              !host.hasSuffix(".")
        else {
            return false
        }
        return true
    }

    private static func isValidSelector(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains(":"),
              !trimmed.contains("("),
              !trimmed.contains(")")
        else {
            return false
        }
        return trimmed.unicodeScalars.allSatisfy {
            safeSelectorCharacters.contains($0)
        }
    }

    private static func hostRule(for domain: String, action: String) -> [String: Any] {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        let urlFilter = "^https?://([^/:]+\\.)?\(escaped)[:/]"
        return [
            "trigger": [
                "url-filter": urlFilter,
                "load-type": ["third-party", "first-party"],
                "resource-type": resourceTypes,
            ],
            "action": ["type": action],
        ]
    }

    private static func cosmeticRule(
        domains: [String]?,
        selector: String
    ) -> [String: Any] {
        var trigger: [String: Any] = ["url-filter": ".*"]
        if let domains {
            trigger["if-domain"] = domains
        }
        return [
            "trigger": trigger,
            "action": [
                "type": "css-display-none",
                "selector": selector,
            ],
        ]
    }
}
