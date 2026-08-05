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

/// 一个网站保存的全部权限决定。
struct WebsiteSitePermission: Codable, Equatable, Sendable {
    let host: String
    var permissions: [WebsitePermission: WebsitePermissionDecision]
}

/// 持久化各网站的敏感权限决定，供 WebKit 授权询问与设置页使用。
final class WebsitePermissionStore {
    static let shared = WebsitePermissionStore()
    static let storageKey = "com.sniffbrowser.websitePermissions"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func decision(
        for host: String,
        permission: WebsitePermission
    ) -> WebsitePermissionDecision? {
        sites().first(where: { $0.host == host })?.permissions[permission]
    }

    func setDecision(
        _ decision: WebsitePermissionDecision,
        for host: String,
        permission: WebsitePermission
    ) {
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

    func removeSite(host: String) {
        persist(sites().filter { $0.host != host })
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    func sites() -> [WebsiteSitePermission] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([WebsiteSitePermission].self, from: data)) ?? []
    }

    private func persist(_ sites: [WebsiteSitePermission]) {
        let sortedSites = sites.sorted { $0.host < $1.host }
        guard let data = try? JSONEncoder().encode(sortedSites) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
