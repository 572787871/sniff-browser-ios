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
        contentView.alpha = 1
        contentView.transform = .identity
        accessibilityCustomActions = nil
    }

    func configure(with item: TabOverviewItem) {
        titleLabel.text = item.displayTitle
        domainLabel.text = item.displayDomain
        previewImageView.image = item.thumbnail
        placeholderImageView.isHidden = item.thumbnail != nil
        displaysSelection = item.isSelected
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

    func updateResolvedColors() {
        contentView.layer.borderWidth = displaysSelection
            ? 1
            : AppMetrics.separatorHeight
        contentView.layer.borderColor = (
            displaysSelection ? Self.selectedBorderColor : AppColors.separator
        )
        .resolvedColor(with: traitCollection)
        .cgColor
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
                pointSize: 22,
                weight: .semibold
            )
        )
        closeConfiguration.baseForegroundColor = UIColor.label.withAlphaComponent(0.86)
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.accessibilityLabel = "关闭标签页"
        closeButton.addTarget(
            self,
            action: #selector(closePressed),
            for: .touchUpInside
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
                constant: AppSpacing.xxs
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: previewContainer.trailingAnchor,
                constant: -AppSpacing.xxs
            ),
            closeButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
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
    private func accessibilityClose() -> Bool {
        onClose?()
        return true
    }
}
