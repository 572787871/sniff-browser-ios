import Combine
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

            LinearGradient(
                colors: [
                    AppSwiftUIColors.accent.opacity(0.075),
                    .clear,
                    AppSwiftUIColors.secondarySurface.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

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

/// ShipSwift Settings recipe 的分区容器，调整为项目的蓝灰玻璃材质。
struct AppSwiftUISectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.regularMaterial)
        .background(AppSwiftUIColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppSwiftUIColors.separator, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.055), radius: 14, y: 7)
    }
}

struct AppSwiftUIIconBadge: View {
    let systemName: String
    var tint: Color = AppSwiftUIColors.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(
                cornerRadius: max(9, size * 0.28),
                style: .continuous
            ))
            .accessibilityHidden(true)
    }
}

/// 导航型设置行。视觉来自 ShipSwift setting recipe，导航仍交给 AppCoordinator。
struct AppSwiftUIActionRow: View {
    let title: String
    var subtitle: String? = nil
    let systemName: String
    var detail: String? = nil
    var tint: Color = AppSwiftUIColors.accent
    var isDestructive = false
    var isEnabled = true
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AppSwiftUIIconBadge(
                    systemName: systemName,
                    tint: isDestructive ? AppSwiftUIColors.danger : tint
                )

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
    var leading: CGFloat = 64

    var body: some View {
        AppSwiftUIColors.separator
            .frame(height: 0.7)
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
        .frame(minHeight: 48)
        .background(.regularMaterial)
        .background(AppSwiftUIColors.surface.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppSwiftUIColors.separator, lineWidth: 0.7)
        }
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
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppSwiftUIColors.accent)
                .frame(width: 76, height: 76)
                .background(
                    AppSwiftUIColors.accentFill,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )

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

struct AppSwiftUIPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppSwiftUIColors.accentContent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                AppSwiftUIColors.accent.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
        AppFaviconImageView()
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
