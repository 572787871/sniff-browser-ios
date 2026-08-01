import AVFoundation
import AVKit
import UIKit

final class ResourceSnifferViewController: BaseViewController {
    var onReturnToPage: (() -> Void)?
    var onShowDownloads: (() -> Void)?

    private enum Filter: Int, CaseIterable {
        case all
        case video
        case audio
        case hls
        case image
        case document
        case subtitle
        case other

        var title: String {
            switch self {
            case .all: return "全部"
            case .video: return "视频"
            case .audio: return "音频"
            case .hls: return "HLS"
            case .image: return "图片"
            case .document: return "文档"
            case .subtitle: return "字幕"
            case .other: return "其他"
            }
        }

        func includes(_ type: ResourceType) -> Bool {
            switch self {
            case .all: return true
            case .video: return type == .video
            case .audio: return type == .audio
            case .hls: return type == .hls
            case .image: return type == .image
            case .document: return type == .document
            case .subtitle: return type == .subtitle
            case .other: return type == .archive || type == .other
            }
        }
    }

    private let viewModel: ResourceSnifferViewModel
    private var resources: [DetectedResource] = []
    private var selectedFilter = Filter.all
    private var scanTask: Task<Void, Never>?
    private var scanState: ResourceScanState = .idle
    private var errorMessage: String?
    private var activationState: SniffingActivationState = .disabled

    private let summaryView = ResourcePageSummaryView()
    private let filterScrollView = UIScrollView()
    private let filterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var emptyState = EmptyStateView(
        configuration: emptyStateConfiguration,
        action: { [weak self] in self?.refreshResources() },
        secondaryAction: { [weak self] in self?.onReturnToPage?() }
    )
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(viewModel: ResourceSnifferViewModel) {
        self.viewModel = viewModel
        super.init(title: "当前页面资源", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSummary()
        configureFilters()
        configureTable()
        configureEmptyState()
        bindViewModel()
        viewModel.start()
        activateSniffingIfNeeded()
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
    }

    private var filteredResources: [DetectedResource] {
        resources.filter { selectedFilter.includes($0.resourceType) }
    }

    private var emptyStateConfiguration: EmptyStateView.Configuration {
        if activationState == .disabled || activationState == .failed {
            return .init(
                symbolName: activationState == .failed
                    ? "exclamationmark.arrow.triangle.2.circlepath"
                    : "dot.radiowaves.left.and.right",
                title: activationState == .failed ? "无法开启资源嗅探" : "资源嗅探已停止",
                message: errorMessage ?? "开启后仅识别当前标签页；其他标签不会受到影响。",
                actionTitle: "开启资源嗅探",
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
            self.updateContent(state: state)
        }
    }

    private func configureSummary() {
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summaryView)
        summaryView.onRefresh = { [weak self] in self?.refreshResources() }

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

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: filterScrollView.bottomAnchor,
                constant: AppSpacing.xs
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        let isScanning = state.scanState == .installing
            || state.scanState == .scanning
        summaryView.configure(
            title: state.pageTitle,
            domain: state.pageURL?.host ?? "尚未打开网页",
            resourceCount: resources.count,
            scanState: state.scanState,
            isPrivate: state.isPrivate
        )
        summaryView.setRefreshAvailable(!isScanning && state.pageURL != nil)
        tableView.reloadData()
        let isEmpty = filteredResources.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        emptyState.configure(
            emptyStateConfiguration,
            action: isScanning ? nil : { [weak self] in
                self?.refreshResources()
            },
            secondaryAction: onReturnToPage
        )
        updateFilterButtons()
        updateRefreshButton(isScanning: isScanning)
    }

    private func updateRefreshButton(isScanning: Bool) {
        if isScanning {
            loadingIndicator.startAnimating()
            navigationItem.rightBarButtonItems = [UIBarButtonItem(
                customView: loadingIndicator
            ), makeManagementItem()]
        } else {
            loadingIndicator.stopAnimating()
            let refreshItem = UIBarButtonItem(
                image: UIImage(systemName: "arrow.clockwise"),
                style: .plain,
                target: self,
                action: #selector(refreshPressed)
            )
            refreshItem.accessibilityLabel = "重新扫描当前页面"
            navigationItem.rightBarButtonItems = [refreshItem, makeManagementItem()]
        }
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
        for case let button as UIButton in filterStack.arrangedSubviews {
            guard let filter = Filter(rawValue: button.tag) else { continue }
            let count = resources.lazy.filter {
                filter.includes($0.resourceType)
            }.count
            button.configuration?.title = count > 0
                ? "\(filter.title) \(count)"
                : filter.title
            button.configuration?.baseForegroundColor =
                filter == selectedFilter ? .white : AppColors.primaryText
            button.configuration?.baseBackgroundColor =
                filter == selectedFilter
                ? AppColors.accent
                : AppColors.progressTrack
            button.accessibilityValue = filter == selectedFilter
                ? "已选择，\(count) 项"
                : "\(count) 项"
        }
    }

    private func refreshResources() {
        guard scanState != .scanning, scanState != .installing else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            do {
                try await self?.viewModel.refresh()
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

    private func activateSniffingIfNeeded() {
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
        guard resource.isPotentiallyDownloadable,
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
        let kind = resource.resourceType == .hls ? "HLS 离线视频" : resource.resourceType.localizedTitle
        let message = [
            "类型：\(kind)",
            "文件名：\(resource.fileName)",
            "预计大小：\(formattedSize(resource.estimatedSize))"
        ].joined(separator: "\n")
        let sheet = UIAlertController(
            title: resource.resourceType == .hls ? "离线保存" : "确认下载",
            message: message,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.addAction(UIAlertAction(
            title: resource.resourceType == .hls ? "开始离线保存" : "开始下载",
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
            let context = await self.viewModel.requestContext(for: resource)
            if resource.resourceType == .image {
                let controller = RemoteResourceImageViewController(
                    title: resource.fileName,
                    tabID: resource.tabID,
                    request: context.makeRequest(cachePolicy: .returnCacheDataElseLoad),
                    allowsDiskCache: !self.viewModel.state.isPrivate
                )
                self.navigationController?.pushViewController(controller, animated: true)
                return
            }
            let asset = AVURLAsset(
                url: context.targetURL,
                options: context.assetOptions()
            )
            let player = AVPlayerViewController()
            player.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.present(player, animated: true) { player.player?.play() }
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

    @objc private func refreshPressed() {
        refreshResources()
    }

    @objc private func filterPressed(_ sender: UIButton) {
        guard let filter = Filter(rawValue: sender.tag) else { return }
        selectedFilter = filter
        let state = viewModel.state
        updateContent(state: state)
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
            onCopy: { [weak self] in self?.copy(resource) },
            onShare: { [weak self] in self?.share(resource) },
            onDetails: { [weak self] in self?.showDetails(resource) },
            onPreview: [.image, .video, .audio, .hls].contains(resource.resourceType)
                ? { [weak self] in self?.preview(resource) }
                : nil,
            onDownload: resource.isPotentiallyDownloadable
                && ["http", "https"].contains(
                    resource.canonicalURL.scheme?.lowercased() ?? ""
                )
                ? { [weak self] in self?.requestDownload(resource) }
                : nil
        )
        return cell
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
    private let imageView = UIImageView()
    private let indicator = UIActivityIndicatorView(style: .large)
    private var token: ResourceThumbnailToken?

    init(
        title: String,
        tabID: UUID,
        request: URLRequest,
        allowsDiskCache: Bool
    ) {
        self.tabID = tabID
        self.request = request
        self.allowsDiskCache = allowsDiskCache
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
        token = ResourceThumbnailLoader.shared.load(ResourceThumbnailRequest(
            resourceID: UUID(),
            tabID: tabID,
            request: request,
            targetPixelSize: CGSize(width: 2_400, height: 2_400),
            allowsDiskCache: allowsDiskCache
        )) { [weak self] image in
            self?.indicator.stopAnimating()
            self?.imageView.image = image
        }
    }

    deinit { token?.cancel() }
}

private final class ResourcePageSummaryView: UIView {
    var onRefresh: (() -> Void)?

    private let iconContainer = UIView()
    private let iconView = UIImageView(
        image: UIImage(systemName: "globe.asia.australia.fill")
    )
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private let countLabel = UILabel()
    private let privacyLabel = UILabel()
    private let refreshButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        domain: String,
        resourceCount: Int,
        scanState: ResourceScanState,
        isPrivate: Bool
    ) {
        titleLabel.text = title
        domainLabel.text = domain
        switch scanState {
        case .installing, .scanning:
            countLabel.text = "正在扫描"
        case .failed:
            countLabel.text = "扫描失败"
        case .idle, .completed:
            countLabel.text = resourceCount == 0
                ? "暂未发现资源"
                : "已发现 \(resourceCount) 项"
        }
        privacyLabel.text = isPrivate
            ? "无痕结果仅保留在当前会话"
            : nil
        privacyLabel.isHidden = !isPrivate
        accessibilityLabel = [
            title,
            domain,
            countLabel.text,
            privacyLabel.text
        ].compactMap { $0 }.joined(separator: "，")
    }

    func setRefreshAvailable(_ isAvailable: Bool) {
        refreshButton.alpha = isAvailable ? 1 : 0.35
        refreshButton.isEnabled = isAvailable
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.card
        layer.cornerCurve = .continuous
        layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 12)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = AppColors.accentFill
        iconContainer.layer.cornerRadius = AppRadius.control
        iconContainer.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = AppColors.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 21,
            weight: .medium
        )
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        domainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = AppColors.secondaryText
        domainLabel.numberOfLines = 1
        domainLabel.lineBreakMode = .byTruncatingMiddle
        countLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = AppColors.secondaryText
        privacyLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        privacyLabel.adjustsFontForContentSizeCategory = true
        privacyLabel.textColor = AppColors.secondaryText
        privacyLabel.numberOfLines = 1

        let labels = UIStackView(
            arrangedSubviews: [
                titleLabel,
                domainLabel,
                countLabel,
                privacyLabel
            ]
        )
        labels.axis = .vertical
        labels.alignment = .fill
        labels.distribution = .fill
        labels.spacing = 3
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.setImage(
            UIImage(systemName: "arrow.clockwise"),
            for: .normal
        )
        refreshButton.accessibilityLabel = "重新扫描"
        refreshButton.addTarget(
            self,
            action: #selector(refreshPressed),
            for: .touchUpInside
        )

        let stack = UIStackView(
            arrangedSubviews: [iconContainer, labels, refreshButton]
        )
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = AppSpacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 44),
            iconContainer.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            refreshButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            refreshButton.heightAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }
}
