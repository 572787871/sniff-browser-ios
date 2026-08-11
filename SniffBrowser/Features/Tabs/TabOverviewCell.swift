import UIKit

/// 等比铺满并固定显示图片顶部的页面快照视图。
@MainActor
final class TabPageSnapshotView: UIView {
    var image: UIImage? {
        didSet {
            imageView.image = image
            setNeedsLayout()
        }
    }

    var renderedImageFrame: CGRect {
        imageView.frame
    }

    private let imageView = UIImageView()

    init(image: UIImage? = nil) {
        self.image = image
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        imageView.isAccessibilityElement = false
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image else {
            imageView.frame = bounds
            return
        }
        imageView.frame = TabOverviewTransitionGeometry.pageFillFrame(
            contentSize: image.size,
            containerSize: bounds.size
        )
    }
}

@MainActor
final class TabOverviewCell: UICollectionViewCell {
    static let reuseIdentifier = "TabOverviewCell"

    var onClose: (() -> Void)?

    private static let selectedBorderColor = UIColor { traits in
        AppColors.accent
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.42 : 0.28)
    }

    /// 无痕标签只在内存中缓存网站自身的 favicon，不写入磁盘，也不查询第三方。
    private static let ephemeralFaviconLoader: FaviconLoader = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return FaviconLoader(
            sessionConfiguration: configuration,
            memoryLimit: 2 * 1_024 * 1_024,
            diskLimit: 0,
            usesDiskCache: false
        )
    }()

    private let previewContainer = UIView()
    private let previewImageView = TabPageSnapshotView()
    private let placeholderImageView = UIImageView(
        image: UIImage(systemName: "globe.americas.fill")
    )
    private let closeButton = UIButton(type: .system)
    private let selectedBadge = UIImageView(
        image: UIImage(systemName: "checkmark.circle.fill")
    )
    private let metadataIconView = UIImageView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private var displaysSelection = false
    private var displaysWebsiteLogo = false
    private var faviconLoader: FaviconLoader?
    private var faviconURL: URL?
    private var faviconRequestID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        registerForEnvironmentChanges()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isHighlighted: Bool {
        didSet {
            let changes = {
                self.contentView.alpha = self.isHighlighted ? 0.76 : 1
                if !UIAccessibility.isReduceMotionEnabled {
                    self.contentView.transform = self.isHighlighted
                        ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                        : .identity
                }
            }
            UIView.animate(
                withDuration: 0.14,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: changes
            )
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelFaviconLoad()
        onClose = nil
        previewImageView.image = nil
        displaysSelection = false
        previewContainer.alpha = 1
        contentView.alpha = 1
        contentView.transform = .identity
        accessibilityCustomActions = nil
    }

    func configure(with item: TabOverviewItem) {
        cancelFaviconLoad()
        previewContainer.alpha = 1
        titleLabel.text = item.displayTitle
        domainLabel.text = item.displayDomain
        previewImageView.image = item.thumbnail
        metadataIconView.image = UIImage(systemName: "globe")
        placeholderImageView.image = item.url == nil
            ? AppIconography.scanApertureImage(pointSize: 26, weight: 2)
            : UIImage(systemName: "globe.americas.fill")
        placeholderImageView.isHidden = item.thumbnail != nil
        displaysSelection = item.isSelected
        selectedBadge.isHidden = !item.isSelected
        updateResolvedColors()
        loadFavicon(for: item)

        accessibilityLabel = "\(item.displayTitle)，\(item.displayDomain)"
        accessibilityValue = item.isSelected ? "当前标签页" : nil
        accessibilityHint = "双击打开，长按显示更多操作"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "关闭标签页",
                target: self,
                selector: #selector(accessibilityClose)
            )
        ]
    }

    func transitionPreviewFrame(in coordinateSpace: UIView) -> CGRect {
        contentView.layoutIfNeeded()
        return previewContainer.convert(
            previewContainer.bounds,
            to: coordinateSpace
        )
    }

    func setTransitionPreviewHidden(_ hidden: Bool) {
        previewContainer.alpha = hidden ? 0 : 1
    }

    func updateResolvedColors() {
        contentView.backgroundColor = .clear
        previewContainer.backgroundColor = AppColors.tertiarySurface
        titleLabel.textColor = AppColors.primaryText
        domainLabel.textColor = AppColors.secondaryText
        if displaysWebsiteLogo {
            metadataIconView.tintColor = nil
        } else {
            metadataIconView.tintColor = displaysSelection
                ? AppColors.accent
                : AppColors.secondaryText
        }
        placeholderImageView.tintColor = AppColors.tertiaryText
        closeButton.configuration?.baseForegroundColor = AppColors.secondaryText
        closeButton.backgroundColor = AppColors.elevatedSurface.withAlphaComponent(0.86)
        selectedBadge.tintColor = AppColors.accent
        selectedBadge.backgroundColor = AppColors.surface
        previewContainer.layer.borderWidth = displaysSelection
            ? 1
            : AppMetrics.separatorHeight
        previewContainer.layer.borderColor = (
            displaysSelection ? Self.selectedBorderColor : AppColors.separator
        )
        .resolvedColor(with: traitCollection)
        .cgColor
    }

    private func configureView() {
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        contentView.backgroundColor = .clear
        contentView.layer.masksToBounds = false

        previewContainer.backgroundColor = AppColors.tertiarySurface
        previewContainer.layer.cornerRadius = AppRadius.card
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.borderWidth = AppMetrics.separatorHeight
        previewContainer.layer.masksToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewContainer)

        previewImageView.accessibilityIdentifier = "tabs.previewImage"
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImageView)

        placeholderImageView.tintColor = AppColors.tertiaryText
        placeholderImageView.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.isAccessibilityElement = false
        previewContainer.addSubview(placeholderImageView)

        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14,
                weight: .medium
            )
        )
        closeConfiguration.baseForegroundColor = AppColors.secondaryText
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.backgroundColor = AppColors.elevatedSurface.withAlphaComponent(0.86)
        closeButton.layer.cornerRadius = 18
        closeButton.clipsToBounds = true
        closeButton.accessibilityLabel = "关闭标签页"
        closeButton.addTarget(
            self,
            action: #selector(closePressed),
            for: .touchUpInside
        )
        closeButton.addTarget(
            self,
            action: #selector(closeButtonTouchDown),
            for: .touchDown
        )
        closeButton.addTarget(
            self,
            action: #selector(closeButtonTouchUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(closeButton)

        selectedBadge.tintColor = AppColors.accent
        selectedBadge.backgroundColor = AppColors.surface
        selectedBadge.layer.cornerRadius = 8
        selectedBadge.clipsToBounds = true
        selectedBadge.isAccessibilityElement = false
        selectedBadge.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(selectedBadge)

        AppTypography.configure(titleLabel, style: .headline, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityIdentifier = "tabs.title"

        AppTypography.configure(domainLabel, style: .caption1)
        domainLabel.textColor = AppColors.secondaryText
        domainLabel.numberOfLines = 1
        domainLabel.lineBreakMode = .byTruncatingMiddle

        let labels = UIStackView(arrangedSubviews: [titleLabel, domainLabel])
        labels.axis = .vertical
        labels.alignment = .fill
        labels.spacing = AppSpacing.xxs
        labels.translatesAutoresizingMaskIntoConstraints = false

        metadataIconView.contentMode = .scaleAspectFit
        metadataIconView.tintColor = AppColors.secondaryText
        metadataIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular
        )
        metadataIconView.layer.cornerRadius = 3
        metadataIconView.clipsToBounds = true
        metadataIconView.transform = CGAffineTransform(translationX: 0, y: 3)
        metadataIconView.accessibilityIdentifier = "tabs.metadataIcon"
        metadataIconView.isAccessibilityElement = false
        metadataIconView.translatesAutoresizingMaskIntoConstraints = false

        let metadata = UIStackView(arrangedSubviews: [metadataIconView, labels])
        metadata.axis = .horizontal
        metadata.alignment = .top
        metadata.spacing = AppSpacing.xs
        metadata.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metadata)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainer.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -TabOverviewGridLayoutMetrics.metadataAreaHeight
            ),

            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(
                equalTo: previewContainer.centerXAnchor
            ),
            placeholderImageView.centerYAnchor.constraint(
                equalTo: previewContainer.centerYAnchor
            ),

            closeButton.topAnchor.constraint(
                equalTo: previewContainer.topAnchor,
                constant: 10
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: previewContainer.trailingAnchor,
                constant: -10
            ),
            closeButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),

            selectedBadge.leadingAnchor.constraint(
                equalTo: previewContainer.leadingAnchor,
                constant: AppSpacing.xs
            ),
            selectedBadge.topAnchor.constraint(
                equalTo: previewContainer.topAnchor,
                constant: AppSpacing.xs
            ),
            selectedBadge.widthAnchor.constraint(equalToConstant: 16),
            selectedBadge.heightAnchor.constraint(equalTo: selectedBadge.widthAnchor),

            metadata.topAnchor.constraint(
                equalTo: previewContainer.bottomAnchor,
                constant: AppSpacing.xs
            ),
            metadata.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.xxs
            ),
            metadata.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.xxs
            ),
            metadata.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.xxs
            ),
            metadataIconView.widthAnchor.constraint(equalToConstant: 17),
            metadataIconView.heightAnchor.constraint(equalToConstant: 17),
        ])
    }

    private func loadFavicon(for item: TabOverviewItem) {
        guard let pageURL = item.url else { return }
        let loader: FaviconLoader
        let resolvedURL: URL?
        if item.isPrivate {
            loader = Self.ephemeralFaviconLoader
            resolvedURL = FaviconLoader.directFaviconURL(for: pageURL)
        } else {
            loader = .shared
            resolvedURL = FaviconLoader.faviconURL(for: pageURL)
        }
        guard let resolvedURL else { return }

        faviconLoader = loader
        faviconURL = resolvedURL
        var requestID: UUID?
        requestID = loader.load(url: resolvedURL) { [weak self] image in
            guard let self,
                  self.faviconRequestID == requestID,
                  let image
            else {
                return
            }
            self.displaysWebsiteLogo = true
            self.metadataIconView.image = image.withRenderingMode(.alwaysOriginal)
            self.metadataIconView.tintColor = nil
        }
        faviconRequestID = requestID
    }

    private func cancelFaviconLoad() {
        if let faviconLoader, let faviconURL, let faviconRequestID {
            faviconLoader.cancel(url: faviconURL, requestID: faviconRequestID)
        }
        faviconLoader = nil
        faviconURL = nil
        faviconRequestID = nil
        displaysWebsiteLogo = false
    }

    private func registerForEnvironmentChanges() {
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self
        ]) { (cell: TabOverviewCell, _) in
            cell.updateResolvedColors()
        }
    }

    @objc
    private func closePressed() {
        onClose?()
    }

    @objc
    private func closeButtonTouchDown() {
        closeButton.backgroundColor = AppColors.accentFill
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.closeButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc
    private func closeButtonTouchUp() {
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.closeButton.transform = .identity
            self.closeButton.backgroundColor = AppColors.elevatedSurface
                .withAlphaComponent(0.86)
        }
    }

    @objc
    private func accessibilityClose() -> Bool {
        onClose?()
        return true
    }
}
