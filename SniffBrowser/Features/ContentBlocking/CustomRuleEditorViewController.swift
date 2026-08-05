import UIKit

/// 自定义规则编辑器：规则类型、内容输入（语法高亮）、实时校验与模板。
final class CustomRuleEditorViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let manager = ContentBlockManager.shared
    private let editingRule: CustomRule?

    private var selectedType: CustomRuleType
    private var content: String
    private var validationMessage = ""

    init(rule: CustomRule?) {
        editingRule = rule
        selectedType = rule?.type ?? .block
        content = rule?.content ?? ""
        super.init(title: rule == nil ? "添加规则" : "编辑规则", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        configureTableView()
        validate()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
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

    private func validate() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedType.isSystemBlockable {
            validationMessage =
                "此类型无法通过系统内容拦截器生效，可保存但不会应用。建议改用元素隐藏规则。"
        } else if trimmed.isEmpty {
            validationMessage = "请输入规则内容"
        } else {
            switch selectedType {
            case .block, .allow, .whitelist:
                validationMessage = isDomainRuleValid(trimmed)
                    ? "语法正确"
                    : "示例：||example.com^ 或 @@||example.com^"
            case .elementHide:
                validationMessage = trimmed.hasPrefix("##")
                    ? "语法正确"
                    : "示例：##.ad-banner 或 example.com##.ad-banner"
            default:
                validationMessage = ""
            }
        }
    }

    private func isDomainRuleValid(_ text: String) -> Bool {
        let candidates = [text, text.hasPrefix("@@") ? String(text.dropFirst(2)) : text]
        return candidates.contains { candidate in
            let trimmed = candidate
                .replacingOccurrences(of: "||", with: "")
                .replacingOccurrences(of: "^", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.range(
                of: "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$",
                options: [.regularExpression, .caseInsensitive]
            ) != nil && trimmed.contains(".")
        }
    }

    @objc private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentAlert(title: "规则内容不能为空")
            return
        }
        let now = Date()
        if var existing = editingRule {
            existing.name = trimmed
            existing.content = trimmed
            existing.type = selectedType
            existing.updatedAt = now
            manager.customManager.updateRule(existing)
        } else {
            manager.customManager.addRule(
                CustomRule(
                    name: trimmed,
                    content: trimmed,
                    type: selectedType,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        Task {
            try? await ContentBlockerService.shared.rebuildRules(reloadPages: true)
        }
        navigationController?.popViewController(animated: true)
    }

    @objc private func cancel() {
        navigationController?.popViewController(animated: true)
    }

    private func presentAlert(title: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension CustomRuleEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? CustomRuleType.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "规则类型"
        case 1: return "规则内容"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 ? validationMessage : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsCheckmarkCell.reuseIdentifier,
                for: indexPath
            ) as? SettingsCheckmarkCell else {
                return UITableViewCell()
            }
            let type = CustomRuleType.allCases[indexPath.row]
            cell.configure(
                title: type.displayName,
                symbol: type.isSystemBlockable ? "checkmark.circle" : "exclamationmark.triangle",
                isSelected: type == selectedType
            )
            return cell
        }
        if indexPath.section == 1 {
            let cell = RuleEditorCell()
            cell.configure(content: content) { [weak self] newValue in
                self?.content = newValue
                self?.validate()
                self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
            }
            return cell
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = "插入模板"
        configuration.image = UIImage(systemName: "text.badge.plus")
        configuration.imageProperties.tintColor = AppColors.accent
        cell.contentConfiguration = configuration
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            selectedType = CustomRuleType.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
            validate()
            tableView.reloadSections(IndexSet(integer: 2), with: .none)
        } else if indexPath.section == 2 {
            presentTemplateMenu()
        }
    }

    private func presentTemplateMenu() {
        let templates: [(String, String)] = [
            ("隐藏横幅广告", "##.banner-ad"),
            ("拦截广告域名", "||ads.example.com^"),
            ("允许网站", "@@||example.com^"),
            ("隐藏站内推广", "hl365.com##.article-top-banner"),
        ]
        let alert = UIAlertController(
            title: "插入模板",
            message: nil,
            preferredStyle: .actionSheet
        )
        for (name, template) in templates {
            alert.addAction(
                UIAlertAction(title: name, style: .default) { [weak self] _ in
                    self?.content = template
                    self?.tableView.reloadSections(IndexSet(integer: 1), with: .none)
                    self?.validate()
                    self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
                }
            )
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

/// 带语法高亮与实时回调的内容编辑单元。
private final class RuleEditorCell: UITableViewCell {
    static let reuseIdentifier = "RuleEditorCell"

    private let textView = UITextView()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
        selectionStyle = .none

        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(
            top: 10,
            left: 8,
            bottom: 10,
            right: 8
        )
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(content: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        textView.text = content
        highlight()
    }

    @objc private func textDidChange() {
        highlight()
        onChange?(textView.text)
    }

    private func highlight() {
        let attributed = NSMutableAttributedString(
            string: textView.text,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: AppColors.primaryText,
            ]
        )
        let fullRange = NSRange(location: 0, length: (textView.text as NSString).length)
        for match in Self.keywordRegex.matches(
            in: textView.text,
            options: [],
            range: fullRange
        ) {
            attributed.addAttribute(
                .foregroundColor,
                value: AppColors.accent,
                range: match.range
            )
        }
        textView.attributedText = attributed
    }

    private static let keywordRegex = try! NSRegularExpression(
        pattern: "^(\\|\\||@@\\|\\||##|#@#)|\\^",
        options: [.anchorsMatchLines]
    )
}
