import UIKit

final class HistoryViewController: BaseViewController {
    var onClearHistory: (() -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            updateNavigationActions()
        }
    }
    var onStartBrowsing: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }
    var onOpenPrivateTab: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }

    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "clock.arrow.circlepath",
            title: "暂无浏览记录",
            message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。",
            actionTitle: "开始浏览",
            secondaryActionTitle: "新建无痕标签"
        )
    )

    init() {
        super.init(title: "历史记录", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureEmptyState()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索网页标题或网址"
        searchController.searchBar.accessibilityLabel = "搜索历史记录"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        updateNavigationActions()
    }

    private func updateNavigationActions() {
        guard onClearHistory != nil else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let clearAction = UIAction(
            title: "清除浏览记录",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
        ) { [weak self] _ in
            self?.confirmClearHistory()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [clearAction])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "历史记录更多操作"
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        updateEmptyStateActions()
    }

    private func updateEmptyStateActions() {
        emptyState.configure(
            .init(
                symbolName: "clock.arrow.circlepath",
                title: "暂无浏览记录",
                message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。",
                actionTitle: "开始浏览",
                secondaryActionTitle: "新建无痕标签"
            ),
            action: actionWithFeedback(onStartBrowsing),
            secondaryAction: actionWithFeedback(onOpenPrivateTab)
        )
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    private func confirmClearHistory() {
        guard onClearHistory != nil else { return }
        let alert = UIAlertController(
            title: "清除全部历史记录？",
            message: "此操作会删除已保存的网页访问记录，且无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.onClearHistory?()
        })
        present(alert, animated: true)
    }
}
