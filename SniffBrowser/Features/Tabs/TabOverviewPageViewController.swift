import UIKit

@MainActor
final class TabOverviewPageViewController: UIViewController {
    var onSelectItem: ((UUID) -> Void)?
    var onCloseItem: ((UUID) -> Void)?
    var contextMenuProvider: ((
        TabOverviewItem,
        UIView,
        CGRect
    ) -> UIMenu?)?
    var onScrollOffsetChange: ((CGFloat) -> Void)?

    let mode: TabOverviewMode

    private enum Section {
        case tabs
    }

    private var items: [TabOverviewItem] = []
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private lazy var dataSource = makeDataSource()
    private let emptyView: EmptyStateView
    private var pendingRestoredOffset: CGFloat?

    init(mode: TabOverviewMode) {
        self.mode = mode
        emptyView = EmptyStateView(configuration: Self.emptyConfiguration(for: mode))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        updateContent(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restorePendingOffsetIfPossible()
    }

    var scrollOffsetY: CGFloat {
        max(0, collectionView.contentOffset.y)
    }

    func update(items: [TabOverviewItem], animated: Bool) {
        self.items = items
        guard isViewLoaded else { return }
        updateContent(animated: animated)
    }

    func restoreScrollOffset(_ offset: CGFloat) {
        pendingRestoredOffset = max(0, offset)
        guard isViewLoaded else { return }
        view.layoutIfNeeded()
        restorePendingOffsetIfPossible()
    }

    func invalidateGridLayout() {
        guard isViewLoaded else { return }
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func configureView() {
        view.backgroundColor = .clear

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isDirectionalLockEnabled = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(
            TabOverviewCell.self,
            forCellWithReuseIdentifier: TabOverviewCell.reuseIdentifier
        )
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.topAnchor.constraint(equalTo: view.topAnchor),
            emptyView.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            emptyView.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .vertical

        return UICollectionViewCompositionalLayout(
            sectionProvider: { _, environment in
                let metrics = TabOverviewGridLayoutMetrics.resolve(
                    containerSize: environment.container.effectiveContentSize
                )
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(metrics.itemSize.height)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(metrics.itemSize.height)
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: groupSize,
                    repeatingSubitem: item,
                    count: metrics.columnCount
                )
                group.interItemSpacing = .fixed(
                    TabOverviewGridLayoutMetrics.interItemSpacing
                )

                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing =
                    TabOverviewGridLayoutMetrics.interRowSpacing
                section.orthogonalScrollingBehavior = .none
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: TabOverviewGridLayoutMetrics.topInset,
                    leading: TabOverviewGridLayoutMetrics.horizontalInset,
                    bottom: TabOverviewGridLayoutMetrics.bottomInset,
                    trailing: TabOverviewGridLayoutMetrics.horizontalInset
                )
                return section
            },
            configuration: configuration
        )
    }

    private func makeDataSource()
        -> UICollectionViewDiffableDataSource<Section, UUID>
    {
        UICollectionViewDiffableDataSource<Section, UUID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            guard
                let self,
                let item = self.items.first(where: { $0.id == itemID }),
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TabOverviewCell.reuseIdentifier,
                    for: indexPath
                ) as? TabOverviewCell
            else {
                return UICollectionViewCell()
            }

            cell.configure(with: item)
            cell.onClose = { [weak self] in
                self?.onCloseItem?(itemID)
            }
            return cell
        }
    }

    private func updateContent(animated: Bool) {
        let identifiers = items.map(\.id)
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
    }

    private func restorePendingOffsetIfPossible() {
        guard let pendingRestoredOffset else { return }
        collectionView.layoutIfNeeded()

        let minimumOffset = -collectionView.adjustedContentInset.top
        let maximumOffset = max(
            minimumOffset,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        collectionView.setContentOffset(
            CGPoint(
                x: -collectionView.adjustedContentInset.left,
                y: min(maximumOffset, max(minimumOffset, pendingRestoredOffset))
            ),
            animated: false
        )
        self.pendingRestoredOffset = nil
    }

    private static func emptyConfiguration(
        for mode: TabOverviewMode
    ) -> EmptyStateView.Configuration {
        if mode.isPrivate {
            return .init(
                symbolName: "eye.slash",
                title: "没有无痕标签页",
                message: "无痕标签不会保存在浏览历史或下次会话中。"
            )
        }
        return .init(
            symbolName: "square.on.square",
            title: "没有打开的标签页",
            message: "新建标签页后，可以在这里快速切换和管理网页。"
        )
    }
}

extension TabOverviewPageViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelectItem?(itemID)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let itemID = dataSource.itemIdentifier(for: indexPath),
            let item = items.first(where: { $0.id == itemID })
        else {
            return nil
        }

        let sourceRect = collectionView.layoutAttributesForItem(at: indexPath)?.frame
            ?? CGRect(origin: point, size: .zero)
        return UIContextMenuConfiguration(
            identifier: itemID.uuidString as NSString,
            previewProvider: nil
        ) { [weak self, weak collectionView] _ in
            guard let self, let collectionView else { return nil }
            return self.contextMenuProvider?(item, collectionView, sourceRect)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard
            !scrollView.isDragging,
            !scrollView.isDecelerating
        else {
            return
        }
        onScrollOffsetChange?(max(0, scrollView.contentOffset.y))
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard !decelerate else { return }
        onScrollOffsetChange?(max(0, scrollView.contentOffset.y))
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onScrollOffsetChange?(max(0, scrollView.contentOffset.y))
    }
}
