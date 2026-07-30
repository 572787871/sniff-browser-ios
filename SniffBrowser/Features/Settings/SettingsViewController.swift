import UIKit

final class SettingsViewController: BaseViewController {
    enum Destination {
        case searchEngine
        case newTabBehavior
        case appearance
        case contentBlocking
        case websitePermissions
        case clearBrowsingData
        case downloadPreferences
        case storage
        case privacyPolicy
        case terms
        case openSourceLicenses
        case about
    }

    var onSelectDestination: ((Destination) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private struct Row {
        let title: String
        let subtitle: String?
        let symbol: String
        let destination: Destination
    }

    private struct Section {
        let title: String
        let footer: String?
        let rows: [Row]
    }

    private lazy var sections: [Section] = [
        Section(
            title: "浏览",
            footer: nil,
            rows: [
                Row(title: "默认搜索引擎", subtitle: "Google", symbol: "magnifyingglass", destination: .searchEngine),
                Row(title: "新标签页", subtitle: "嗅探浏览器首页", symbol: "plus.square.on.square", destination: .newTabBehavior),
                Row(title: "外观", subtitle: "跟随系统", symbol: "circle.lefthalf.filled", destination: .appearance)
            ]
        ),
        Section(
            title: "隐私与安全",
            footer: "网站权限始终由用户明确决定；应用不会绕过 HTTPS 证书验证。",
            rows: [
                Row(title: "内容拦截", subtitle: nil, symbol: "shield.lefthalf.filled", destination: .contentBlocking),
                Row(title: "网站权限", subtitle: nil, symbol: "hand.raised", destination: .websitePermissions),
                Row(title: "清除浏览数据", subtitle: nil, symbol: "trash", destination: .clearBrowsingData)
            ]
        ),
        Section(
            title: "下载与存储",
            footer: nil,
            rows: [
                Row(title: "下载设置", subtitle: nil, symbol: "arrow.down.circle", destination: .downloadPreferences),
                Row(title: "存储空间", subtitle: nil, symbol: "internaldrive", destination: .storage)
            ]
        ),
        Section(
            title: "关于",
            footer: "嗅探浏览器仅用于访问和管理用户有权获取的资源。",
            rows: [
                Row(title: "隐私政策", subtitle: nil, symbol: "lock.shield", destination: .privacyPolicy),
                Row(title: "使用条款", subtitle: nil, symbol: "doc.text", destination: .terms),
                Row(title: "开源许可证", subtitle: nil, symbol: "chevron.left.forwardslash.chevron.right", destination: .openSourceLicenses),
                Row(title: "关于嗅探浏览器", subtitle: nil, symbol: "info.circle", destination: .about)
            ]
        )
    ]

    init() {
        super.init(title: "设置", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
    }

    private func configureTableView() {
        tableView.backgroundColor = AppColors.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
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

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        sections[section].title
    }

    func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        sections[section].footer
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.title
        configuration.secondaryText = row.subtitle
        configuration.image = UIImage(systemName: row.symbol)
        configuration.imageProperties.tintColor = row.destination == .clearBrowsingData
            ? AppColors.danger
            : AppColors.accent
        configuration.textProperties.color = row.destination == .clearBrowsingData
            ? AppColors.danger
            : AppColors.primaryText
        configuration.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        configuration.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .subheadline)
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = AppColors.surface
        cell.accessibilityLabel = [row.title, row.subtitle].compactMap { $0 }.joined(separator: "，")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let destination = sections[indexPath.section].rows[indexPath.row].destination
        if let onSelectDestination {
            onSelectDestination(destination)
        } else {
            navigationController?.pushViewController(
                SettingsDetailViewController(destination: destination),
                animated: true
            )
        }
    }
}

private final class SettingsDetailViewController: BaseViewController {
    private let stateConfiguration: EmptyStateView.Configuration

    init(destination: SettingsViewController.Destination) {
        let content = Self.content(for: destination)
        stateConfiguration = .init(
            symbolName: content.symbol,
            title: content.title,
            message: content.message
        )
        super.init(title: content.title, prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showStateView(EmptyStateView(configuration: stateConfiguration))
    }

    private static func content(
        for destination: SettingsViewController.Destination
    ) -> (title: String, symbol: String, message: String) {
        switch destination {
        case .searchEngine:
            return ("默认搜索引擎", "magnifyingglass", "当前默认使用 Google；后续版本将在此提供搜索引擎选择。")
        case .newTabBehavior:
            return ("新标签页", "plus.square.on.square", "新标签页当前使用本地原生页面，不加载新闻、广告或推荐内容。")
        case .appearance:
            return ("外观", "circle.lefthalf.filled", "当前自动跟随系统深色或浅色外观，并响应辅助功能设置。")
        case .contentBlocking:
            return ("内容拦截", "shield.lefthalf.filled", "内容过滤引擎将在隐私阶段接入；当前不会注入来源不明的规则。")
        case .websitePermissions:
            return ("网站权限", "hand.raised", "敏感权限将始终由系统询问，不会静默授权。")
        case .clearBrowsingData:
            return ("清除浏览数据", "trash", "建立历史与网站数据存储后，此处将提供按范围清理与二次确认。")
        case .downloadPreferences:
            return ("下载设置", "arrow.down.circle", "后台下载模块接入后，此处将管理并发、网络与保存位置。")
        case .storage:
            return ("存储空间", "internaldrive", "文件资料库接入后，此处将显示下载、缓存和缩略图占用。")
        case .privacyPolicy:
            return ("隐私政策", "lock.shield", "正式发布前将在此提供完整、可访问的隐私政策。")
        case .terms:
            return ("使用条款", "doc.text", "正式发布前将在此提供完整的使用条款。")
        case .openSourceLicenses:
            return ("开源许可证", "chevron.left.forwardslash.chevron.right", "当前版本未引入第三方运行时依赖。")
        case .about:
            return ("关于嗅探浏览器", "info.circle", "原生 Swift + UIKit 浏览器，当前版本 0.1.0。")
        }
    }
}
