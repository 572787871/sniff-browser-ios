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
    private let privacyNoticeView = UIView()
    private let privacyNoticeIcon = UIImageView(
        image: UIImage(systemName: "eye.slash.fill")
    )
    private let privacyNoticeLabel = UILabel()
    private var pendingRestoredOffset: CGFloat?
    private var lastLaidOutSize: CGSize = .zero

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
        let currentSize = collectionView.bounds.size
        if currentSize.width > 0,
           currentSize.height > 0,
           currentSize != lastLaidOutSize {
            lastLaidOutSize = currentSize
            collectionView.collectionViewLayout.invalidateLayout()
        }
        restorePendingOffsetIfPossible()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        invalidateGridLayout()
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

    func transitionFrame(
        for itemID: UUID,
        in coordinateSpace: UIView,
        ensureVisible: Bool
    ) -> CGRect? {
        loadViewIfNeeded()
        view.layoutIfNeeded()
        guard let indexPath = dataSource.indexPath(for: itemID) else {
            return nil
        }
        if ensureVisible,
           !collectionView.indexPathsForVisibleItems.contains(indexPath) {
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredVertically,
                animated: false
            )
        }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView
            .layoutAttributesForItem(at: indexPath)
        else { return nil }
        if let cell = collectionView.cellForItem(at: indexPath)
            as? TabOverviewCell {
            return cell.transitionPreviewFrame(in: coordinateSpace)
        }
        return collectionView.convert(attributes.frame, to: coordinateSpace)
    }

    func setTransitionItemHidden(_ itemID: UUID, hidden: Bool) {
        guard let indexPath = dataSource.indexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath)
        else { return }
        guard let cell = cell as? TabOverviewCell else { return }
        cell.setTransitionPreviewHidden(hidden)
    }

    private func configureView() {
        overrideUserInterfaceStyle = mode.isPrivate ? .dark : .unspecified
        view.backgroundColor = mode.isPrivate
            ? AppColors.privateBrowsingBackground
            : .clear
        view.clipsToBounds = true

        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = true
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

        let collectionTopAnchor: NSLayoutYAxisAnchor
        if mode.isPrivate {
            configurePrivacyNotice()
            collectionTopAnchor = privacyNoticeView.bottomAnchor
        } else {
            collectionTopAnchor = view.topAnchor
        }

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: collectionTopAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.topAnchor.constraint(equalTo: collectionTopAnchor),
            emptyView.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            emptyView.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configurePrivacyNotice() {
        privacyNoticeView.translatesAutoresizingMaskIntoConstraints = false
        privacyNoticeView.backgroundColor =
            AppColors.privateBrowsingSurface.withAlphaComponent(0.82)
        privacyNoticeView.layer.cornerRadius = AppRadius.control
        privacyNoticeView.layer.cornerCurve = .continuous
        view.addSubview(privacyNoticeView)

        privacyNoticeIcon.translatesAutoresizingMaskIntoConstraints = false
        privacyNoticeIcon.tintColor = AppColors.privateBrowsingAccent
        privacyNoticeIcon.contentMode = .scaleAspectFit
        privacyNoticeIcon.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        privacyNoticeIcon.isAccessibilityElement = false
        privacyNoticeView.addSubview(privacyNoticeIcon)

        privacyNoticeLabel.translatesAutoresizingMaskIntoConstraints = false
        AppTypography.configure(privacyNoticeLabel, style: .caption1)
        privacyNoticeLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        privacyNoticeLabel.numberOfLines = 2
        privacyNoticeLabel.text =
            "无痕标签不会保存到浏览历史，下载和主动收藏的内容仍会保留。"
        privacyNoticeView.addSubview(privacyNoticeLabel)

        NSLayoutConstraint.activate([
            privacyNoticeView.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: AppSpacing.xs
            ),
            privacyNoticeView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: AppSpacing.md
            ),
            privacyNoticeView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -AppSpacing.md
            ),

            privacyNoticeIcon.leadingAnchor.constraint(
                equalTo: privacyNoticeView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            privacyNoticeIcon.centerYAnchor.constraint(
                equalTo: privacyNoticeView.centerYAnchor
            ),
            privacyNoticeIcon.widthAnchor.constraint(equalToConstant: 24),
            privacyNoticeIcon.heightAnchor.constraint(equalToConstant: 24),

            privacyNoticeLabel.leadingAnchor.constraint(
                equalTo: privacyNoticeIcon.trailingAnchor,
                constant: AppSpacing.xs
            ),
            privacyNoticeLabel.trailingAnchor.constraint(
                equalTo: privacyNoticeView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            privacyNoticeLabel.topAnchor.constraint(
                equalTo: privacyNoticeView.topAnchor,
                constant: AppSpacing.xs
            ),
            privacyNoticeLabel.bottomAnchor.constraint(
                equalTo: privacyNoticeView.bottomAnchor,
                constant: -AppSpacing.xs
            )
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
                    widthDimension: .absolute(metrics.itemSize.width),
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
                message: "无痕标签不会保存到浏览历史，下载和主动收藏的内容仍会保留。"
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
