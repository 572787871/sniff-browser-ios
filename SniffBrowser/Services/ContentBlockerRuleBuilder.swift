import Foundation

/// 把 AdGuard/EasyList 风格的过滤器文本转换为 WKContentRuleList 规则 JSON。
///
/// WebKit 内容拦截的正则不支持 `|` 交替、环视与反向引用，因此这里
/// 只保留整域规则（`||domain^`）及其例外，一条规则对应一个域名，
/// 与 scripts/build-content-blocker.py 保持一致。
enum ContentBlockerRuleBuilder {
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

    static func buildJSONData(from filterText: String) -> Data? {
        var blockDomains: Set<String> = []
        var exceptionDomains: Set<String> = []

        for rawLine in filterText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("!"),
                  !line.hasPrefix("[")
            else {
                continue
            }
            if line.hasPrefix("@@||") {
                if let host = plainHost(afterPrefix: String(line.dropFirst(4))) {
                    exceptionDomains.insert(host)
                }
                continue
            }
            if line.hasPrefix("||") {
                if let host = plainHost(afterPrefix: String(line.dropFirst(2))) {
                    blockDomains.insert(host)
                }
            }
        }
        guard !blockDomains.isEmpty else { return nil }

        var rules: [[String: Any]] = []
        for domain in blockDomains.subtracting(exceptionDomains).sorted() {
            rules.append(rule(for: domain, action: "block"))
        }
        for domain in exceptionDomains.sorted() {
            rules.append(rule(for: domain, action: "ignore-previous-rules"))
        }
        return try? JSONSerialization.data(withJSONObject: rules)
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

    private static func plainHost(afterPrefix line: String) -> String? {
        guard line.hasSuffix("^") else { return nil }
        let host = String(line.dropLast()).lowercased()
        guard isValidDomain(host) else { return nil }
        return host
    }

    private static func isValidDomain(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.range(of: "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$",
                         options: .regularExpression) != nil,
              host.contains("."),
              !host.contains(".."),
              !host.hasPrefix("."),
              !host.hasSuffix(".")
        else {
            return false
        }
        return true
    }

    private static func rule(for domain: String, action: String) -> [String: Any] {
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
}
