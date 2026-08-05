import UIKit

/// 自定义规则页：搜索、列表、增删改、复制、收藏、批量与拖拽排序。
final class CustomRulesViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private let manager = ContentBlockManager.shared
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "text.badge.plus",
            title: "还没有自定义规则",
            message: "点击右上角 + 添加规则，支持阻止、允许、白名单与元素隐藏。"
        )
    )
    private var isEditingMode = false
    private var selectedIDs: Set<UUID> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "自定义规则"
        configureNavigation()
        configureTable()
        configureEmptyState()
        render()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索规则"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addRule)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "编辑",
            style: .plain,
            target: self,
            action: #selector(toggleEditMode)
        )
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.register(
            CustomRuleCell.self,
            forCellReuseIdentifier: CustomRuleCell.reuseIdentifier
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

    private func rules() -> [CustomRule] {
        let query = searchController.searchBar.text ?? ""
        return manager.customManager.searchRules(query: query)
    }

    private func render() {
        tableView.reloadData()
        let isEmpty = rules().isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }

    @objc private func addRule() {
        navigationController?.pushViewController(
            CustomRuleEditorViewController(rule: nil),
            animated: true
        )
    }

    @objc private func toggleEditMode() {
        isEditingMode.toggle()
        selectedIDs = []
        tableView.setEditing(isEditingMode, animated: true)
        navigationItem.leftBarButtonItem?.title = isEditingMode ? "完成" : "编辑"
        navigationItem.rightBarButtonItem = isEditingMode
            ? UIBarButtonItem(
                title: "批量操作",
                style: .plain,
                target: self,
                action: #selector(showBatchMenu)
            )
            : UIBarButtonItem(
                barButtonSystemItem: .add,
                target: self,
                action: #selector(addRule)
            )
    }

    @objc private func showBatchMenu() {
        guard !selectedIDs.isEmpty else {
            presentSingleButtonAlert(title: "请先选择规则", message: nil)
            return
        }
        let alert = UIAlertController(title: "批量操作 (\(selectedIDs.count))", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "批量启用", style: .default) { [weak self] _ in
            self?.applyBatch(enabled: true)
        })
        alert.addAction(UIAlertAction(title: "批量禁用", style: .default) { [weak self] _ in
            self?.applyBatch(enabled: false)
        })
        alert.addAction(UIAlertAction(title: "批量删除", style: .destructive) { [weak self] _ in
            self?.deleteSelected()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func applyBatch(enabled: Bool) {
        manager.customManager.batchToggle(Array(selectedIDs), enabled: enabled)
        selectedIDs = []
        render()
    }

    private func deleteSelected() {
        manager.customManager.batchDelete(Array(selectedIDs))
        selectedIDs = []
        render()
    }

    private func presentSingleButtonAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension CustomRulesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        render()
    }
}

extension CustomRulesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rules().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CustomRuleCell.reuseIdentifier,
            for: indexPath
        ) as? CustomRuleCell else {
            return UITableViewCell()
        }
        let rule = rules()[indexPath.row]
        cell.configure(rule: rule) { [weak self] enabled in
            var updated = rule
            updated.isEnabled = enabled
            self?.manager.customManager.updateRule(updated)
            Task {
                try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditingMode {
            let rule = rules()[indexPath.row]
            if selectedIDs.contains(rule.id) {
                selectedIDs.remove(rule.id)
            } else {
                selectedIDs.insert(rule.id)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let rule = rules()[indexPath.row]
        navigationController?.pushViewController(
            CustomRuleEditorViewController(rule: rule),
            animated: true
        )
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let rule = rules()[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") {
            [weak self] _, _, completion in
            self?.manager.customManager.deleteRule(id: rule.id)
            self?.render()
            completion(true)
        }
        let copy = UIContextualAction(style: .normal, title: "复制") {
            [weak self] _, _, completion in
            self?.manager.customManager.duplicateRule(id: rule.id)
            self?.render()
            completion(true)
        }
        copy.backgroundColor = AppColors.accent
        let favorite = UIContextualAction(
            style: .normal,
            title: rule.isFavorite ? "取消收藏" : "收藏"
        ) { [weak self] _, _, completion in
            self?.manager.customManager.toggleFavorite(id: rule.id)
            self?.render()
            completion(true)
        }
        favorite.backgroundColor = .systemOrange
        let configuration = UISwipeActionsConfiguration(actions: [delete, copy, favorite])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        manager.customManager.moveRules(
            from: IndexSet(integer: sourceIndexPath.row),
            to: destinationIndexPath.row
        )
    }
}

private final class CustomRuleCell: UITableViewCell {
    static let reuseIdentifier = "CustomRuleCell"

    private let titleLabel = UILabel()
    private let contentLabel = UILabel()
    private let metaLabel = UILabel()
    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(rule: CustomRule, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        titleLabel.text = rule.name + (rule.isFavorite ? " ★" : "")
        contentLabel.text = rule.content
        contentLabel.textColor = rule.type.isSystemBlockable
            ? AppColors.secondaryText
            : AppColors.danger
        let meta = "\(rule.type.displayName) · 命中 \(rule.hitCount) 次"
            + (rule.lastHitAt.map { " · \(Self.timeFormatter.string(from: $0))" } ?? "")
        metaLabel.text = meta
        toggle.setOn(rule.isEnabled, animated: false)
        toggle.accessibilityIdentifier = "customRule.\(rule.id.uuidString).switch"
        accessibilityLabel = "\(rule.name)，\(meta)"
    }

    @objc private func toggleChanged() {
        onChange?(toggle.isOn)
    }

    private func configureView() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background

        AppTypography.configure(titleLabel, style: .body, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 1

        AppTypography.configure(contentLabel, style: .caption1)
        contentLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        contentLabel.numberOfLines = 1
        contentLabel.lineBreakMode = .byTruncatingMiddle

        AppTypography.configure(metaLabel, style: .caption2)
        metaLabel.textColor = AppColors.tertiaryText
        metaLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, contentLabel, metaLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        accessoryView = toggle

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
