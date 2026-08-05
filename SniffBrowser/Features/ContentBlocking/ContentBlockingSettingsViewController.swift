import UIKit
import UniformTypeIdentifiers

/// 内容拦截设置页：总开关、内置规则开关、更新、导入规则与白名单。
final class ContentBlockingSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "内容拦截"
        configureTableView()
        observeChanges()
        ContentBlockerService.shared.loadIfNeeded()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
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

    private func toggleRuleList(_ sourceKey: String, enabled: Bool) {
        manager.filterManager.setEnabled(enabled, for: sourceKey)
        Task {
            try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
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

    private func importRules() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .plainText],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension ContentBlockingSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url)
        else { return }
        let imported: Int
        if url.pathExtension.lowercased() == "json" {
            imported = manager.customManager.importJSON(data)
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            imported = manager.customManager.importLines(
                text.components(separatedBy: .newlines)
            )
        }
        if imported > 0 {
            Task {
                try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
            }
            presentAlert(title: "导入成功", message: "已导入 \(imported) 条规则。")
        } else {
            presentAlert(title: "导入失败", message: "没有识别到有效规则。")
        }
    }
}

extension ContentBlockingSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return manager.filterManager.allLists().count
        case 2: return 2
        default: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "内置规则"
        case 2: return "更新"
        default: return "其他"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1
            ? "开关即时生效；导入的规则与白名单会一并参与编译。"
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let service = ContentBlockerService.shared
        switch indexPath.section {
        case 0:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "内容拦截",
                subtitle: "过滤广告、追踪器与恶意网站",
                symbol: "shield.lefthalf.filled",
                isOn: service.isEnabled,
                accessibilityIdentifier: "contentBlocking.master"
            ) { [weak self] enabled in
                service.setEnabled(enabled)
                self?.tableView.reloadData()
            }
            return cell
        case 1:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            let list = manager.filterManager.allLists()[indexPath.row]
            cell.configure(
                title: list.name,
                subtitle: "\(list.details) · \(list.ruleCount) 条",
                symbol: "doc.text",
                isOn: list.isEnabled,
                accessibilityIdentifier: "filterList.\(list.sourceKey)"
            ) { [weak self] enabled in
                self?.toggleRuleList(list.sourceKey, enabled: enabled)
            }
            return cell
        case 2:
            if indexPath.row == 0 {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: GlassSummaryCell.reuseIdentifier,
                    for: indexPath
                ) as? GlassSummaryCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    title: "立即更新",
                    subtitle: service.updateDescription,
                    symbol: "arrow.triangle.2.circlepath",
                    tint: AppColors.accent
                )
                return cell
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "自动更新",
                subtitle: "启动时检查，超过 5 天自动更新",
                symbol: "arrow.clockwise.circle",
                isOn: service.isAutoUpdateEnabled,
                accessibilityIdentifier: "contentBlocking.autoUpdate"
            ) { enabled in
                service.setAutoUpdateEnabled(enabled)
            }
            return cell
        default:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            if indexPath.row == 0 {
                cell.configure(
                    title: "导入规则",
                    subtitle: "支持 txt / JSON 文件",
                    symbol: "square.and.arrow.down",
                    tint: AppColors.accent
                )
            } else {
                cell.configure(
                    title: "网站白名单",
                    subtitle: "\(manager.whitelistManager.allPatterns().count) 个模式",
                    symbol: "shield.slash",
                    tint: .systemGray
                )
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 2:
            if indexPath.row == 0 {
                runUpdate()
            }
        case 3:
            if indexPath.row == 0 {
                importRules()
            } else {
                navigationController?.pushViewController(
                    WhitelistViewController(),
                    animated: true
                )
            }
        default:
            break
        }
    }
}
