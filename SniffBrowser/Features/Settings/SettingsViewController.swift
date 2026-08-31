import Combine
import SwiftUI
import UIKit

/// 设置路由继续由 UIKit/AppCoordinator 管理，页面内容统一由 SwiftUI 绘制。
final class SettingsViewController: BaseViewController {
    static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.6.7"
    }

    enum Destination: Equatable {
        case searchEngine
        case newTabBehavior
        case appearance
        case contentBlocking
        case websitePermissions
        case clearBrowsingData
        case downloadPreferences
        case storage
        case privacyPolicy
        case terms
        case openSourceLicenses
        case about
    }

    var onSelectDestination: ((Destination) -> Void)?
    var onRoute: ((AppRoute) -> Void)?
    var onClearBrowsingData: (() -> Void)? {
        didSet {
            store.canClearBrowsingData = onClearBrowsingData != nil
        }
    }

    private let store = SettingsSwiftUIStore()

    init() {
        super.init(title: "设置", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.canClearBrowsingData = onClearBrowsingData != nil
        installSwiftUI(
            SettingsSwiftUIScreen(
                store: store,
                onSelect: { [weak self] destination in
                    self?.selectDestination(destination)
                }
            ),
            in: contentView
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.refresh()
    }

    /// 统一设置路由入口，也供测试验证 SwiftUI 行与旧路由保持一致。
    func selectDestination(_ destination: Destination) {
        if destination == .clearBrowsingData {
            onClearBrowsingData?()
            return
        }
        if destination == .appearance {
            navigationController?.pushViewController(
                AppearanceSettingsViewController(),
                animated: true
            )
            return
        }
        if destination == .downloadPreferences {
            if let onRoute {
                onRoute(.downloadSettings)
            } else {
                navigationController?.pushViewController(
                    DownloadSettingsViewController(),
                    animated: true
                )
            }
            return
        }

        switch destination {
        case .searchEngine:
            navigationController?.pushViewController(
                SearchEngineSettingsViewController(),
                animated: true
            )
        case .newTabBehavior:
            navigationController?.pushViewController(
                NewTabSettingsViewController(),
                animated: true
            )
        case .websitePermissions:
            navigationController?.pushViewController(
                WebsitePermissionsViewController(),
                animated: true
            )
        case .contentBlocking:
            navigationController?.pushViewController(
                ContentBlockingSettingsViewController(),
                animated: true
            )
        case .privacyPolicy:
            pushStaticContent(
                title: "隐私政策",
                segments: SettingsLegalContent.privacyPolicy()
            )
        case .terms:
            pushStaticContent(
                title: "使用条款",
                segments: SettingsLegalContent.terms()
            )
        case .openSourceLicenses:
            pushStaticContent(
                title: "开源许可证",
                segments: SettingsLegalContent.openSourceLicenses()
            )
        case .about:
            pushStaticContent(
                title: "关于嗅探浏览器",
                segments: SettingsLegalContent.about()
            )
        case .storage:
            if let onSelectDestination {
                onSelectDestination(.storage)
            } else {
                navigationController?.pushViewController(
                    SettingsStorageInfoViewController(),
                    animated: true
                )
            }
        case .appearance, .clearBrowsingData, .downloadPreferences:
            break
        }
    }

    func showBrowsingDataClearCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let alert = UIAlertController(
            title: "浏览数据已清除",
            message: "Cookie、网站存储与网页缓存已移除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func pushStaticContent(
        title: String,
        segments: [StaticContentSegment]
    ) {
        navigationController?.pushViewController(
            StaticContentViewController(title: title, segments: segments),
            animated: true
        )
    }
}

@MainActor
private final class SettingsSwiftUIStore: ObservableObject {
    @Published var searchEngine = BrowserPreferences().searchEngine.displayName
    @Published var appearance = AppearancePreference.current.displayName
    @Published var theme = AppThemeColor.current.displayName
    @Published var canClearBrowsingData = false

    func refresh() {
        searchEngine = BrowserPreferences().searchEngine.displayName
        appearance = AppearancePreference.current.displayName
        theme = AppThemeColor.current.displayName
    }
}

private struct SettingsSwiftUIScreen: View {
    @ObservedObject var store: SettingsSwiftUIStore
    let onSelect: (SettingsViewController.Destination) -> Void
    @State private var confirmsClear = false

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                LazyVStack(spacing: 22) {
                    browserSection
                    privacySection
                    storageSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .alert("清除浏览数据？", isPresented: $confirmsClear) {
            Button("清除", role: .destructive) {
                onSelect(.clearBrowsingData)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Cookie、网站存储与网页缓存将被清除，当前网页会重新载入。")
        }
    }

    private var browserSection: some View {
        section(title: "浏览") {
            row(
                "默认搜索引擎",
                "地址栏与新标签页搜索",
                "magnifyingglass",
                detail: store.searchEngine,
                destination: .searchEngine
            )
            AppSwiftUIDivider()
            row(
                "新标签页",
                "主页背景、快捷入口与打开方式",
                "plus.square.on.square",
                destination: .newTabBehavior
            )
            AppSwiftUIDivider()
            row(
                "外观与主题",
                "全局界面、按钮和图标颜色",
                "circle.lefthalf.filled",
                detail: "\(store.appearance) · \(store.theme)",
                destination: .appearance
            )
        }
    }

    private var privacySection: some View {
        section(
            title: "隐私与安全",
            footer: "网站权限始终由用户明确决定；应用不会绕过 HTTPS 证书验证。"
        ) {
            row(
                "内容拦截",
                "过滤规则、统计和网站白名单",
                "shield.lefthalf.filled",
                destination: .contentBlocking
            )
            AppSwiftUIDivider()
            row(
                "网站权限",
                "摄像头、麦克风与位置",
                "hand.raised",
                destination: .websitePermissions
            )
            AppSwiftUIDivider()
            AppSwiftUIActionRow(
                title: "清除浏览数据",
                subtitle: "Cookie、网站数据与缓存",
                systemName: "trash",
                showsLeadingIcon: false,
                isDestructive: true,
                isEnabled: store.canClearBrowsingData,
                showsChevron: false
            ) {
                confirmsClear = true
            }
            .accessibilityIdentifier("settings.clearBrowsingData")
        }
    }

    private var storageSection: some View {
        section(title: "下载与存储") {
            row(
                "下载设置",
                "网络、并发、重试与保存位置",
                "arrow.down.circle",
                destination: .downloadPreferences,
                identifier: "settings.downloadPreferences"
            )
            AppSwiftUIDivider()
            row(
                "存储空间",
                "本地文件与缓存占用",
                "internaldrive",
                destination: .storage
            )
        }
    }

    private var aboutSection: some View {
        section(
            title: "关于",
            footer: "嗅探浏览器仅用于访问和管理用户有权获取的资源。"
        ) {
            row("隐私政策", nil, "lock.shield", destination: .privacyPolicy)
            AppSwiftUIDivider()
            row("使用条款", nil, "doc.text", destination: .terms)
            AppSwiftUIDivider()
            row(
                "开源许可证",
                nil,
                "chevron.left.forwardslash.chevron.right",
                destination: .openSourceLicenses
            )
            AppSwiftUIDivider()
            row(
                "关于嗅探浏览器",
                "版本 \(SettingsViewController.appVersion)",
                "info.circle",
                destination: .about
            )
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: title)
            AppSwiftUISectionCard {
                content()
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.tertiaryText)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(
        _ title: String,
        _ subtitle: String?,
        _ symbol: String,
        detail: String? = nil,
        destination: SettingsViewController.Destination,
        identifier: String? = nil
    ) -> some View {
        AppSwiftUIActionRow(
            title: title,
            subtitle: subtitle,
            systemName: symbol,
            showsLeadingIcon: false,
            detail: detail
        ) {
            onSelect(destination)
        }
        .accessibilityIdentifier(identifier ?? "settings.\(symbol)")
    }
}

private final class SettingsStorageInfoViewController: BaseViewController {
    init() {
        super.init(title: "存储空间", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(
            AppSwiftUIScreen {
                AppSwiftUIEmptyState(
                    systemName: "internaldrive",
                    title: "存储由文件管理统一维护",
                    message: "已完成的下载、视频包和缩略图缓存会显示在文件管理中。"
                )
            },
            in: contentView
        )
    }
}
