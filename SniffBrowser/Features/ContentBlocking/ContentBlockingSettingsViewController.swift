import UIKit
import UniformTypeIdentifiers

/// 内容拦截设置页：总开关、拦截统计（支持按时间范围筛选）、导入规则与白名单。
final class ContentBlockingSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private var selectedRange: StatisticsRange = .today
    private weak var rangeButton: UIButton?
    private var changeObserver: NSObjectProtocol?

    init() {
        super.init(title: "内容拦截", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItems()
        configureTableView()
        observeChanges()
        ContentBlockerService.shared.loadIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.register(
            ContentBlockMasterCardCell.self,
            forCellReuseIdentifier: ContentBlockMasterCardCell.reuseIdentifier
        )
        tableView.register(
            ContentBlockStatsCardCell.self,
            forCellReuseIdentifier: ContentBlockStatsCardCell.reuseIdentifier
        )
        tableView.register(
            ContentBlockActionCardCell.self,
            forCellReuseIdentifier: ContentBlockActionCardCell.reuseIdentifier
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

    /// 顶部导航：左侧圆形返回按钮、居中标题（参考图：右上无按钮）。
    private func configureNavigationItems() {
        navigationItem.hidesBackButton = true
        let backButton = UIButton(type: .custom)
        backButton.setImage(
            UIImage(named: "back_button")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.clipsToBounds = false
        backButton.frame = CGRect(x: 0, y: 0, width: 42, height: 42)
        backButton.addAction(
            UIAction { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            },
            for: .touchUpInside
        )
        backButton.accessibilityLabel = "返回"
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)
        // 隐藏系统返回按钮后保留边缘右滑返回手势。
        navigationController?.interactivePopGestureRecognizer?.delegate = self
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

    // MARK: - 时间范围筛选

    private func selectRange(_ range: StatisticsRange) {
        selectedRange = range
        // 原位更新数据与按钮标题，避免整段刷新造成的闪动。
        rangeButton?.accessibilityLabel = "统计时间范围，当前\(range.rawValue)"
        rangeButton?.menu = makeRangeMenu()
        if let cell = tableView.cellForRow(
            at: IndexPath(row: 0, section: 1)
        ) as? ContentBlockStatsCardCell {
            configureStatsCell(cell)
        }
    }

    private func makeRangeButton() -> UIButton {
        // “今日”筛选按钮使用 today_selector 素材，禁止 tint / 重绘。
        let button = UIButton(type: .custom)
        button.setImage(
            UIImage(named: "today_selector")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        button.imageView?.contentMode = .scaleAspectFit
        button.clipsToBounds = false
        button.frame = CGRect(x: 0, y: 0, width: 82, height: 34)
        button.showsMenuAsPrimaryAction = true
        button.menu = makeRangeMenu()
        button.accessibilityLabel = "统计时间范围，当前\(selectedRange.rawValue)"
        rangeButton = button
        return button
    }

    private func makeRangeMenu() -> UIMenu {
        UIMenu(children: StatisticsRange.allCases.map { range in
            UIAction(
                title: range.rawValue,
                state: range == selectedRange ? .on : .off
            ) { [weak self] _ in
                self?.selectRange(range)
            }
        })
    }

    private func configureStatsCell(_ cell: ContentBlockStatsCardCell) {
        let summary = manager.statisticsManager.summary(for: selectedRange)
        cell.configure(
            blocked: summary.todayBlocked,
            pageLoads: summary.todayPageLoads,
            ruleCount: summary.ruleCount,
            filterCount: summary.filterCount,
            blockedTitle: selectedRange.metricTitle(for: .blocked),
            pageLoadTitle: selectedRange.metricTitle(for: .pageLoads)
        )
    }

    // MARK: - 导入规则

    private func showImportMenu() {
        let alert = UIAlertController(
            title: "导入规则",
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(title: "从文件导入", style: .default) { [weak self] _ in
                self?.importFromFile()
            }
        )
        alert.addAction(
            UIAlertAction(title: "从链接导入", style: .default) { [weak self] _ in
                self?.presentURLImport()
            }
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func importFromFile() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .plainText],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentURLImport() {
        let alert = UIAlertController(
            title: "从链接导入",
            message: "输入过滤规则的下载地址（txt 或 JSON）。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/filter.txt"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
                guard let text = alert?.textFields?.first?.text,
                      let url = URL(string: text.trimmingCharacters(in: .whitespaces))
                else { return }
                self?.importFromURL(url)
            }
        )
        present(alert, animated: true)
    }

    private func importFromURL(_ url: URL) {
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 60
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200
                else {
                    throw URLError(.badServerResponse)
                }
                let imported: Int
                if url.pathExtension.lowercased() == "json" {
                    imported = self.manager.customManager.importJSON(data)
                } else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    imported = self.manager.customManager.importLines(
                        text.components(separatedBy: .newlines)
                    )
                }
                if imported > 0 {
                    try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
                    self.presentAlert(title: "导入成功", message: "已导入 \(imported) 条规则。")
                } else {
                    self.presentAlert(title: "导入失败", message: "链接中没有识别到有效规则。")
                }
            } catch {
                self.presentAlert(title: "导入失败", message: "无法下载规则，请检查链接与网络。")
            }
        }
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

extension ContentBlockingSettingsViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        navigationController?.viewControllers.count ?? 0 > 1
    }
}

extension ContentBlockingSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 1
        default: return 2
        }
    }

    func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        switch section {
        case 1:
            return ContentBlockSectionHeaderView(
                title: "拦截统计",
                trailing: makeRangeButton()
            )
        case 2:
            return ContentBlockSectionHeaderView(title: "其他")
        default:
            return nil
        }
    }

    func tableView(
        _ tableView: UITableView,
        heightForHeaderInSection section: Int
    ) -> CGFloat {
        section == 0 ? 10 : 36
    }

    func tableView(
        _ tableView: UITableView,
        viewForFooterInSection section: Int
    ) -> UIView? {
        nil
    }

    func tableView(
        _ tableView: UITableView,
        heightForFooterInSection section: Int
    ) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let service = ContentBlockerService.shared
        switch indexPath.section {
        case 0:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ContentBlockMasterCardCell.reuseIdentifier,
                for: indexPath
            ) as? ContentBlockMasterCardCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "内容拦截",
                subtitle: "过滤广告、追踪器与恶意网站",
                isOn: service.isEnabled,
                accessibilityIdentifier: "contentBlocking.master"
            ) { [weak self] enabled in
                service.setEnabled(enabled)
                self?.tableView.reloadData()
            }
            return cell
        case 1:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ContentBlockStatsCardCell.reuseIdentifier,
                for: indexPath
            ) as? ContentBlockStatsCardCell else {
                return UITableViewCell()
            }
            configureStatsCell(cell)
            return cell
        case 2:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ContentBlockActionCardCell.reuseIdentifier,
                for: indexPath
            ) as? ContentBlockActionCardCell else {
                return UITableViewCell()
            }
            if indexPath.row == 0 {
                cell.configure(
                    title: "导入规则",
                    subtitle: "支持 txt / JSON 文件",
                    imageName: "import_rule"
                )
            } else {
                cell.configure(
                    title: "网站白名单",
                    subtitle: "\(manager.whitelistManager.allPatterns().count) 个模式",
                    imageName: "whitelist"
                )
            }
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 2:
            if indexPath.row == 0 {
                showImportMenu()
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
