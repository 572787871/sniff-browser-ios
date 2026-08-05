import UIKit

extension FilterCategory {
    var tintColor: UIColor {
        switch self {
        case .ads: return .systemBlue
        case .privacy: return .systemGreen
        case .social: return .systemIndigo
        case .malware: return .systemRed
        case .cookie: return .systemOrange
        case .dns: return .systemTeal
        case .custom: return .systemPurple
        }
    }
}

/// 内容拦截中心首页：总开关、实时统计、规则分类与各功能区入口。
final class ContentBlockingCenterViewController: BaseViewController {
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

    private func push(_ controller: UIViewController) {
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension ContentBlockingCenterViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        5
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return FilterCategory.allCases.count
        case 2: return 2
        case 3: return 1
        default: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "规则管理"
        case 2: return "更新与白名单"
        case 3: return "日志与统计"
        default: return "高级"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "开启后立即生效；拦截次数、节省流量与提速受系统限制无法精确统计，以下显示可观察数据。"
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            let service = ContentBlockerService.shared
            cell.configure(
                title: "内容拦截",
                subtitle: "过滤广告、追踪器、恶意网站、Cookie 横幅及其他网页垃圾内容。",
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
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            let category = FilterCategory.allCases[indexPath.row]
            cell.configure(
                title: category.displayName,
                subtitle: category == .custom
                    ? "\(manager.customManager.allRules().count) 条自定义规则"
                    : nil,
                symbol: category.symbolName,
                tint: category.tintColor
            )
            return cell
        case 2:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            if indexPath.row == 0 {
                cell.configure(
                    title: "更新规则",
                    subtitle: ContentBlockerService.shared.updateDescription,
                    symbol: "arrow.triangle.2.circlepath",
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
        case 3:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            if indexPath.row == 0 {
                cell.configure(
                    title: "请求日志",
                    subtitle: "仅记录主框架导航（系统限制）",
                    symbol: "list.bullet.rectangle",
                    tint: .systemTeal
                )
            } else {
                cell.configure(
                    title: "性能统计",
                    subtitle: nil,
                    symbol: "gauge",
                    tint: .systemPink
                )
            }
            return cell
        default:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            switch indexPath.row {
            case 0:
                cell.configure(
                    title: "高级设置",
                    subtitle: "开发者模式 · 调试 · 导入导出",
                    symbol: "gearshape",
                    tint: .systemGray
                )
            case 1:
                cell.configure(
                    title: "恢复默认配置",
                    subtitle: "重置规则与白名单设置",
                    symbol: "arrow.counterclockwise",
                    tint: AppColors.danger
                )
            default:
                break
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 1:
            push(
                FilterCategoryViewController(
                    category: FilterCategory.allCases[indexPath.row]
                )
            )
        case 2:
            if indexPath.row == 0 {
                push(UpdateRulesViewController())
            } else {
                push(WhitelistViewController())
            }
        case 3:
            if indexPath.row == 0 {
                push(RequestLogViewController())
            } else {
                push(StatsViewController())
            }
        default:
            switch indexPath.row {
            case 0:
                push(AdvancedSettingsViewController())
            default:
                confirmRestoreDefaults()
            }
        }
    }

    private func confirmRestoreDefaults() {
        let alert = UIAlertController(
            title: "恢复默认配置？",
            message: "将重置规则列表开关、自定义规则、白名单与更新周期。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "恢复", style: .destructive) { [weak self] _ in
                self?.manager.restoreDefaults()
                self?.tableView.reloadData()
            }
        )
        present(alert, animated: true)
    }
}
