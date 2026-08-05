import Foundation

/// 内容拦截中心的规则分类（一级页面展示的分类）。
enum FilterCategory: String, CaseIterable, Codable, Sendable {
    case ads
    case privacy
    case social
    case malware
    case cookie
    case dns
    case custom

    var displayName: String {
        switch self {
        case .ads: return "广告过滤"
        case .privacy: return "隐私保护"
        case .social: return "社交媒体过滤"
        case .malware: return "恶意网站"
        case .cookie: return "Cookie 拦截"
        case .dns: return "DNS 拦截"
        case .custom: return "自定义规则"
        }
    }

    var symbolName: String {
        switch self {
        case .ads: return "shield.lefthalf.filled"
        case .privacy: return "hand.raised.fill"
        case .social: return "person.2.crop.square.stack.fill"
        case .malware: return "shield.checkered"
        case .cookie: return "cookie"
        case .dns: return "network"
        case .custom: return "text.badge.plus"
        }
    }

    var tintName: String {
        switch self {
        case .ads: return "systemBlue"
        case .privacy: return "systemGreen"
        case .social: return "systemIndigo"
        case .malware: return "systemRed"
        case .cookie: return "systemOrange"
        case .dns: return "systemTeal"
        case .custom: return "systemPurple"
        }
    }
}

/// 官方规则列表元数据。sourceKey 对应 AdGuard 优化版过滤器编号。
struct FilterListMeta: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceKey }
    let sourceKey: String
    var name: String
    var details: String
    var author: String
    var license: String
    var version: String
    var updatedAt: Date?
    var ruleCount: Int
    var isEnabled: Bool
    var sortOrder: Int
    let category: FilterCategory
}

/// 自定义规则类型。
enum CustomRuleType: String, CaseIterable, Codable, Sendable {
    case block
    case allow
    case whitelist
    case elementHide
    case cssInject
    case jsInject
    case urlRewrite
    case scriptlet

    var displayName: String {
        switch self {
        case .block: return "阻止"
        case .allow: return "允许"
        case .whitelist: return "白名单"
        case .elementHide: return "元素隐藏"
        case .cssInject: return "CSS 注入"
        case .jsInject: return "JS 注入"
        case .urlRewrite: return "URL Rewrite"
        case .scriptlet: return "Scriptlet"
        }
    }

    var isSystemBlockable: Bool {
        switch self {
        case .block, .allow, .whitelist, .elementHide: return true
        default: return false
        }
    }
}

struct CustomRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var content: String
    var type: CustomRuleType
    var isEnabled: Bool
    var hitCount: Int
    var lastHitAt: Date?
    var sortOrder: Int
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        type: CustomRuleType = .block,
        isEnabled: Bool = true,
        hitCount: Int = 0,
        lastHitAt: Date? = nil,
        sortOrder: Int = 0,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.type = type
        self.isEnabled = isEnabled
        self.hitCount = hitCount
        self.lastHitAt = lastHitAt
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

/// 自动更新周期。
enum UpdateSchedule: Int, CaseIterable, Codable, Sendable {
    case off = 0
    case daily = 1
    case threeDays = 3
    case fiveDays = 5
    case sevenDays = 7

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .daily: return "每天"
        case .threeDays: return "每 3 天"
        case .fiveDays: return "每 5 天"
        case .sevenDays: return "每 7 天"
        }
    }

    var interval: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue) * 24 * 60 * 60
    }
}

/// 性能统计。
struct StatsRecord: Codable, Equatable, Sendable {
    var todayBlocked: Int
    var totalBlocked: Int
    var savedTrafficMB: Double
    var averageSpeedUpPercent: Double
    var ruleCount: Int
    var filterCount: Int
    var dayKey: String

    static let empty = StatsRecord(
        todayBlocked: 0,
        totalBlocked: 0,
        savedTrafficMB: 0,
        averageSpeedUpPercent: 0,
        ruleCount: 0,
        filterCount: 0,
        dayKey: ""
    )
}

/// 请求日志条目（仅记录公开 API 可观察的主框架导航）。
struct RequestLogEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var url: String
    var host: String
    var resourceType: String
    var status: String
    var isBlocked: Bool
    var ruleIdentifier: String?
    var durationMs: Double
    var sizeBytes: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        url: String,
        host: String,
        resourceType: String = "Document",
        status: String,
        isBlocked: Bool = false,
        ruleIdentifier: String? = nil,
        durationMs: Double = 0,
        sizeBytes: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.host = host
        self.resourceType = resourceType
        self.status = status
        self.isBlocked = isBlocked
        self.ruleIdentifier = ruleIdentifier
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}
