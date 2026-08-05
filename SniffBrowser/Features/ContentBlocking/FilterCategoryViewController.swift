import UIKit

/// 规则分类二级页：展示该分类下的官方规则列表；无内置列表的分类给出诚实说明。
final class FilterCategoryViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private let category: FilterCategory
    private var changeObserver: NSObjectProtocol?

    init(category: FilterCategory) {
        self.category = category
        super.init(title: category.displayName, prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        tableView.estimatedRowHeight = 62
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

}

extension FilterCategoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(manager.filterManager.lists(in: category).count, 1)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch category {
        case .ads:
            return "每个规则列表可独立开关与排序；点击查看详情与许可证。"
        case .privacy:
            return "隐私保护规则来自 EasyPrivacy（CC BY-SA 3.0）。"
        case .custom:
            return "自定义规则在独立页面管理，支持阻止、允许、白名单与元素隐藏。"
        case .dns:
            return "DNS 拦截依赖系统网络能力，当前版本不内置 DNS 服务器，此分类暂无规则。"
        default:
            return "该分类暂未内置独立规则列表，相关过滤能力由 AdGuard Base 规则覆盖。"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        let lists = manager.filterManager.lists(in: category)
        if lists.isEmpty {
            cell.configure(
                title: "暂无独立规则",
                subtitle: "\(category.displayName) 暂未内置专属规则列表",
                symbol: category.symbolName,
                tint: .systemGray,
                isEnabled: false
            )
            return cell
        }
        let list = lists[indexPath.row]
        cell.configure(
            title: list.name,
            subtitle: "\(list.details) · \(list.ruleCount) 条 · \(list.version)",
            symbol: "doc.text",
            tint: category.tintColor
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let lists = manager.filterManager.lists(in: category)
        guard indexPath.row < lists.count else { return }
        navigationController?.pushViewController(
            FilterListDetailViewController(list: lists[indexPath.row]),
            animated: true
        )
    }
}

/// 规则列表详情页：开关、说明、作者、许可证、版本、更新时间与更新日志。
final class FilterListDetailViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private let list: FilterListMeta

    init(list: FilterListMeta) {
        self.list = list
        super.init(title: list.name, prefersLargeTitle: false)
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

    private func currentList() -> FilterListMeta {
        manager.filterManager.allLists().first {
            $0.sourceKey == list.sourceKey
        } ?? list
    }
}

extension FilterListDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 5
        default: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "信息" : section == 2 ? "操作" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let list = currentList()
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsToggleCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "启用规则",
                subtitle: list.details,
                symbol: "checkmark.circle",
                isOn: list.isEnabled,
                accessibilityIdentifier: "filterList.\(list.sourceKey)"
            ) { [weak self] enabled in
                guard let self else { return }
                self.manager.filterManager.setEnabled(enabled, for: list.sourceKey)
                Task {
                    try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
                }
                self.tableView.reloadData()
            }
            return cell
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        if indexPath.section == 1 {
            let values: [(String, String, String)] = [
                ("作者", list.author, "person"),
                ("许可证", list.license, "doc.plaintext"),
                ("版本号", list.version, "number"),
                ("规则数量", "\(list.ruleCount)", "list.bullet"),
                (
                    "更新时间",
                    list.updatedAt.map(Self.dateFormatter.string) ?? "尚未更新",
                    "clock"
                ),
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
        if indexPath.row == 0 {
            cell.configure(
                title: "查看更新日志",
                subtitle: nil,
                symbol: "doc.text",
                tint: AppColors.accent
            )
        } else {
            cell.configure(
                title: "立即更新此规则",
                subtitle: nil,
                symbol: "arrow.triangle.2.circlepath",
                tint: AppColors.accent
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2 else { return }
        if indexPath.row == 0 {
            navigationController?.pushViewController(
                UpdateRulesViewController(),
                animated: true
            )
        } else {
            Task {
                try? await ContentBlockerService.shared.updateRules(reloadPages: true)
                tableView.reloadData()
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
