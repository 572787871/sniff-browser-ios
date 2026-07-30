import UIKit

final class FavoritesViewController: BaseViewController {
    var onAddCurrentPage: (() -> Void)?

    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "star",
            title: "还没有收藏",
            message: "在浏览器的更多菜单中收藏网页，之后可从这里快速访问。"
        )
    )

    init() {
        super.init(title: "收藏夹", prefersLargeTitle: true)
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
        searchController.searchBar.placeholder = "搜索收藏名称或网址"
        searchController.searchBar.accessibilityLabel = "搜索收藏夹"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addPressed)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "收藏当前网页"
        navigationItem.rightBarButtonItem?.isEnabled = onAddCurrentPage != nil
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

    @objc private func addPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAddCurrentPage?()
    }
}
