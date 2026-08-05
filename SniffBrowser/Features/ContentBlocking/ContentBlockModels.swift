import Foundation

/// 官方规则列表元数据。sourceKey 对应 AdGuard 优化版过滤器编号。
struct FilterListMeta: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceKey }
    let sourceKey: String
    var name: String
    var details: String
    var ruleCount: Int
    var isEnabled: Bool
    var sortOrder: Int
}

/// 导入的自定义规则（简单文本形式）。
struct CustomRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var content: String
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

/// 白名单匹配类型。
enum WhitelistMatchType: String, CaseIterable, Codable, Sendable {
    case domain
    case subdomain
    case wildcard
    case regex

    var displayName: String {
        switch self {
        case .domain: return "域名"
        case .subdomain: return "子域名"
        case .wildcard: return "通配符"
        case .regex: return "正则"
        }
    }
}

struct WhitelistPattern: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pattern: String
    var matchType: WhitelistMatchType
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pattern: String,
        matchType: WhitelistMatchType = .domain,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern
        self.matchType = matchType
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
