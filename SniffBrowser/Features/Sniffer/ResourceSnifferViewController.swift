import SwiftUI
import UIKit

final class ResourceSnifferViewController: BaseViewController {
    var onReturnToPage: (() -> Void)?
    var onShowDownloads: (() -> Void)?

    private struct RenderedResourceRow: Equatable {
        let id: UUID
        let canonicalURL: URL
        let originalURLString: String
        let fileName: String
        let fileExtension: String?
        let mimeType: String?
        let resourceType: ResourceType
        let estimatedSize: Int64?
        let duration: Double?
        let width: Int?
        let height: Int?
        let bitrate: Int?
        let thumbnailURL: URL?
        let isPotentiallyDownloadable: Bool

        init(_ resource: DetectedResource) {
            id = resource.id
            canonicalURL = resource.canonicalURL
            originalURLString = resource.originalURLString
            fileName = resource.fileName
            fileExtension = resource.fileExtension
            mimeType = resource.mimeType
            resourceType = resource.resourceType
            estimatedSize = resource.estimatedSize
            duration = resource.duration
            width = resource.width
            height = resource.height
            bitrate = resource.bitrate
            thumbnailURL = resource.thumbnailURL
            isPotentiallyDownloadable = resource.isPotentiallyDownloadable
        }
    }

    private struct RenderedContent: Equatable {
        let pageTitle: String
        let pageURL: URL?
        let isPrivate: Bool
        let scanState: ResourceScanState
        let errorMessage: String?
        let activationState: SniffingActivationState
        let hasStarted: Bool
        let selectedFilter: ResourceSnifferFilter
        let selectedSortOrder: ResourceSnifferSortOrder
        let filterCounts: [Int]
        let rows: [RenderedResourceRow]
    }

    private let viewModel: ResourceSnifferViewModel
    private var resources: [DetectedResource] = []
    private var selectedFilter: ResourceSnifferFilter
    private var selectedSortOrder: ResourceSnifferSortOrder
    private var scanTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var scanState: ResourceScanState = .idle
    private var activationState: SniffingActivationState = .disabled
    private var hasStarted = false
    private var renderedRows: [RenderedResourceRow] = []
    private var renderedContent: RenderedContent?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var chromeHost = UIHostingController(
        rootView: makeChromeView(state: viewModel.state)
    )
    private lazy var emptyStateHost = UIHostingController(
        rootView: makeEmptyStateView(state: viewModel.state)
    )
    init(
        viewModel: ResourceSnifferViewModel
    ) {
        self.viewModel = viewModel
        let presentationState = viewModel.presentationState
        selectedFilter = presentationState.selectedFilter
        selectedSortOrder = presentationState.selectedSortOrder
        super.init(title: "资源嗅探", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureNavigation()
        configureChrome()
        configureTable()
        configureEmptyState()
        bindViewModel()
        viewModel.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed
            || navigationController?.isBeingDismissed == true
            || isMovingFromParent
        else {
            return
        }
        scanTask?.cancel()
        downloadTask?.cancel()
        playbackTask?.cancel()
        viewModel.stop()
        if isBeingDismissed
            || navigationController?.isBeingDismissed == true
            || isMovingFromParent {
            scanTask = Task { [weak viewModel] in
                await viewModel?.disable()
            }
        }
    }

    private var filteredResources: [DetectedResource] {
        // A stopped scan keeps its results visible. A brand-new page has no
        // visible resources until the user has explicitly started scanning.
        guard activationState.isEnabled || hasStarted else { return [] }
        let filtered = resources.filter {
            selectedFilter.includes($0.resourceType)
        }
        return sorted(filtered)
    }

    private func sorted(
        _ resources: [DetectedResource]
    ) -> [DetectedResource] {
        resources.sorted { lhs, rhs in
            if lhs.resourceType == .hls, rhs.resourceType == .hls,
               lhs.detectionSource.confidence != rhs.detectionSource.confidence {
                // Player-declared/current streams must reach the visible rows
                // (and therefore thumbnail extraction) before large pre-roll
                // playlists reported by Performance APIs.
                return lhs.detectionSource.confidence
                    > rhs.detectionSource.confidence
            }
            switch selectedSortOrder {
            case .newest:
                break
            case .type:
                if lhs.resourceType.sortPriority != rhs.resourceType.sortPriority {
                    return lhs.resourceType.sortPriority
                        < rhs.resourceType.sortPriority
                }
            case .size:
                let left = lhs.estimatedSize ?? -1
                let right = rhs.estimatedSize ?? -1
                if left != right { return left > right }
            case .resolution:
                let left = Int64(lhs.width ?? 0) * Int64(lhs.height ?? 0)
                let right = Int64(rhs.width ?? 0) * Int64(rhs.height ?? 0)
                if left != right { return left > right }
            }
            if lhs.detectedAt != rhs.detectedAt {
                return lhs.detectedAt > rhs.detectedAt
            }
            return lhs.canonicalURL.absoluteString
                < rhs.canonicalURL.absoluteString
        }
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            guard let self else { return }
            self.resources = state.resources
            self.scanState = state.scanState
            self.activationState = state.activationState
            self.hasStarted = state.hasStarted
            self.updateContent(state: state)
        }
    }

    private func configureNavigation() {
        let titleView = ResourceSnifferNavigationTitleView()
        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem = makeCloseItem()
        navigationItem.rightBarButtonItem = makeManagementItem()
        titleView.configure(
            status: statusTitle,
            style: statusStyle,
            accessibilityValue: statusTitle
        )
    }

    private var statusTitle: String {
        switch activationState {
        case .starting: return "正在启动"
        case .active: return scanState == .failed ? "检测失败" : "嗅探中"
        case .stopping: return "正在停止"
        case .failed: return "启动失败"
        case .disabled: return hasStarted ? "已停止" : "未开始"
        }
    }

    private var statusStyle: ResourceSnifferChromeConfiguration.StatusStyle {
        switch activationState {
        case .starting, .stopping:
            return .working
        case .active:
            return scanState == .failed ? .failed : .active
        case .failed:
            return .failed
        case .disabled:
            return .stopped
        }
    }

    private func configureAppearance() {
        view.backgroundColor = ResourceSnifferPalette.background
        contentView.backgroundColor = ResourceSnifferPalette.background

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ResourceSnifferPalette.background
        appearance.shadowColor = ResourceSnifferPalette.border
        appearance.titleTextAttributes = [
            .foregroundColor: ResourceSnifferPalette.primaryText,
            .font: AppTypography.headline
        ]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = ResourceSnifferPalette.accent
    }

    private func configureChrome() {
        addChild(chromeHost)
        chromeHost.sizingOptions = [.intrinsicContentSize]
        chromeHost.view.backgroundColor = .clear
        chromeHost.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chromeHost.view)
        chromeHost.didMove(toParent: self)

        NSLayoutConstraint.activate([
            chromeHost.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            chromeHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func makeChromeView(
        state: ResourceSnifferViewModel.State
    ) -> ResourceSnifferChromeView {
        ResourceSnifferChromeView(
            configuration: ResourceSnifferChromeConfiguration(
                state: state,
                selectedFilter: selectedFilter,
                selectedSortOrder: selectedSortOrder
            ),
            onPrimaryAction: { [weak self] in
                self?.primarySniffingAction()
            },
            onSelectFilter: { [weak self] filter in
                self?.selectFilter(filter)
            },
            onSelectSortOrder: { [weak self] order in
                self?.selectSortOrder(order)
            }
        )
    }

    private func makeEmptyStateView(
        state: ResourceSnifferViewModel.State
    ) -> ResourceSnifferEmptyStateView {
        ResourceSnifferEmptyStateView(
            configuration: ResourceSnifferEmptyConfiguration(state: state),
            onAction: { [weak self] in self?.refreshResources() },
            onSecondaryAction: { [weak self] in self?.onReturnToPage?() }
        )
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 118
        tableView.register(
            ResourceListCell.self,
            forCellReuseIdentifier: ResourceListCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: chromeHost.view.bottomAnchor,
                constant: AppSpacing.xs
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        addChild(emptyStateHost)
        emptyStateHost.view.backgroundColor = .clear
        emptyStateHost.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyStateHost.view)
        emptyStateHost.didMove(toParent: self)
        NSLayoutConstraint.activate([
            emptyStateHost.view.topAnchor.constraint(
                equalTo: chromeHost.view.bottomAnchor,
                constant: AppSpacing.xs
            ),
            emptyStateHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateHost.view.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            )
        ])
    }

    private func updateContent(state: ResourceSnifferViewModel.State) {
        let nextRows = filteredResources.map(RenderedResourceRow.init)
        let canShowResults = state.hasStarted || state.activationState.isEnabled
        let previouslyAllowedMediaFrameExtraction = renderedContent.map {
            $0.activationState == .active && $0.scanState == .completed
        } ?? false
        let allowsMediaFrameExtraction = state.activationState == .active
            && state.scanState == .completed
        let nextContent = RenderedContent(
            pageTitle: state.pageTitle,
            pageURL: state.pageURL,
            isPrivate: state.isPrivate,
            scanState: state.scanState,
            errorMessage: state.errorMessage,
            activationState: state.activationState,
            hasStarted: state.hasStarted,
            selectedFilter: selectedFilter,
            selectedSortOrder: selectedSortOrder,
            filterCounts: ResourceSnifferFilter.allCases.map { filter in
                (canShowResults ? resources : []).lazy.filter {
                    filter.includes($0.resourceType)
                }.count
            },
            rows: nextRows
        )
        guard nextContent != renderedContent else { return }
        renderedContent = nextContent
        chromeHost.rootView = makeChromeView(state: state)
        if nextRows != renderedRows
            || previouslyAllowedMediaFrameExtraction != allowsMediaFrameExtraction {
            renderedRows = nextRows
            tableView.reloadData()
        }
        let isEmpty = filteredResources.isEmpty
        tableView.isHidden = isEmpty
        emptyStateHost.view.isHidden = !isEmpty
        emptyStateHost.rootView = makeEmptyStateView(state: state)
        updateNavigation()
    }

    private func updateNavigation() {
        navigationItem.rightBarButtonItem = makeManagementItem()
        (navigationItem.titleView as? ResourceSnifferNavigationTitleView)?.configure(
            status: statusTitle,
            style: statusStyle,
            accessibilityValue: statusTitle
        )
    }

    private func makeCloseItem() -> UIBarButtonItem {
        let button = makeNavigationCircleButton(
            symbolName: "xmark",
            accessibilityLabel: "关闭资源嗅探"
        )
        button.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    private func makeManagementItem() -> UIBarButtonItem {
        let stop = UIAction(
            title: "停止嗅探",
            image: UIImage(systemName: "stop.circle"),
            attributes: activationState.isEnabled ? [] : [.disabled]
        ) { [weak self] _ in self?.stopSniffing() }
        let clear = UIAction(
            title: "清空结果",
            image: UIImage(systemName: "trash"),
            attributes: resources.isEmpty ? [.disabled] : [.destructive]
        ) { [weak self] _ in self?.confirmClearResults() }
        let button = makeNavigationCircleButton(
            symbolName: "ellipsis",
            accessibilityLabel: "资源管理"
        )
        button.menu = UIMenu(children: [stop, clear])
        button.showsMenuAsPrimaryAction = true
        return UIBarButtonItem(customView: button)
    }

    private func makeNavigationCircleButton(
        symbolName: String,
        accessibilityLabel: String
    ) -> UIButton {
        let button = UIButton(type: .system)
        let configuration = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .semibold
        )
        button.setImage(
            UIImage(systemName: symbolName, withConfiguration: configuration),
            for: .normal
        )
        button.tintColor = ResourceSnifferPalette.primaryText
        button.backgroundColor = ResourceSnifferPalette.secondarySurface
            .withAlphaComponent(0.72)
        button.layer.cornerRadius = AppMetrics.minimumTapSize / 2
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            button.heightAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            )
        ])
        return button
    }

    private func primarySniffingAction() {
        if activationState.isEnabled {
            stopSniffing()
        } else {
            startSniffing()
        }
    }

    private func refreshResources() {
        guard scanState != .scanning, scanState != .installing else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            do {
                guard let self else { return }
                if self.activationState.isEnabled {
                    try await self.viewModel.refresh()
                } else {
                    try await self.viewModel.activateIfNeeded()
                }
                guard !Task.isCancelled else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func startSniffing() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            do {
                try await self?.viewModel.startSniffing()
            } catch is CancellationError {
                return
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func stopSniffing() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.viewModel.disable()
        }
    }

    private func confirmClearResults() {
        let alert = UIAlertController(
            title: "清空识别结果？",
            message: "只会清空当前标签页的结果，不会删除网页或已下载文件。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) {
            [weak self] _ in self?.viewModel.clearResults()
        })
        present(alert, animated: true)
    }

    private func copy(_ resource: DetectedResource) {
        UIPasteboard.general.string = resource.originalURLString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func share(_ resource: DetectedResource) {
        let controller = UIActivityViewController(
            activityItems: [resource.canonicalURL],
            applicationActivities: nil
        )
        present(controller, animated: true)
    }

    private func requestDownload(_ resource: DetectedResource) {
        guard (resource.isPotentiallyDownloadable || resource.resourceType == .hls),
              ["http", "https"].contains(
                resource.canonicalURL.scheme?.lowercased() ?? ""
              )
        else {
            showMessage(
                title: "无法下载",
                message: resource.limitationReason ?? "此资源不支持直接下载。"
            )
            return
        }
        let beginDownload = { [weak self] in
            self?.startDownload(resource)
        }
        guard !DownloadComplianceAcknowledgement.hasAcknowledged else {
            beginDownload()
            return
        }
        let alert = UIAlertController(
            title: "下载内容合规说明",
            message: "请仅下载您拥有版权、已经获得授权或网站明确允许保存的资源。应用不支持受 DRM 保护的内容。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "我已了解", style: .default) { _ in
            DownloadComplianceAcknowledgement.hasAcknowledged = true
            beginDownload()
        })
        present(alert, animated: true)
    }

    private func startDownload(_ resource: DetectedResource) {
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.viewModel.startDownload(resource: resource)
                switch result {
                case .created:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.showDownloadCreatedMessage()
                case .alreadyDownloading:
                    self.showMessage(title: "已在下载", message: "相同资源已有进行中的任务。")
                case .fileAlreadyExists:
                    self.showMessage(title: "文件已存在", message: "相同资源已经下载完成，可前往文件库查看。")
                }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.showMessage(
                    title: "无法创建下载",
                    message: DownloadErrorMapper.message(for: error)
                )
            }
        }
    }

    private func showDownloadCreatedMessage() {
        let alert = UIAlertController(
            title: "已加入下载",
            message: "任务已进入下载队列。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "继续查看", style: .cancel))
        if onShowDownloads != nil {
            alert.addAction(UIAlertAction(title: "查看下载", style: .default) {
                [weak self] _ in self?.onShowDownloads?()
            })
        }
        present(alert, animated: true)
    }

    private func preview(_ resource: DetectedResource) {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            if resource.resourceType == .image {
                let imageURL = URL(string: resource.originalURLString)
                    ?? resource.canonicalURL
                let controller = RemoteResourceImageViewController(
                    title: resource.fileName,
                    tabID: resource.tabID,
                    request: await self.viewModel.thumbnailRequest(for: imageURL),
                    allowsDiskCache: !self.viewModel.state.isPrivate,
                    inlineDataProvider: { [weak self] in
                        guard let self else { return nil }
                        return await self.viewModel.thumbnailData(for: imageURL)
                    }
                )
                self.navigationController?.pushViewController(controller, animated: true)
                return
            }
            let context = await self.viewModel.requestContext(for: resource)
            do {
                // HLS 和普通视频都由本机回环服务带着网页 Referer、UA 与
                // 匹配 Cookie 请求。普通媒体按 Range 分块转发，既修复
                // 防盗链导致的在线播放失败，也保留系统播放器的拖动能力。
                let kind: RemoteMediaPlaybackKind = resource.resourceType == .hls
                    ? .hls
                    : .direct
                let playbackURL = try await RemoteHLSPlaybackServer.shared
                    .playbackURL(context: context, kind: kind)
                guard !Task.isCancelled else { return }
                let player = ResourceMediaPreviewViewController(
                    title: resource.fileName,
                    playbackURL: playbackURL,
                    downloadTitle: resource.resourceType == .audio
                        ? "下载音频"
                        : "下载视频",
                    onDownload: { [weak self] in
                        self?.requestDownload(resource)
                    }
                )
                self.present(player, animated: true)
            } catch {
                self.showMessage(
                    title: "无法准备播放",
                    message: "视频代理连接失败，可以重试或直接下载此资源。\n\(error.localizedDescription)"
                )
            }
        }
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func showDetails(_ resource: DetectedResource) {
        let details = [
            "类型：\(resource.resourceType.localizedTitle)",
            "格式：\(resource.fileExtension?.uppercased() ?? "未知")",
            "MIME：\(resource.mimeType ?? "未知")",
            "来源：\(resource.canonicalURL.host ?? "未知")",
            "大小：\(formattedSize(resource.estimatedSize))",
            formattedResolution(resource),
            formattedDuration(resource.duration),
            "检测来源：\(resource.detectionSource.rawValue)",
            resource.limitationReason
        ].compactMap { $0 }.joined(separator: "\n")
        let alert = UIAlertController(
            title: resource.fileName,
            message: details,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "复制链接", style: .default) {
            [weak self] _ in self?.copy(resource)
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    private func formattedSize(_ size: Int64?) -> String {
        guard let size else { return "大小未知" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formattedResolution(_ resource: DetectedResource) -> String? {
        guard let width = resource.width, let height = resource.height else {
            return nil
        }
        return "分辨率：\(width)×\(height)"
    }

    private func formattedDuration(_ duration: Double?) -> String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let totalSeconds = Int(duration.rounded())
        return String(
            format: "时长：%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    private func selectFilter(_ filter: ResourceSnifferFilter) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        savePresentationState()
        let state = viewModel.state
        updateContent(state: state)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func selectSortOrder(_ order: ResourceSnifferSortOrder) {
        guard selectedSortOrder != order else { return }
        selectedSortOrder = order
        savePresentationState()
        renderedContent = nil
        updateContent(state: viewModel.state)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func savePresentationState() {
        viewModel.updatePresentationState(
            ResourceSnifferPresentationState(
                selectedFilter: selectedFilter,
                selectedSortOrder: selectedSortOrder
            )
        )
    }

}

extension ResourceSnifferViewController: UITableViewDataSource,
    UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        filteredResources.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ResourceListCell.reuseIdentifier,
            for: indexPath
        ) as? ResourceListCell else {
            return UITableViewCell()
        }
        guard filteredResources.indices.contains(indexPath.row) else {
            // Metadata resolution can reorder HLS rows while UIKit is
            // finishing a previous data-source request. Never index a stale
            // row during those rapid incremental updates.
            return cell
        }
        let resource = filteredResources[indexPath.row]
        cell.configure(
            resource: resource,
            allowsThumbnailDiskCache: !viewModel.state.isPrivate,
            allowsMediaFrameExtraction: activationState == .active
                && scanState == .completed,
            thumbnailRequestProvider: { [weak viewModel] url in
                guard let viewModel else { return nil }
                return await viewModel.thumbnailRequest(for: url)
            },
            inlineDataProvider: { [weak viewModel] url in
                guard let viewModel else { return nil }
                return await viewModel.thumbnailData(for: url)
            },
            mediaContextProvider: { [weak viewModel] resource in
                guard let viewModel else { return nil }
                return await viewModel.requestContext(for: resource)
            },
            onCopy: { [weak self] in self?.copy(resource) },
            onShare: { [weak self] in self?.share(resource) },
            onDetails: { [weak self] in self?.showDetails(resource) },
            onPreview: [.image, .video, .audio, .hls].contains(resource.resourceType)
                ? { [weak self] in self?.preview(resource) }
                : nil,
            onDownload: (resource.isPotentiallyDownloadable || resource.resourceType == .hls)
                && ["http", "https"].contains(
                    resource.canonicalURL.scheme?.lowercased() ?? ""
                )
                ? { [weak self] in self?.requestDownload(resource) }
                : nil
        )
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        guard filteredResources.indices.contains(indexPath.row) else { return }
        let resource = filteredResources[indexPath.row]
        guard [.image, .video, .audio, .hls].contains(resource.resourceType)
        else { return }
        preview(resource)
    }
}

enum DownloadComplianceAcknowledgement {
    private static let key = "download.complianceAcknowledged"
    static var hasAcknowledged: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

private final class RemoteResourceImageViewController: BaseViewController {
    private let tabID: UUID
    private let request: URLRequest
    private let allowsDiskCache: Bool
    private let inlineDataProvider: () async -> Data?
    private let imageView = UIImageView()
    private let indicator = UIActivityIndicatorView(style: .large)
    private var token: ResourceThumbnailToken?

    init(
        title: String,
        tabID: UUID,
        request: URLRequest,
        allowsDiskCache: Bool,
        inlineDataProvider: @escaping () async -> Data? = { nil }
    ) {
        self.tabID = tabID
        self.request = request
        self.allowsDiskCache = allowsDiskCache
        self.inlineDataProvider = inlineDataProvider
        super.init(title: title, prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ResourceSnifferPalette.background
        contentView.backgroundColor = ResourceSnifferPalette.background
        indicator.color = ResourceSnifferPalette.accent
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.addSubview(indicator)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            indicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        indicator.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            let inlineData = await inlineDataProvider()
            guard !Task.isCancelled else { return }
            self.token = ResourceThumbnailLoader.shared.load(
                ResourceThumbnailRequest(
                    resourceID: UUID(),
                    tabID: self.tabID,
                    request: self.request,
                    targetPixelSize: CGSize(width: 2_400, height: 2_400),
                    allowsDiskCache: self.allowsDiskCache,
                    inlineData: inlineData
                )
            ) { [weak self] image in
                self?.indicator.stopAnimating()
                self?.imageView.image = image
                if image == nil {
                    self?.imageView.image = UIImage(
                        systemName: "photo.badge.exclamationmark"
                    )
                    self?.imageView.tintColor = ResourceSnifferPalette.secondaryText
                }
            }
        }
    }

    deinit { token?.cancel() }
}

private final class ResourceSnifferNavigationTitleView: UIView {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = AppSpacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        titleLabel.font = AppTypography.headline
        titleLabel.textColor = ResourceSnifferPalette.primaryText
        statusLabel.font = AppTypography.caption
        statusLabel.textColor = ResourceSnifferPalette.accent
        statusLabel.backgroundColor = ResourceSnifferPalette.accentFill
        statusLabel.layer.cornerRadius = 9
        statusLabel.layer.cornerCurve = .continuous
        statusLabel.clipsToBounds = true
        statusLabel.textAlignment = .center
        statusLabel.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 3, leading: 7, bottom: 3, trailing: 7
        )
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    required init?(coder: NSCoder) { return nil }

    func configure(
        status: String,
        style: ResourceSnifferChromeConfiguration.StatusStyle,
        accessibilityValue: String
    ) {
        titleLabel.text = "资源嗅探"
        statusLabel.text = "  \(status)  "
        switch style {
        case .active:
            statusLabel.textColor = ResourceSnifferPalette.accent
            statusLabel.backgroundColor = ResourceSnifferPalette.accentFill
        case .working:
            statusLabel.textColor = AppColors.warning
            statusLabel.backgroundColor = AppColors.warning.withAlphaComponent(0.14)
        case .failed:
            statusLabel.textColor = AppColors.danger
            statusLabel.backgroundColor = AppColors.danger.withAlphaComponent(0.14)
        case .stopped:
            statusLabel.textColor = ResourceSnifferPalette.secondaryText
            statusLabel.backgroundColor = ResourceSnifferPalette.secondarySurface
        }
        accessibilityLabel = "资源嗅探，\(accessibilityValue)"
    }
}

private final class ResourceImageCell: UICollectionViewCell {
    static let reuseIdentifier = "ResourceImageCell"

    private let cardView = UIView()
    private let imageView = UIImageView()
    private let formatLabel = UILabel()
    private let dimensionLabel = UILabel()
    private let sizeLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let indicator = UIActivityIndicatorView(style: .medium)
    private var token: ResourceThumbnailToken?
    private var task: Task<Void, Never>?
    private var retry: (() -> Void)?
    private var retryCount = 0
    private var onPreview: (() -> Void)?
    private var representedID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) { return nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        token?.cancel()
        token = nil
        representedID = nil
        retry = nil
        retryCount = 0
        onPreview = nil
        imageView.image = UIImage(systemName: "photo")
        retryButton.isHidden = true
        indicator.stopAnimating()
    }

    func configure(
        resource: DetectedResource,
        allowsDiskCache: Bool,
        requestProvider: @escaping @MainActor (URL) async -> URLRequest?,
        inlineDataProvider: @escaping @MainActor (URL) async -> Data?,
        onPreview: @escaping () -> Void,
        onMore: @escaping () -> Void,
        retrying: Bool = false
    ) {
        task?.cancel()
        token?.cancel()
        representedID = resource.id
        if !retrying { retryCount = 0 }
        retry = nil
        self.onPreview = onPreview
        imageView.image = UIImage(systemName: "photo")
        retryButton.isHidden = true
        indicator.startAnimating()
        formatLabel.text = ResourceImageCell.format(for: resource)
        dimensionLabel.text = resource.width.flatMap { width in
            resource.height.map { "\(width) × \($0)" }
        } ?? "分辨率未知"
        sizeLabel.text = resource.estimatedSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "大小未知"
        moreButton.menu = UIMenu(children: [
            UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = resource.originalURLString
            },
            UIAction(title: "更多操作", image: UIImage(systemName: "ellipsis")) { _ in
                onMore()
            }
        ])
        task = Task { [weak self] in
            guard let self else { return }
            let imageURL = URL(string: resource.originalURLString)
                ?? resource.canonicalURL
            let request = await requestProvider(imageURL)
                ?? URLRequest(url: imageURL)
            let inlineData = await inlineDataProvider(imageURL)
            guard !Task.isCancelled else { return }
            self.retry = { [weak self] in
                guard let self else { return }
                guard self.retryCount < 1 else { return }
                self.retryCount += 1
                self.configure(
                    resource: resource,
                    allowsDiskCache: allowsDiskCache,
                    requestProvider: requestProvider,
                    inlineDataProvider: inlineDataProvider,
                    onPreview: onPreview,
                    onMore: onMore,
                    retrying: true
                )
            }
            self.token = ResourceThumbnailLoader.shared.load(
                ResourceThumbnailRequest(
                    resourceID: resource.id,
                    tabID: resource.tabID,
                    request: request,
                    targetPixelSize: CGSize(width: 360, height: 300),
                    allowsDiskCache: allowsDiskCache,
                    inlineData: inlineData
                )
            ) { [weak self] image in
                guard let self, self.representedID == resource.id else { return }
                self.indicator.stopAnimating()
                if let image {
                    self.imageView.image = image
                    if resource.width == nil, resource.height == nil,
                       let cgImage = image.cgImage {
                        self.dimensionLabel.text = "\(cgImage.width) × \(cgImage.height)"
                    }
                    self.retryButton.isHidden = true
                } else {
                    self.imageView.image = UIImage(systemName: "photo.badge.exclamationmark")
                    self.imageView.tintColor = ResourceSnifferPalette.secondaryText
                    self.retryButton.isHidden = self.retryCount >= 1
                }
            }
        }
    }

    private func configureView() {
        backgroundColor = .clear
        cardView.backgroundColor = ResourceSnifferPalette.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = AppMetrics.separatorHeight
        cardView.layer.borderColor = ResourceSnifferPalette.border.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        imageView.backgroundColor = ResourceSnifferPalette.secondarySurface
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.tintColor = ResourceSnifferPalette.secondaryText
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(imageView)

        moreButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        moreButton.tintColor = ResourceSnifferPalette.primaryText
        moreButton.backgroundColor = ResourceSnifferPalette.surface.withAlphaComponent(0.88)
        moreButton.layer.cornerRadius = 16
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.showsMenuAsPrimaryAction = true
        cardView.addSubview(moreButton)

        retryButton.setTitle("重试", for: .normal)
        retryButton.titleLabel?.font = AppTypography.caption
        retryButton.tintColor = ResourceSnifferPalette.accent
        retryButton.backgroundColor = ResourceSnifferPalette.surface
        retryButton.layer.cornerRadius = AppRadius.control
        retryButton.isHidden = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        cardView.addSubview(retryButton)

        indicator.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(indicator)

        [formatLabel, dimensionLabel, sizeLabel].forEach {
            $0.font = AppTypography.caption
            $0.textColor = ResourceSnifferPalette.secondaryText
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 1
        }
        formatLabel.textColor = ResourceSnifferPalette.primaryText
        formatLabel.font = AppTypography.subheadline
        let metadata = UIStackView(arrangedSubviews: [formatLabel, dimensionLabel, sizeLabel])
        metadata.axis = .vertical
        metadata.spacing = 2
        metadata.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(metadata)

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardPressed))
        cardView.addGestureRecognizer(tap)
        cardView.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 148),
            moreButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.xs),
            moreButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.xs),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
            retryButton.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 54),
            retryButton.heightAnchor.constraint(equalToConstant: 30),
            indicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            metadata.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: AppSpacing.xs),
            metadata.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.sm),
            metadata.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.sm),
            metadata.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    @objc private func cardPressed() { onPreview?() }
    @objc private func retryPressed() { retry?() }

    private static func format(for resource: DetectedResource) -> String {
        ImageResourceFormat.allCases.dropFirst().first {
            $0.matches(resource)
        }?.title ?? "图片"
    }
}
