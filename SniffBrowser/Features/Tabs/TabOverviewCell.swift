import UIKit

@MainActor
final class TabOverviewCell: UICollectionViewCell {
    static let reuseIdentifier = "TabOverviewCell"

    var onClose: (() -> Void)?

    private static let selectedBorderColor = UIColor { traits in
        UIColor.systemBlue
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.42 : 0.28)
    }

    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderImageView = UIImageView(
        image: UIImage(systemName: "globe.americas.fill")
    )
    private let closeButton = UIButton(type: .system)
    private let selectedBadge = UIImageView(
        image: UIImage(systemName: "checkmark.circle.fill")
    )
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private var displaysSelection = false
    private var displaysPrivateMode = false

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
        onClose = nil
        previewImageView.image = nil
        displaysSelection = false
        displaysPrivateMode = false
        previewContainer.alpha = 1
        contentView.alpha = 1
        contentView.transform = .identity
        accessibilityCustomActions = nil
    }

    func configure(with item: TabOverviewItem) {
        previewContainer.alpha = 1
        titleLabel.text = item.displayTitle
        domainLabel.text = item.displayDomain
        previewImageView.image = item.thumbnail
        placeholderImageView.isHidden = item.thumbnail != nil
        displaysSelection = item.isSelected
        displaysPrivateMode = item.isPrivate
        selectedBadge.isHidden = !item.isSelected
        updateResolvedColors()

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
        contentView.backgroundColor = displaysPrivateMode
            ? AppColors.privateBrowsingSurface
            : AppColors.surface
        previewContainer.backgroundColor = displaysPrivateMode
            ? UIColor(
                red: 0.10,
                green: 0.105,
                blue: 0.125,
                alpha: 1
            )
            : AppColors.tertiarySurface
        titleLabel.textColor = displaysPrivateMode
            ? UIColor.white.withAlphaComponent(0.96)
            : AppColors.primaryText
        domainLabel.textColor = displaysPrivateMode
            ? UIColor.white.withAlphaComponent(0.58)
            : AppColors.secondaryText
        placeholderImageView.tintColor = displaysPrivateMode
            ? UIColor.white.withAlphaComponent(0.42)
            : AppColors.tertiaryText
        closeButton.configuration?.baseForegroundColor = displaysPrivateMode
            ? UIColor.white.withAlphaComponent(0.78)
            : UIColor.secondaryLabel
        selectedBadge.tintColor = displaysPrivateMode
            ? AppColors.privateBrowsingAccent
            : AppColors.accent
        selectedBadge.backgroundColor = displaysPrivateMode
            ? AppColors.privateBrowsingSurface
            : AppColors.surface
        contentView.layer.borderWidth = displaysSelection
            ? 1
            : AppMetrics.separatorHeight
        if displaysSelection, displaysPrivateMode {
            contentView.layer.borderColor =
                AppColors.privateBrowsingAccent.withAlphaComponent(0.48).cgColor
        } else {
            contentView.layer.borderColor = (
                displaysSelection ? Self.selectedBorderColor : AppColors.separator
            )
            .resolvedColor(with: traitCollection)
            .cgColor
        }
    }

    private func configureView() {
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        contentView.backgroundColor = AppColors.surface
        contentView.layer.cornerRadius = AppRadius.card
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = AppMetrics.separatorHeight
        contentView.layer.masksToBounds = true

        previewContainer.backgroundColor = AppColors.tertiarySurface
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewContainer)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
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
        closeConfiguration.baseForegroundColor = UIColor.secondaryLabel
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.backgroundColor = .clear
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
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        AppTypography.configure(domainLabel, style: .caption1)
        domainLabel.textColor = AppColors.secondaryText
        domainLabel.numberOfLines = 1
        domainLabel.lineBreakMode = .byTruncatingMiddle

        let labels = UIStackView(arrangedSubviews: [titleLabel, domainLabel])
        labels.axis = .vertical
        labels.alignment = .fill
        labels.spacing = AppSpacing.xxs
        labels.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labels)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainer.heightAnchor.constraint(
                equalTo: contentView.heightAnchor,
                multiplier: TabOverviewGridLayoutMetrics.previewHeightRatio
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

            labels.topAnchor.constraint(
                equalTo: previewContainer.bottomAnchor,
                constant: AppSpacing.xs
            ),
            labels.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            labels.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            labels.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.xs
            )
        ])
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
        let pressColor: UIColor = displaysPrivateMode
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor.systemGray5.withAlphaComponent(0.5)
        closeButton.backgroundColor = pressColor
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
            self.closeButton.backgroundColor = .clear
        }
    }

    @objc
    private func accessibilityClose() -> Bool {
        onClose?()
        return true
    }
}
