import UIKit

final class ResourceSnifferViewController: BaseViewController {
    var sniffingService: ResourceSniffingService?
    var onPreviewResource: ((DetectedResource) -> Void)?
    var onDownloadResource: ((DetectedResource) -> Void)?

    private enum Filter: Int, CaseIterable {
        case all
        case video
        case audio
        case hls
        case image
        case document
        case other

        var title: String {
            switch self {
            case .all: return "全部"
            case .video: return "视频"
            case .audio: return "音频"
            case .hls: return "HLS"
            case .image: return "图片"
            case .document: return "文档"
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
            case .other: return type == .archive || type == .other
            }
        }
    }

    private var pageTitle: String?
    private var pageURL: URL?
    private var resources: [DetectedResource] = []
    private var selectedFilter = Filter.all
    private var scanTask: Task<Void, Never>?

    private let summaryView = ResourcePageSummaryView()
    private let filterScrollView = UIScrollView()
    private let filterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "dot.radiowaves.left.and.right",
            title: "暂未发现可下载资源",
            message: "尝试播放网页中的视频或音频，然后重新扫描当前页面。",
            actionTitle: "重新扫描"
        ),
        action: { [weak self] in self?.refreshResources() }
    )
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(title: "当前页面资源", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureSummary()
        configureFilters()
        configureTable()
        configureEmptyState()
        updateContent()
    }

    func configurePage(title: String?, url: URL?) {
        pageTitle = title
        pageURL = url
        guard isViewLoaded else { return }
        updateSummary()
    }

    func update(resources: [DetectedResource]) {
        self.resources = resources.sorted { $0.detectedAt > $1.detectedAt }
        guard isViewLoaded else { return }
        updateContent()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            scanTask?.cancel()
        }
    }

    private var filteredResources: [DetectedResource] {
        resources.filter { selectedFilter.includes($0.resourceType) }
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshPressed)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "重新扫描当前页面"
    }

    private func configureSummary() {
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summaryView)
        summaryView.onRefresh = { [weak self] in self?.refreshResources() }
        updateSummary()

        NSLayoutConstraint.activate([
            summaryView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            summaryView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            summaryView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureFilters() {
        filterScrollView.showsHorizontalScrollIndicator = false
        filterScrollView.contentInsetAdjustmentBehavior = .never
        filterScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(filterScrollView)

        filterStack.axis = .horizontal
        filterStack.spacing = 8
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterScrollView.addSubview(filterStack)

        for filter in Filter.allCases {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = filter.title
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = filter == selectedFilter ? .white : AppColors.primaryText
            configuration.baseBackgroundColor = filter == selectedFilter
                ? AppColors.accent
                : AppColors.progressTrack
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 7,
                leading: 14,
                bottom: 7,
                trailing: 14
            )
            let button = UIButton(configuration: configuration)
            button.tag = filter.rawValue
            button.accessibilityLabel = "\(filter.title)资源"
            button.addTarget(self, action: #selector(filterPressed(_:)), for: .touchUpInside)
            filterStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            filterScrollView.topAnchor.constraint(equalTo: summaryView.bottomAnchor, constant: 12),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
            ),

            filterStack.topAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.topAnchor, constant: 4),
            filterStack.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            filterStack.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            filterStack.bottomAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.bottomAnchor, constant: -4),
            filterStack.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor, constant: -8)
        ])
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 112
        tableView.register(
            ResourceListCell.self,
            forCellReuseIdentifier: ResourceListCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 50),
            emptyState.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            emptyState.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12)
        ])
    }

    private func updateSummary() {
        summaryView.configure(
            title: pageTitle ?? "新标签页",
            domain: pageURL?.host ?? "尚未打开网页",
            resourceCount: resources.count
        )
    }

    private func updateContent() {
        loadingIndicator.stopAnimating()
        tableView.reloadData()
        let isEmpty = filteredResources.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        updateSummary()
        updateFilterButtons()
    }

    private func updateFilterButtons() {
        for case let button as UIButton in filterStack.arrangedSubviews {
            guard let filter = Filter(rawValue: button.tag) else { continue }
            button.configuration?.baseForegroundColor = filter == selectedFilter ? .white : AppColors.primaryText
            button.configuration?.baseBackgroundColor = filter == selectedFilter
                ? AppColors.accent
                : AppColors.progressTrack
            button.accessibilityValue = filter == selectedFilter ? "已选择" : nil
        }
    }

    private func refreshResources() {
        guard let sniffingService else {
            updateContent()
            return
        }
        scanTask?.cancel()
        emptyState.isHidden = true
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: loadingIndicator)

        let pageURL = pageURL
        let pageTitle = pageTitle
        scanTask = Task { [weak self] in
            do {
                let detected = try await sniffingService.scanResources(
                    forPageURL: pageURL,
                    pageTitle: pageTitle
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.resources = detected
                    self?.restoreRefreshButton()
                    self?.updateContent()
                    UINotificationFeedbackGenerator().notificationOccurred(
                        detected.isEmpty ? .warning : .success
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.restoreRefreshButton()
                    self?.updateContent()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func restoreRefreshButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshPressed)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "重新扫描当前页面"
    }

    @objc private func refreshPressed() {
        refreshResources()
    }

    @objc private func filterPressed(_ sender: UIButton) {
        guard let filter = Filter(rawValue: sender.tag) else { return }
        selectedFilter = filter
        updateContent()
    }
}

extension ResourceSnifferViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
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
        cell.configure(resource: resource)
        cell.onPreview = { [weak self] in self?.onPreviewResource?(resource) }
        cell.onDownload = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.onDownloadResource?(resource)
        }
        return cell
    }
}

private final class ResourcePageSummaryView: UIView {
    var onRefresh: (() -> Void)?

    private let iconView = UIImageView(image: UIImage(systemName: "globe.asia.australia.fill"))
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private let countLabel = UILabel()
    private let refreshButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, domain: String, resourceCount: Int) {
        titleLabel.text = title
        domainLabel.text = domain
        countLabel.text = "已识别 \(resourceCount) 项"
        accessibilityLabel = "\(title)，\(domain)，已识别 \(resourceCount) 项资源"
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.card
        layer.cornerCurve = .continuous
        layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 12)

        iconView.tintColor = AppColors.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        domainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = AppColors.secondaryText
        domainLabel.lineBreakMode = .byTruncatingMiddle

        countLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = AppColors.secondaryText

        let labels = UIStackView(arrangedSubviews: [titleLabel, domainLabel, countLabel])
        labels.axis = .vertical
        labels.spacing = 3

        refreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        refreshButton.accessibilityLabel = "重新扫描"
        refreshButton.addTarget(self, action: #selector(refreshPressed), for: .touchUpInside)
        refreshButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
        ).isActive = true
        refreshButton.heightAnchor.constraint(
            greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
        ).isActive = true

        let stack = UIStackView(arrangedSubviews: [iconView, labels, refreshButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
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

private final class ResourceListCell: UITableViewCell {
    static let reuseIdentifier = "ResourceListCell"

    var onPreview: (() -> Void)?
    var onDownload: (() -> Void)?

    private let cardView = UIView()
    private let typeIconView = UIImageView()
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let domainLabel = UILabel()
    private let previewButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPreview = nil
        onDownload = nil
    }

    func configure(resource: DetectedResource) {
        nameLabel.text = resource.fileName
        let format = resource.mimeType?.split(separator: "/").last.map(String.init)
            ?? resource.url.pathExtension.uppercased()
        let size = resource.estimatedSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "大小未知"
        metadataLabel.text = [resource.resourceType.localizedTitle, format, size]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        domainLabel.text = resource.url.host ?? resource.sourcePageURL?.host
        typeIconView.image = UIImage(systemName: symbolName(for: resource.resourceType))
        accessibilityLabel = "\(resource.fileName)，\(metadataLabel.text ?? "")"
    }

    private func configureView() {
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        typeIconView.tintColor = AppColors.accent
        typeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24)
        typeIconView.contentMode = .center
        typeIconView.backgroundColor = AppColors.accentFill
        typeIconView.layer.cornerRadius = AppRadius.control
        typeIconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2

        metadataLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.textColor = AppColors.secondaryText
        metadataLabel.numberOfLines = 2

        domainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = AppColors.tertiaryText
        domainLabel.lineBreakMode = .byTruncatingMiddle

        let labels = UIStackView(arrangedSubviews: [nameLabel, metadataLabel, domainLabel])
        labels.axis = .vertical
        labels.spacing = 3

        previewButton.setImage(UIImage(systemName: "play.circle"), for: .normal)
        previewButton.accessibilityLabel = "在线播放"
        previewButton.addTarget(self, action: #selector(previewPressed), for: .touchUpInside)
        previewButton.widthAnchor.constraint(
            equalToConstant: AppMetrics.minimumTapSize
        ).isActive = true
        previewButton.heightAnchor.constraint(
            equalToConstant: AppMetrics.minimumTapSize
        ).isActive = true

        var downloadConfiguration = UIButton.Configuration.tinted()
        downloadConfiguration.image = UIImage(systemName: "arrow.down")
        downloadConfiguration.cornerStyle = .medium
        downloadButton.configuration = downloadConfiguration
        downloadButton.accessibilityLabel = "下载资源"
        downloadButton.addTarget(self, action: #selector(downloadPressed), for: .touchUpInside)
        downloadButton.widthAnchor.constraint(
            equalToConstant: AppMetrics.minimumTapSize
        ).isActive = true
        downloadButton.heightAnchor.constraint(
            equalToConstant: AppMetrics.minimumTapSize
        ).isActive = true

        let actions = UIStackView(arrangedSubviews: [previewButton, downloadButton])
        actions.axis = .horizontal
        actions.spacing = 2

        let stack = UIStackView(arrangedSubviews: [typeIconView, labels, actions])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            typeIconView.widthAnchor.constraint(
                equalToConstant: AppMetrics.primaryButtonHeight
            ),
            typeIconView.heightAnchor.constraint(
                equalToConstant: AppMetrics.primaryButtonHeight
            ),

            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14)
        ])
    }

    private func symbolName(for type: ResourceType) -> String {
        switch type {
        case .video: return "film"
        case .audio: return "waveform"
        case .hls: return "dot.radiowaves.left.and.right"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }

    @objc private func previewPressed() {
        onPreview?()
    }

    @objc private func downloadPressed() {
        onDownload?()
    }
}
