import AVFoundation
import AVKit
import UIKit

final class ResourceSnifferViewController: BaseViewController {
    var onReturnToPage: (() -> Void)?
    var onShowDownloads: (() -> Void)?

    private enum Filter: Int, CaseIterable, Equatable {
        case all
        case video
        case audio
        case image

        var title: String {
            switch self {
            case .all: return "全部"
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            }
        }

        func includes(_ type: ResourceType) -> Bool {
            switch self {
            case .all: return true
            case .video: return type == .video || type == .hls
            case .audio: return type == .audio
            case .image: return type == .image
            }
        }
    }

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
        let imageFilters: Set<ImageResourceFormat>
        let selectedFilter: Filter
        let filterCounts: [Int]
        let rows: [RenderedResourceRow]
    }

    private let viewModel: ResourceSnifferViewModel
    private var resources: [DetectedResource] = []
    private var selectedFilter: Filter
    private var scanTask: Task<Void, Never>?
    private var scanState: ResourceScanState = .idle
    private var errorMessage: String?
    private var activationState: SniffingActivationState = .disabled
    private var hasStarted = false
    private var imageFilters: Set<ImageResourceFormat> = []
    private var renderedRows: [RenderedResourceRow] = []
    private var renderedContent: RenderedContent?

    private let summaryView = ResourcePageSummaryViewV2()
    private let filterScrollView = UIScrollView()
    private let filterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let imageCollectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewFlowLayout()
    )
    private lazy var emptyState = EmptyStateView(
        configuration: emptyStateConfiguration,
        action: { [weak self] in self?.refreshResources() },
        secondaryAction: { [weak self] in self?.onReturnToPage?() }
    )
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(viewModel: ResourceSnifferViewModel) {
        self.viewModel = viewModel
        selectedFilter = viewModel.state.imageFilters.isEmpty ? .all : .image
        super.init(title: "当前页面资源", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureSummary()
        configureFilters()
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
        let filtered = resources.filter { selectedFilter.includes($0.resourceType) }
        guard selectedFilter == .image,
              !imageFilters.isEmpty,
              imageFilters != [.all]
        else { return filtered }
        return filtered.filter { resource in
            imageFilters.contains { $0.matches(resource) }
        }
    }

    private var emptyStateConfiguration: EmptyStateView.Configuration {
        if activationState == .disabled || activationState == .failed {
            let canRetry = activationState == .failed || hasStarted
            return .init(
                symbolName: activationState == .failed
                    ? "exclamationmark.arrow.triangle.2.circlepath"
                    : "dot.radiowaves.left.and.right",
                title: activationState == .failed
                    ? "无法开启资源嗅探"
                    : (hasStarted ? "嗅探已停止" : "尚未开始嗅探"),
                message: errorMessage
                    ?? (hasStarted
                        ? "点击上方按钮可再次检测当前页面资源。"
                        : "点击上方按钮后显示发现的资源。"),
                actionTitle: canRetry ? "重新开始嗅探" : nil,
                secondaryActionTitle: "返回网页"
            )
        }
        let isFailed = scanState == .failed
        return .init(
            symbolName: isFailed
                ? "exclamationmark.arrow.triangle.2.circlepath"
                : "dot.radiowaves.left.and.right",
            title: isFailed ? "资源扫描失败" : "暂未发现资源",
            message: isFailed
                ? (errorMessage ?? "请确认网页已完成加载后重新扫描。")
                : "尝试播放网页中的视频或音频，然后重新扫描当前页面。",
            actionTitle: scanState == .scanning ? nil : "重新扫描",
            secondaryActionTitle: "返回网页继续播放"
        )
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            guard let self else { return }
            self.resources = state.resources
            self.scanState = state.scanState
            self.errorMessage = state.errorMessage
            self.activationState = state.activationState
            self.hasStarted = state.hasStarted
            self.imageFilters = state.imageFilters
            self.updateContent(state: state)
        }
    }

    private func configureNavigation() {
        let titleView = ResourceSnifferNavigationTitleView()
        navigationItem.titleView = titleView
        navigationItem.rightBarButtonItem = makeManagementItem()
        titleView.configure(
            status: statusTitle,
            accessibilityValue: statusTitle
        )
    }

    private var statusTitle: String {
        switch activationState {
        case .starting, .active: return "嗅探中"
        case .stopping: return "正在停止"
        case .failed: return "未开始"
        case .disabled: return hasStarted ? "已停止" : "未开始"
        }
    }

    private func configureSummary() {
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summaryView)
        summaryView.onAction = { [weak self] in self?.primarySniffingAction() }

        NSLayoutConstraint.activate([
            summaryView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sm
            ),
            summaryView.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            summaryView.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            )
        ])
    }

    private func configureFilters() {
        filterScrollView.showsHorizontalScrollIndicator = false
        filterScrollView.contentInsetAdjustmentBehavior = .never
        filterScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(filterScrollView)

        filterStack.axis = .horizontal
        filterStack.spacing = AppSpacing.xs
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterScrollView.addSubview(filterStack)

        for filter in Filter.allCases {
            let button = makeFilterButton(filter)
            filterStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            filterScrollView.topAnchor.constraint(
                equalTo: summaryView.bottomAnchor,
                constant: AppSpacing.md
            ),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 52),

            filterStack.topAnchor.constraint(
                equalTo: filterScrollView.contentLayoutGuide.topAnchor,
                constant: AppSpacing.xxs
            ),
            filterStack.leadingAnchor.constraint(
                equalTo: filterScrollView.contentLayoutGuide.leadingAnchor,
                constant: AppSpacing.md
            ),
            filterStack.trailingAnchor.constraint(
                equalTo: filterScrollView.contentLayoutGuide.trailingAnchor,
                constant: -AppSpacing.md
            ),
            filterStack.bottomAnchor.constraint(
                equalTo: filterScrollView.contentLayoutGuide.bottomAnchor,
                constant: -AppSpacing.xxs
            ),
            filterStack.heightAnchor.constraint(
                equalTo: filterScrollView.frameLayoutGuide.heightAnchor,
                constant: -AppSpacing.xs
            )
        ])
    }

    private func makeFilterButton(_ filter: Filter) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = filter.title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 7,
            leading: 14,
            bottom: 7,
            trailing: 14
        )
        let button = UIButton(configuration: configuration)
        button.tag = filter.rawValue
        button.accessibilityLabel = "\(filter.title)资源"
        button.addTarget(
            self,
            action: #selector(filterPressed(_:)),
            for: .touchUpInside
        )
        return button
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
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        let imageLayout = imageCollectionView.collectionViewLayout
            as? UICollectionViewFlowLayout
        imageLayout?.minimumInteritemSpacing = AppSpacing.sm
        imageLayout?.minimumLineSpacing = AppSpacing.sm
        imageLayout?.sectionInset = UIEdgeInsets(
            top: AppSpacing.xs,
            left: AppSpacing.md,
            bottom: AppSpacing.lg,
            right: AppSpacing.md
        )
        imageCollectionView.backgroundColor = .clear
        imageCollectionView.alwaysBounceVertical = true
        imageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        imageCollectionView.register(
            ResourceImageCell.self,
            forCellWithReuseIdentifier: ResourceImageCell.reuseIdentifier
        )
        imageCollectionView.dataSource = self
        imageCollectionView.delegate = self
        contentView.addSubview(imageCollectionView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: filterScrollView.bottomAnchor,
                constant: AppSpacing.xs
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageCollectionView.topAnchor.constraint(
                equalTo: filterScrollView.bottomAnchor,
                constant: AppSpacing.xs
            ),
            imageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(
                equalTo: filterScrollView.bottomAnchor,
                constant: AppSpacing.lg
            ),
            emptyState.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor,
                constant: AppSpacing.sm
            ),
            emptyState.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor,
                constant: -AppSpacing.sm
            ),
            emptyState.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.md
            )
        ])
    }

    private func updateContent(state: ResourceSnifferViewModel.State) {
        let nextRows = filteredResources.map(RenderedResourceRow.init)
        let canShowResults = state.hasStarted || state.activationState.isEnabled
        let nextContent = RenderedContent(
            pageTitle: state.pageTitle,
            pageURL: state.pageURL,
            isPrivate: state.isPrivate,
            scanState: state.scanState,
            errorMessage: state.errorMessage,
            activationState: state.activationState,
            hasStarted: state.hasStarted,
            imageFilters: state.imageFilters,
            selectedFilter: selectedFilter,
            filterCounts: Filter.allCases.map { filter in
                (canShowResults ? resources : []).lazy.filter {
                    filter.includes($0.resourceType)
                }.count
            },
            rows: nextRows
        )
        guard nextContent != renderedContent else { return }
        renderedContent = nextContent
        let isScanning = state.scanState == .installing
            || state.scanState == .scanning
        summaryView.configure(
            title: state.pageTitle,
            domain: state.pageURL?.host ?? "尚未打开网页",
            pageURL: state.pageURL,
            resourceCount: canShowResults ? resources.count : 0,
            scanState: state.scanState,
            isPrivate: state.isPrivate,
            activationState: state.activationState,
            hasStarted: state.hasStarted
        )
        summaryView.setActionEnabled(
            state.activationState != .starting && state.activationState != .stopping
        )
        if nextRows != renderedRows {
            renderedRows = nextRows
            tableView.reloadData()
            imageCollectionView.reloadData()
        }
        let isImageGrid = selectedFilter == .image
        let isEmpty = filteredResources.isEmpty
        tableView.isHidden = isImageGrid || isEmpty
        imageCollectionView.isHidden = !isImageGrid || isEmpty
        emptyState.isHidden = !isEmpty
        emptyState.configure(
            emptyStateConfiguration,
            action: isScanning ? nil : { [weak self] in
                self?.refreshResources()
            },
            secondaryAction: onReturnToPage
        )
        updateFilterButtons()
        updateNavigation(isScanning: isScanning)
    }

    private func updateNavigation(isScanning: Bool) {
        if isScanning { loadingIndicator.startAnimating() }
        else { loadingIndicator.stopAnimating() }
        navigationItem.rightBarButtonItem = makeManagementItem()
        (navigationItem.titleView as? ResourceSnifferNavigationTitleView)?.configure(
            status: statusTitle,
            accessibilityValue: statusTitle
        )
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
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [stop, clear])
        )
        item.accessibilityLabel = "资源管理"
        return item
    }

    private func updateFilterButtons() {
        let canShowResults = hasStarted || activationState.isEnabled
        for case let button as UIButton in filterStack.arrangedSubviews {
            guard let filter = Filter(rawValue: button.tag) else { continue }
            let count = (canShowResults ? resources : []).lazy.filter {
                filter.includes($0.resourceType)
            }.count
            button.configuration?.title = count > 0
                ? "\(filter.title) \(count)"
                : filter.title
            button.configuration?.baseForegroundColor =
                filter == selectedFilter ? AppColors.accentContent : AppColors.primaryText
            button.configuration?.baseBackgroundColor =
                filter == selectedFilter
                ? AppColors.accent
                : AppColors.progressTrack
            button.configuration?.image = filter == .image
                && !imageFilters.isEmpty
                && imageFilters != [.all]
                ? UIImage(systemName: "line.3.horizontal.decrease.circle.fill")
                : nil
            button.accessibilityValue = filter == selectedFilter
                ? "已选择，\(count) 项"
                : "\(count) 项"
        }
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
                try await self?.viewModel.activateIfNeeded()
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
        let continueToConfirmation = { [weak self] in
            self?.presentDownloadConfirmation(resource)
        }
        guard !DownloadComplianceAcknowledgement.hasAcknowledged else {
            continueToConfirmation()
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
            continueToConfirmation()
        })
        present(alert, animated: true)
    }

    private func presentDownloadConfirmation(_ resource: DetectedResource) {
        let kind = resource.resourceType == .hls ? "视频" : resource.resourceType.localizedTitle
        // Content-Length on an HLS URL is only the playlist text size. It is
        // never the size of the video represented by that playlist.
        let expectedSize = resource.resourceType == .hls
            ? "下载时计算"
            : formattedSize(resource.estimatedSize)
        let message = [
            "类型：\(kind)",
            "文件名：\(resource.fileName)",
            "预计大小：\(expectedSize)"
        ].joined(separator: "\n")
        let sheet = UIAlertController(
            title: resource.resourceType == .hls ? "下载视频" : "确认下载",
            message: message,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.addAction(UIAlertAction(
            title: "开始下载",
            style: .default
        ) { [weak self] _ in
            self?.startDownload(resource)
        })
        present(sheet, animated: true)
    }

    private func startDownload(_ resource: DetectedResource) {
        scanTask = Task { [weak self] in
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
        scanTask = Task { [weak self] in
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
                let playbackURL: URL
                let options: [String: Any]
                if resource.resourceType == .hls {
                    playbackURL = try await RemoteHLSPlaybackServer.shared
                        .playbackURL(context: context)
                    options = [:]
                } else {
                    playbackURL = context.targetURL
                    options = context.assetOptions()
                }
                guard !Task.isCancelled else { return }
                let asset = AVURLAsset(url: playbackURL, options: options)
                let player = AVPlayerViewController()
                player.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                self.present(player, animated: true) { player.player?.play() }
            } catch {
                self.showMessage(
                    title: "无法在线播放",
                    message: error.localizedDescription
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

    @objc private func filterPressed(_ sender: UIButton) {
        guard let filter = Filter(rawValue: sender.tag) else { return }
        if filter == .image {
            selectedFilter = .image
            updateContent(state: viewModel.state)
            presentImageFilterPanel()
            return
        }
        selectedFilter = filter
        let state = viewModel.state
        updateContent(state: state)
    }

    private func presentImageFilterPanel() {
        let controller = ImageResourceFilterViewController(selection: imageFilters)
        controller.onFinish = { [weak self] filters in
            guard let self else { return }
            self.viewModel.setImageFilters(filters)
            self.selectedFilter = .image
            self.dismiss(animated: true)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = AppRadius.sheet
        }
        present(navigation, animated: true)
    }
}

extension ResourceSnifferViewController: UITableViewDataSource {
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
        let resource = filteredResources[indexPath.row]
        cell.configure(
            resource: resource,
            allowsThumbnailDiskCache: !viewModel.state.isPrivate,
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
}

extension ResourceSnifferViewController: UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        filteredResources.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ResourceImageCell.reuseIdentifier,
            for: indexPath
        ) as? ResourceImageCell else {
            return UICollectionViewCell()
        }
        let resource = filteredResources[indexPath.item]
        let imageURL = URL(string: resource.originalURLString) ?? resource.canonicalURL
        cell.configure(
            resource: resource,
            allowsDiskCache: !viewModel.state.isPrivate,
            requestProvider: { [weak viewModel] _ in
                guard let viewModel else { return nil }
                return await viewModel.thumbnailRequest(for: imageURL)
            },
            inlineDataProvider: { [weak viewModel] _ in
                guard let viewModel else { return nil }
                return await viewModel.thumbnailData(for: imageURL)
            },
            onPreview: { [weak self] in self?.preview(resource) },
            onMore: { [weak self] in self?.presentImageActions(for: resource) }
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let layout = collectionViewLayout as? UICollectionViewFlowLayout
        let horizontalInsets = (layout?.sectionInset.left ?? AppSpacing.md)
            + (layout?.sectionInset.right ?? AppSpacing.md)
        let spacing = layout?.minimumInteritemSpacing ?? AppSpacing.sm
        let width = max(120, (collectionView.bounds.width - horizontalInsets - spacing) / 2)
        return CGSize(width: width, height: 218)
    }

    private func presentImageActions(for resource: DetectedResource) {
        let sheet = UIAlertController(
            title: resource.fileName,
            message: "选择操作",
            preferredStyle: .actionSheet
        )
        let download = UIAlertAction(title: "下载", style: .default) { [weak self] _ in
            self?.requestDownload(resource)
        }
        download.isEnabled = resource.isPotentiallyDownloadable
            && ["http", "https"].contains(resource.canonicalURL.scheme?.lowercased() ?? "")
        sheet.addAction(download)
        sheet.addAction(UIAlertAction(title: "复制链接", style: .default) { [weak self] _ in
            self?.copy(resource)
        })
        sheet.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
            self?.share(resource)
        })
        sheet.addAction(UIAlertAction(title: "查看详情", style: .default) { [weak self] _ in
            self?.showDetails(resource)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }
}

private enum DownloadComplianceAcknowledgement {
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
                    self?.imageView.tintColor = AppColors.secondaryText
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
        titleLabel.textColor = AppColors.primaryText
        statusLabel.font = AppTypography.caption
        statusLabel.textColor = AppColors.accent
        statusLabel.backgroundColor = AppColors.accentFill
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

    func configure(status: String, accessibilityValue: String) {
        titleLabel.text = "资源嗅探"
        statusLabel.text = "  \(status)  "
        accessibilityLabel = "资源嗅探，\(accessibilityValue)"
    }
}

private final class ResourcePageSummaryViewV2: UIView {
    var onAction: (() -> Void)?

    private let iconContainer = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "globe"))
    private let contextLabel = UILabel()
    private let domainLabel = UILabel()
    private let detailLabel = UILabel()
    private let privacyLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var faviconURL: URL?
    private var faviconRequestID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) { return nil }

    func configure(
        title: String,
        domain: String,
        pageURL: URL?,
        resourceCount: Int,
        scanState: ResourceScanState,
        isPrivate: Bool,
        activationState: SniffingActivationState,
        hasStarted: Bool
    ) {
        contextLabel.text = "当前网页"
        domainLabel.text = domain
        configureFavicon(for: pageURL, isPrivate: isPrivate)
        switch activationState {
        case .starting, .active, .stopping:
            detailLabel.text = scanState == .scanning || scanState == .installing
                ? "正在检测网页后续资源…"
                : (resourceCount > 0
                    ? "已发现 \(resourceCount) 项资源"
                    : "尚未发现资源")
        case .failed:
            detailLabel.text = "暂时无法连接资源检测"
        case .disabled:
            detailLabel.text = hasStarted
                ? "已停止新增资源，已有结果仍保留"
                : "点击开始后检测当前页面资源"
        }
        privacyLabel.text = isPrivate
            ? "仅在本次页面手动开启，不会自动扫描 · 无痕结果仅保留在当前会话"
            : "仅在本次页面手动开启，不会自动扫描"
        privacyLabel.isHidden = false
        let isRunning = activationState.isEnabled
            || activationState == .stopping
            || activationState == .starting
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = isRunning
            ? AppColors.secondaryText
            : AppColors.accent
        configuration.baseForegroundColor = AppColors.accentContent
        configuration.image = UIImage(
            systemName: isRunning ? "stop.fill" : "dot.radiowaves.left.and.right"
        )
        configuration.imagePadding = AppSpacing.xs
        configuration.title = isRunning ? "停止嗅探" : "开始嗅探"
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sm,
            leading: AppSpacing.md,
            bottom: AppSpacing.sm,
            trailing: AppSpacing.md
        )
        actionButton.configuration = configuration
        actionButton.accessibilityLabel = configuration.title
        accessibilityLabel = [
            title,
            contextLabel.text,
            domainLabel.text,
            detailLabel.text,
            privacyLabel.text
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }

    func setActionEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        actionButton.alpha = enabled ? 1 : 0.55
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = AppMetrics.separatorHeight
        layer.borderColor = AppColors.separator.cgColor
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.md,
            leading: AppSpacing.md,
            bottom: AppSpacing.md,
            trailing: AppSpacing.md
        )

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = AppColors.accentFill
        iconContainer.layer.cornerRadius = AppRadius.control
        iconContainer.layer.cornerCurve = .continuous
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = AppColors.accent
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        [contextLabel, domainLabel, detailLabel, privacyLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 1
        }
        contextLabel.font = AppTypography.caption
        contextLabel.textColor = AppColors.secondaryText
        domainLabel.font = AppTypography.headline
        domainLabel.textColor = AppColors.primaryText
        domainLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.font = AppTypography.subheadline
        detailLabel.textColor = AppColors.secondaryText
        privacyLabel.font = AppTypography.caption
        privacyLabel.textColor = AppColors.secondaryText
        privacyLabel.numberOfLines = 2
        privacyLabel.isHidden = false

        let labels = UIStackView(
            arrangedSubviews: [contextLabel, domainLabel, detailLabel, privacyLabel]
        )
        labels.axis = .vertical
        labels.spacing = 3
        labels.alignment = .fill
        labels.translatesAutoresizingMaskIntoConstraints = false

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [iconContainer, labels])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = AppSpacing.sm
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 50),
            iconContainer.heightAnchor.constraint(equalToConstant: 50),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            header.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: header.bottomAnchor, constant: AppSpacing.md),
            actionButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
    }

    @objc private func actionPressed() { onAction?() }

    private func configureFavicon(for pageURL: URL?, isPrivate: Bool) {
        let nextURL = pageURL.flatMap {
            isPrivate
                ? FaviconLoader.directFaviconURL(for: $0)
                : FaviconLoader.faviconURL(for: $0)
        }
        guard nextURL != faviconURL else { return }
        if let faviconURL, let faviconRequestID {
            FaviconLoader.shared.cancel(url: faviconURL, requestID: faviconRequestID)
        }
        faviconURL = nextURL
        faviconRequestID = nil
        iconView.image = UIImage(systemName: "globe")
        guard let nextURL else { return }
        faviconRequestID = FaviconLoader.shared.load(url: nextURL) { [weak self] image in
            guard let self, self.faviconURL == nextURL else { return }
            self.faviconRequestID = nil
            self.iconView.image = image ?? UIImage(systemName: "globe")
        }
    }

    deinit {
        if let faviconURL, let faviconRequestID {
            FaviconLoader.shared.cancel(url: faviconURL, requestID: faviconRequestID)
        }
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
                    self.imageView.tintColor = AppColors.secondaryText
                    self.retryButton.isHidden = self.retryCount >= 1
                }
            }
        }
    }

    private func configureView() {
        backgroundColor = .clear
        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = AppMetrics.separatorHeight
        cardView.layer.borderColor = AppColors.separator.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        imageView.backgroundColor = AppColors.progressTrack
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.tintColor = AppColors.secondaryText
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(imageView)

        moreButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        moreButton.tintColor = AppColors.primaryText
        moreButton.backgroundColor = AppColors.surface.withAlphaComponent(0.88)
        moreButton.layer.cornerRadius = 16
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.showsMenuAsPrimaryAction = true
        cardView.addSubview(moreButton)

        retryButton.setTitle("重试", for: .normal)
        retryButton.titleLabel?.font = AppTypography.caption
        retryButton.tintColor = AppColors.accent
        retryButton.backgroundColor = AppColors.surface
        retryButton.layer.cornerRadius = AppRadius.control
        retryButton.isHidden = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        cardView.addSubview(retryButton)

        indicator.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(indicator)

        [formatLabel, dimensionLabel, sizeLabel].forEach {
            $0.font = AppTypography.caption
            $0.textColor = AppColors.secondaryText
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 1
        }
        formatLabel.textColor = AppColors.primaryText
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

private final class ImageResourceFilterViewController: UITableViewController {
    var onFinish: ((Set<ImageResourceFormat>) -> Void)?
    private var selection: Set<ImageResourceFormat>

    init(selection: Set<ImageResourceFormat>) {
        self.selection = selection.isEmpty || selection.contains(.all)
            ? [.all]
            : selection
        super.init(style: .insetGrouped)
        title = "图片类型"
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelPressed)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(donePressed)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ImageFilterCell")
        tableView.rowHeight = 52
        tableView.accessibilityLabel = "图片类型筛选"
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int { ImageResourceFormat.allCases.count }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ImageFilterCell",
            for: indexPath
        )
        let format = ImageResourceFormat.allCases[indexPath.row]
        let isSelected = selection.contains(format)
        var content = cell.defaultContentConfiguration()
        content.text = format.title
        content.textProperties.font = AppTypography.body
        cell.contentConfiguration = content
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.tintColor = AppColors.accent
        cell.contentView.layer.cornerRadius = AppRadius.control
        cell.contentView.layer.cornerCurve = .continuous
        cell.contentView.layer.borderWidth = isSelected
            ? AppMetrics.separatorHeight * 2
            : 0
        cell.contentView.layer.borderColor = isSelected
            ? AppColors.accent.cgColor
            : UIColor.clear.cgColor
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        let format = ImageResourceFormat.allCases[indexPath.row]
        if format == .all {
            selection = [.all]
        } else {
            selection.remove(.all)
            if selection.contains(format) { selection.remove(format) }
            else { selection.insert(format) }
            if selection.isEmpty { selection = [.all] }
        }
        tableView.reloadData()
    }

    @objc private func cancelPressed() { dismiss(animated: true) }

    @objc private func donePressed() {
        onFinish?(selection == [.all] ? [] : selection)
    }
}
