import UIKit

final class SettingsViewController: BaseViewController {
    fileprivate static var appVersion: String {
        if let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String {
            return version
        }
        return "0.4.0"
    }

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
    var onRoute: ((AppRoute) -> Void)?
    var onClearBrowsingData: (() -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            tableView.reloadData()
        }
    }
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
                Row(title: "外观", subtitle: "\(AppearancePreference.current.displayName)", symbol: "circle.lefthalf.filled", destination: .appearance)
            ]
        ),
        Section(
            title: "隐私与安全",
            footer: "网站权限始终由用户明确决定；应用不会绕过 HTTPS 证书验证。",
            rows: [
                Row(title: "内容拦截", subtitle: "规则与网站白名单", symbol: "shield.lefthalf.filled", destination: .contentBlocking),
                Row(title: "网站权限", subtitle: "摄像头、麦克风与位置", symbol: "hand.raised", destination: .websitePermissions),
                Row(title: "清除浏览数据", subtitle: "Cookie、网站数据与缓存", symbol: "trash", destination: .clearBrowsingData)
            ]
        ),
        Section(
            title: "下载与存储",
            footer: nil,
            rows: [
                Row(title: "下载设置", subtitle: "网络、并发与保存位置", symbol: "arrow.down.circle", destination: .downloadPreferences),
                Row(title: "存储空间", subtitle: "文件与缓存占用", symbol: "internaldrive", destination: .storage)
            ]
        ),
        Section(
            title: "关于",
            footer: "嗅探浏览器仅用于访问和管理用户有权获取的资源。",
            rows: [
                Row(title: "隐私政策", subtitle: "了解数据处理方式", symbol: "lock.shield", destination: .privacyPolicy),
                Row(title: "使用条款", subtitle: "使用范围与责任说明", symbol: "doc.text", destination: .terms),
                Row(title: "开源许可证", subtitle: "第三方软件声明", symbol: "chevron.left.forwardslash.chevron.right", destination: .openSourceLicenses),
                Row(title: "关于嗅探浏览器", subtitle: "版本 \(Self.appVersion)", symbol: "info.circle", destination: .about)
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh appearance subtitle when returning from the detail page
        tableView.reloadData()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
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
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GlassSummaryCell.reuseIdentifier,
            for: indexPath
        ) as? GlassSummaryCell else {
            return UITableViewCell()
        }
        let row = sections[indexPath.section].rows[indexPath.row]
        let isClearAction = row.destination == .clearBrowsingData
        let isEnabled = !isClearAction || onClearBrowsingData != nil
        let subtitle: String?
        switch row.destination {
        case .searchEngine:
            subtitle = BrowserPreferences().searchEngine.displayName
        case .appearance:
            subtitle = "\(AppearancePreference.current.displayName) · \(AppThemeColor.current.displayName)"
        default:
            subtitle = row.subtitle
        }
        let tint = tintColor(for: row.destination)
        cell.configure(
            title: row.title,
            subtitle: subtitle,
            symbol: row.symbol,
            tint: tint,
            titleColor: isClearAction ? AppColors.danger : AppColors.primaryText,
            isEnabled: isEnabled
        )
        return cell
    }

    private func tintColor(for destination: Destination) -> UIColor {
        switch destination {
        case .searchEngine, .newTabBehavior, .appearance:
            return AppColors.accent
        case .contentBlocking, .websitePermissions:
            return AppColors.accent
        case .clearBrowsingData:
            return AppColors.danger
        case .downloadPreferences, .storage:
            return AppColors.accent
        case .privacyPolicy, .terms, .openSourceLicenses, .about:
            return AppColors.secondaryText
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let destination = sections[indexPath.section].rows[indexPath.row].destination
        if destination == .clearBrowsingData {
            guard onClearBrowsingData != nil else { return }
            confirmClearBrowsingData()
            return
        }
        if destination == .appearance {
            let vc = AppearanceSettingsViewController()
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        if destination == .downloadPreferences {
            if let onRoute {
                onRoute(.downloadSettings)
            } else {
                navigationController?.pushViewController(
                    DownloadSettingsViewController(),
                    animated: true
                )
            }
            return
        }
        switch destination {
        case .searchEngine:
            navigationController?.pushViewController(
                SearchEngineSettingsViewController(),
                animated: true
            )
            return
        case .newTabBehavior:
            navigationController?.pushViewController(
                NewTabSettingsViewController(),
                animated: true
            )
            return
        case .websitePermissions:
            navigationController?.pushViewController(
                WebsitePermissionsViewController(),
                animated: true
            )
            return
        case .contentBlocking:
            navigationController?.pushViewController(
                ContentBlockingSettingsViewController(),
                animated: true
            )
            return
        case .privacyPolicy:
            pushStaticContent(
                title: "隐私政策",
                segments: SettingsLegalContent.privacyPolicy()
            )
            return
        case .terms:
            pushStaticContent(
                title: "使用条款",
                segments: SettingsLegalContent.terms()
            )
            return
        case .openSourceLicenses:
            pushStaticContent(
                title: "开源许可证",
                segments: SettingsLegalContent.openSourceLicenses()
            )
            return
        case .about:
            pushStaticContent(
                title: "关于嗅探浏览器",
                segments: SettingsLegalContent.about()
            )
            return
        default:
            break
        }
        if let onSelectDestination {
            onSelectDestination(destination)
        } else {
            guard let detail = SettingsDetailViewController(
                destination: destination
            ) else {
                return
            }
            navigationController?.pushViewController(detail, animated: true)
        }
    }

    private func pushStaticContent(
        title: String,
        segments: [StaticContentSegment]
    ) {
        navigationController?.pushViewController(
            StaticContentViewController(title: title, segments: segments),
            animated: true
        )
    }

    private func confirmClearBrowsingData() {
        let alert = UIAlertController(
            title: "清除浏览数据？",
            message: "Cookie、网站存储与网页缓存将被清除，当前网页会重新载入。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.onClearBrowsingData?()
        })
        present(alert, animated: true)
    }

    func showBrowsingDataClearCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let alert = UIAlertController(
            title: "浏览数据已清除",
            message: "Cookie、网站存储与网页缓存已移除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

private final class SettingsDetailViewController: BaseViewController {
    private let stateConfiguration: EmptyStateView.Configuration

    init?(destination: SettingsViewController.Destination) {
        guard let content = Self.content(for: destination) else {
            return nil
        }
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
    ) -> (title: String, symbol: String, message: String)? {
        switch destination {
        case .searchEngine, .newTabBehavior, .websitePermissions, .contentBlocking,
             .privacyPolicy, .terms, .openSourceLicenses, .about:
            return nil
        case .appearance:
            return ("外观", "circle.lefthalf.filled", "设置应用外观模式：跟随系统、浅色或深色。")
        case .clearBrowsingData:
            return ("清除浏览数据", "trash", "此操作会清除 Cookie、网站存储与网页缓存，并重新载入当前网页。")
        case .downloadPreferences:
            return nil
        case .storage:
            return ("存储空间", "internaldrive", "文件资料库接入后，此处将显示下载、缓存和缩略图占用。")
        }
    }
}

/// 设置与用户中心共用的轻量玻璃摘要行。
///
/// 数据与操作状态由页面注入；该视图只负责一致的视觉、动态字体和辅助功能。
final class GlassSummaryCell: UITableViewCell {
    static let reuseIdentifier = "GlassSummaryCell"

    private let materialView = AppMaterialView(
        style: .systemMaterial,
        fallbackColor: AppColors.chromeFallback
    )
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private let labelsStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String?,
        symbol: String,
        tint: UIColor = AppColors.accent,
        titleColor: UIColor = AppColors.primaryText,
        isEnabled: Bool = true
    ) {
        titleLabel.text = title
        titleLabel.textColor = titleColor
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        iconView.tintColor = tint
        iconContainer.backgroundColor = tint.withAlphaComponent(0.12)

        isUserInteractionEnabled = isEnabled
        contentView.alpha = isEnabled ? 1 : 0.46
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: "，")
        accessibilityTraits = isEnabled ? [.button] : [.button, .notEnabled]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
        contentView.alpha = 1
        isUserInteractionEnabled = true
        accessibilityTraits = [.button]
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        guard isUserInteractionEnabled else { return }
        let updates = {
            self.materialView.alpha = highlighted ? 0.72 : 1
            self.contentView.transform = highlighted
                ? CGAffineTransform(scaleX: 0.992, y: 0.992)
                : .identity
        }
        if animated {
            AppAppearance.animate(duration: AppAppearance.quickAnimationDuration, animations: updates)
        } else {
            updates()
        }
    }

    private func configureView() {
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none
        isAccessibilityElement = true

        materialView.layer.cornerRadius = AppRadius.control
        materialView.layer.cornerCurve = .continuous
        materialView.layer.borderWidth = AppMetrics.separatorHeight
        materialView.layer.borderColor = AppColors.separator.cgColor
        materialView.clipsToBounds = true
        materialView.contentView.backgroundColor = AppColors.surface.withAlphaComponent(0.90)
        materialView.isUserInteractionEnabled = false
        materialView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(materialView)
        contentView.sendSubviewToBack(materialView)

        iconContainer.layer.cornerRadius = AppRadius.small
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconContainer)

        iconView.contentMode = .center
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .medium)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 0

        AppTypography.configure(subtitleLabel, style: .caption1)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 0

        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = AppSpacing.xxs
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.addArrangedSubview(titleLabel)
        labelsStack.addArrangedSubview(subtitleLabel)
        contentView.addSubview(labelsStack)

        chevronView.tintColor = AppColors.tertiaryText
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.isAccessibilityElement = false
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            materialView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

            iconContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            labelsStack.topAnchor.constraint(
                greaterThanOrEqualTo: contentView.topAnchor,
                constant: AppSpacing.sm
            ),
            labelsStack.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            labelsStack.trailingAnchor.constraint(
                equalTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sm
            ),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -AppSpacing.sm
            ),

            chevronView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }
}
