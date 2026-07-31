import UIKit

final class FavoritesViewController: BaseViewController {
    var onAddCurrentPage: (() -> Void)? {
        didSet {
            guard isViewLoaded else {
                updateEmptyStateActions()
                return
            }
            updateNavigationAction()
            updateEmptyStateActions()
        }
    }
    var onStartBrowsing: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }

    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "star",
            title: "收藏夹为空",
            message: "收藏持久化将在下一阶段接入；当前可以先返回浏览器继续浏览。",
            actionTitle: "开始浏览",
            secondaryActionTitle: "功能说明"
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

        updateNavigationAction()
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
                symbolName: "star",
                title: "收藏夹为空",
                message: "收藏持久化将在下一阶段接入；当前可以先返回浏览器继续浏览。",
                actionTitle: "开始浏览",
                secondaryActionTitle: "功能说明"
            ),
            action: actionWithFeedback(onStartBrowsing),
            secondaryAction: { [weak self] in self?.showFavoriteHelp() }
        )
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    @objc private func addPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAddCurrentPage?()
    }

    private func showFavoriteHelp() {
        let alert = UIAlertController(
            title: "收藏功能",
            message: "当前版本尚未保存收藏记录。下一阶段接入持久化后，收藏夹会支持新增、搜索与管理。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}
