import Combine
import Foundation
import SwiftUI
import UIKit

/// SwiftUI 对 UIKit 语义色的唯一映射。所有迁移页面都从这里取色，
/// 因此外观模式和全局主题色切换仍由现有 trait 系统驱动。
enum AppSwiftUIColors {
    static let background = Color(uiColor: AppColors.background)
    static let surface = Color(uiColor: AppColors.surface)
    static let secondarySurface = Color(uiColor: AppColors.secondarySurface)
    static let tertiarySurface = Color(uiColor: AppColors.tertiarySurface)
    static let primaryText = Color(uiColor: AppColors.primaryText)
    static let secondaryText = Color(uiColor: AppColors.secondaryText)
    static let tertiaryText = Color(uiColor: AppColors.tertiaryText)
    static let accent = Color(uiColor: AppColors.accent)
    static let accentContent = Color(uiColor: AppColors.accentContent)
    static let accentFill = Color(uiColor: AppColors.accentFill)
    static let separator = Color(uiColor: AppColors.separator)
    static let danger = Color(uiColor: AppColors.danger)
    static let success = Color(uiColor: AppColors.success)
}

/// 管理页面中可安全跨启动保留的展示偏好。这里只保存筛选/排序的原始值，
/// 不保存搜索词、网页内容或任何敏感数据。
struct AppManagementListPreferences {
    private enum Key {
        static let downloadScope = "management.download.scope"
        static let fileCategory = "management.files.category"
        static let fileSortOrder = "management.files.sortOrder"
        static let contentBlockingStatisticsRange =
            "management.contentBlocking.statisticsRange"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var downloadScopeRawValue: Int {
        get { defaults.integer(forKey: Key.downloadScope) }
        nonmutating set { defaults.set(newValue, forKey: Key.downloadScope) }
    }

    var fileCategoryRawValue: Int {
        get { defaults.integer(forKey: Key.fileCategory) }
        nonmutating set { defaults.set(newValue, forKey: Key.fileCategory) }
    }

    var fileSortOrderRawValue: Int {
        get {
            // 日期是文件页原有默认顺序。UserDefaults 在键不存在时返回 0，
            // 会被误解为“名称”，因此显式区分首次使用和已保存的值。
            guard defaults.object(forKey: Key.fileSortOrder) != nil else {
                return 1
            }
            return defaults.integer(forKey: Key.fileSortOrder)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.fileSortOrder) }
    }

    var contentBlockingStatisticsRangeRawValue: String {
        get {
            defaults.string(forKey: Key.contentBlockingStatisticsRange)
                ?? "今日"
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.contentBlockingStatisticsRange)
        }
    }
}

/// 全应用 SwiftUI 页面画布。背景只属于应用界面，不会覆盖 WKWebView 网页。
struct AppSwiftUIScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppSwiftUIColors.background
                .ignoresSafeArea()
            content
        }
        .tint(AppSwiftUIColors.accent)
        .foregroundStyle(AppSwiftUIColors.primaryText)
    }
}

struct AppSwiftUISectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppSwiftUIColors.primaryText)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.tertiaryText)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 同类内容共享一个不透明面板，以细分隔线组织层级；平面内容不使用玻璃。
struct AppSwiftUISectionCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AppSwiftUIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay {
            if colorSchemeContrast == .increased {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .stroke(AppSwiftUIColors.separator, lineWidth: 1)
            }
        }
    }
}

/// 为仍需保留系统 `List` 左滑操作的管理页面提供统一分组外形。
/// `List(.insetGrouped)` 的默认圆角小于应用面板圆角，因此只替换每行
/// 的背景几何；列表的滚动、左滑操作和系统上下文菜单均保持不变。
enum AppSwiftUIGroupedRowPosition: Equatable {
    case single
    case first
    case middle
    case last

    init(index: Int, count: Int) {
        if count <= 1 {
            self = .single
        } else if index <= 0 {
            self = .first
        } else if index >= count - 1 {
            self = .last
        } else {
            self = .middle
        }
    }

    var roundsTopCorners: Bool {
        self == .single || self == .first
    }

    var roundsBottomCorners: Bool {
        self == .single || self == .last
    }
}

struct AppSwiftUIGroupedRowBackground: View {
    let position: AppSwiftUIGroupedRowPosition

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: position.roundsTopCorners ? AppRadius.panel : 0,
            bottomLeadingRadius: position.roundsBottomCorners ? AppRadius.panel : 0,
            bottomTrailingRadius: position.roundsBottomCorners ? AppRadius.panel : 0,
            topTrailingRadius: position.roundsTopCorners ? AppRadius.panel : 0,
            style: .continuous
        )
        .fill(AppSwiftUIColors.surface)
    }
}

struct AppSwiftUIIconBadge: View {
    let systemName: String
    var tint: Color = AppSwiftUIColors.secondaryText
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: min(22, size * 0.72), weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 导航型设置行。视觉来自 ShipSwift setting recipe，导航仍交给 AppCoordinator。
struct AppSwiftUIActionRow: View {
    let title: String
    var subtitle: String? = nil
    let systemName: String
    var showsLeadingIcon = true
    var detail: String? = nil
    var tint: Color = AppSwiftUIColors.accent
    var isDestructive = false
    var isEnabled = true
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if showsLeadingIcon {
                    AppSwiftUIIconBadge(
                        systemName: systemName,
                        tint: isDestructive ? AppSwiftUIColors.danger : tint
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(
                            isDestructive
                                ? AppSwiftUIColors.danger
                                : AppSwiftUIColors.primaryText
                        )
                        .lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppSwiftUIColors.secondaryText)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppSwiftUIColors.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct AppSwiftUIDivider: View {
    var leading: CGFloat = 16

    var body: some View {
        AppSwiftUIColors.separator
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, leading)
    }
}

/// ShipSwift Search Bar recipe adapted to the app's semantic palette.
struct AppSwiftUISearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppSwiftUIColors.secondaryText)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AppSwiftUIColors.primaryText)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppSwiftUIColors.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(AppSwiftUIColors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}

struct AppSwiftUIEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var primaryTitle: String? = nil
    var secondaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .frame(width: 64, height: 64)

            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppSwiftUIColors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppSwiftUIColors.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

/// 轻量、可撤销操作的统一反馈。用于单条收藏和历史记录删除；真正删除
/// 文件或批量清空仍由确认弹窗保护。
struct AppSwiftUIUndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppSwiftUIColors.success)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppSwiftUIColors.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("撤销", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppSwiftUIColors.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .background(AppSwiftUIColors.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.overlayControl, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        // 保留“撤销”按钮为独立可操作元素，VoiceOver 不会把它合并成
        // 一段无法点击的静态文字。
        .accessibilityElement(children: .contain)
    }
}

struct AppSwiftUIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppSwiftUIColors.accentContent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                AppSwiftUIColors.accent.opacity(configuration.isPressed ? 0.78 : 1),
                in: Capsule(style: .continuous)
            )
            .scaleEffect(
                reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1)
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}

@MainActor
extension UIViewController {
    /// 将 SwiftUI 展示层安装到现有 UIKit 控制器中；控制器仍保留路由、
    /// 文档选择器、分享和 WebKit 等系统职责。
    @discardableResult
    func installSwiftUI<Content: View>(
        _ rootView: Content,
        in container: UIView
    ) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        host.didMove(toParent: self)
        return host
    }
}

/// SwiftUI 列表中复用现有 favicon 缓存，避免引入第二套网络图片实现。
struct AppSwiftUIFavicon: UIViewRepresentable {
    let pageURL: URL
    var faviconURL: URL? = nil
    var fallbackSystemName = "globe"

    func makeUIView(context: Context) -> AppFaviconImageView {
        AppFaviconImageView(frame: .zero)
    }

    func updateUIView(_ uiView: AppFaviconImageView, context: Context) {
        uiView.configure(
            pageURL: pageURL,
            faviconURL: faviconURL,
            fallbackSystemName: fallbackSystemName
        )
    }

    static func dismantleUIView(_ uiView: AppFaviconImageView, coordinator: ()) {
        uiView.cancelLoad()
    }
}

final class AppFaviconImageView: UIImageView {
    private var currentURL: URL?
    private var requestID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        pageURL: URL,
        faviconURL: URL?,
        fallbackSystemName: String
    ) {
        let resolvedURL = faviconURL ?? FaviconLoader.faviconURL(for: pageURL)
        guard resolvedURL != currentURL else { return }
        cancelLoad()
        currentURL = resolvedURL
        image = UIImage(systemName: fallbackSystemName)
        tintColor = AppColors.accent
        backgroundColor = .clear
        guard let resolvedURL else { return }

        var pendingID: UUID?
        pendingID = FaviconLoader.shared.load(url: resolvedURL) { [weak self] image in
            guard let self,
                  self.currentURL == resolvedURL,
                  self.requestID == pendingID,
                  let image
            else { return }
            self.image = image
            self.tintColor = nil
            self.contentMode = .scaleAspectFit
        }
        requestID = pendingID
    }

    func cancelLoad() {
        if let currentURL, let requestID {
            FaviconLoader.shared.cancel(url: currentURL, requestID: requestID)
        }
        currentURL = nil
        requestID = nil
    }
}
