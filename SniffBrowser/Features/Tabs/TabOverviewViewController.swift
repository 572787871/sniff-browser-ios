import UIKit

@MainActor
final class TabOverviewViewController: BaseViewController {
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: ((Bool) -> Void)?

    var onCloseOtherTabs: ((UUID) -> Void)?
    var onCloseAllNormalTabs: (() -> Void)?
    var onCopyTabURL: ((UUID, URL) -> Void)?
    var onShareTab: ((UUID, URL?) -> Void)?
    var onOpenFavorites: ((UUID) -> Void)?
    var onModeChanged: ((Bool) -> Void)?
    var onDone: (() -> Void)?

    private enum Section {
        case tabs
    }

    private var allItems: [TabOverviewItem]
    private var selectedMode: TabOverviewMode

    private var visibleItems: [TabOverviewItem] {
        allItems.filter { $0.isPrivate == selectedMode.isPrivate }
    }

    private let privacyTintView = UIView()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private lazy var dataSource = makeDataSource()
    private let emptyView = EmptyStateView(
        configuration: .init(
            symbolName: "square.on.square",
            title: "没有打开的标签页",
            message: "新建标签页后，可以在这里快速切换和管理网页。"
        )
    )
    private let bottomBar = TabOverviewBottomBar()

    init(items: [TabOverviewItem]) {
        allItems = items
        selectedMode = items.first(where: \.isSelected)?.isPrivate == true
            ? .privateBrowsing
            : .standard
        super.init(title: "标签页", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureBackground()
        configureBottomBar()
        configureCollectionView()
        registerForEnvironmentChanges()
        updateContent(animated: false)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    func update(items: [TabOverviewItem]) {
        allItems = items
        guard isViewLoaded else { return }
        updateContent(animated: true)
    }

    func selectMode(isPrivate: Bool, animated: Bool = true) {
        let mode: TabOverviewMode = isPrivate ? .privateBrowsing : .standard
        guard selectedMode != mode else { return }
        selectedMode = mode
        guard isViewLoaded else { return }
        updateContent(animated: animated)
    }

    private func configureNavigation() {
        navigationItem.title = "标签页"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
    }

    private func configureBackground() {
        privacyTintView.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.045)
        privacyTintView.isUserInteractionEnabled = false
        privacyTintView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(privacyTintView)

        NSLayoutConstraint.activate([
            privacyTintView.topAnchor.constraint(equalTo: contentView.topAnchor),
            privacyTintView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            privacyTintView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            privacyTintView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInset = UIEdgeInsets(
            top: AppSpacing.sm,
            left: 0,
            bottom: 84,
            right: 0
        )
        collectionView.verticalScrollIndicatorInsets.bottom = 82
        collectionView.register(
            TabOverviewCell.self,
            forCellWithReuseIdentifier: TabOverviewCell.reuseIdentifier
        )
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyView)
        contentView.bringSubviewToFront(bottomBar)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.topAnchor
            ),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyView.topAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.topAnchor
            ),
            emptyView.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            emptyView.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            emptyView.bottomAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: -AppSpacing.xs
            )
        ])
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomBar)
        bottomBar.mode = selectedMode
        bottomBar.onModeChange = { [weak self] mode in
            self?.changeMode(mode, notifyDelegate: true)
        }
        bottomBar.onNewTab = { [weak self] mode in
            self?.createTab(isPrivate: mode.isPrivate)
        }
        bottomBar.onDone = { [weak self] in
            self?.finish()
        }

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            bottomBar.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            bottomBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sm
            )
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            let width = environment.container.effectiveContentSize.width
            let isAccessibilitySize =
                self?.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
                == true
            let columns = isAccessibilitySize ? 1 : (width >= 700 ? 3 : 2)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(columns == 1 ? 330 : 250)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(columns == 1 ? 330 : 250)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(AppSpacing.sm)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = AppSpacing.sm
            section.contentInsets = NSDirectionalEdgeInsets(
                top: AppSpacing.xs,
                leading: AppSpacing.md,
                bottom: AppSpacing.md,
                trailing: AppSpacing.md
            )
            return section
        }
    }

    private func makeDataSource()
        -> UICollectionViewDiffableDataSource<Section, UUID>
    {
        UICollectionViewDiffableDataSource<Section, UUID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            guard
                let self,
                let item = self.allItems.first(where: { $0.id == itemID }),
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TabOverviewCell.reuseIdentifier,
                    for: indexPath
                ) as? TabOverviewCell
            else {
                return UICollectionViewCell()
            }

            cell.configure(with: item)
            cell.onClose = { [weak self] in
                self?.close(itemID: itemID)
            }
            return cell
        }
    }

    private func updateContent(animated: Bool) {
        let identifiers = visibleItems.map(\.id)
        let previousIdentifiers = Set(dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.tabs])
        snapshot.appendItems(identifiers)
        snapshot.reloadItems(identifiers.filter(previousIdentifiers.contains))
        dataSource.apply(
            snapshot,
            animatingDifferences: animated && view.window != nil
        )

        let isEmpty = identifiers.isEmpty
        collectionView.isHidden = isEmpty
        emptyView.isHidden = !isEmpty
        configureEmptyState()
        updateModeAppearance(animated: animated)
        bottomBar.mode = selectedMode
    }

    private func configureEmptyState() {
        if selectedMode.isPrivate {
            emptyView.configure(
                .init(
                    symbolName: "eye.slash",
                    title: "没有无痕标签页",
                    message: "无痕标签不会保存在浏览历史或下次会话中。"
                )
            )
        } else {
            emptyView.configure(
                .init(
                    symbolName: "square.on.square",
                    title: "没有打开的标签页",
                    message: "新建标签页后，可以在这里快速切换和管理网页。"
                )
            )
        }
    }

    private func updateModeAppearance(animated: Bool) {
        navigationItem.title = selectedMode.isPrivate ? "无痕标签页" : "标签页"
        let changes = {
            self.privacyTintView.alpha = self.selectedMode.isPrivate ? 1 : 0
        }
        if animated {
            AppAppearance.animate(animations: changes)
        } else {
            changes()
        }
    }

    private func registerForEnvironmentChanges() {
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self
        ]) { (controller: TabOverviewViewController, _) in
            controller.collectionView.collectionViewLayout.invalidateLayout()
            controller.dataSource.applySnapshotUsingReloadData(
                controller.dataSource.snapshot()
            )
        }
    }

    private func createTab(isPrivate: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onNewTab?(isPrivate)
    }

    private func close(itemID: UUID) {
        guard allItems.contains(where: { $0.id == itemID }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll { $0.id == itemID }
        updateContent(animated: true)
        onCloseTab?(itemID)
    }

    private func closeOtherTabs(keeping item: TabOverviewItem) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll {
            $0.isPrivate == item.isPrivate && $0.id != item.id
        }
        updateContent(animated: true)
        onCloseOtherTabs?(item.id)
    }

    private func closeAllNormalTabs() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll { !$0.isPrivate }
        updateContent(animated: true)
        onCloseAllNormalTabs?()
    }

    private func copyURL(for item: TabOverviewItem) {
        guard let url = item.url else { return }
        UIPasteboard.general.url = url
        onCopyTabURL?(item.id, url)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func share(_ item: TabOverviewItem, sourceRect: CGRect) {
        if let onShareTab {
            onShareTab(item.id, item.url)
            return
        }
        guard let url = item.url else { return }
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        activityController.popoverPresentationController?.sourceView = collectionView
        activityController.popoverPresentationController?.sourceRect = sourceRect
        present(activityController, animated: true)
    }

    private func openFavorites(_ item: TabOverviewItem) {
        onOpenFavorites?(item.id)
    }

    private func makeContextMenu(for item: TabOverviewItem) -> UIMenu {
        let copy = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "doc.on.doc"),
            attributes: item.url == nil ? [.disabled] : []
        ) { [weak self] _ in
            self?.copyURL(for: item)
        }
        let share = UIAction(
            title: "分享",
            image: UIImage(systemName: "square.and.arrow.up"),
            attributes: item.url == nil ? [.disabled] : []
        ) { [weak self] _ in
            guard let self else { return }
            let indexPath = self.dataSource.indexPath(for: item.id)
            let sourceRect = indexPath
                .flatMap { self.collectionView.layoutAttributesForItem(at: $0)?.frame }
                ?? self.collectionView.bounds
            self.share(item, sourceRect: sourceRect)
        }
        let favorite = UIAction(
            title: "打开收藏夹",
            image: UIImage(systemName: "star"),
            attributes: onOpenFavorites == nil ? [.disabled] : []
        ) { [weak self] _ in
            self?.openFavorites(item)
        }

        let closeCurrent = UIAction(
            title: "关闭标签页",
            image: UIImage(systemName: "xmark"),
            attributes: [.destructive]
        ) { [weak self] _ in
            self?.close(itemID: item.id)
        }
        let sameModeCount = allItems.filter {
            $0.isPrivate == item.isPrivate
        }.count
        let closeOthers = UIAction(
            title: "关闭其他标签页",
            image: UIImage(systemName: "square.on.square.dashed"),
            attributes: sameModeCount > 1 ? [.destructive] : [.disabled, .destructive]
        ) { [weak self] _ in
            self?.closeOtherTabs(keeping: item)
        }
        let normalCount = allItems.lazy.filter { !$0.isPrivate }.count
        let closeAllNormal = UIAction(
            title: "关闭全部普通标签页",
            image: UIImage(systemName: "rectangle.stack.badge.minus"),
            attributes: normalCount > 0 ? [.destructive] : [.disabled, .destructive]
        ) { [weak self] _ in
            self?.closeAllNormalTabs()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [copy, share, favorite]),
            UIMenu(
                options: .displayInline,
                children: [closeCurrent, closeOthers, closeAllNormal]
            )
        ])
    }

    private func changeMode(
        _ mode: TabOverviewMode,
        notifyDelegate: Bool
    ) {
        guard selectedMode != mode else { return }
        selectedMode = mode
        updateContent(animated: true)
        if notifyDelegate {
            onModeChanged?(mode.isPrivate)
        }
    }

    private func finish() {
        if let onDone {
            onDone()
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}

extension TabOverviewViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelectTab?(itemID)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let itemID = dataSource.itemIdentifier(for: indexPath),
            let item = allItems.first(where: { $0.id == itemID })
        else {
            return nil
        }

        return UIContextMenuConfiguration(
            identifier: itemID.uuidString as NSString,
            previewProvider: nil
        ) { [weak self] _ in
            self?.makeContextMenu(for: item)
        }
    }
}
