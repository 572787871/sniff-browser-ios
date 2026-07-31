import UIKit

@MainActor
final class TabOverviewBottomBar: UIView {
    var onModeChange: ((TabOverviewMode) -> Void)?
    var onNewTab: ((TabOverviewMode) -> Void)?
    var onDone: (() -> Void)?

    var mode: TabOverviewMode = .standard {
        didSet {
            updateMode()
        }
    }

    private let materialView = AppMaterialView(
        style: .systemChromeMaterial,
        fallbackColor: AppColors.chromeFallback
    )
    private let modeControl = UISegmentedControl(
        items: TabOverviewMode.allCases.map(\.title)
    )
    private let newTabButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        registerForEnvironmentChanges()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: traitCollection.preferredContentSizeCategory.isAccessibilityCategory
                ? 76
                : 64
        )
    }

    private func configureView() {
        backgroundColor = .clear

        materialView.layer.cornerRadius = AppRadius.sheet
        materialView.layer.cornerCurve = .continuous
        materialView.layer.borderWidth = AppMetrics.separatorHeight
        materialView.clipsToBounds = true
        materialView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(materialView)

        configureModeControl()
        configureNewTabButton()
        configureDoneButton()

        materialView.contentView.addSubview(modeControl)
        materialView.contentView.addSubview(newTabButton)
        materialView.contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

            modeControl.leadingAnchor.constraint(
                equalTo: materialView.contentView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            modeControl.centerYAnchor.constraint(
                equalTo: materialView.contentView.centerYAnchor
            ),
            modeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            modeControl.widthAnchor.constraint(lessThanOrEqualToConstant: 132),
            modeControl.trailingAnchor.constraint(
                lessThanOrEqualTo: newTabButton.leadingAnchor,
                constant: -AppSpacing.xs
            ),

            newTabButton.centerXAnchor.constraint(
                equalTo: materialView.contentView.centerXAnchor
            ),
            newTabButton.centerYAnchor.constraint(
                equalTo: materialView.contentView.centerYAnchor
            ),
            newTabButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            newTabButton.heightAnchor.constraint(equalTo: newTabButton.widthAnchor),
            newTabButton.trailingAnchor.constraint(
                lessThanOrEqualTo: doneButton.leadingAnchor,
                constant: -AppSpacing.xs
            ),

            doneButton.trailingAnchor.constraint(
                equalTo: materialView.contentView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            doneButton.centerYAnchor.constraint(
                equalTo: materialView.contentView.centerYAnchor
            ),
            doneButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            ),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        updateMode()
        updateResolvedColors()
    }

    private func configureModeControl() {
        modeControl.selectedSegmentTintColor = AppColors.elevatedSurface
        modeControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modeControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.caption,
                .foregroundColor: AppColors.secondaryText
            ],
            for: .normal
        )
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.caption,
                .foregroundColor: AppColors.primaryText
            ],
            for: .selected
        )
        modeControl.addTarget(
            self,
            action: #selector(modeControlChanged),
            for: .valueChanged
        )
        modeControl.accessibilityLabel = "标签页模式"
        modeControl.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureNewTabButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "plus")
        configuration.baseForegroundColor = AppColors.accent
        configuration.baseBackgroundColor = AppColors.accentFill
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        newTabButton.configuration = configuration
        newTabButton.addTarget(
            self,
            action: #selector(newTabPressed),
            for: .touchUpInside
        )
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureDoneButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "完成"
        configuration.baseForegroundColor = AppColors.accent
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: AppSpacing.xs,
            bottom: 0,
            trailing: AppSpacing.xs
        )
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = AppTypography.headline
                return attributes
            }
        doneButton.configuration = configuration
        doneButton.addTarget(
            self,
            action: #selector(donePressed),
            for: .touchUpInside
        )
        doneButton.accessibilityLabel = "完成标签页管理"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateMode() {
        modeControl.selectedSegmentIndex = mode.rawValue
        newTabButton.accessibilityLabel = mode.isPrivate
            ? "新建无痕标签页"
            : "新建普通标签页"
    }

    private func updateResolvedColors() {
        materialView.layer.borderColor = AppColors.separator
            .resolvedColor(with: traitCollection)
            .cgColor
    }

    private func registerForEnvironmentChanges() {
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self
        ]) { (bar: TabOverviewBottomBar, _) in
            bar.updateResolvedColors()
        }

        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self
        ]) { (bar: TabOverviewBottomBar, _) in
            bar.invalidateIntrinsicContentSize()
        }
    }

    @objc
    private func modeControlChanged() {
        guard let selectedMode = TabOverviewMode(
            rawValue: modeControl.selectedSegmentIndex
        ) else {
            return
        }
        mode = selectedMode
        onModeChange?(selectedMode)
    }

    @objc
    private func newTabPressed() {
        onNewTab?(mode)
    }

    @objc
    private func donePressed() {
        onDone?()
    }
}
