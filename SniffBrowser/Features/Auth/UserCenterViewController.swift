import UIKit

final class UserCenterViewController: BaseViewController {
    enum Destination {
        case login
        case downloads
        case files
        case favorites
        case history
        case settings
        case privacy
        case about
    }

    var onSelectDestination: ((Destination) -> Void)?
    var onLogin: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var session: AuthSession?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let profileHeader = UserProfileHeaderView()

    init(session: AuthSession? = nil) {
        self.session = session
        super.init(title: "用户中心", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTable()
        updateProfile()
    }

    func update(session: AuthSession?) {
        self.session = session
        guard isViewLoaded else { return }
        updateProfile()
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UserCenterCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        profileHeader.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 164)
        profileHeader.onPrimaryAction = { [weak self] in
            self?.route(to: .login)
        }
        tableView.tableHeaderView = profileHeader

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateProfile() {
        profileHeader.configure(session: session)
        tableView.reloadData()
    }

    private func route(to destination: Destination) {
        if destination == .login, let onLogin {
            onLogin()
            return
        }
        if destination == .settings, let onOpenSettings {
            onOpenSettings()
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
        case .downloads:
            viewController = DownloadManagerViewController()
        case .files:
            viewController = FileManagerViewController()
        case .favorites:
            viewController = FavoritesViewController()
        case .history:
            viewController = HistoryViewController()
        case .settings:
            viewController = SettingsViewController()
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

    private var sections: [[Row]] {
        [
            [
                Row(title: "下载管理", subtitle: "查看下载任务", symbol: "arrow.down.circle", destination: .downloads),
                Row(title: "文件管理", subtitle: "管理已保存的文件", symbol: "folder", destination: .files)
            ],
            [
                Row(title: "收藏夹", subtitle: nil, symbol: "star", destination: .favorites),
                Row(title: "历史记录", subtitle: nil, symbol: "clock.arrow.circlepath", destination: .history)
            ],
            [
                Row(title: "浏览器设置", subtitle: nil, symbol: "gearshape", destination: .settings),
                Row(title: "隐私与安全", subtitle: nil, symbol: "hand.raised", destination: .privacy),
                Row(title: "关于嗅探浏览器", subtitle: nil, symbol: "info.circle", destination: .about)
            ]
        ]
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCenterCell", for: indexPath)
        let row = sections[indexPath.section][indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.title
        configuration.secondaryText = row.subtitle
        configuration.image = UIImage(systemName: row.symbol)
        configuration.imageProperties.tintColor = AppColors.accent
        configuration.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        configuration.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .caption1)
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = AppColors.surface
        cell.accessibilityLabel = [row.title, row.subtitle].compactMap { $0 }.joined(separator: "，")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        route(to: sections[indexPath.section][indexPath.row].destination)
    }
}

private final class UserProfileHeaderView: UIView {
    var onPrimaryAction: (() -> Void)?

    private let cardView = UIView()
    private let avatarView = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(session: AuthSession?) {
        if let session {
            titleLabel.text = session.user.displayName
                ?? session.user.email
                ?? "已登录用户"
            subtitleLabel.text = session.user.email ?? "账户数据已连接"
            actionButton.setTitle("账户", for: .normal)
        } else {
            titleLabel.text = "游客模式"
            subtitleLabel.text = "无需登录即可使用浏览器；登录后可同步个人数据。"
            actionButton.setTitle("登录或注册", for: .normal)
        }
    }

    private func configureView() {
        backgroundColor = .clear

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        avatarView.tintColor = AppColors.accent
        avatarView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46)
        avatarView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 2

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 4

        var buttonConfiguration = UIButton.Configuration.tinted()
        buttonConfiguration.cornerStyle = .medium
        actionButton.configuration = buttonConfiguration
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        actionButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        actionButton.accessibilityHint = "打开登录和账户页面"

        let stack = UIStackView(arrangedSubviews: [avatarView, labels, actionButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),

            actionButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            )
        ])
    }

    @objc private func actionPressed() {
        onPrimaryAction?()
    }
}
