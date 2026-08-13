import Combine
import SwiftUI
import UIKit

@MainActor
final class FavoritesViewController: BaseViewController {
    var onAddCurrentPage: (() -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            updateNavigationAction()
        }
    }
    var onStartBrowsing: (() -> Void)?
    var onOpenFavorite: ((FavoriteItem) -> Void)?
    var onOpenFavoriteInNewTab: ((FavoriteItem) -> Void)?
    var onError: ((Error) -> Void)?

    private let store: FavoritesSwiftUIStore

    init(viewModel: FavoritesViewModel? = nil) {
        store = FavoritesSwiftUIStore(viewModel: viewModel ?? FavoritesViewModel())
        super.init(title: "收藏夹", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        store = FavoritesSwiftUIStore(viewModel: FavoritesViewModel())
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateNavigationAction()
        store.onError = { [weak self] error in
            self?.onError?(error)
        }
        installSwiftUI(
            FavoritesSwiftUIScreen(
                store: store,
                onStartBrowsing: { [weak self] in self?.onStartBrowsing?() },
                onOpen: { [weak self] item in self?.onOpenFavorite?(item) },
                onOpenInNewTab: { [weak self] item in
                    self?.onOpenFavoriteInNewTab?(item)
                }
            ),
            in: contentView
        )
        store.reload()
    }

    private func updateNavigationAction() {
        guard onAddCurrentPage != nil else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addPressed)
        )
        addButton.accessibilityLabel = "收藏当前网页"
        navigationItem.rightBarButtonItem = addButton
    }

    @objc private func addPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAddCurrentPage?()
    }
}

@MainActor
private final class FavoritesSwiftUIStore: ObservableObject {
    @Published private(set) var state = FavoritesViewState.empty
    @Published var pendingDeletion: FavoriteItem?
    @Published var errorMessage: String?
    var onError: ((Error) -> Void)?

    private let viewModel: FavoritesViewModel

    init(viewModel: FavoritesViewModel) {
        self.viewModel = viewModel
        state = viewModel.state
        viewModel.onStateChange = { [weak self] state in
            self?.state = state
        }
        viewModel.onError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
            self?.onError?(error)
        }
    }

    var query: String {
        get { state.searchQuery }
        set { viewModel.updateSearchQuery(newValue) }
    }

    func reload() {
        viewModel.reload()
    }

    func removePendingItem() {
        guard let item = pendingDeletion else { return }
        pendingDeletion = nil
        if viewModel.remove(item) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func copy(_ item: FavoriteItem) {
        UIPasteboard.general.url = item.url
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct FavoritesSwiftUIScreen: View {
    @ObservedObject var store: FavoritesSwiftUIStore
    let onStartBrowsing: () -> Void
    let onOpen: (FavoriteItem) -> Void
    let onOpenInNewTab: (FavoriteItem) -> Void

    private var queryBinding: Binding<String> {
        Binding(get: { store.query }, set: { store.query = $0 })
    }

    var body: some View {
        AppSwiftUIScreen {
            VStack(spacing: 12) {
                AppSwiftUISearchField(
                    placeholder: "搜索收藏名称或网址",
                    text: queryBinding
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("favorites.search")

                if store.state.items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
        .alert(
            "删除收藏？",
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.pendingDeletion = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                store.removePendingItem()
            }
            Button("取消", role: .cancel) {
                store.pendingDeletion = nil
            }
        } message: {
            Text("“\(store.pendingDeletion?.title ?? "此网页")”将从收藏夹中移除。")
        }
        .alert(
            "无法更新收藏夹",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "请稍后重试。")
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.state.items) { item in
                    FavoriteSwiftUIRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(item) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) {
                                store.pendingDeletion = item
                            }
                            .tint(AppSwiftUIColors.danger)
                        }
                        .contextMenu {
                            Button("打开", systemImage: "arrow.up.right.square") {
                                onOpen(item)
                            }
                            Button("在新标签页打开", systemImage: "plus.square.on.square") {
                                onOpenInNewTab(item)
                            }
                            Button("复制链接", systemImage: "doc.on.doc") {
                                store.copy(item)
                            }
                            ShareLink(item: item.url) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                store.pendingDeletion = item
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .listRowBackground(AppSwiftUIColors.surface.opacity(0.78))
                }
            } header: {
                Text("已收藏 \(store.state.totalCount)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("favorites.list")
    }

    private var emptyState: some View {
        Group {
            if store.state.isFiltering {
                AppSwiftUIEmptyState(
                    systemName: "magnifyingglass",
                    title: "未找到收藏",
                    message: "没有与“\(store.state.searchQuery)”匹配的标题或网址。",
                    primaryTitle: "清除搜索",
                    primaryAction: { store.query = "" }
                )
            } else {
                AppSwiftUIEmptyState(
                    systemName: "star",
                    title: "收藏夹为空",
                    message: "收藏的网页会安全保存在这台设备上。",
                    primaryTitle: "开始浏览",
                    primaryAction: onStartBrowsing
                )
            }
        }
    }
}

private struct FavoriteSwiftUIRow: View {
    let item: FavoriteItem

    var body: some View {
        HStack(spacing: 10) {
            AppSwiftUIFavicon(
                pageURL: item.url,
                faviconURL: item.faviconURL,
                fallbackSystemName: "star.fill"
            )
            .frame(width: 16, height: 16)
            .clipped()
            .frame(width: 28, height: 28)
            .background(
                AppSwiftUIColors.accentFill,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppSwiftUIColors.primaryText)
                    .lineLimit(2)
                Text(item.host)
                    .font(.subheadline)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("收藏于 \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.tertiaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
