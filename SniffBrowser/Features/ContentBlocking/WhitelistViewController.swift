import UIKit
import UniformTypeIdentifiers

/// 网站白名单：域名/子域名/通配符/正则，支持导入导出。
final class WhitelistViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
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
        let addActions = WhitelistMatchType.allCases.map { type in
            UIAction(
                title: "添加（\(type.displayName)）",
                image: UIImage(
                    systemName: type == .regex ? "curlybraces" : "globe"
                )
            ) { [weak self] _ in
                self?.presentPatternInput(type: type)
            }
        }
        let importAction = UIAction(
            title: "导入白名单",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            self?.importWhitelist()
        }
        let exportAction = UIAction(
            title: "导出白名单",
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.exportWhitelist()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            menu: UIMenu(children: addActions + [importAction, exportAction])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "添加或管理白名单"
        navigationItem.leftBarButtonItem = nil
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
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

    private func render() {
        tableView.reloadData()
        let isEmpty = manager.whitelistManager.allPatterns().isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }

    private func presentPatternInput(type: WhitelistMatchType) {
        let alert = UIAlertController(
            title: "添加（\(type.displayName)）",
            message: type == .regex
                ? "输入正则表达式，例如 ^ads\\.example\\.com$"
                : "输入域名或通配符，例如 example.com 或 *.example.com",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = type == .regex ? "^ads\\.example\\.com$" : "example.com"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "添加", style: .default) { [weak self, weak alert] _ in
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
        present(alert, animated: true)
    }

    private func importWhitelist() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    private func exportWhitelist() {
        guard let data = manager.whitelistManager.exportJSON() else { return }
        let activity = UIActivityViewController(
            activityItems: [data],
            applicationActivities: nil
        )
        present(activity, animated: true)
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
        manager.whitelistManager.allPatterns().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsToggleCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsToggleCell else {
            return UITableViewCell()
        }
        let pattern = manager.whitelistManager.allPatterns()[indexPath.row]
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
        let pattern = manager.whitelistManager.allPatterns()[indexPath.row]
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
