import UIKit
import UniformTypeIdentifiers

// MARK: - 更新规则

final class UpdateRulesViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "更新规则"
        configureTableView()
        observeChanges()
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
        tableView.estimatedRowHeight = 52
        tableView.register(
            SettingsToggleCell.self,
            forCellReuseIdentifier: SettingsToggleCell.reuseIdentifier
        )
        tableView.register(
            GlassSummaryCell.self,
            forCellReuseIdentifier: GlassSummaryCell.reuseIdentifier
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

    private func observeChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .contentBlockerDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    private func runUpdate() {
        Task {
            do {
                try await ContentBlockerService.shared.updateRules(reloadPages: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                presentAlert(title: "规则已更新", message: "最新过滤规则已生效。")
            } catch {
                presentAlert(title: "更新失败", message: error.localizedDescription)
            }
            tableView.reloadData()
        }
    }

    private func restoreDefaults() {
        manager.restoreDefaults()
        Task {
            try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
        }
        tableView.reloadData()
        presentAlert(title: "已恢复默认", message: "规则列表、自定义规则与白名单已重置。")
    }

    private func clearCache() {
        Task {
            try? await ContentBlockerService.shared.clearSourceCache()
        }
        presentAlert(title: "已清除缓存", message: "规则缓存已清除，下一次更新会重新下载。")
    }

    private func presentAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension UpdateRulesViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3
        case 1: return 1 + UpdateSchedule.allCases.count
        case 2: return 3
        default: return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "自动更新"
        case 2: return "更新日志"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1
            ? "超过设定天数后，应用启动时会在后台静默下载并应用新规则，不重载当前页面。"
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let service = ContentBlockerService.shared
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            let values: [(String, String, String)] = [
                ("当前版本", service.filterVersion ?? "内置规则", "number"),
                ("更新时间", service.updateDescription, "clock"),
                ("规则数量", "\(service.ruleCount) 条", "list.bullet"),
            ]
            let value = values[indexPath.row]
            cell.configure(
                title: value.0,
                subtitle: value.1,
                symbol: value.2,
                tint: .systemGray,
                isEnabled: false
            )
            return cell
        }
        if indexPath.section == 1 {
            if indexPath.row == 0 {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: SettingsToggleCell.reuseIdentifier,
                    for: indexPath
                ) as? SettingsToggleCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    title: "自动更新",
                    subtitle: "后台静默下载",
                    symbol: "arrow.triangle.2.circlepath",
                    isOn: service.isAutoUpdateEnabled,
                    accessibilityIdentifier: "updateRules.auto"
                ) { [weak self] enabled in
                    service.setAutoUpdateEnabled(enabled)
                    self?.tableView.reloadData()
                }
                return cell
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsCheckmarkCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsCheckmarkCell else {
                return UITableViewCell()
            }
            let schedule = UpdateSchedule.allCases[indexPath.row - 1]
            cell.configure(
                title: schedule.displayName,
                symbol: "clock",
                isSelected: manager.updateSchedule == schedule
            )
            return cell
        }
        if indexPath.section == 2 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            let logs = [
                ("新增中文站广告规则", "checkmark.circle"),
                ("优化移动端广告拦截性能", "checkmark.circle"),
                ("修复部分站点误拦截", "checkmark.circle"),
            ]
            let log = logs[indexPath.row]
            cell.configure(
                title: log.0,
                subtitle: nil,
                symbol: log.1,
                tint: .systemGreen,
                isEnabled: false
            )
            return cell
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        switch indexPath.row {
        case 0:
            cell.configure(
                title: "立即更新",
                subtitle: nil,
                symbol: "arrow.triangle.2.circlepath",
                tint: AppColors.accent
            )
        case 1:
            cell.configure(
                title: "恢复默认规则",
                subtitle: nil,
                symbol: "arrow.counterclockwise",
                tint: AppColors.accent
            )
        default:
            cell.configure(
                title: "清除规则缓存",
                subtitle: nil,
                symbol: "trash",
                tint: AppColors.danger
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1, indexPath.row > 0 {
            let schedule = UpdateSchedule.allCases[indexPath.row - 1]
            manager.setUpdateSchedule(schedule)
            tableView.reloadData()
        } else if indexPath.section == 3 {
            switch indexPath.row {
            case 0: runUpdate()
            case 1: restoreDefaults()
            default: clearCache()
            }
        }
    }
}

// MARK: - 网站白名单

final class WhitelistViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private let manager = ContentBlockManager.shared
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "shield.slash",
            title: "暂无白名单",
            message: "添加网站后，该网站不执行任何过滤规则。"
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "网站白名单"
        configureNavigation()
        configureTable()
        configureEmptyState()
        render()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索白名单"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPattern)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(showTransferMenu)
        )
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.register(
            SettingsToggleCell.self,
            forCellReuseIdentifier: SettingsToggleCell.reuseIdentifier
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

    private func patterns() -> [WhitelistPattern] {
        manager.whitelistManager.searchPatterns(
            query: searchController.searchBar.text ?? ""
        )
    }

    private func render() {
        tableView.reloadData()
        let isEmpty = patterns().isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }

    @objc private func addPattern() {
        let alert = UIAlertController(
            title: "添加白名单",
            message: "输入域名、通配符或正则表达式。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "example.com 或 *.example.com"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        for type in WhitelistMatchType.allCases {
            alert.addAction(
                UIAlertAction(title: "添加（\(type.displayName)）", style: .default) {
                    [weak self, weak alert] _ in
                    guard let self,
                          let text = alert?.textFields?.first?.text,
                          !text.trimmingCharacters(in: .whitespaces).isEmpty
                    else { return }
                    self.manager.whitelistManager.addPattern(
                        WhitelistPattern(pattern: text, matchType: type)
                    )
                    self.render()
                    Task {
                        try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
                    }
                }
            )
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func showTransferMenu() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(
            UIAlertAction(title: "导出白名单", style: .default) { [weak self] _ in
                self?.exportWhitelist()
            }
        )
        alert.addAction(
            UIAlertAction(title: "导入白名单", style: .default) { [weak self] _ in
                self?.importWhitelist()
            }
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func exportWhitelist() {
        guard let data = manager.whitelistManager.exportJSON() else { return }
        let activity = UIActivityViewController(
            activityItems: [data],
            applicationActivities: nil
        )
        present(activity, animated: true)
    }

    private func importWhitelist() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }
}

extension WhitelistViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        render()
    }
}

extension WhitelistViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url)
        else { return }
        if manager.whitelistManager.importJSON(data) {
            render()
        }
    }
}

extension WhitelistViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        patterns().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsToggleCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsToggleCell else {
            return UITableViewCell()
        }
        let pattern = patterns()[indexPath.row]
        cell.configure(
            title: pattern.pattern,
            subtitle: pattern.matchType.displayName,
            symbol: pattern.matchType == .regex ? "curlybraces" : "globe",
            isOn: pattern.isEnabled,
            accessibilityIdentifier: "whitelist.\(pattern.id.uuidString)"
        ) { [weak self] enabled in
            self?.manager.whitelistManager.setEnabled(enabled, id: pattern.id)
            Task {
                try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
            }
        }
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let pattern = patterns()[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") {
            [weak self] _, _, completion in
            self?.manager.whitelistManager.deletePattern(id: pattern.id)
            self?.render()
            Task {
                try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
            }
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

// MARK: - 请求日志

final class RequestLogViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "list.bullet.rectangle",
            title: "暂无日志",
            message: "系统限制下仅记录主框架导航。"
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "请求日志"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "清除",
            style: .plain,
            target: self,
            action: #selector(clearLogs)
        )
        configureTable()
        configureEmptyState()
        render()
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
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

    private func render() {
        tableView.reloadData()
        let isEmpty = manager.logManager.allEntries().isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }

    @objc private func clearLogs() {
        manager.logManager.clear()
        render()
    }
}

extension RequestLogViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        manager.logManager.allEntries().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        let entry = manager.logManager.allEntries()[indexPath.row]
        cell.configure(
            title: entry.host,
            subtitle: "\(entry.url) · \(entry.resourceType) · \(entry.status)",
            symbol: "globe",
            tint: entry.isBlocked ? AppColors.danger : AppColors.accent
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = manager.logManager.allEntries()[indexPath.row]
        let alert = UIAlertController(
            title: entry.host,
            message: """
            URL：\(entry.url)
            类型：\(entry.resourceType)
            状态：\(entry.status)
            命中规则：\(entry.ruleIdentifier ?? "不可用（系统限制）")
            耗时：\(Int(entry.durationMs)) ms

            完整请求头/响应头受 WebKit 系统限制，无法获取。
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - 性能统计

final class StatsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "性能统计"
        configureTable()
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
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
}

extension StatsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 6 : 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "拦截统计" : "排行"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "拦截次数、节省流量与平均提速受 WebKit 系统限制无法精确统计，显示为不可用（—）。"
            : "过滤器、网站与资源类型排行需要逐请求数据，当前系统限制下不可用。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        let stats = manager.statisticsManager.current()
        if indexPath.section == 0 {
            let values: [(String, String, String)] = [
                ("今日拦截次数", "—", "number"),
                ("累计拦截次数", "—", "number"),
                ("节省流量", "—", "arrow.down.circle"),
                ("平均提速", "—", "gauge"),
                ("命中率", "—", "percent"),
                ("当前规则", "\(stats.ruleCount) 条", "list.bullet"),
            ]
            let value = values[indexPath.row]
            cell.configure(
                title: value.0,
                subtitle: value.1,
                symbol: value.2,
                tint: .systemGray,
                isEnabled: false
            )
        } else {
            let names = ["过滤器命中排行", "网站拦截排行", "资源类型排行"]
            cell.configure(
                title: names[indexPath.row],
                subtitle: "不可用（系统限制）",
                symbol: "chart.bar",
                tint: .systemGray,
                isEnabled: false
            )
        }
        return cell
    }
}

// MARK: - 高级设置

final class AdvancedSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private var debugRules = false
    private var debugRequests = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "高级设置"
        configureTable()
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
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

    private func exportRules() {
        guard let data = manager.exportCustomRulesJSON() else {
            return
        }
        let activity = UIActivityViewController(
            activityItems: [data],
            applicationActivities: nil
        )
        present(activity, animated: true)
    }

    private func importRules() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .plainText],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }
}

extension AdvancedSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url)
        else { return }
        if manager.importCustomRulesJSON(data) {
            let alert = UIAlertController(
                title: "导入成功",
                message: "自定义规则已导入。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }
}

extension AdvancedSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 3
        default: return 4
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "开发者"
        case 1: return "调试"
        default: return "数据"
        }
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
                title: "Developer Mode",
                subtitle: "显示调试入口",
                symbol: "hammer",
                isOn: manager.isDeveloperMode,
                accessibilityIdentifier: "advanced.developerMode"
            ) { [weak self] enabled in
                self?.manager.setDeveloperMode(enabled)
            }
            return cell
        }
        if indexPath.section == 1 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            let values = [
                ("过滤器调试", "记录规则编译与更新状态", "debugRules"),
                ("请求日志", "记录主框架导航", "debugRequests"),
                ("DNS 日志", "当前版本不可用（系统限制）", "debugDNS"),
            ]
            let value = values[indexPath.row]
            cell.configure(
                title: value.0,
                subtitle: value.1,
                symbol: "ladybug",
                isOn: value.2 == "debugRules" ? debugRules
                    : value.2 == "debugRequests" ? debugRequests : false,
                accessibilityIdentifier: "advanced.\(value.2)"
            ) { [weak self] enabled in
                if value.2 == "debugRules" {
                    self?.debugRules = enabled
                } else if value.2 == "debugRequests" {
                    self?.debugRequests = enabled
                }
            }
            return cell
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        let values = [
            ("导出规则", "自定义规则 JSON", "square.and.arrow.up"),
            ("导入规则", "JSON / 文本", "square.and.arrow.down"),
            ("清除规则缓存", "删除已下载的规则源", "trash"),
            ("恢复默认配置", "重置所有设置", "arrow.counterclockwise"),
        ]
        let value = values[indexPath.row]
        cell.configure(
            title: value.0,
            subtitle: value.1,
            symbol: value.2,
            tint: indexPath.row == 2 || indexPath.row == 3 ? AppColors.danger : AppColors.accent
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2 else { return }
        switch indexPath.row {
        case 0:
            exportRules()
        case 1:
            importRules()
        case 2:
            Task {
                try? await ContentBlockerService.shared.clearSourceCache()
            }
            let alert = UIAlertController(
                title: "已清除缓存",
                message: "下一次更新会重新下载规则。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        default:
            manager.restoreDefaults()
            let alert = UIAlertController(
                title: "已恢复默认",
                message: "规则列表、自定义规则与白名单已重置。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }
}
