import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 内容拦截控制台。规则编译、导入和白名单仍使用原有服务，仅将旧的
/// UITableView 统计方块重组为一条清晰的“状态 → 趋势 → 规则”信息流。
final class ContentBlockingSettingsViewController: BaseViewController {
    private let manager = ContentBlockManager.shared
    private let dashboardStore = ContentBlockingDashboardStore()
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
        installSwiftUI(
            ContentBlockingDashboardView(
                store: dashboardStore,
                onImport: { [weak self] in self?.showImportMenu() },
                onWhitelist: { [weak self] in self?.openWhitelist() },
                onRebuild: { [weak self] in self?.rebuildRules() }
            ),
            in: contentView
        )
        observeChanges()
        ContentBlockerService.shared.loadIfNeeded()
        dashboardStore.reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dashboardStore.reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }

    private func observeChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .contentBlockerDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dashboardStore.reload()
            }
        }
    }

    private func openWhitelist() {
        navigationController?.pushViewController(
            WhitelistViewController(),
            animated: true
        )
    }

    private func rebuildRules() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await dashboardStore.rebuildRules()
                presentAlert(
                    title: "规则已重新编译",
                    message: "新的规则已经应用到浏览器页面。"
                )
            } catch {
                presentAlert(
                    title: "重新编译失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - 规则导入

    private func showImportMenu() {
        let alert = UIAlertController(
            title: "导入规则",
            message: "支持 AdBlock 文本规则与 JSON 规则文件。",
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
                      let url = URL(
                        string: text.trimmingCharacters(in: .whitespacesAndNewlines)
                      )
                else { return }
                self?.importFromURL(url)
            }
        )
        present(alert, animated: true)
    }

    private func importFromURL(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 60
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode)
                else {
                    throw URLError(.badServerResponse)
                }
                finishImport(data: data, fileExtension: url.pathExtension)
            } catch {
                presentAlert(
                    title: "导入失败",
                    message: "无法下载规则，请检查链接与网络。"
                )
            }
        }
    }

    private func finishImport(data: Data, fileExtension: String) {
        let imported: Int
        if fileExtension.lowercased() == "json" {
            imported = manager.customManager.importJSON(data)
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            imported = manager.customManager.importLines(
                text.components(separatedBy: .newlines)
            )
        }
        guard imported > 0 else {
            presentAlert(title: "导入失败", message: "没有识别到有效规则。")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await ContentBlockerService.shared.rebuildRules(
                    reloadPages: true
                )
                dashboardStore.reload()
                presentAlert(
                    title: "导入成功",
                    message: "已导入并应用 \(imported) 条规则。"
                )
            } catch {
                dashboardStore.reload()
                presentAlert(
                    title: "已导入，暂未应用",
                    message: "规则已保存，但本次编译失败：\(error.localizedDescription)"
                )
            }
        }
    }

    private func presentAlert(title: String, message: String?) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
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
        finishImport(data: data, fileExtension: url.pathExtension)
    }
}

extension ContentBlockingSettingsViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        navigationController?.viewControllers.count ?? 0 > 1
    }
}

@MainActor
private final class ContentBlockingDashboardStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isReady = false
    @Published private(set) var isRebuilding = false
    @Published private(set) var statusDetail = "正在准备规则"
    @Published private(set) var blockedCount = 0
    @Published private(set) var pageLoadCount = 0
    @Published private(set) var ruleCount = 0
    @Published private(set) var filterCount = 0
    @Published private(set) var customRuleCount = 0
    @Published private(set) var whitelistCount = 0
    @Published private(set) var blockedSeries: [Double] = []
    @Published private(set) var pageLoadSeries: [Double] = []
    @Published private(set) var selectedRange: StatisticsRange = .today

    private let manager = ContentBlockManager.shared
    private let service = ContentBlockerService.shared

    func reload() {
        isEnabled = service.isEnabled
        isReady = service.isReady
        statusDetail = service.lastLoadError
            ?? (service.isReady ? service.updateDescription : "正在准备过滤规则")
        customRuleCount = manager.customManager.allRules().count
        whitelistCount = manager.whitelistManager.allPatterns().count
        updateStatistics()
    }

    func setEnabled(_ enabled: Bool) {
        service.setEnabled(enabled)
        reload()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectRange(_ range: StatisticsRange) {
        guard selectedRange != range else { return }
        selectedRange = range
        updateStatistics()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func rebuildRules() async throws {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer {
            isRebuilding = false
            reload()
        }
        try await service.rebuildRules(reloadPages: true)
    }

    private func updateStatistics() {
        let statistics = manager.statisticsManager
        let summary = statistics.summary(for: selectedRange)
        blockedCount = summary.todayBlocked
        pageLoadCount = summary.todayPageLoads
        ruleCount = summary.ruleCount
        filterCount = summary.filterCount
        blockedSeries = statistics.sparkline(
            for: selectedRange,
            kind: .blocked
        )
        pageLoadSeries = statistics.sparkline(
            for: selectedRange,
            kind: .pageLoads
        )
    }
}

private struct ContentBlockingDashboardView: View {
    @ObservedObject var store: ContentBlockingDashboardStore
    let onImport: () -> Void
    let onWhitelist: () -> Void
    let onRebuild: () -> Void

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    protectionHeader
                    activitySection
                    rulesSection
                    privacyFooter
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
    }

    private var protectionHeader: some View {
        AppSwiftUISectionCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            store.isEnabled
                                ? AppSwiftUIColors.success.opacity(0.14)
                                : AppSwiftUIColors.tertiarySurface.opacity(0.55)
                        )
                    Circle()
                        .stroke(
                            store.isEnabled
                                ? AppSwiftUIColors.success.opacity(0.34)
                                : AppSwiftUIColors.separator,
                            lineWidth: 1
                        )
                    Image(systemName: store.isEnabled
                        ? "shield.checkered"
                        : "shield.slash")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(store.isEnabled
                            ? AppSwiftUIColors.success
                            : AppSwiftUIColors.secondaryText)
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(store.isEnabled ? "保护已开启" : "保护已暂停")
                            .font(.title3.weight(.bold))
                        Circle()
                            .fill(store.isReady
                                ? AppSwiftUIColors.success
                                : AppSwiftUIColors.tertiaryText)
                            .frame(width: 7, height: 7)
                    }
                    Text(store.statusDetail)
                        .font(.caption)
                        .foregroundStyle(AppSwiftUIColors.secondaryText)
                        .lineLimit(3)
                }
                Spacer(minLength: 6)
                Toggle(
                    "内容拦截",
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .accessibilityIdentifier("contentBlocking.master")
            }
            .padding(16)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "拦截活动", detail: store.selectedRange.rawValue)
            AppSwiftUISectionCard {
                VStack(alignment: .leading, spacing: 18) {
                    rangeSelector

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formatted(store.blockedCount))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(store.selectedRange.metricTitle(for: .blocked))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppSwiftUIColors.secondaryText)
                    }

                    ContentBlockingTrendView(
                        primary: store.blockedSeries,
                        secondary: store.pageLoadSeries
                    )
                    .frame(height: 96)

                    HStack(spacing: 0) {
                        metric(
                            title: store.selectedRange.metricTitle(for: .pageLoads),
                            value: store.pageLoadCount,
                            symbol: "globe"
                        )
                        metric(
                            title: "生效规则",
                            value: store.ruleCount,
                            symbol: "list.bullet.rectangle"
                        )
                        metric(
                            title: "规则组",
                            value: store.filterCount,
                            symbol: "square.stack.3d.up"
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 4) {
            ForEach(StatisticsRange.allCases, id: \.rawValue) { range in
                Button {
                    store.selectRange(range)
                } label: {
                    Text(range.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(range == store.selectedRange
                            ? AppSwiftUIColors.accentContent
                            : AppSwiftUIColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            range == store.selectedRange
                                ? AppSwiftUIColors.accent
                                : Color.clear,
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            AppSwiftUIColors.secondarySurface.opacity(0.66),
            in: Capsule(style: .continuous)
        )
    }

    private func metric(
        title: String,
        value: Int,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .lineLimit(1)
            Text(formatted(value))
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppSwiftUIColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "规则与例外")
            AppSwiftUISectionCard {
                AppSwiftUIActionRow(
                    title: "导入自定义规则",
                    subtitle: "从 txt、JSON 文件或网络链接添加",
                    systemName: "square.and.arrow.down",
                    detail: store.customRuleCount == 0
                        ? nil
                        : "\(store.customRuleCount) 条"
                ) {
                    onImport()
                }
                AppSwiftUIDivider()
                AppSwiftUIActionRow(
                    title: "网站白名单",
                    subtitle: "这些网站不会应用拦截规则",
                    systemName: "checkmark.shield",
                    detail: store.whitelistCount == 0
                        ? "暂无"
                        : "\(store.whitelistCount) 个"
                ) {
                    onWhitelist()
                }
                AppSwiftUIDivider()
                AppSwiftUIActionRow(
                    title: store.isRebuilding ? "正在重新编译" : "重新编译规则",
                    subtitle: "应用当前规则源、自定义规则与白名单",
                    systemName: store.isRebuilding
                        ? "arrow.triangle.2.circlepath"
                        : "hammer",
                    isEnabled: !store.isRebuilding,
                    showsChevron: false
                ) {
                    onRebuild()
                }
            }
        }
    }

    private var privacyFooter: some View {
        Label {
            Text("过滤由 WebKit 在设备上执行；浏览记录和规则匹配结果不会上传。")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(AppSwiftUIColors.tertiaryText)
        .padding(.horizontal, 6)
    }

    private func formatted(_ value: Int) -> String {
        NumberFormatter.localizedString(
            from: NSNumber(value: value),
            number: .decimal
        )
    }
}

private struct ContentBlockingTrendView: View {
    let primary: [Double]
    let secondary: [Double]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Spacer()
                        AppSwiftUIColors.separator.opacity(0.55)
                            .frame(height: 0.5)
                    }
                }
                ContentBlockingTrendShape(values: secondary)
                    .stroke(
                        AppSwiftUIColors.tertiaryText.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                ContentBlockingTrendShape(values: primary)
                    .stroke(
                        AppSwiftUIColors.accent,
                        style: StrokeStyle(
                            lineWidth: 2.6,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("拦截趋势")
    }
}

private struct ContentBlockingTrendShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = max(1, maximum - minimum)
        let denominator = max(1, values.count - 1)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.minX
                + rect.width * CGFloat(index) / CGFloat(denominator)
            let normalized = CGFloat((value - minimum) / range)
            let y = rect.maxY - normalized * rect.height * 0.82 - rect.height * 0.09
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
