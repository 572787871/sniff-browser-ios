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

/// 单日拦截统计（按自然日累计）。
struct DailyCount: Codable, Equatable, Sendable {
    var blocked: Int
    var pageLoads: Int

    static let zero = DailyCount(blocked: 0, pageLoads: 0)
}

/// 统计时间范围（“今日”下拉筛选）。
enum StatisticsRange: String, CaseIterable, Sendable {
    case today = "今日"
    case week = "近7日"
    case month = "近30日"
    case all = "全部"

    /// 覆盖天数；全部为 nil（直接使用累计值）。
    var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }

    /// 统计卡片标题：今日拦截 / 近7日拦截 / 近30日拦截 / 累计拦截。
    func metricTitle(for kind: StatisticsMetricKind) -> String {
        let suffix = kind == .blocked ? "拦截" : "访问"
        switch self {
        case .today: return "今日\(suffix)"
        case .week: return "近7日\(suffix)"
        case .month: return "近30日\(suffix)"
        case .all: return "累计\(suffix)"
        }
    }
}

/// 统计指标类型。
enum StatisticsMetricKind: Sendable {
    case blocked
    case pageLoads
}

/// 趋势图数据类别。
enum StatisticsSparklineKind: Sendable {
    case blocked
    case pageLoads
    case ruleCount
    case filterCount
}
