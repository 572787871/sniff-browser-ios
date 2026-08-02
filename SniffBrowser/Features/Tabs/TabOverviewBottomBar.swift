import UIKit

@MainActor
final class TabOverviewBottomBar: UIView {
    var onNewTab: ((TabOverviewMode) -> Void)?
    var onCloseAllTabs: ((TabOverviewMode) -> Void)?
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
    private let newTabButton = UIButton(type: .system)
    private let closeAllTabsButton = UIButton(type: .system)
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

        configureNewTabButton()
        configureCloseAllTabsButton()
        configureDoneButton()

        materialView.contentView.addSubview(newTabButton)
        materialView.contentView.addSubview(closeAllTabsButton)
        materialView.contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

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

            closeAllTabsButton.leadingAnchor.constraint(
                equalTo: materialView.contentView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            closeAllTabsButton.centerYAnchor.constraint(
                equalTo: materialView.contentView.centerYAnchor
            ),
            closeAllTabsButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            ),
            closeAllTabsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

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

    private func configureCloseAllTabsButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "trash")
        configuration.title = "关闭全部"
        configuration.imagePadding = AppSpacing.xxs
        configuration.baseForegroundColor = AppColors.danger
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: AppSpacing.xs,
            bottom: 0,
            trailing: AppSpacing.xs
        )
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = AppTypography.subheadline
                return attributes
            }
        closeAllTabsButton.configuration = configuration
        closeAllTabsButton.addTarget(
            self,
            action: #selector(closeAllTabsPressed),
            for: .touchUpInside
        )
        closeAllTabsButton.accessibilityLabel = "关闭所有标签页"
        closeAllTabsButton.translatesAutoresizingMaskIntoConstraints = false
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
        let isPrivate = mode.isPrivate
        overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
        materialView.contentView.backgroundColor = isPrivate
            ? AppColors.privateBrowsingSurface.withAlphaComponent(0.72)
            : .clear
        newTabButton.configuration?.baseForegroundColor = isPrivate
            ? AppColors.privateBrowsingAccent
            : AppColors.accent
        newTabButton.configuration?.baseBackgroundColor = isPrivate
            ? AppColors.privateBrowsingAccent.withAlphaComponent(0.18)
            : AppColors.accentFill
        doneButton.configuration?.baseForegroundColor = isPrivate
            ? AppColors.privateBrowsingAccent
            : AppColors.accent
        closeAllTabsButton.configuration?.baseForegroundColor = isPrivate
            ? AppColors.privateBrowsingAccent.withAlphaComponent(0.78)
            : AppColors.danger
        newTabButton.accessibilityLabel = mode.isPrivate
            ? "新建无痕标签页"
            : "新建普通标签页"
        updateResolvedColors()
    }

    private func updateResolvedColors() {
        materialView.layer.borderColor = (
            mode.isPrivate
                ? UIColor.white.withAlphaComponent(0.14)
                : AppColors.separator.resolvedColor(with: traitCollection)
        ).cgColor
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
    private func newTabPressed() {
        onNewTab?(mode)
    }

    @objc
    private func closeAllTabsPressed() {
        onCloseAllTabs?(mode)
    }

    @objc
    private func donePressed() {
        onDone?()
    }
}
