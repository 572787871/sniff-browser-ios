import UIKit

final class ResourceSnifferViewController: BaseViewController {
    var onReturnToPage: (() -> Void)?

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
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                customView: loadingIndicator
            )
        } else {
            loadingIndicator.stopAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "arrow.clockwise"),
                style: .plain,
                target: self,
                action: #selector(refreshPressed)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel =
                "重新扫描当前页面"
        }
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
            onCopy: { [weak self] in self?.copy(resource) },
            onShare: { [weak self] in self?.share(resource) },
            onDetails: { [weak self] in self?.showDetails(resource) }
        )
        return cell
    }
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
