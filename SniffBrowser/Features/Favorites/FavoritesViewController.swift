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
    @Published var errorMessage: String?
    @Published private(set) var undoMessage: String?
    var onError: ((Error) -> Void)?

    private let viewModel: FavoritesViewModel
    private var pendingUndoItem: FavoriteItem?
    private var undoDismissTask: Task<Void, Never>?

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

    func remove(_ item: FavoriteItem) {
        guard let removedItem = viewModel.removeForUndo(item) else { return }
        pendingUndoItem = removedItem
        undoMessage = "已删除“\(removedItem.title)”"
        scheduleUndoDismissal()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func undoDeletion() {
        guard let item = pendingUndoItem else { return }
        undoDismissTask?.cancel()
        pendingUndoItem = nil
        undoMessage = nil
        if viewModel.restore(item) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func copy(_ item: FavoriteItem) {
        UIPasteboard.general.url = item.url
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func scheduleUndoDismissal() {
        undoDismissTask?.cancel()
        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingUndoItem = nil
            self?.undoMessage = nil
        }
    }

    deinit {
        undoDismissTask?.cancel()
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
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if let undoMessage = store.undoMessage {
                AppSwiftUIUndoBanner(
                    message: undoMessage,
                    onUndo: store.undoDeletion
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.undoMessage)
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
                                store.remove(item)
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
                                store.remove(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .listRowBackground(AppSwiftUIColors.surface)
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
                fallbackSystemName: "globe"
            )
            // 与“文件”页面的缩略图使用同一尺寸，避免 favicon 在列表中
            // 看起来像一个被二次缩小的小徽标。
            .frame(
                width: AppMetrics.primaryButtonHeight,
                height: AppMetrics.primaryButtonHeight
            )
            .clipped()
            .background(
                AppSwiftUIColors.accentFill,
                in: RoundedRectangle(
                    cornerRadius: AppRadius.control,
                    style: .continuous
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppRadius.control,
                    style: .continuous
                )
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
