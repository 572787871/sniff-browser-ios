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
        tableView.register(
            ContentBlockStatsCardCell.self,
            forCellReuseIdentifier: ContentBlockStatsCardCell.reuseIdentifier
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "拦截统计"
        default: return "其他"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            return "统计被隐藏的广告元素与拦截的主框架导航，为近似值。"
        default:
            return nil
        }
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
                withIdentifier: ContentBlockStatsCardCell.reuseIdentifier,
                for: indexPath
            ) as? ContentBlockStatsCardCell else {
                return UITableViewCell()
            }
            cell.configure(
                todayBlocked: manager.statisticsManager.current().todayBlocked,
                todayPageLoads: manager.statisticsManager.current().todayPageLoads,
                ruleCount: service.ruleCount,
                filterCount: manager.filterManager.enabledSourceKeys().count
            )
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

/// 顶部拦截统计卡片：2×2 数据块。
private final class ContentBlockStatsCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockStatsCardCell"

    private let gridStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
        selectionStyle = .none

        gridStack.axis = .vertical
        gridStack.spacing = 10
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridStack)
        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            gridStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            gridStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            gridStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        todayBlocked: Int,
        todayPageLoads: Int,
        ruleCount: Int,
        filterCount: Int
    ) {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let top = makeRow(
            (("shield.lefthalf.filled", "今日拦截", "\(todayBlocked)", .systemRed),
             ("globe", "今日访问", "\(todayPageLoads)", .systemBlue))
        )
        let bottom = makeRow(
            (("list.bullet", "当前规则", "\(ruleCount)", .systemGreen),
             ("checkmark.circle", "过滤器", "\(filterCount)", .systemOrange))
        )
        gridStack.addArrangedSubview(top)
        gridStack.addArrangedSubview(bottom)
    }

    private func makeRow(
        _ items: ((String, String, String, UIColor), (String, String, String, UIColor))
    ) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.addArrangedSubview(makeTile(items.0))
        row.addArrangedSubview(makeTile(items.1))
        return row
    }

    private func makeTile(
        _ item: (symbol: String, title: String, value: String, color: UIColor)
    ) -> UIView {
        let tile = UIView()
        tile.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08)
                : UIColor(white: 0.5, alpha: 0.1)
        }
        tile.layer.cornerRadius = AppRadius.control
        tile.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: item.symbol))
        iconView.tintColor = item.color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.text = item.value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6

        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = AppColors.secondaryText
        titleLabel.text = item.title
        titleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [iconView, valueLabel, titleLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            tile.heightAnchor.constraint(greaterThanOrEqualToConstant: 78)
        ])
        return tile
    }
}
