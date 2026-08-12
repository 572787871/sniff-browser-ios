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
    private let persistence = WebsitePermissionStore.shared

    func reload() {
        sites = persistence.sites()
    }

    func remove(_ site: WebsiteSitePermission) {
        persistence.removeSite(host: site.host)
        reload()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct WebsitePermissionsSwiftUIScreen: View {
    @ObservedObject var store: WebsitePermissionsSwiftUIStore
    let onOpen: (WebsiteSitePermission) -> Void

    var body: some View {
        AppSwiftUIScreen {
            if store.sites.isEmpty {
                AppSwiftUIEmptyState(
                    systemName: "hand.raised",
                    title: "还没有网站权限记录",
                    message: "网页请求摄像头、麦克风或位置时，你的选择会显示在这里。"
                )
            } else {
                List {
                    Section {
                        ForEach(store.sites, id: \.host) { site in
                            Button {
                                onOpen(site)
                            } label: {
                                HStack(spacing: 12) {
                                    AppSwiftUIIconBadge(systemName: "globe")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(site.host)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppSwiftUIColors.primaryText)
                                        Text(summary(for: site))
                                            .font(.caption)
                                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppSwiftUIColors.tertiaryText)
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("清除", role: .destructive) {
                                    store.remove(site)
                                }
                            }
                            .listRowBackground(AppSwiftUIColors.surface.opacity(0.78))
                        }
                    } header: {
                        Text("已保存的网站")
                    } footer: {
                        Text("网页请求敏感功能时，应用会先征求同意并记住选择。")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func summary(for site: WebsiteSitePermission) -> String {
        let values = WebsitePermission.allCases.compactMap { permission -> String? in
            guard let decision = site.permissions[permission] else { return nil }
            return "\(permission.displayName) \(decision == .allow ? "允许" : "拒绝")"
        }
        return values.isEmpty ? "已保存权限" : values.joined(separator: " · ")
    }
}

final class WebsiteSitePermissionViewController: BaseViewController {
    var onChanged: (() -> Void)?
    private let store: WebsiteSitePermissionSwiftUIStore

    init(host: String, store: WebsitePermissionStore = .shared) {
        self.store = WebsiteSitePermissionSwiftUIStore(host: host, persistence: store)
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
    @Published private(set) var decisions: [WebsitePermission: WebsitePermissionDecision] = [:]
    private let persistence: WebsitePermissionStore

    init(host: String, persistence: WebsitePermissionStore) {
        self.host = host
        self.persistence = persistence
        reload()
    }

    func decision(for permission: WebsitePermission) -> WebsitePermissionDecision? {
        decisions[permission]
    }

    func setAllowed(_ allowed: Bool, permission: WebsitePermission) {
        persistence.setDecision(
            allowed ? .allow : .deny,
            for: host,
            permission: permission
        )
        reload()
    }

    func reset() {
        persistence.removeSite(host: host)
        decisions = [:]
    }

    private func reload() {
        decisions = Dictionary(uniqueKeysWithValues: WebsitePermission.allCases.compactMap {
            permission in
            persistence.decision(for: host, permission: permission).map {
                (permission, $0)
            }
        })
    }
}

private struct WebsiteSitePermissionSwiftUIScreen: View {
    @ObservedObject var store: WebsiteSitePermissionSwiftUIStore
    let onChanged: () -> Void
    let onReset: () -> Void

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        AppSwiftUISectionHeader(title: "权限")
                        AppSwiftUISectionCard {
                            ForEach(Array(WebsitePermission.allCases.enumerated()), id: \.element.rawValue) {
                                index, permission in
                                HStack(spacing: 12) {
                                    AppSwiftUIIconBadge(systemName: permission.symbolName)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(permission.displayName)
                                            .font(.body.weight(.medium))
                                        Text(store.decision(for: permission) == .allow ? "允许" : "拒绝")
                                            .font(.caption)
                                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                                    }
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { store.decision(for: permission) == .allow },
                                            set: { enabled in
                                                store.setAllowed(enabled, permission: permission)
                                                onChanged()
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .accessibilityIdentifier("sitePermission.\(permission.rawValue)")
                                if index < WebsitePermission.allCases.count - 1 {
                                    AppSwiftUIDivider()
                                }
                            }
                        }
                        Text("打开表示允许该网站使用对应功能，关闭表示拒绝。")
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.tertiaryText)
                            .padding(.horizontal, 6)
                    }

                    AppSwiftUISectionCard {
                        AppSwiftUIActionRow(
                            title: "恢复为每次询问",
                            subtitle: "清除此网站保存的全部权限决定",
                            systemName: "arrow.counterclockwise",
                            isDestructive: true,
                            showsChevron: false
                        ) {
                            store.reset()
                            onReset()
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}
