import Combine
import SwiftUI
import UIKit

final class WebsitePermissionsViewController: BaseViewController {
    private let store = WebsitePermissionsSwiftUIStore()

    init() {
        super.init(title: "网站权限", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(
            WebsitePermissionsSwiftUIScreen(
                store: store,
                onOpen: { [weak self] site in self?.open(site) }
            ),
            in: contentView
        )
        store.reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
    }

    private func open(_ site: WebsiteSitePermission) {
        let detail = WebsiteSitePermissionViewController(host: site.host)
        detail.onChanged = { [weak store = self.store] in store?.reload() }
        navigationController?.pushViewController(detail, animated: true)
    }
}

@MainActor
private final class WebsitePermissionsSwiftUIStore: ObservableObject {
    @Published private(set) var sites: [WebsiteSitePermission] = []
    @Published private(set) var defaultPolicies:
        [WebsitePermission: WebsitePermissionDefaultPolicy] = [:]
    private let persistence = WebsitePermissionStore.shared

    func reload() {
        sites = persistence.sites()
        defaultPolicies = Dictionary(uniqueKeysWithValues:
            WebsitePermission.allCases.map { permission in
                (permission, persistence.defaultPolicy(for: permission))
            }
        )
    }

    func defaultPolicy(
        for permission: WebsitePermission
    ) -> WebsitePermissionDefaultPolicy {
        defaultPolicies[permission] ?? .ask
    }

    func setDefaultPolicy(
        _ policy: WebsitePermissionDefaultPolicy,
        for permission: WebsitePermission
    ) {
        persistence.setDefaultPolicy(policy, for: permission)
        reload()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func remove(_ site: WebsiteSitePermission) {
        persistence.removeSite(host: site.host)
        reload()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func removeAllSites() {
        persistence.removeAll()
        reload()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct WebsitePermissionsSwiftUIScreen: View {
    @ObservedObject var store: WebsitePermissionsSwiftUIStore
    let onOpen: (WebsiteSitePermission) -> Void
    @State private var query = ""
    @State private var showsClearConfirmation = false

    private var filteredSites: [WebsiteSitePermission] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return store.sites }
        return store.sites.filter {
            $0.host.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    privacyOverview
                    defaultBehavior
                    siteExceptions
                    privacyNote
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .alert("清除全部网站例外？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                store.removeAllSites()
            }
        } message: {
            Text("默认权限行为会保留；所有网站单独保存的允许或阻止决定将被删除。")
        }
    }

    private var privacyOverview: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.raised")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(AppSwiftUIColors.secondaryText)
                .frame(width: 36, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("权限由你掌控")
                    .font(.title3.weight(.bold))
                Text("摄像头、麦克风和位置默认不会静默开放。先设置全局行为，再为特定网站添加例外。")
                    .font(.subheadline)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var defaultBehavior: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(
                title: "默认行为",
                detail: "适用于未保存例外的网站"
            )
            AppSwiftUISectionCard {
                ForEach(
                    Array(WebsitePermission.allCases.enumerated()),
                    id: \.element.rawValue
                ) { index, permission in
                    permissionDefaultRow(permission)
                    if index < WebsitePermission.allCases.count - 1 {
                        AppSwiftUIDivider()
                    }
                }
            }
        }
    }

    private func permissionDefaultRow(_ permission: WebsitePermission) -> some View {
        let policy = store.defaultPolicy(for: permission)
        return HStack(spacing: 12) {
            AppSwiftUIIconBadge(systemName: permission.symbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.displayName)
                    .font(.body.weight(.medium))
                Text(policy.detail)
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(WebsitePermissionDefaultPolicy.allCases, id: \.rawValue) {
                    option in
                    Button {
                        store.setDefaultPolicy(option, for: permission)
                    } label: {
                        if option == policy {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(policy.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppSwiftUIColors.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("websitePermission.default.\(permission.rawValue)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var siteExceptions: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(
                title: "网站例外",
                detail: store.sites.isEmpty ? "暂无" : "\(store.sites.count) 个网站"
            )
            if !store.sites.isEmpty {
                AppSwiftUISearchField(placeholder: "搜索网站", text: $query)
            }
            AppSwiftUISectionCard {
                if filteredSites.isEmpty {
                    HStack(spacing: 12) {
                        AppSwiftUIIconBadge(systemName: "globe.badge.chevron.backward")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(query.isEmpty ? "还没有网站例外" : "没有匹配的网站")
                                .font(.body.weight(.medium))
                            Text(query.isEmpty
                                ? "网页请求权限并保存选择后会显示在这里。"
                                : "尝试输入其他域名。")
                                .font(.caption)
                                .foregroundStyle(AppSwiftUIColors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(filteredSites.enumerated()), id: \.element.host) {
                        index, site in
                        siteRow(site)
                        if index < filteredSites.count - 1 {
                            AppSwiftUIDivider()
                        }
                    }
                }
            }

            if !store.sites.isEmpty {
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label("清除全部网站例外", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppSwiftUIColors.danger)
            }
        }
    }

    private func siteRow(_ site: WebsiteSitePermission) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpen(site)
            } label: {
                HStack(spacing: 12) {
                    AppSwiftUIIconBadge(systemName: "globe")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(site.host)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppSwiftUIColors.primaryText)
                            .lineLimit(1)
                        Text(summary(for: site))
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppSwiftUIColors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.remove(site)
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppSwiftUIColors.tertiaryText)
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除 \(site.host) 的权限")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    private var privacyNote: some View {
        Label {
            Text("网站权限只控制网页访问敏感能力；iOS 系统权限仍会在需要时单独询问。")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(AppSwiftUIColors.tertiaryText)
        .padding(.horizontal, 6)
    }

    private func summary(for site: WebsiteSitePermission) -> String {
        let values = WebsitePermission.allCases.compactMap { permission -> String? in
            guard let decision = site.permissions[permission] else { return nil }
            return "\(permission.displayName) \(decision == .allow ? "允许" : "阻止")"
        }
        return values.isEmpty ? "遵循默认行为" : values.joined(separator: " · ")
    }
}

final class WebsiteSitePermissionViewController: BaseViewController {
    var onChanged: (() -> Void)?
    private let store: WebsiteSitePermissionSwiftUIStore

    init(host: String, store: WebsitePermissionStore = .shared) {
        self.store = WebsiteSitePermissionSwiftUIStore(
            host: host,
            persistence: store
        )
        super.init(title: host, prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(
            WebsiteSitePermissionSwiftUIScreen(
                store: store,
                onChanged: { [weak self] in self?.onChanged?() },
                onReset: { [weak self] in
                    self?.onChanged?()
                    self?.navigationController?.popViewController(animated: true)
                }
            ),
            in: contentView
        )
    }
}

@MainActor
private final class WebsiteSitePermissionSwiftUIStore: ObservableObject {
    let host: String
    @Published private(set) var decisions:
        [WebsitePermission: WebsitePermissionDecision] = [:]
    private let persistence: WebsitePermissionStore

    init(host: String, persistence: WebsitePermissionStore) {
        self.host = host
        self.persistence = persistence
        reload()
    }

    func decision(for permission: WebsitePermission) -> WebsitePermissionDecision? {
        decisions[permission]
    }

    func defaultPolicy(
        for permission: WebsitePermission
    ) -> WebsitePermissionDefaultPolicy {
        persistence.defaultPolicy(for: permission)
    }

    func setDecision(
        _ decision: WebsitePermissionDecision?,
        permission: WebsitePermission
    ) {
        if let decision {
            persistence.setDecision(decision, for: host, permission: permission)
        } else {
            persistence.removeDecision(for: host, permission: permission)
        }
        reload()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func reset() {
        persistence.removeSite(host: host)
        decisions = [:]
    }

    private func reload() {
        decisions = Dictionary(uniqueKeysWithValues:
            WebsitePermission.allCases.compactMap { permission in
                persistence.decision(for: host, permission: permission).map {
                    (permission, $0)
                }
            }
        )
    }
}

private struct WebsiteSitePermissionSwiftUIScreen: View {
    @ObservedObject var store: WebsiteSitePermissionSwiftUIStore
    let onChanged: () -> Void
    let onReset: () -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 13) {
                        Image(systemName: "network")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                            .frame(width: 32, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.host)
                                .font(.headline)
                                .lineLimit(2)
                            Text("单独设置会覆盖浏览器默认行为")
                                .font(.caption)
                                .foregroundStyle(AppSwiftUIColors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 9) {
                        AppSwiftUISectionHeader(title: "此网站的权限")
                        AppSwiftUISectionCard {
                            ForEach(
                                Array(WebsitePermission.allCases.enumerated()),
                                id: \.element.rawValue
                            ) { index, permission in
                                permissionRow(permission)
                                if index < WebsitePermission.allCases.count - 1 {
                                    AppSwiftUIDivider()
                                }
                            }
                        }
                        Text("“遵循默认”会使用上一页设置的全局行为。")
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.tertiaryText)
                            .padding(.horizontal, 6)
                    }

                    AppSwiftUISectionCard {
                        AppSwiftUIActionRow(
                            title: "清除此网站的全部例外",
                            subtitle: "摄像头、麦克风和位置恢复为默认行为",
                            systemName: "arrow.counterclockwise",
                            showsLeadingIcon: false,
                            isDestructive: true,
                            showsChevron: false
                        ) {
                            showsResetConfirmation = true
                        }
                    }
                }
                .padding(16)
            }
        }
        .alert("清除此网站的权限例外？", isPresented: $showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                store.reset()
                onReset()
            }
        }
    }

    private func permissionRow(_ permission: WebsitePermission) -> some View {
        let decision = store.decision(for: permission)
        return HStack(spacing: 12) {
            AppSwiftUIIconBadge(systemName: permission.symbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.displayName)
                    .font(.body.weight(.medium))
                Text(detail(for: permission, decision: decision))
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
            }
            Spacer(minLength: 8)
            Menu {
                Button("遵循默认") {
                    store.setDecision(nil, permission: permission)
                    onChanged()
                }
                Button("始终允许") {
                    store.setDecision(.allow, permission: permission)
                    onChanged()
                }
                Button("始终阻止", role: .destructive) {
                    store.setDecision(.deny, permission: permission)
                    onChanged()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(choiceTitle(decision))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(decision == .deny
                    ? AppSwiftUIColors.danger
                    : AppSwiftUIColors.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("sitePermission.\(permission.rawValue)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func choiceTitle(_ decision: WebsitePermissionDecision?) -> String {
        switch decision {
        case .allow: return "允许"
        case .deny: return "阻止"
        case nil: return "默认"
        }
    }

    private func detail(
        for permission: WebsitePermission,
        decision: WebsitePermissionDecision?
    ) -> String {
        switch decision {
        case .allow: return "此网站以后直接获得权限"
        case .deny: return "此网站的请求会被自动拒绝"
        case nil:
            return "遵循默认 · \(store.defaultPolicy(for: permission).displayName)"
        }
    }
}
