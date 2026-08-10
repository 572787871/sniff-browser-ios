import UIKit

/// 外观设置页面，提供深浅模式与全局主题色预设。
final class AppearanceSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let appearanceOptions = AppearancePreference.allCases
    private let themeOptions = AppThemeColor.allCases

    private enum Section: Int, CaseIterable {
        case appearance
        case themeColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "外观"
        configureTableView()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.register(AppearanceOptionCell.self, forCellReuseIdentifier: AppearanceOptionCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

extension AppearanceSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .appearance: return appearanceOptions.count
        case .themeColor: return themeOptions.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .appearance: return "外观模式"
        case .themeColor: return "浏览器主题色"
        case nil: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .appearance:
            return "选择「跟随系统」时，应用将自动匹配设备的浅色或深色模式。"
        case .themeColor:
            return "主题色会统一应用到按钮、图标、选中状态、进度与徽标。"
        case nil:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: AppearanceOptionCell.reuseIdentifier,
            for: indexPath
        ) as? AppearanceOptionCell else {
            return UITableViewCell()
        }
        switch Section(rawValue: indexPath.section) {
        case .appearance:
            let option = appearanceOptions[indexPath.row]
            cell.configure(
                title: option.displayName,
                symbol: option.symbolName,
                accentColor: AppColors.accent,
                isSelected: option == AppearancePreference.current
            )
        case .themeColor:
            let option = themeOptions[indexPath.row]
            cell.configure(
                title: option.displayName,
                symbol: "circle.fill",
                accentColor: option.previewColor,
                isSelected: option == AppThemeColor.current
            )
        case nil:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .appearance:
            let option = appearanceOptions[indexPath.row]
            guard option != AppearancePreference.current else { return }
            AppearancePreference.current = option
        case .themeColor:
            let option = themeOptions[indexPath.row]
            guard option != AppThemeColor.current else { return }
            AppThemeColor.current = option
        case nil:
            return
        }
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// 外观选项行（单选样式）。
private final class AppearanceOptionCell: UITableViewCell {
    static let reuseIdentifier = "AppearanceOptionCell"

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

    func configure(
        title: String,
        symbol: String,
        accentColor: UIColor,
        isSelected: Bool
    ) {
        titleLabel.text = title
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        iconView.tintColor = accentColor
        iconContainer.backgroundColor = accentColor.withAlphaComponent(0.12)
        tintColor = accentColor
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
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none
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
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
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
