import UIKit

/// 外观设置页面，提供跟随系统 / 浅色 / 深色 三个选项。
final class AppearanceSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let options = AppearancePreference.allCases

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
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "外观模式"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "选择「跟随系统」时，应用将自动匹配设备的浅色或深色模式。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: AppearanceOptionCell.reuseIdentifier,
            for: indexPath
        ) as? AppearanceOptionCell else {
            return UITableViewCell()
        }
        let option = options[indexPath.row]
        let isSelected = option == AppearancePreference.current
        cell.configure(
            title: option.displayName,
            symbol: option.symbolName,
            isSelected: isSelected
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = options[indexPath.row]
        guard option != AppearancePreference.current else { return }
        AppearancePreference.current = option
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
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark"))

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
        iconView.tintColor = AppColors.accent
        iconContainer.backgroundColor = AppColors.accent.withAlphaComponent(0.12)
        checkmarkView.isHidden = !isSelected
        checkmarkView.tintColor = AppColors.accent
        accessoryType = isSelected ? .checkmark : .none
        accessibilityLabel = title
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        iconView.image = nil
        checkmarkView.isHidden = true
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
