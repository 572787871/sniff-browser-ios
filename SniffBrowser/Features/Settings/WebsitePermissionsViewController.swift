import UIKit

/// 网站权限管理页：查看、修改或清除各网站保存的权限决定。
final class WebsitePermissionsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let store = WebsitePermissionStore.shared
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "hand.raised",
            title: "还没有网站权限记录",
            message: "网页请求摄像头、麦克风或位置时，你的选择会显示在这里。"
        )
    )
    private var sites: [WebsiteSitePermission] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "网站权限"
        configureTableView()
        configureEmptyState()
        reload()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.register(
            WebsiteSiteCell.self,
            forCellReuseIdentifier: WebsiteSiteCell.reuseIdentifier
        )
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

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func reload() {
        sites = store.sites()
        tableView.reloadData()
        let isEmpty = sites.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }
}

extension WebsitePermissionsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sites.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "已保存的网站"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "网页请求摄像头、麦克风或位置时，应用会先征求你的同意并记住选择。点击网站可修改权限。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: WebsiteSiteCell.reuseIdentifier,
            for: indexPath
        ) as? WebsiteSiteCell else {
            return UITableViewCell()
        }
        cell.configure(with: sites[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let site = sites[indexPath.row]
        let detail = WebsiteSitePermissionViewController(
            host: site.host,
            store: store
        )
        detail.onChanged = { [weak self] in
            self?.reload()
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let site = sites[indexPath.row]
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "清除"
        ) { [weak self] _, _, completion in
            self?.store.removeSite(host: site.host)
            self?.reload()
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

/// 单个网站权限详情页：逐项修改并支持恢复为每次询问。
final class WebsiteSitePermissionViewController: BaseViewController {
    var onChanged: (() -> Void)?

    private let host: String
    private let store: WebsitePermissionStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(host: String, store: WebsitePermissionStore = .shared) {
        self.host = host
        self.store = store
        super.init(title: host, prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.register(
            SettingsToggleCell.self,
            forCellReuseIdentifier: SettingsToggleCell.reuseIdentifier
        )
        tableView.register(
            SettingsCheckmarkCell.self,
            forCellReuseIdentifier: SettingsCheckmarkCell.reuseIdentifier
        )
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

extension WebsiteSitePermissionViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? WebsitePermission.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "权限" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "打开开关表示允许该网站使用对应功能，关闭表示拒绝。" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            let permission = WebsitePermission.allCases[indexPath.row]
            let decision = store.decision(for: host, permission: permission)
            cell.configure(
                title: permission.displayName,
                subtitle: decision == .allow ? "允许" : "拒绝",
                symbol: permission.symbolName,
                isOn: decision == .allow,
                accessibilityIdentifier: "sitePermission.\(permission.rawValue)"
            ) { [weak self] enabled in
                guard let self else { return }
                self.store.setDecision(
                    enabled ? .allow : .deny,
                    for: self.host,
                    permission: permission
                )
                self.onChanged?()
                tableView.reloadRows(at: [indexPath], with: .none)
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsCheckmarkCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsCheckmarkCell else {
            return UITableViewCell()
        }
        cell.configure(
            title: "恢复为每次询问",
            symbol: "arrow.counterclockwise",
            isSelected: false
        )
        cell.accessibilityLabel = "清除此网站保存的权限"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        store.removeSite(host: host)
        onChanged?()
        navigationController?.popViewController(animated: true)
    }
}

private final class WebsiteSiteCell: UITableViewCell {
    static let reuseIdentifier = "WebsiteSiteCell"

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(with site: WebsiteSitePermission) {
        titleLabel.text = site.host
        let parts = WebsitePermission.allCases.compactMap { permission -> String? in
            guard let decision = site.permissions[permission] else { return nil }
            return "\(permission.displayName) \(decision == .allow ? "允许" : "拒绝")"
        }
        subtitleLabel.text = parts.isEmpty ? "已保存权限" : parts.joined(separator: " · ")
        accessibilityLabel = "\(site.host)，\(subtitleLabel.text ?? "")"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    private func configureView() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
        selectionStyle = .default
        accessoryType = .disclosureIndicator
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconContainer.backgroundColor = AppColors.accentFill
        iconContainer.layer.cornerRadius = AppRadius.small
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconContainer)

        iconView.image = UIImage(
            systemName: "globe",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        iconView.tintColor = AppColors.accent
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 1

        AppTypography.configure(subtitleLabel, style: .caption1)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.spacing = AppSpacing.xxs
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        contentView.addSubview(textStack)

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

            textStack.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            textStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: AppSpacing.sm
            ),
            textStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.sm
            ),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }
}
