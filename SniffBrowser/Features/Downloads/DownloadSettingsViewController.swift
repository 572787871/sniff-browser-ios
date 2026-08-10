import UIKit
import UserNotifications

@MainActor
protocol DownloadNotificationAuthorizing: AnyObject {
    func requestAuthorization() async throws -> Bool
}

@MainActor
final class SystemDownloadNotificationAuthorizer: DownloadNotificationAuthorizing {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }
}

@MainActor
final class DownloadSettingsViewModel {
    var onStateChange: ((DownloadSettingsState) -> Void)?

    private let preferences: DownloadPreferences
    private let notificationAuthorizer: DownloadNotificationAuthorizing

    private(set) var state: DownloadSettingsState
    private var notificationRequestRevision = 0

    init(
        preferences: DownloadPreferences,
        notificationAuthorizer: DownloadNotificationAuthorizing
    ) {
        self.preferences = preferences
        self.notificationAuthorizer = notificationAuthorizer
        state = preferences.state
    }

    convenience init() {
        self.init(
            preferences: DownloadPreferences(),
            notificationAuthorizer: SystemDownloadNotificationAuthorizer()
        )
    }

    func setAllowsCellularDownloads(_ enabled: Bool) {
        preferences.allowsCellularDownloads = enabled
        publishState()
    }

    func setMaximumConcurrentDownloads(_ count: Int) {
        preferences.maximumConcurrentDownloads = count
        publishState()
    }

    @discardableResult
    func setCompletionNotificationsEnabled(_ enabled: Bool) async throws -> Bool {
        notificationRequestRevision += 1
        let revision = notificationRequestRevision

        guard enabled else {
            preferences.completionNotificationsEnabled = false
            publishState()
            return false
        }

        let accepted = try await notificationAuthorizer.requestAuthorization()
        try Task.checkCancellation()
        guard revision == notificationRequestRevision else {
            throw CancellationError()
        }

        preferences.completionNotificationsEnabled = accepted
        publishState()
        return accepted
    }

    func setAutomaticRetryEnabled(_ enabled: Bool) {
        preferences.automaticRetryEnabled = enabled
        publishState()
    }

    private func publishState() {
        state = preferences.state
        onStateChange?(state)
    }
}

@MainActor
final class DownloadSettingsViewController: BaseViewController {
    private enum Row: Int {
        case cellular
        case concurrency
        case completionNotification
        case saveLocation
        case automaticRetry
    }

    private struct Section {
        let title: String
        let footer: String?
        let rows: [Row]
    }

    private let viewModel: DownloadSettingsViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var notificationAuthorizationTask: Task<Void, Never>?

    private let sections: [Section] = [
        Section(
            title: "网络",
            footer: "关闭后，下载策略只允许在非蜂窝网络下开始新任务。",
            rows: [.cellular]
        ),
        Section(
            title: "任务",
            footer: "并发上限和自动重试会持久保存，供下载服务在调度任务时读取。",
            rows: [.concurrency, .automaticRetry]
        ),
        Section(
            title: "通知",
            footer: "开启时会请求系统通知权限；关闭此开关不会更改系统设置中的授权。",
            rows: [.completionNotification]
        ),
        Section(
            title: "保存位置",
            footer: "下载文件保存在 App 沙盒中，可从“文件”页面统一管理。",
            rows: [.saveLocation]
        )
    ]

    init(viewModel: DownloadSettingsViewModel) {
        self.viewModel = viewModel
        super.init(title: "下载设置", prefersLargeTitle: false)
    }

    convenience init() {
        self.init(viewModel: DownloadSettingsViewModel())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        bindViewModel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || isBeingDismissed else { return }
        notificationAuthorizationTask?.cancel()
        notificationAuthorizationTask = nil
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
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

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] _ in
            self?.tableView.reloadData()
        }
        tableView.reloadData()
    }

    private func showNotificationAuthorizationError(
        title: String,
        message: String
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension DownloadSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
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
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .cellular:
            return toggleCell(
                tableView: tableView,
                identifier: "downloadSettings.cellular",
                title: "允许蜂窝网络下载",
                subtitle: "使用移动数据开始和继续下载",
                symbol: "antenna.radiowaves.left.and.right",
                isOn: viewModel.state.allowsCellularDownloads
            ) { [weak self] enabled in
                self?.viewModel.setAllowsCellularDownloads(enabled)
            }
        case .concurrency:
            let identifier = "downloadSettings.concurrency"
            let cell = dequeueStepperCell(tableView, identifier: identifier)
            cell.configure(
                title: "最大并发下载数量",
                subtitle: "同时执行的下载任务上限",
                symbol: "arrow.down.to.line.compact",
                value: viewModel.state.maximumConcurrentDownloads,
                range: DownloadPreferences.concurrentDownloadRange,
                accessibilityIdentifier: identifier
            ) { [weak self] value in
                self?.viewModel.setMaximumConcurrentDownloads(value)
            }
            return cell
        case .completionNotification:
            return toggleCell(
                tableView: tableView,
                identifier: "downloadSettings.completionNotification",
                title: "下载完成通知",
                subtitle: "任务完成后由系统发送提醒",
                symbol: "bell.badge",
                isOn: viewModel.state.completionNotificationsEnabled
            ) { [weak self] enabled in
                guard let self else { return }
                self.notificationAuthorizationTask?.cancel()
                self.notificationAuthorizationTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let accepted = try await self.viewModel
                            .setCompletionNotificationsEnabled(enabled)
                        if enabled && !accepted {
                            self.showNotificationAuthorizationError(
                                title: "通知未开启",
                                message: "系统未授予通知权限，下载完成通知仍保持关闭。"
                            )
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        self.tableView.reloadData()
                        self.showNotificationAuthorizationError(
                            title: "无法开启通知",
                            message: "系统通知权限请求失败，请稍后重试。"
                        )
                    }
                }
            }
        case .automaticRetry:
            return toggleCell(
                tableView: tableView,
                identifier: "downloadSettings.automaticRetry",
                title: "自动重试",
                subtitle: "网络恢复后允许失败任务自动重试",
                symbol: "arrow.clockwise",
                isOn: viewModel.state.automaticRetryEnabled
            ) { [weak self] enabled in
                self?.viewModel.setAutomaticRetryEnabled(enabled)
            }
        case .saveLocation:
            let identifier = "downloadSettings.saveLocation"
            let cell = dequeueInfoCell(tableView, identifier: identifier)
            cell.configure(
                title: "默认保存位置",
                subtitle: viewModel.state.defaultSaveLocationDescription,
                symbol: "folder",
                accessibilityIdentifier: identifier
            )
            return cell
        }
    }

    private func toggleCell(
        tableView: UITableView,
        identifier: String,
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> UITableViewCell {
        let cell: DownloadSettingToggleCell
        if let reused = tableView.dequeueReusableCell(withIdentifier: identifier)
            as? DownloadSettingToggleCell {
            cell = reused
        } else {
            cell = DownloadSettingToggleCell(reuseIdentifier: identifier)
        }
        cell.configure(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            isOn: isOn,
            accessibilityIdentifier: identifier,
            onChange: onChange
        )
        return cell
    }

    private func dequeueStepperCell(
        _ tableView: UITableView,
        identifier: String
    ) -> DownloadSettingStepperCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            as? DownloadSettingStepperCell {
            return cell
        }
        return DownloadSettingStepperCell(reuseIdentifier: identifier)
    }

    private func dequeueInfoCell(
        _ tableView: UITableView,
        identifier: String
    ) -> DownloadSettingInfoCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            as? DownloadSettingInfoCell {
            return cell
        }
        return DownloadSettingInfoCell(reuseIdentifier: identifier)
    }
}

private final class DownloadSettingToggleCell: UITableViewCell {
    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    init(reuseIdentifier: String) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        configureBackground()
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        accessoryView = toggle
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Bool,
        accessibilityIdentifier: String,
        onChange: @escaping (Bool) -> Void
    ) {
        self.onChange = onChange
        toggle.setOn(isOn, animated: false)
        toggle.accessibilityIdentifier = "\(accessibilityIdentifier).switch"

        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = title
        configuration.secondaryText = subtitle
        configuration.image = UIImage(systemName: symbol)
        configuration.imageProperties.tintColor = AppColors.accent
        configuration.textProperties.color = AppColors.primaryText
        configuration.secondaryTextProperties.color = AppColors.secondaryText
        contentConfiguration = configuration

        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = title
        accessibilityValue = isOn ? "已开启" : "已关闭"
    }

    private func configureBackground() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
    }

    @objc private func toggleChanged() {
        accessibilityValue = toggle.isOn ? "已开启" : "已关闭"
        onChange?(toggle.isOn)
    }
}

private final class DownloadSettingStepperCell: UITableViewCell {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let valueLabel = UILabel()
    private let stepper = UIStepper()
    private let controlStack = UIStackView()
    private var onChange: ((Int) -> Void)?

    init(reuseIdentifier: String) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        configureBackground()

        iconContainer.backgroundColor = AppColors.accentFill
        iconContainer.layer.cornerRadius = AppRadius.control
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconContainer)

        iconView.tintColor = AppColors.accent
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .regular
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .regular)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(
            .defaultHigh,
            for: .horizontal
        )

        AppTypography.configure(subtitleLabel, style: .caption1)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.distribution = .fill
        textStack.spacing = AppSpacing.xxs
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        AppTypography.configure(valueLabel, style: .headline, weight: .semibold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.textAlignment = .center
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        stepper.stepValue = 1
        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        stepper.setContentHuggingPriority(.required, for: .horizontal)
        stepper.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        controlStack.axis = .horizontal
        controlStack.alignment = .center
        controlStack.distribution = .fill
        controlStack.spacing = AppSpacing.xs
        controlStack.addArrangedSubview(valueLabel)
        controlStack.addArrangedSubview(stepper)
        controlStack.setContentHuggingPriority(.required, for: .horizontal)
        controlStack.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlStack)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.topAnchor.constraint(
                greaterThanOrEqualTo: contentView.topAnchor,
                constant: AppSpacing.md
            ),
            iconContainer.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -AppSpacing.md
            ),
            iconContainer.widthAnchor.constraint(equalToConstant: 44),
            iconContainer.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 23),
            iconView.heightAnchor.constraint(equalToConstant: 23),

            textStack.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            textStack.topAnchor.constraint(
                greaterThanOrEqualTo: contentView.topAnchor,
                constant: AppSpacing.xs
            ),
            textStack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -AppSpacing.xs
            ),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            controlStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: textStack.trailingAnchor,
                constant: AppSpacing.xs
            ),
            controlStack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            controlStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String,
        symbol: String,
        value: Int,
        range: ClosedRange<Int>,
        accessibilityIdentifier: String,
        onChange: @escaping (Int) -> Void
    ) {
        self.onChange = onChange
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        stepper.minimumValue = Double(range.lowerBound)
        stepper.maximumValue = Double(range.upperBound)
        stepper.value = Double(value)
        stepper.accessibilityIdentifier = "\(accessibilityIdentifier).stepper"
        valueLabel.text = "\(value)"

        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = title
        accessibilityValue = "\(value)"
    }

    private func configureBackground() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
    }

    @objc private func stepperChanged() {
        let value = Int(stepper.value)
        valueLabel.text = "\(value)"
        accessibilityValue = "\(value)"
        onChange?(value)
    }
}

private final class DownloadSettingInfoCell: UITableViewCell {
    init(reuseIdentifier: String) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        configureBackground()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String,
        symbol: String,
        accessibilityIdentifier: String
    ) {
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = title
        configuration.secondaryText = subtitle
        configuration.image = UIImage(systemName: symbol)
        configuration.imageProperties.tintColor = AppColors.accent
        configuration.textProperties.color = AppColors.primaryText
        configuration.secondaryTextProperties.color = AppColors.secondaryText
        contentConfiguration = configuration

        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = "\(title)，\(subtitle)"
    }

    private func configureBackground() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
    }
}
