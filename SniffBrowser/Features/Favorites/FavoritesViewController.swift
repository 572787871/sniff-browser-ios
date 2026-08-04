import UIKit

@MainActor
final class FavoritesViewController: BaseViewController {
    var onAddCurrentPage: (() -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            updateNavigationAction()
        }
    }
    var onStartBrowsing: (() -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            render(viewModel.state)
        }
    }
    var onOpenFavorite: ((FavoriteItem) -> Void)?
    var onOpenFavoriteInNewTab: ((FavoriteItem) -> Void)?
    var onError: ((Error) -> Void)?

    private let viewModel: FavoritesViewModel
    private let searchController = UISearchController(searchResultsController: nil)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var pendingError: Error?
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "star",
            title: "收藏夹为空",
            message: "收藏的网页会安全保存在这台设备上。",
            actionTitle: "开始浏览"
        )
    )

    init(viewModel: FavoritesViewModel? = nil) {
        self.viewModel = viewModel ?? FavoritesViewModel()
        super.init(title: "收藏夹", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        viewModel = FavoritesViewModel()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureTable()
        configureEmptyState()
        bindViewModel()
        render(viewModel.state)
        viewModel.reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let pendingError else { return }
        presentPersistenceError(pendingError)
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索收藏名称或网址"
        searchController.searchBar.accessibilityLabel = "搜索收藏夹"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
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

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.register(
            FavoriteCell.self,
            forCellReuseIdentifier: FavoriteCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "favorites.list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
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
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
        viewModel.onError = { [weak self] error in
            self?.showPersistenceError(error)
        }
    }

    private func render(_ state: FavoritesViewState) {
        tableView.reloadData()
        let isEmpty = state.items.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        guard isEmpty else { return }

        if state.isFiltering {
            emptyState.configure(
                .init(
                    symbolName: "magnifyingglass",
                    title: "未找到收藏",
                    message: "没有与“\(state.searchQuery)”匹配的标题或网址。",
                    actionTitle: "清除搜索"
                ),
                action: { [weak self] in
                    self?.searchController.searchBar.text = nil
                    self?.viewModel.updateSearchQuery("")
                }
            )
        } else {
            emptyState.configure(
                .init(
                    symbolName: "star",
                    title: "收藏夹为空",
                    message: "收藏的网页会安全保存在这台设备上。",
                    actionTitle: onStartBrowsing == nil ? nil : "开始浏览"
                ),
                action: actionWithFeedback(onStartBrowsing)
            )
        }
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    private func confirmDelete(
        _ item: FavoriteItem,
        completion: ((Bool) -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: "删除收藏？",
            message: "“\(item.title)”将从收藏夹中移除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completion?(false)
        })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) {
            [weak self] _ in
            guard self?.viewModel.remove(item) == true else {
                completion?(false)
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completion?(true)
        })
        present(alert, animated: true)
    }

    private func copyLink(_ item: FavoriteItem) {
        UIPasteboard.general.url = item.url
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func share(_ item: FavoriteItem, sourceView: UIView?) {
        let controller = UIActivityViewController(
            activityItems: [item.title, item.url],
            applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = sourceView?.bounds ?? CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }

    private func showPersistenceError(_ error: Error) {
        onError?(error)
        presentPersistenceError(error)
    }

    private func presentPersistenceError(_ error: Error) {
        guard view.window != nil, presentedViewController == nil else {
            pendingError = error
            return
        }
        pendingError = nil
        let alert = UIAlertController(
            title: "无法更新收藏夹",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    @objc
    private func addPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAddCurrentPage?()
    }
}

extension FavoritesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.updateSearchQuery(searchController.searchBar.text ?? "")
    }
}

extension FavoritesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        viewModel.state.items.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: FavoriteCell.reuseIdentifier,
            for: indexPath
        ) as? FavoriteCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.state.items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onOpenFavorite?(viewModel.state.items[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = viewModel.state.items[indexPath.row]
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "删除"
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            self.confirmDelete(item, completion: completion)
        }
        deleteAction.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let item = viewModel.state.items[indexPath.row]
        return UIContextMenuConfiguration(
            identifier: item.id.uuidString as NSString,
            previewProvider: nil
        ) { [weak self, weak tableView] _ in
            guard let self else { return nil }
            let open = UIAction(
                title: "打开",
                image: UIImage(systemName: "arrow.up.right.square"),
                attributes: self.onOpenFavorite == nil ? [.disabled] : []
            ) { [weak self] _ in
                self?.onOpenFavorite?(item)
            }
            let openInNewTab = UIAction(
                title: "在新标签页打开",
                image: UIImage(systemName: "plus.square.on.square"),
                attributes: self.onOpenFavoriteInNewTab == nil ? [.disabled] : []
            ) { [weak self] _ in
                self?.onOpenFavoriteInNewTab?(item)
            }
            let copy = UIAction(
                title: "复制链接",
                image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                self?.copyLink(item)
            }
            let share = UIAction(
                title: "分享",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self, weak tableView] _ in
                self?.share(
                    item,
                    sourceView: tableView?.cellForRow(at: indexPath)
                )
            }
            let delete = UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: [.destructive]
            ) { [weak self] _ in
                self?.confirmDelete(item)
            }
            return UIMenu(children: [
                UIMenu(options: .displayInline, children: [open, openInNewTab]),
                UIMenu(options: .displayInline, children: [copy, share]),
                UIMenu(options: .displayInline, children: [delete])
            ])
        }
    }
}

private final class FavoriteCell: UITableViewCell {
    static let reuseIdentifier = "FavoriteCell"

    private let symbolContainer = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let dateLabel = UILabel()
    private let textStack = UIStackView()
    private var currentFaviconURL: URL?
    private var faviconRequestID: UUID?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(with item: FavoriteItem) {
        titleLabel.text = item.title
        hostLabel.text = item.host
        let formattedDate = item.createdAt.formatted(
            date: .abbreviated,
            time: .omitted
        )
        dateLabel.text = "收藏于 \(formattedDate)"
        accessibilityLabel =
            "\(item.title)，\(item.host)，收藏于 \(formattedDate)"
        loadFavicon(for: item)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let url = currentFaviconURL, let faviconRequestID {
            FaviconLoader.shared.cancel(url: url, requestID: faviconRequestID)
        }
        currentFaviconURL = nil
        faviconRequestID = nil
    }

    private func loadFavicon(for item: FavoriteItem) {
        if let url = currentFaviconURL, let faviconRequestID {
            FaviconLoader.shared.cancel(url: url, requestID: faviconRequestID)
        }
        // Reset to default star icon
        symbolView.image = UIImage(systemName: "star.fill")
        symbolView.tintColor = AppColors.accent
        symbolContainer.backgroundColor = AppColors.accentFill

        let faviconURL = item.faviconURL ?? FaviconLoader.faviconURL(for: item.url)
        guard let url = faviconURL else { return }

        currentFaviconURL = url
        var requestID: UUID?
        requestID = FaviconLoader.shared.load(url: url) { [weak self] image in
            guard let self, let image, self.faviconRequestID == requestID else {
                return
            }
            self.symbolView.image = image
            self.symbolView.contentMode = .scaleAspectFill
            self.symbolView.tintColor = nil
            self.symbolContainer.backgroundColor = AppColors.tertiarySurface
        }
        faviconRequestID = requestID
    }

    private func configureView() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
        selectionStyle = .default
        accessoryType = .disclosureIndicator

        symbolContainer.backgroundColor = AppColors.accentFill
        symbolContainer.layer.cornerRadius = AppRadius.small
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false

        symbolView.image = UIImage(systemName: "star.fill")
        symbolView.tintColor = AppColors.accent
        symbolView.contentMode = .scaleAspectFill
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.addSubview(symbolView)

        AppTypography.configure(titleLabel, style: .body, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 2

        AppTypography.configure(hostLabel, style: .subheadline)
        hostLabel.textColor = AppColors.secondaryText
        hostLabel.numberOfLines = 1
        hostLabel.lineBreakMode = .byTruncatingMiddle

        AppTypography.configure(dateLabel, style: .caption1)
        dateLabel.textColor = AppColors.tertiaryText
        dateLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = AppSpacing.xxs
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(hostLabel)
        textStack.addArrangedSubview(dateLabel)

        contentView.addSubview(symbolContainer)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            symbolContainer.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor
            ),
            symbolContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolContainer.widthAnchor.constraint(equalToConstant: 40),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor),

            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 20),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),

            textStack.topAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.topAnchor
            ),
            textStack.leadingAnchor.constraint(
                equalTo: symbolContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            textStack.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            textStack.bottomAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.bottomAnchor
            ),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}
