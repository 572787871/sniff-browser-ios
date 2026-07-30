import UIKit

final class TabOverviewViewController: BaseViewController {
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: ((Bool) -> Void)?

    private var allItems: [TabOverviewItem]
    private var visibleItems: [TabOverviewItem] {
        allItems.filter { $0.isPrivate == (modeControl.selectedSegmentIndex == 1) }
    }

    private let modeControl = UISegmentedControl(items: ["标签页", "无痕"])
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private let emptyView = EmptyStateView(
        configuration: .init(
            symbolName: "square.on.square",
            title: "没有打开的标签页",
            message: "新建标签页后，可以在这里快速切换和管理网页。"
        )
    )
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let newTabButton = UIButton(type: .system)

    init(items: [TabOverviewItem]) {
        allItems = items
        super.init(title: "标签页", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureModeControl()
        configureCollectionView()
        configureBottomBar()
        updateContent()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.collectionView.setCollectionViewLayout(self?.makeLayout() ?? UICollectionViewFlowLayout(), animated: true)
        }
    }

    func update(items: [TabOverviewItem]) {
        allItems = items
        guard isViewLoaded else { return }
        updateContent()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [
                UIAction(
                    title: "新建无痕标签页",
                    image: UIImage(systemName: "eye.slash")
                ) { [weak self] _ in
                    self?.createTab(isPrivate: true)
                }
            ])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "标签页更多操作"
    }

    private func configureModeControl() {
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.setContentHuggingPriority(.required, for: .vertical)
        contentView.addSubview(modeControl)

        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            modeControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            modeControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 96, right: 0)
        collectionView.register(
            TabOverviewCell.self,
            forCellWithReuseIdentifier: TabOverviewCell.reuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: modeControl.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureBottomBar() {
        bottomBar.layer.cornerRadius = AppRadius.sheet
        bottomBar.layer.cornerCurve = .continuous
        bottomBar.clipsToBounds = true
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomBar)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "新建标签页"
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePadding = 8
        configuration.cornerStyle = .medium
        newTabButton.configuration = configuration
        newTabButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        newTabButton.addTarget(self, action: #selector(newTabPressed), for: .touchUpInside)
        newTabButton.accessibilityLabel = "新建标签页"
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(newTabButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            newTabButton.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            newTabButton.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 10),
            newTabButton.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -10),
            newTabButton.bottomAnchor.constraint(equalTo: bottomBar.contentView.bottomAnchor, constant: -10),
            newTabButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            )
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            let usesSingleColumn = environment.container.effectiveContentSize.width < 360
                || self?.traitCollection.preferredContentSizeCategory.isAccessibilityCategory == true
            let columns = usesSingleColumn ? 1 : 2
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .estimated(250)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(250)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            return section
        }
    }

    private func updateContent() {
        collectionView.reloadData()
        let isEmpty = visibleItems.isEmpty
        collectionView.isHidden = isEmpty
        emptyView.isHidden = !isEmpty
    }

    private func createTab(isPrivate: Bool) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        onNewTab?(isPrivate)
    }

    @objc private func modeChanged() {
        updateContent()
    }

    @objc private func newTabPressed() {
        createTab(isPrivate: modeControl.selectedSegmentIndex == 1)
    }
}

extension TabOverviewViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabOverviewCell.reuseIdentifier,
            for: indexPath
        ) as? TabOverviewCell else {
            return UICollectionViewCell()
        }
        let item = visibleItems[indexPath.item]
        cell.configure(with: item)
        cell.onClose = { [weak self] in
            self?.close(itemID: item.id)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelectTab?(visibleItems[indexPath.item].id)
    }

    private func close(itemID: UUID) {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.impactOccurred()
        allItems.removeAll { $0.id == itemID }
        updateContent()
        onCloseTab?(itemID)
    }
}

private final class TabOverviewCell: UICollectionViewCell {
    static let reuseIdentifier = "TabOverviewCell"

    var onClose: (() -> Void)?

    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderImageView = UIImageView(image: UIImage(systemName: "globe"))
    private let closeButton = UIButton(type: .system)
    private let selectedBadge = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onClose = nil
        previewImageView.image = nil
    }

    func configure(with item: TabOverviewItem) {
        titleLabel.text = item.title.isEmpty ? "新标签页" : item.title
        domainLabel.text = item.url?.host ?? "嗅探浏览器"
        previewImageView.image = item.thumbnail
        placeholderImageView.isHidden = item.thumbnail != nil
        selectedBadge.isHidden = !item.isSelected
        contentView.layer.borderWidth = item.isSelected ? 2 : 0.5
        contentView.layer.borderColor = (
            item.isSelected ? AppColors.accent : AppColors.separator
        ).cgColor
        accessibilityLabel = "\(titleLabel.text ?? "标签页")，\(domainLabel.text ?? "")"
        accessibilityValue = item.isSelected ? "当前标签页" : nil
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "关闭标签页",
                target: self,
                selector: #selector(accessibilityClose)
            )
        ]
    }

    private func configureView() {
        isAccessibilityElement = true
        contentView.backgroundColor = AppColors.surface
        contentView.layer.cornerRadius = AppRadius.card
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        previewContainer.backgroundColor = AppColors.background
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewContainer)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImageView)

        placeholderImageView.tintColor = AppColors.tertiaryText
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30)
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(placeholderImageView)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = AppColors.secondaryText
        closeButton.backgroundColor = AppColors.elevatedSurface
        closeButton.layer.cornerRadius = AppRadius.card
        closeButton.accessibilityLabel = "关闭标签页"
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(closeButton)

        selectedBadge.tintColor = AppColors.accent
        selectedBadge.backgroundColor = .systemBackground
        selectedBadge.layer.cornerRadius = AppRadius.control
        selectedBadge.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(selectedBadge)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        domainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = AppColors.secondaryText
        domainLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, domainLabel])
        labels.axis = .vertical
        labels.spacing = 4
        labels.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labels)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainer.heightAnchor.constraint(equalTo: previewContainer.widthAnchor, multiplier: 0.72),

            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),

            closeButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            selectedBadge.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 10),
            selectedBadge.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 10),
            selectedBadge.widthAnchor.constraint(equalToConstant: 20),
            selectedBadge.heightAnchor.constraint(equalToConstant: 20),

            labels.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 12),
            labels.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            labels.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func accessibilityClose() -> Bool {
        onClose?()
        return true
    }
}
