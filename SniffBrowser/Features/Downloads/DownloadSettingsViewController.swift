import Combine
import SwiftUI
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
    static let policyAccessibilityIdentifiers: Set<String> = [
        "downloadSettings.cellular",
        "downloadSettings.concurrency",
        "downloadSettings.automaticRetry",
        "downloadSettings.completionNotification",
        "downloadSettings.saveLocation"
    ]

    private let store: DownloadSettingsSwiftUIStore

    init(viewModel: DownloadSettingsViewModel) {
        store = DownloadSettingsSwiftUIStore(viewModel: viewModel)
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
        installSwiftUI(DownloadSettingsSwiftUIScreen(store: store), in: contentView)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || isBeingDismissed else { return }
        store.cancelPendingAuthorization()
    }
}

@MainActor
private final class DownloadSettingsSwiftUIStore: ObservableObject {
    @Published private(set) var state: DownloadSettingsState
    @Published var alert: AlertMessage?

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private let viewModel: DownloadSettingsViewModel
    private var notificationTask: Task<Void, Never>?

    init(viewModel: DownloadSettingsViewModel) {
        self.viewModel = viewModel
        state = viewModel.state
        viewModel.onStateChange = { [weak self] state in
            self?.state = state
        }
    }

    func setCellular(_ enabled: Bool) {
        viewModel.setAllowsCellularDownloads(enabled)
    }

    func setConcurrency(_ value: Int) {
        viewModel.setMaximumConcurrentDownloads(value)
    }

    func setAutomaticRetry(_ enabled: Bool) {
        viewModel.setAutomaticRetryEnabled(enabled)
    }

    func setNotifications(_ enabled: Bool) {
        notificationTask?.cancel()
        notificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let accepted = try await viewModel
                    .setCompletionNotificationsEnabled(enabled)
                if enabled && !accepted {
                    alert = AlertMessage(
                        title: "通知未开启",
                        message: "系统未授予通知权限，下载完成通知仍保持关闭。"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                state = viewModel.state
                alert = AlertMessage(
                    title: "无法开启通知",
                    message: "系统通知权限请求失败，请稍后重试。"
                )
            }
        }
    }

    func cancelPendingAuthorization() {
        notificationTask?.cancel()
        notificationTask = nil
    }
}

private struct DownloadSettingsSwiftUIScreen: View {
    @ObservedObject var store: DownloadSettingsSwiftUIStore

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                LazyVStack(spacing: 22) {
                    toggleSection(
                        title: "网络",
                        footer: "关闭后，下载策略只允许在非蜂窝网络下开始新任务。",
                        titleText: "允许蜂窝网络下载",
                        subtitle: "使用移动数据开始和继续下载",
                        symbol: "antenna.radiowaves.left.and.right",
                        identifier: "downloadSettings.cellular",
                        isOn: Binding(
                            get: { store.state.allowsCellularDownloads },
                            set: store.setCellular
                        )
                    )

                    taskSection

                    toggleSection(
                        title: "通知",
                        footer: "开启时会请求系统通知权限；关闭不会更改系统设置中的授权。",
                        titleText: "下载完成通知",
                        subtitle: "任务完成后由系统发送提醒",
                        symbol: "bell.badge",
                        identifier: "downloadSettings.completionNotification",
                        isOn: Binding(
                            get: { store.state.completionNotificationsEnabled },
                            set: store.setNotifications
                        )
                    )

                    saveLocationSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "任务")
            AppSwiftUISectionCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("最大并发下载数量")
                            .font(.body.weight(.medium))
                        Text("同时执行的下载任务上限")
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                    }
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { store.state.maximumConcurrentDownloads },
                            set: store.setConcurrency
                        ),
                        in: DownloadPreferences.concurrentDownloadRange
                    ) {
                        Text("\(store.state.maximumConcurrentDownloads)")
                            .font(.headline.monospacedDigit())
                            .frame(minWidth: 22)
                    }
                    .labelsHidden()
                    Text("\(store.state.maximumConcurrentDownloads)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityIdentifier("downloadSettings.concurrency")

                AppSwiftUIDivider()

                toggleRow(
                    title: "自动重试",
                    subtitle: "网络恢复后允许失败任务自动重试",
                    symbol: "arrow.clockwise",
                    identifier: "downloadSettings.automaticRetry",
                    isOn: Binding(
                        get: { store.state.automaticRetryEnabled },
                        set: store.setAutomaticRetry
                    )
                )
            }
            Text("并发上限和自动重试会持久保存，供下载服务调度任务时读取。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private var saveLocationSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "保存位置")
            AppSwiftUISectionCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("默认保存位置")
                            .font(.body.weight(.medium))
                        Text(store.state.defaultSaveLocationDescription)
                            .font(.caption)
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityIdentifier("downloadSettings.saveLocation")
            }
            Text("下载文件保存在 App 沙盒中，可从“文件”页面统一管理。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func toggleSection(
        title: String,
        footer: String,
        titleText: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: title)
            AppSwiftUISectionCard {
                toggleRow(
                    title: titleText,
                    subtitle: subtitle,
                    symbol: symbol,
                    identifier: identifier,
                    isOn: isOn
                )
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
