import Combine
import SwiftUI
import UIKit

/// 用户中心的隐私入口。这里只展示隐私相关能力，避免把用户带回完整设置页。
final class PrivacySecurityViewController: BaseViewController {
    enum Destination: Equatable {
        case websitePermissions
        case contentBlocking
        case privacyPolicy
        case clearBrowsingData
    }

    var onClearBrowsingData: (() -> Void)? {
        didSet {
            store.canClearBrowsingData = onClearBrowsingData != nil
        }
    }

    private let store = PrivacySecuritySwiftUIStore()

    init() {
        super.init(title: "隐私与安全", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.canClearBrowsingData = onClearBrowsingData != nil
        installSwiftUI(
            PrivacySecuritySwiftUIScreen(
                store: store,
                onSelect: { [weak self] destination in
                    self?.selectDestination(destination)
                }
            ),
            in: contentView
        )
    }

    /// 单一导航入口，供 SwiftUI 行与回归测试共同使用。
    func selectDestination(_ destination: Destination) {
        switch destination {
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
            navigationController?.pushViewController(
                StaticContentViewController(
                    title: "隐私政策",
                    segments: SettingsLegalContent.privacyPolicy()
                ),
                animated: true
            )
        case .clearBrowsingData:
            onClearBrowsingData?()
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
}

@MainActor
private final class PrivacySecuritySwiftUIStore: ObservableObject {
    @Published var canClearBrowsingData = false
}

private struct PrivacySecuritySwiftUIScreen: View {
    @ObservedObject var store: PrivacySecuritySwiftUIStore
    let onSelect: (PrivacySecurityViewController.Destination) -> Void
    @State private var confirmsClear = false

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 22) {
                    privacySummary
                    privacyControls
                    dataControls
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

    private var privacySummary: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(AppSwiftUIColors.secondaryText)
                .frame(width: 36, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("隐私由你控制")
                    .font(.headline)
                Text("管理网站权限、内容拦截和本地浏览数据。")
                    .font(.subheadline)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var privacyControls: some View {
        section(title: "网站与内容") {
            row(
                "网站权限",
                "摄像头、麦克风与位置",
                "hand.raised",
                destination: .websitePermissions,
                identifier: "privacySecurity.websitePermissions"
            )
            AppSwiftUIDivider()
            row(
                "内容拦截",
                "过滤规则、统计和网站白名单",
                "shield.lefthalf.filled",
                destination: .contentBlocking,
                identifier: "privacySecurity.contentBlocking"
            )
        }
    }

    private var dataControls: some View {
        section(title: "数据与政策") {
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
            .accessibilityIdentifier("privacySecurity.clearBrowsingData")
            AppSwiftUIDivider()
            row(
                "隐私政策",
                "了解应用如何处理本地数据",
                "lock.shield",
                destination: .privacyPolicy,
                identifier: "privacySecurity.privacyPolicy"
            )
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: title)
            AppSwiftUISectionCard {
                content()
            }
        }
    }

    private func row(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        destination: PrivacySecurityViewController.Destination,
        identifier: String
    ) -> some View {
        AppSwiftUIActionRow(
            title: title,
            subtitle: subtitle,
            systemName: symbol,
            showsLeadingIcon: false
        ) {
            onSelect(destination)
        }
        .accessibilityIdentifier(identifier)
    }
}
