import Combine
import SwiftUI
import UIKit

final class HistoryViewController: BaseViewController {
    var onStartBrowsing: (() -> Void)?
    var onOpenPrivateTab: (() -> Void)?
    var onOpenHistoryItem: ((HistoryItem) -> Void)?

    private let store = HistorySwiftUIStore()

    init() {
        super.init(title: "历史记录", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        installSwiftUI(
            HistorySwiftUIScreen(
                store: store,
                onStartBrowsing: { [weak self] in self?.onStartBrowsing?() },
                onOpenPrivateTab: { [weak self] in self?.onOpenPrivateTab?() },
                onOpen: { [weak self] item in self?.onOpenHistoryItem?(item) }
            ),
            in: contentView
        )
        store.reload()
    }

    private func configureNavigation() {
        let clearAction = UIAction(
            title: "清除浏览记录",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
        ) { [weak store = self.store] _ in
            store?.confirmsClear = true
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [clearAction])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "历史记录更多操作"
    }
}

@MainActor
private final class HistorySwiftUIStore: ObservableObject {
    @Published private(set) var state = HistoryViewState.empty
    @Published var confirmsClear = false
    @Published var errorMessage: String?
    private let viewModel = HistoryViewModel()

    init() {
        viewModel.onStateChange = { [weak self] state in
            self?.state = state
        }
        viewModel.onError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
        }
    }

    var query: String {
        get { state.searchQuery }
        set { viewModel.updateSearchQuery(newValue) }
    }

    func reload() {
        viewModel.reload()
    }

    func remove(_ item: HistoryItem) {
        if viewModel.remove(item) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func clearAll() {
        confirmsClear = false
        if viewModel.clearAll() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

private struct HistorySwiftUIScreen: View {
    @ObservedObject var store: HistorySwiftUIStore
    let onStartBrowsing: () -> Void
    let onOpenPrivateTab: () -> Void
    let onOpen: (HistoryItem) -> Void

    private var queryBinding: Binding<String> {
        Binding(get: { store.query }, set: { store.query = $0 })
    }

    var body: some View {
        AppSwiftUIScreen {
            VStack(spacing: 12) {
                AppSwiftUISearchField(
                    placeholder: "搜索网页标题或网址",
                    text: queryBinding
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("history.search")

                if store.state.sections.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    historyList
                }
            }
        }
        .alert("清除全部历史记录？", isPresented: $store.confirmsClear) {
            Button("清除", role: .destructive) { store.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除已保存的网页访问记录，且无法撤销。")
        }
        .alert(
            "无法更新历史记录",
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

    private var historyList: some View {
        List {
            ForEach(store.state.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        HistorySwiftUIRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("删除", role: .destructive) {
                                    store.remove(item)
                                }
                            }
                            .listRowBackground(AppSwiftUIColors.surface.opacity(0.78))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("history.list")
    }

    private var emptyState: some View {
        Group {
            if store.state.isFiltering {
                AppSwiftUIEmptyState(
                    systemName: "magnifyingglass",
                    title: "未找到记录",
                    message: "没有与“\(store.state.searchQuery)”匹配的标题或网址。",
                    primaryTitle: "清除搜索",
                    primaryAction: { store.query = "" }
                )
            } else {
                AppSwiftUIEmptyState(
                    systemName: "clock.arrow.circlepath",
                    title: "暂无浏览记录",
                    message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。",
                    primaryTitle: "开始浏览",
                    secondaryTitle: "新建无痕标签",
                    primaryAction: onStartBrowsing,
                    secondaryAction: onOpenPrivateTab
                )
            }
        }
    }
}

private struct HistorySwiftUIRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            AppSwiftUIIconBadge(systemName: "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(item.host)
                    .font(.subheadline)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.visitedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
