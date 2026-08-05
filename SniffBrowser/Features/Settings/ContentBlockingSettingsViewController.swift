import UIKit

/// 内容拦截设置页：广告过滤开关与网站白名单管理。
final class ContentBlockingSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let service = ContentBlockerService.shared
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "内容拦截"
        configureTableView()
        observeChanges()
        service.loadIfNeeded()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
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
            GlassSummaryCell.self,
            forCellReuseIdentifier: GlassSummaryCell.reuseIdentifier
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

    private func observeChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .contentBlockerDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    private func presentAddWhitelistAlert() {
        let alert = UIAlertController(
            title: "添加白名单网站",
            message: "输入网站域名，例如 example.com。该网站将不执行广告过滤。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "example.com"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "添加", style: .default) { [weak self, weak alert] _ in
                guard let self,
                      let host = alert?.textFields?.first?.text
                else { return }
                self.service.setWhitelisted(true, host: host)
            }
        )
        present(alert, animated: true)
    }
}

extension ContentBlockingSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : service.whitelistedHosts.count + 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "广告过滤" : "网站白名单"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let count = service.bundledRuleCount
            let rulesText = count > 0 ? "\(count) 条规则" : "规则加载中"
            let errorText = service.lastLoadError.map { "（\($0)）" } ?? ""
            return "使用内置的 \(rulesText) 广告过滤规则\(errorText)，规则来源：AdGuard Base Filter（GPL-3.0）。"
        }
        return "白名单网站不会执行广告过滤，刷新后生效。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "启用广告过滤",
                subtitle: "拦截常见广告与跟踪请求",
                symbol: "shield.lefthalf.filled",
                isOn: service.isEnabled,
                accessibilityIdentifier: "contentBlocking.enabled"
            ) { [weak self] enabled in
                self?.service.setEnabled(enabled)
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        if indexPath.row < service.whitelistedHosts.count {
            let host = service.whitelistedHosts[indexPath.row]
            cell.configure(
                title: host,
                subtitle: "已禁用广告过滤",
                symbol: "shield.slash",
                tint: .systemIndigo
            )
        } else {
            cell.configure(
                title: "添加网站…",
                subtitle: nil,
                symbol: "plus.circle",
                tint: AppColors.accent
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, indexPath.row == service.whitelistedHosts.count else {
            return
        }
        presentAddWhitelistAlert()
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1,
              indexPath.row < service.whitelistedHosts.count
        else {
            return nil
        }
        let host = service.whitelistedHosts[indexPath.row]
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "移除"
        ) { [weak self] _, _, completion in
            self?.service.setWhitelisted(false, host: host)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
