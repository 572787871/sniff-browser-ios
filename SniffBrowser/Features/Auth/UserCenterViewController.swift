import UIKit

final class UserCenterViewController: BaseViewController {
    enum Destination {
        case login
        case sync
        case downloads
        case files
        case favorites
        case history
        case privacy
        case about
    }

    var onSelectDestination: ((Destination) -> Void)?
    var onLogin: (() -> Void)?

    private var session: AuthSession?
    private var counts: UserCenterCounts
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let profileHeader = UserProfileHeaderView()

    init(
        session: AuthSession? = nil,
        counts: UserCenterCounts = UserCenterCounts()
    ) {
        self.session = session
        self.counts = counts
        super.init(title: "用户中心", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        profileHeader.configure(session: session, counts: counts)
        configureTable()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayout()
    }

    func update(session: AuthSession?) {
        self.session = session
        guard isViewLoaded else { return }
        profileHeader.update(session: session)
        tableView.reloadData()
        updateHeaderLayout()
    }

    func update(counts: UserCenterCounts) {
        self.counts = counts
        guard isViewLoaded else { return }
        profileHeader.update(counts: counts)
    }

    private func configureTable() {
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

        let initialWidth = max(view.bounds.width, 1)
        profileHeader.frame = CGRect(
            x: 0,
            y: 0,
            width: initialWidth,
            height: profileHeader.fittingHeight(forWidth: initialWidth)
        )
        profileHeader.onPrimaryAction = { [weak self] in
            guard let self else { return }
            self.route(to: self.session == nil ? .login : .sync)
        }
        profileHeader.onSelectSummary = { [weak self] destination in
            self?.route(to: destination)
        }
        tableView.tableHeaderView = profileHeader

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateHeaderLayout() {
        guard tableView.bounds.width > 0 else { return }
        let targetWidth = tableView.bounds.width
        if abs(profileHeader.frame.width - targetWidth) > 0.5 {
            profileHeader.frame.size.width = targetWidth
        }
        let fittingHeight = profileHeader.fittingHeight(forWidth: targetWidth)
        guard abs(profileHeader.frame.height - fittingHeight) > 0.5 else {
            return
        }
        profileHeader.frame.size.height = fittingHeight
        tableView.tableHeaderView = profileHeader
    }

    private func route(to destination: Destination) {
        if destination == .login, let onLogin {
            onLogin()
            return
        }
        if destination == .sync, session == nil {
            route(to: .login)
            return
        }
        if let onSelectDestination {
            onSelectDestination(destination)
            return
        }

        let viewController: UIViewController?
        switch destination {
        case .login:
            viewController = LoginViewController()
        case .sync:
            viewController = nil
        case .downloads:
            viewController = DownloadManagerViewController()
        case .files:
            viewController = FileManagerViewController()
        case .favorites:
            viewController = FavoritesViewController()
        case .history:
            viewController = HistoryViewController()
        case .privacy, .about:
            viewController = SettingsViewController()
        }

        if let viewController {
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}

extension UserCenterViewController: UITableViewDataSource, UITableViewDelegate {
    private struct Row {
        let title: String
        let subtitle: String?
        let symbol: String
        let destination: Destination
    }

    private struct Section {
        let title: String
        let rows: [Row]
    }

    private var sections: [Section] {
        [
            Section(title: "账户与应用", rows: [
                Row(
                    title: "数据同步",
                    subtitle: session == nil ? "登录后可用" : "同步浏览数据",
                    symbol: "arrow.triangle.2.circlepath",
                    destination: .sync
                ),
                Row(title: "隐私与安全", subtitle: "网站权限与浏览数据", symbol: "hand.raised", destination: .privacy),
                Row(title: "关于嗅探浏览器", subtitle: "版本与许可信息", symbol: "info.circle", destination: .about)
            ])
        ]
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
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
        cell.configure(
            title: row.title,
            subtitle: row.subtitle,
            symbol: row.symbol
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        route(to: sections[indexPath.section].rows[indexPath.row].destination)
    }
}

private final class UserProfileHeaderView: UIView {
    var onPrimaryAction: (() -> Void)?
    var onSelectSummary: ((UserCenterViewController.Destination) -> Void)?

    private let cardView = AppMaterialView(
        style: .systemMaterial,
        fallbackColor: AppColors.chromeFallback
    )
    private let avatarContainer = UIView()
    private let avatarView = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let summaryStack = UIStackView()
    private let downloadSummary = UserSummaryCard(
        title: "下载",
        value: 0,
        symbol: "arrow.down.circle"
    )
    private let fileSummary = UserSummaryCard(
        title: "文件",
        value: 0,
        symbol: "folder"
    )
    private let favoriteSummary = UserSummaryCard(
        title: "收藏",
        value: 0,
        symbol: "star"
    )
    private let historySummary = UserSummaryCard(
        title: "历史",
        value: 0,
        symbol: "clock"
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(session: AuthSession?, counts: UserCenterCounts) {
        update(session: session)
        update(counts: counts)
    }

    func update(session: AuthSession?) {
        if let session {
            titleLabel.text = session.user.displayName
                ?? session.user.email
                ?? "已登录用户"
            subtitleLabel.text = session.user.email ?? "账户数据已连接"
            actionButton.configuration?.title = "同步设置"
            actionButton.accessibilityLabel = "打开数据同步设置"
        } else {
            titleLabel.text = "游客模式"
            subtitleLabel.text = "无需登录即可使用浏览器；登录后可同步个人数据。"
            actionButton.configuration?.title = "登录或注册"
            actionButton.accessibilityLabel = "登录或注册"
        }
    }

    func update(counts: UserCenterCounts) {
        downloadSummary.setValue(counts.downloads)
        fileSummary.setValue(counts.files)
        favoriteSummary.setValue(counts.favorites)
        historySummary.setValue(counts.history)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        frame.size = CGSize(width: width, height: max(frame.height, 260))
        setNeedsLayout()
        layoutIfNeeded()
        let fittingSize = systemLayoutSizeFitting(
            CGSize(
                width: width,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return max(260, ceil(fittingSize.height))
    }

    private func configureView() {
        backgroundColor = .clear

        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = AppMetrics.separatorHeight
        cardView.layer.borderColor = AppColors.separator.cgColor
        cardView.clipsToBounds = true
        cardView.contentView.backgroundColor = AppColors.surface.withAlphaComponent(0.90)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        avatarContainer.backgroundColor = AppColors.accentFill
        avatarContainer.layer.cornerRadius = AppRadius.control
        avatarContainer.layer.cornerCurve = .continuous
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false

        avatarView.tintColor = AppColors.accent
        avatarView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 27)
        avatarView.contentMode = .center
        avatarView.isAccessibilityElement = false
        avatarView.accessibilityIdentifier = "userCenter.avatar"
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarView)
        avatarView.setContentHuggingPriority(.required, for: .horizontal)

        AppTypography.configure(titleLabel, style: .title2, weight: .semibold)
        titleLabel.numberOfLines = 0

        AppTypography.configure(subtitleLabel, style: .subheadline)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = AppSpacing.xxs

        var buttonConfiguration = UIButton.Configuration.tinted()
        buttonConfiguration.cornerStyle = .medium
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sm,
            leading: AppSpacing.lg,
            bottom: AppSpacing.sm,
            trailing: AppSpacing.lg
        )
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = AppTypography.headline
            return attributes
        }
        actionButton.configuration = buttonConfiguration
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        actionButton.isAccessibilityElement = true
        actionButton.accessibilityIdentifier = "userCenter.primaryAction"
        actionButton.accessibilityHint = "打开登录和账户页面"

        let identityRow = UIStackView(arrangedSubviews: [avatarContainer, labels])
        identityRow.axis = .horizontal
        identityRow.alignment = .center
        identityRow.spacing = AppSpacing.sm

        summaryStack.axis = .horizontal
        summaryStack.alignment = .fill
        summaryStack.distribution = .fillEqually
        summaryStack.spacing = AppSpacing.xs
        let summaries: [
            (
                card: UserSummaryCard,
                destination: UserCenterViewController.Destination,
                accessibilityIdentifier: String
            )
        ] = [
            (downloadSummary, .downloads, "userCenter.summary.downloads"),
            (fileSummary, .files, "userCenter.summary.files"),
            (favoriteSummary, .favorites, "userCenter.summary.favorites"),
            (historySummary, .history, "userCenter.summary.history")
        ]
        summaries.forEach { summary in
            summary.card.accessibilityIdentifier = summary.accessibilityIdentifier
            summary.card.addAction(
                UIAction { [weak self] _ in
                    self?.onSelectSummary?(summary.destination)
                },
                for: .touchUpInside
            )
            summaryStack.addArrangedSubview(summary.card)
        }

        let stack = UIStackView(
            arrangedSubviews: [identityRow, actionButton, summaryStack]
        )
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sm),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.md),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.md),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sm),

            avatarContainer.widthAnchor.constraint(equalToConstant: 52),
            avatarContainer.heightAnchor.constraint(equalTo: avatarContainer.widthAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),

            stack.topAnchor.constraint(
                equalTo: cardView.contentView.topAnchor,
                constant: AppSpacing.md
            ),
            stack.leadingAnchor.constraint(
                equalTo: cardView.contentView.leadingAnchor,
                constant: AppSpacing.md
            ),
            stack.trailingAnchor.constraint(
                equalTo: cardView.contentView.trailingAnchor,
                constant: -AppSpacing.md
            ),
            stack.bottomAnchor.constraint(
                equalTo: cardView.contentView.bottomAnchor,
                constant: -AppSpacing.md
            ),
            actionButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            ),
            summaryStack.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 76
            )
        ])
    }

    @objc private func actionPressed() {
        onPrimaryAction?()
    }
}

private final class UserSummaryCard: UIControl {
    private let iconView = UIImageView()
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    init(title: String, value: Int, symbol: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        valueLabel.text = "\(max(0, value))"
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func setValue(_ value: Int) {
        valueLabel.text = "\(max(0, value))"
        accessibilityLabel = "\(titleLabel.text ?? "")，\(valueLabel.text ?? "0")"
    }

    override var isHighlighted: Bool {
        didSet {
            let updates = {
                self.alpha = self.isHighlighted ? 0.62 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                    : .identity
            }
            AppAppearance.animate(
                duration: AppAppearance.quickAnimationDuration,
                animations: updates
            )
        }
    }

    private func configureView() {
        backgroundColor = AppColors.tertiarySurface
        layer.cornerRadius = AppRadius.control
        layer.cornerCurve = .continuous
        layer.borderWidth = AppMetrics.separatorHeight
        layer.borderColor = AppColors.separator.cgColor
        isAccessibilityElement = true
        accessibilityLabel = "\(titleLabel.text ?? "")，\(valueLabel.text ?? "0")"
        accessibilityTraits = .button

        iconView.tintColor = AppColors.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        AppTypography.configure(valueLabel, style: .headline, weight: .semibold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.textAlignment = .center

        AppTypography.configure(titleLabel, style: .caption1)
        titleLabel.textColor = AppColors.secondaryText
        titleLabel.textAlignment = .center

        let stack = UIStackView(
            arrangedSubviews: [iconView, valueLabel, titleLabel]
        )
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.xxs
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                greaterThanOrEqualTo: topAnchor,
                constant: AppSpacing.xs
            ),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: AppSpacing.xxs
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -AppSpacing.xxs
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor,
                constant: -AppSpacing.xs
            ),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])
    }
}
