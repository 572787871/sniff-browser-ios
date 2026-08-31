import SwiftUI
import UIKit

enum BrowserQuickAction: CaseIterable, Hashable {
    case newTab
    case share
    case favorite
    case reload

    var title: String {
        switch self {
        case .newTab: return "新建标签"
        case .share: return "分享"
        case .favorite: return "添加收藏"
        case .reload: return "刷新"
        }
    }

    var symbolName: String {
        switch self {
        case .newTab: return "plus"
        case .share: return "square.and.arrow.up"
        case .favorite: return "star"
        case .reload: return "arrow.clockwise"
        }
    }
}

enum BrowserMenuDestination: CaseIterable, Hashable {
    case downloads
    case files
    case favorites
    case history
    case userCenter
    case settings

    var title: String {
        switch self {
        case .downloads: return "下载管理"
        case .files: return "文件管理"
        case .favorites: return "收藏夹"
        case .history: return "历史记录"
        case .userCenter: return "用户中心"
        case .settings: return "浏览器设置"
        }
    }

    var symbolName: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .files: return "folder"
        case .favorites: return "star"
        case .history: return "clock.arrow.circlepath"
        case .userCenter: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}

struct BrowserMoreMenuState: Equatable {
    var hasCurrentPage: Bool
    var downloadSummary: String?
    var fileSummary: String?
    var accountSummary: String?
    var favoriteActionState = FavoriteActionState(
        isEnabled: false,
        isFavorite: false
    )

    func isEnabled(_ action: BrowserQuickAction) -> Bool {
        switch action {
        case .newTab: return true
        case .favorite: return favoriteActionState.isEnabled
        case .share, .reload: return hasCurrentPage
        }
    }

    func title(for action: BrowserQuickAction) -> String {
        action == .favorite ? favoriteActionState.title : action.title
    }

    func symbolName(for action: BrowserQuickAction) -> String {
        action == .favorite
            ? favoriteActionState.systemImageName
            : action.symbolName
    }

    func detail(for destination: BrowserMenuDestination) -> String? {
        switch destination {
        case .downloads: return downloadSummary
        case .files: return fileSummary
        case .userCenter: return accountSummary
        case .favorites, .history, .settings: return nil
        }
    }
}

@MainActor
final class BrowserMoreMenuViewController: UIViewController {
    var onQuickAction: ((BrowserQuickAction) -> Void)?
    var onSelectDestination: ((BrowserMenuDestination) -> Void)?

    private let state: BrowserMoreMenuState

    init(state: BrowserMoreMenuState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "浏览器菜单"
        view.backgroundColor = AppColors.background
        installSwiftUI(
            BrowserMoreMenuSwiftUIScreen(
                state: state,
                onQuickAction: { [weak self] action in
                    self?.dismiss(animated: true) {
                        self?.onQuickAction?(action)
                    }
                },
                onSelectDestination: { [weak self] destination in
                    self?.onSelectDestination?(destination)
                }
            ),
            in: view
        )
    }
}

@MainActor
final class BrowserMoreNavigationController: UINavigationController,
    UINavigationControllerDelegate {
    init(root: BrowserMoreMenuViewController) {
        super.init(rootViewController: root)
        modalPresentationStyle = .pageSheet
        navigationBar.prefersLargeTitles = false
        navigationBar.tintColor = AppColors.accent
        delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        navigationController.setNavigationBarHidden(false, animated: animated)
    }
}

private struct BrowserMoreMenuSwiftUIScreen: View {
    let state: BrowserMoreMenuState
    let onQuickAction: (BrowserQuickAction) -> Void
    let onSelectDestination: (BrowserMenuDestination) -> Void

    private let primaryDestinations: [BrowserMenuDestination] = [
        .downloads, .files, .favorites, .history
    ]
    private let accountDestinations: [BrowserMenuDestination] = [
        .userCenter, .settings
    ]

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 20) {
                    quickActions

                    destinationSection(primaryDestinations)
                    destinationSection(accountDestinations)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(BrowserQuickAction.allCases, id: \.self) { action in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onQuickAction(action)
                } label: {
                    VStack(spacing: 9) {
                        Image(systemName: state.symbolName(for: action))
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(AppSwiftUIColors.primaryText)
                            .frame(width: 44, height: 44)
                        Text(state.title(for: action))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppSwiftUIColors.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                }
                .buttonStyle(.plain)
                .disabled(!state.isEnabled(action))
                .opacity(state.isEnabled(action) ? 1 : 0.38)
                .accessibilityIdentifier("browser.menu.quick.\(action.title)")
            }
        }
    }

    private func destinationSection(
        _ destinations: [BrowserMenuDestination]
    ) -> some View {
        AppSwiftUISectionCard {
            ForEach(Array(destinations.enumerated()), id: \.element) { index, destination in
                AppSwiftUIActionRow(
                    title: destination.title,
                    systemName: destination.symbolName,
                    detail: state.detail(for: destination)
                ) {
                    onSelectDestination(destination)
                }
                .accessibilityIdentifier("browser.menu.\(destination.title)")
                if index < destinations.count - 1 {
                    AppSwiftUIDivider()
                }
            }
        }
    }
}
