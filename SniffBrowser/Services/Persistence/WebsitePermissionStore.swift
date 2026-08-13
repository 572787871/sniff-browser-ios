import Foundation

/// 网页可申请的敏感权限类型。
enum WebsitePermission: String, CaseIterable, Codable, Sendable {
    case camera
    case microphone
    case location

    var displayName: String {
        switch self {
        case .camera: return "摄像头"
        case .microphone: return "麦克风"
        case .location: return "位置"
        }
    }

    var symbolName: String {
        switch self {
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .location: return "location.fill"
        }
    }
}

/// 单个权限的决定；没有保存决定时表示每次由用户现场决定。
enum WebsitePermissionDecision: String, Codable, Sendable {
    case allow
    case deny
}

/// 未为具体网站保存例外时使用的全局行为。敏感能力不提供“默认允许”，
/// 避免一次设置让所有网站静默获得权限。
enum WebsitePermissionDefaultPolicy: String, CaseIterable, Codable, Sendable {
    case ask
    case deny

    var displayName: String {
        switch self {
        case .ask: return "每次询问"
        case .deny: return "自动阻止"
        }
    }

    var detail: String {
        switch self {
        case .ask: return "网站请求时由你决定"
        case .deny: return "不弹窗，直接拒绝"
        }
    }
}

/// 一个网站保存的全部权限决定。
struct WebsiteSitePermission: Codable, Equatable, Sendable {
    let host: String
    var permissions: [WebsitePermission: WebsitePermissionDecision]
}

/// 持久化各网站的敏感权限决定，供 WebKit 授权询问与设置页使用。
final class WebsitePermissionStore {
    static let shared = WebsitePermissionStore()
    static let storageKey = "com.sniffbrowser.websitePermissions"
    static let defaultPolicyStorageKey =
        "com.sniffbrowser.websitePermissionDefaultPolicies"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func decision(
        for host: String,
        permission: WebsitePermission
    ) -> WebsitePermissionDecision? {
        let host = normalizedHost(host)
        return sites().first(where: { $0.host == host })?.permissions[permission]
    }

    func defaultPolicy(
        for permission: WebsitePermission
    ) -> WebsitePermissionDefaultPolicy {
        defaultPolicies()[permission] ?? .ask
    }

    func setDefaultPolicy(
        _ policy: WebsitePermissionDefaultPolicy,
        for permission: WebsitePermission
    ) {
        var policies = defaultPolicies()
        policies[permission] = policy
        guard let data = try? JSONEncoder().encode(policies) else { return }
        defaults.set(data, forKey: Self.defaultPolicyStorageKey)
    }

    func setDecision(
        _ decision: WebsitePermissionDecision,
        for host: String,
        permission: WebsitePermission
    ) {
        let host = normalizedHost(host)
        guard !host.isEmpty else { return }
        var all = sites()
        var entry = all.first(where: { $0.host == host })
            ?? WebsiteSitePermission(host: host, permissions: [:])
        entry.permissions[permission] = decision
        if let index = all.firstIndex(where: { $0.host == host }) {
            all[index] = entry
        } else {
            all.append(entry)
        }
        persist(all)
    }

    func removeDecision(
        for host: String,
        permission: WebsitePermission
    ) {
        let host = normalizedHost(host)
        var all = sites()
        guard let index = all.firstIndex(where: { $0.host == host }) else {
            return
        }
        all[index].permissions[permission] = nil
        if all[index].permissions.isEmpty {
            all.remove(at: index)
        }
        persist(all)
    }

    func removeSite(host: String) {
        let host = normalizedHost(host)
        persist(sites().filter { $0.host != host })
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    func sites() -> [WebsiteSitePermission] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }
        let decoded = (try? JSONDecoder().decode(
            [WebsiteSitePermission].self,
            from: data
        )) ?? []
        var merged: [String: [WebsitePermission: WebsitePermissionDecision]] = [:]
        decoded.forEach { site in
            let host = normalizedHost(site.host)
            guard !host.isEmpty else { return }
            merged[host, default: [:]].merge(site.permissions) { _, latest in
                latest
            }
        }
        return merged.map {
            WebsiteSitePermission(host: $0.key, permissions: $0.value)
        }.sorted { $0.host < $1.host }
    }

    private func defaultPolicies()
        -> [WebsitePermission: WebsitePermissionDefaultPolicy] {
        guard let data = defaults.data(forKey: Self.defaultPolicyStorageKey)
        else { return [:] }
        return (try? JSONDecoder().decode(
            [WebsitePermission: WebsitePermissionDefaultPolicy].self,
            from: data
        )) ?? [:]
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func persist(_ sites: [WebsiteSitePermission]) {
        let sortedSites = sites.sorted { $0.host < $1.host }
        guard let data = try? JSONEncoder().encode(sortedSites) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
