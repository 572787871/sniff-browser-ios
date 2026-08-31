import UIKit

/// 仍由 UIKit 承担的照片选择/背景画廊所使用的兼容摘要行。
/// 新设置主页使用 SwiftUI，但保留该窄适配器避免重复实现系统选择器流程。
final class GlassSummaryCell: UITableViewCell {
    static let reuseIdentifier = "GlassSummaryCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundConfiguration = AppGroupedListAppearance.cellBackground()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String?,
        symbol: String,
        tint: UIColor = AppColors.accent,
        titleColor: UIColor = AppColors.primaryText,
        isEnabled: Bool = true
    ) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = title
        content.secondaryText = subtitle
        content.image = UIImage(systemName: symbol)
        content.imageProperties.tintColor = tint
        content.textProperties.color = titleColor
        content.secondaryTextProperties.color = AppColors.secondaryText
        contentConfiguration = content
        accessoryType = .disclosureIndicator
        isUserInteractionEnabled = isEnabled
        alpha = isEnabled ? 1 : 0.46
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: "，")
        accessibilityTraits = isEnabled ? [.button] : [.button, .notEnabled]
    }
}

/// 单选行：图标 + 标题 + 勾选标记，用于设置页的单选项列表。
final class SettingsCheckmarkCell: UITableViewCell {
    static let reuseIdentifier = "SettingsCheckmarkCell"

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, symbol: String, isSelected: Bool) {
        titleLabel.text = title
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        iconView.tintColor = AppColors.secondaryText
        iconContainer.backgroundColor = .clear
        accessoryType = isSelected ? .checkmark : .none
        accessibilityLabel = title
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        iconView.image = nil
        accessoryType = .none
        accessibilityTraits = [.button]
    }

    private func configureView() {
        backgroundConfiguration = AppGroupedListAppearance.cellBackground()
        selectionStyle = .default
        isAccessibilityElement = true

        iconContainer.layer.cornerRadius = AppRadius.small
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconContainer)

        iconView.contentMode = .center
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .medium)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 28),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            titleLabel.topAnchor.constraint(
                greaterThanOrEqualTo: contentView.topAnchor,
                constant: AppSpacing.sm
            ),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -AppSpacing.sm
            ),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }
}

/// 开关行：图标 + 标题/副标题 + UISwitch，用于设置页的布尔选项。
final class SettingsToggleCell: UITableViewCell {
    static let reuseIdentifier = "SettingsToggleCell"

    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Bool,
        accessibilityIdentifier: String,
        onChange: @escaping (Bool) -> Void
    ) {
        self.onChange = onChange
        toggle.setOn(isOn, animated: false)
        toggle.accessibilityIdentifier = "\(accessibilityIdentifier).switch"

        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = title
        configuration.secondaryText = subtitle
        configuration.image = nil
        configuration.textProperties.color = AppColors.primaryText
        configuration.secondaryTextProperties.color = AppColors.secondaryText
        contentConfiguration = configuration

        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = title
        accessibilityValue = isOn ? "已开启" : "已关闭"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChange = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    @objc private func toggleChanged() {
        accessibilityValue = toggle.isOn ? "已开启" : "已关闭"
        onChange?(toggle.isOn)
    }

    private func configureView() {
        backgroundConfiguration = AppGroupedListAppearance.cellBackground()
        selectionStyle = .none
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        accessoryView = toggle
    }
}
