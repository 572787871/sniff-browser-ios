import UIKit

final class HistoryViewController: BaseViewController {
    var onClearHistory: (() -> Void)?

    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "clock.arrow.circlepath",
            title: "暂无浏览记录",
            message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。"
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

        let clearAction = UIAction(
            title: "清除浏览记录",
            image: UIImage(systemName: "trash"),
            attributes: onClearHistory == nil
                ? [.destructive, .disabled]
                : [.destructive]
        ) { [weak self] _ in
            self?.onClearHistory?()
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
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            emptyState.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12)
        ])
    }
}
