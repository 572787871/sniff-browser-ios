import Combine
import SwiftUI
import UIKit

final class UserCenterViewController: BaseViewController {
    enum Destination: Hashable {
        case login
        case sync
        case downloads
        case files
        case favorites
        case history
        case privacy
        case about
    }

    var onSelectDestination: ((Destination) -> Void)?
    var onLogin: (() -> Void)?

    private let store: UserCenterSwiftUIStore

    init(
        session: AuthSession? = nil,
        counts: UserCenterCounts = UserCenterCounts()
    ) {
        store = UserCenterSwiftUIStore(session: session, counts: counts)
        super.init(title: "用户中心", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(
            UserCenterSwiftUIScreen(
                store: store,
                onSelect: { [weak self] destination in
                    self?.route(to: destination)
                }
            ),
            in: contentView
        )
    }

    func update(session: AuthSession?) {
        store.session = session
    }

    func update(counts: UserCenterCounts) {
        store.counts = counts
    }

    var displayedCounts: UserCenterCounts {
        store.counts
    }

    var summaryAccessibilityLabels: [String] {
        [
            "下载，\(store.counts.downloads)",
            "文件，\(store.counts.files)",
            "收藏，\(store.counts.favorites)",
            "历史，\(store.counts.history)"
        ]
    }

    var menuAccessibilityLabels: [String] {
        [
            "数据同步，\(store.session == nil ? "登录后可用" : "同步浏览数据")",
            "隐私与安全，网站权限与浏览数据",
            "关于嗅探浏览器，版本与许可信息"
        ]
    }

    func route(to destination: Destination) {
        if destination == .login, let onLogin {
            onLogin()
            return
        }
        if destination == .sync, store.session == nil {
            route(to: .login)
            return
        }
        if let onSelectDestination {
            onSelectDestination(destination)
            return
        }

        let controller: UIViewController?
        switch destination {
        case .login: controller = LoginViewController()
        case .sync: controller = nil
        case .downloads: controller = DownloadManagerViewController()
        case .files: controller = FileManagerViewController()
        case .favorites: controller = FavoritesViewController()
        case .history: controller = HistoryViewController()
        case .privacy:
            controller = PrivacySecurityViewController()
        case .about:
            controller = StaticContentViewController(
                title: "关于嗅探浏览器",
                segments: SettingsLegalContent.about()
            )
        }
        if let controller {
            navigationController?.pushViewController(controller, animated: true)
        }
    }
}

@MainActor
private final class UserCenterSwiftUIStore: ObservableObject {
    @Published var session: AuthSession?
    @Published var counts: UserCenterCounts

    init(session: AuthSession?, counts: UserCenterCounts) {
        self.session = session
        self.counts = counts
    }
}

private struct UserCenterSwiftUIScreen: View {
    @ObservedObject var store: UserCenterSwiftUIStore
    let onSelect: (UserCenterViewController.Destination) -> Void

    private struct Summary: Identifiable {
        let title: String
        let value: Int
        let destination: UserCenterViewController.Destination
        var id: UserCenterViewController.Destination { destination }
    }

    private var summaries: [Summary] {
        [
            Summary(title: "下载", value: store.counts.downloads, destination: .downloads),
            Summary(title: "文件", value: store.counts.files, destination: .files),
            Summary(title: "收藏", value: store.counts.favorites, destination: .favorites),
            Summary(title: "历史", value: store.counts.history, destination: .history)
        ]
    }

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 22) {
                    profileCard
                    accountSection
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profileTitle)
                        .font(.title2.weight(.bold))
                    Text(profileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppSwiftUIColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                onSelect(store.session == nil ? .login : .sync)
            } label: {
                Label(
                    store.session == nil ? "登录或注册" : "同步设置",
                    systemImage: store.session == nil ? "person.badge.plus" : "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(AppSwiftUIPrimaryButtonStyle())
            .accessibilityIdentifier("userCenter.primaryAction")

            HStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    Button {
                        onSelect(summary.destination)
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(summary.value)")
                                .font(.headline.monospacedDigit())
                            Text(summary.title)
                                .font(.caption)
                                .foregroundStyle(AppSwiftUIColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("userCenter.summary.\(summary.title)")
                    if index < summaries.count - 1 {
                        AppSwiftUIColors.separator
                            .frame(width: 1 / UIScreen.main.scale, height: 34)
                    }
                }
            }
        }
        .padding(18)
        .background(AppSwiftUIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "账户与应用")
            AppSwiftUISectionCard {
                destinationRow(
                    title: "数据同步",
                    subtitle: store.session == nil ? "登录后可用" : "同步浏览数据",
                    symbol: "arrow.triangle.2.circlepath",
                    destination: .sync
                )
                AppSwiftUIDivider()
                destinationRow(
                    title: "隐私与安全",
                    subtitle: "网站权限与浏览数据",
                    symbol: "hand.raised",
                    destination: .privacy
                )
                AppSwiftUIDivider()
                destinationRow(
                    title: "关于嗅探浏览器",
                    subtitle: "版本与许可信息",
                    symbol: "info.circle",
                    destination: .about
                )
            }
        }
    }

    private func destinationRow(
        title: String,
        subtitle: String,
        symbol: String,
        destination: UserCenterViewController.Destination
    ) -> some View {
        AppSwiftUIActionRow(
            title: title,
            subtitle: subtitle,
            systemName: symbol
        ) {
            onSelect(destination)
        }
    }

    private var profileTitle: String {
        store.session?.user.displayName
            ?? store.session?.user.email
            ?? "游客模式"
    }

    private var profileSubtitle: String {
        if let email = store.session?.user.email {
            return email
        }
        return "无需登录即可使用浏览器；登录后可同步个人数据。"
    }
}
