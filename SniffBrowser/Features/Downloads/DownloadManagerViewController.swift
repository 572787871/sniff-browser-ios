import AVKit
import QuickLook
import UIKit

final class DownloadManagerViewController: BaseViewController {
    var onError: ((Error) -> Void)?
    var onBrowseForDownloads: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }
    var onRoute: ((AppRoute) -> Void)? {
        didSet { updateEmptyStateActions() }
    }

    private enum Scope: Int, CaseIterable {
        case all
        case active
        case paused
        case completed
        case failed

        var title: String {
            switch self {
            case .all: return "全部"
            case .active: return "进行中"
            case .paused: return "已暂停"
            case .completed: return "已完成"
            case .failed: return "失败"
            }
        }

        func includes(_ state: DownloadState) -> Bool {
            switch self {
            case .all: return true
            case .active: return state == .waiting || state.isInProgress
            case .paused: return state == .paused
            case .completed: return state == .completed
            case .failed: return state == .failed
            }
        }
    }

    private let manager: DownloadManaging?
    private var selectedScope = Scope.all
    private var displayedTasks: [DownloadTaskModel] = []
    private var operationTask: Task<Void, Never>?
    private var previewURL: URL?

    private let scopeControl = UISegmentedControl(items: Scope.allCases.map(\.title))
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "arrow.down.circle",
            title: "暂无下载任务",
            message: "从网页资源列表开始下载后，任务状态会显示在这里。",
            actionTitle: "返回浏览器",
            secondaryActionTitle: "下载设置"
        )
    )

    private var filteredTasks: [DownloadTaskModel] {
        guard let tasks = manager?.tasks else { return [] }
        return tasks
            .filter { $0.isHiddenFromDownloadHistory != true }
            .filter { selectedScope.includes($0.state) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    init(manager: DownloadManaging? = nil) {
        self.manager = manager
        super.init(title: "下载", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScopeControl()
        configureTable()
        configureEmptyState()
        configureNavigationActions()
        updateContent()
        manager?.onTasksChanged = { [weak self] in self?.updateContent() }
        reloadTasks()
    }

    func updateContent() {
        guard isViewLoaded else { return }
        let nextTasks = filteredTasks
        let oldTasks = displayedTasks
        displayedTasks = nextTasks

        if oldTasks.map(\.id) != nextTasks.map(\.id) {
            tableView.reloadData()
        } else {
            let oldByID = Dictionary(uniqueKeysWithValues: oldTasks.map { ($0.id, $0) })
            for indexPath in tableView.indexPathsForVisibleRows ?? [] {
                guard nextTasks.indices.contains(indexPath.row),
                      let oldTask = oldByID[nextTasks[indexPath.row].id],
                      oldTask != nextTasks[indexPath.row],
                      let cell = tableView.cellForRow(at: indexPath) as? DownloadTaskCell
                else { continue }
                let task = nextTasks[indexPath.row]
                cell.configure(
                    task: task,
                    fileURL: task.state == .completed ? manager?.fileURL(for: task.id) : nil
                )
            }
        }
        let isEmpty = nextTasks.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        configureNavigationActions()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            operationTask?.cancel()
            manager?.onTasksChanged = nil
        }
    }

    private func configureScopeControl() {
        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scopeControl)

        NSLayoutConstraint.activate([
            scopeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scopeControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scopeControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 118
        tableView.register(
            DownloadTaskCell.self,
            forCellReuseIdentifier: DownloadTaskCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshChanged(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: AppSpacing.xs),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        updateEmptyStateActions()
    }

    private func configureNavigationActions() {
        guard let allTasks = manager?.tasks else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let tasks = allTasks.filter { $0.isHiddenFromDownloadHistory != true }
        guard !tasks.isEmpty else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let pausable = tasks.filter {
            $0.state == .waiting || $0.state.isInProgress
        }
        let resumable = tasks.filter { $0.state == .paused }
        let completed = tasks.filter { $0.state == .completed }

        let pauseAll = UIAction(
            title: "全部暂停",
            image: UIImage(systemName: "pause.circle"),
            attributes: pausable.isEmpty ? [.disabled] : []
        ) { [weak self] _ in
            self?.perform { manager in
                for task in pausable {
                    try await manager.pauseTask(id: task.id)
                }
            }
        }
        let resumeAll = UIAction(
            title: "全部继续",
            image: UIImage(systemName: "play.circle"),
            attributes: resumable.isEmpty ? [.disabled] : []
        ) { [weak self] _ in
            self?.perform { manager in
                for task in resumable {
                    try await manager.resumeTask(id: task.id)
                }
            }
        }
        let clearCompleted = UIAction(
            title: "清理已完成记录",
            image: UIImage(systemName: "checkmark.circle"),
            attributes: completed.isEmpty ? [.disabled] : []
        ) { [weak self] _ in
            self?.confirmClearCompleted(completed)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [pauseAll, resumeAll, clearCompleted])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "下载批量操作"
    }

    private func updateEmptyStateActions() {
        emptyState.configure(
            .init(
                symbolName: "arrow.down.circle",
                title: "暂无下载任务",
                message: "从网页资源列表开始下载后，任务状态会显示在这里。",
                actionTitle: "返回浏览器",
                secondaryActionTitle: "下载设置"
            ),
            action: actionWithFeedback(onBrowseForDownloads),
            secondaryAction: routeActionWithFeedback(.downloadSettings)
        )
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    private func routeActionWithFeedback(_ route: AppRoute) -> (() -> Void)? {
        guard let onRoute else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRoute(route)
        }
    }

    private func reloadTasks() {
        guard let manager else {
            tableView.refreshControl?.endRefreshing()
            updateContent()
            return
        }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            await manager.reloadTasks()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.tableView.refreshControl?.endRefreshing()
                self?.updateContent()
            }
        }
    }

    private func perform(
        operation: @escaping @MainActor (DownloadManaging) async throws -> Void
    ) {
        guard let manager else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                try await operation(manager)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.updateContent() }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.presentOperationError(error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func presentOperationError(_ error: Error) {
        if let onError {
            onError(error)
            return
        }
        let alert = UIAlertController(
            title: "无法完成操作",
            message: DownloadErrorMapper.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func confirmClearCompleted(_ tasks: [DownloadTaskModel]) {
        let alert = UIAlertController(
            title: "清理已完成记录？",
            message: "只删除下载记录，已保存到文件库的文件会继续保留。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清理记录", style: .destructive) {
            [weak self] _ in
            self?.perform { manager in
                for task in tasks {
                    try await manager.deleteTask(id: task.id, deleteFile: false)
                }
            }
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ task: DownloadTaskModel) {
        let alert = UIAlertController(
            title: task.state == .completed ? "删除下载？" : "删除记录？",
            message: task.state == .completed
                ? "可以只删除记录，或同时删除文件库中的文件。"
                : "此操作会移除该下载记录。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除记录", style: .destructive) {
            [weak self] _ in
            self?.perform { manager in
                try await manager.deleteTask(id: task.id, deleteFile: false)
            }
        })
        if task.state == .completed {
            alert.addAction(UIAlertAction(
                title: "删除记录和文件",
                style: .destructive
            ) { [weak self] _ in
                self?.perform { manager in
                    try await manager.deleteTask(id: task.id, deleteFile: true)
                }
            })
        }
        present(alert, animated: true)
    }

    @objc private func scopeChanged() {
        selectedScope = Scope(rawValue: scopeControl.selectedSegmentIndex) ?? .all
        updateContent()
    }

    @objc private func refreshChanged(_ sender: UIRefreshControl) {
        reloadTasks()
    }
}

extension DownloadManagerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedTasks.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: DownloadTaskCell.reuseIdentifier,
            for: indexPath
        ) as? DownloadTaskCell else {
            return UITableViewCell()
        }
        let task = displayedTasks[indexPath.row]
        cell.configure(
            task: task,
            fileURL: task.state == .completed ? manager?.fileURL(for: task.id) : nil
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let task = displayedTasks[indexPath.row]
        guard task.state == .completed,
              let url = manager?.fileURL(for: task.id)
        else { return }

        switch task.resourceType {
        case .video, .audio, .hls:
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: url)
            present(controller, animated: true) {
                controller.player?.play()
            }
        case .image, .document, .subtitle, .archive, .other:
            previewURL = url
            let controller = QLPreviewController()
            controller.dataSource = self
            present(controller, animated: true)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let task = displayedTasks[indexPath.row]
        var actions: [UIContextualAction] = []

        switch task.state {
        case .waiting, .preparing, .downloading, .retrying:
            let pause = UIContextualAction(style: .normal, title: "暂停") { [weak self] _, _, finish in
                self?.perform { manager in try await manager.pauseTask(id: task.id) }
                finish(true)
            }
            pause.backgroundColor = AppColors.warning
            pause.image = UIImage(systemName: "pause")
            actions.append(pause)
        case .paused:
            let resume = UIContextualAction(style: .normal, title: "继续") { [weak self] _, _, finish in
                self?.perform { manager in try await manager.resumeTask(id: task.id) }
                finish(true)
            }
            resume.backgroundColor = AppColors.accent
            resume.image = UIImage(systemName: "play")
            actions.append(resume)
            let restart = UIContextualAction(
                style: .normal,
                title: "重新下载"
            ) { [weak self] _, _, finish in
                self?.confirmRestart(task)
                finish(true)
            }
            restart.backgroundColor = AppColors.secondaryText
            restart.image = UIImage(systemName: "arrow.counterclockwise")
            actions.append(restart)
        case .failed:
            let retry = UIContextualAction(style: .normal, title: "重试") { [weak self] _, _, finish in
                self?.perform { manager in try await manager.retryTask(id: task.id) }
                finish(true)
            }
            retry.backgroundColor = AppColors.accent
            retry.image = UIImage(systemName: "arrow.clockwise")
            actions.append(retry)
        case .finalizing, .completed, .cancelled:
            break
        }

        if task.state != .completed && task.state != .cancelled {
            let cancel = UIContextualAction(style: .destructive, title: "取消") { [weak self] _, _, finish in
                self?.perform { manager in try await manager.cancelTask(id: task.id) }
                finish(true)
            }
            cancel.image = UIImage(systemName: "xmark")
            actions.append(cancel)
        }

        if [.completed, .failed, .cancelled].contains(task.state) {
            let delete = UIContextualAction(
                style: .destructive,
                title: "删除"
            ) { [weak self] _, _, finish in
                self?.confirmDelete(task)
                finish(true)
            }
            delete.image = UIImage(systemName: "trash")
            actions.append(delete)
        }

        guard !actions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func confirmRestart(_ task: DownloadTaskModel) {
        let alert = UIAlertController(
            title: "从头重新下载？",
            message: "已保存的断点数据会被删除，下载将从 0 开始。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重新下载", style: .destructive) {
            [weak self] _ in
            self?.perform { manager in
                try await manager.restartTaskFromBeginning(id: task.id)
            }
        })
        present(alert, animated: true)
    }
}

extension DownloadManagerViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int
    ) -> QLPreviewItem {
        guard let previewURL else {
            preconditionFailure("Quick Look requested without a completed download URL")
        }
        return previewURL as NSURL
    }
}

private final class DownloadTaskCell: UITableViewCell {
    static let reuseIdentifier = "DownloadTaskCell"

    private let cardView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "arrow.down.doc"))
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let sizeLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let indeterminateIndicator = UIActivityIndicatorView(style: .medium)
    private var thumbnailToken: FileThumbnailToken?
    private var posterToken: ResourceThumbnailToken?
    private var representedTaskID: UUID?
    private var representedThumbnailURL: URL?
    private var representedFileURL: URL?
    private var hasArtwork = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailToken?.cancel()
        thumbnailToken = nil
        posterToken?.cancel()
        posterToken = nil
        representedTaskID = nil
        representedThumbnailURL = nil
        representedFileURL = nil
        hasArtwork = false
        iconView.image = nil
    }

    func configure(task: DownloadTaskModel, fileURL: URL?) {
        updateArtworkSourceIfNeeded(for: task, fileURL: fileURL)
        nameLabel.text = task.fileName
        var statusParts = [task.state.localizedTitle]
        if task.state == .failed,
           let reason = task.errorDescription,
           !reason.isEmpty {
            statusParts.append(reason)
        }
        if let speed = task.speedBytesPerSecond, speed > 0 {
            statusParts.append(
                "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/秒"
            )
        }
        if let remaining = task.estimatedRemainingTime,
           remaining.isFinite,
           remaining > 0 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = remaining >= 3_600 ? [.hour, .minute] : [.minute, .second]
            formatter.unitsStyle = .abbreviated
            if let value = formatter.string(from: remaining) {
                statusParts.append("剩余 \(value)")
            }
        }
        statusLabel.text = statusParts.joined(separator: " · ")

        let downloaded = ByteCountFormatter.string(
            fromByteCount: task.downloadedSize,
            countStyle: .file
        )
        if let expected = task.expectedSize, expected > 0 {
            let total = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            sizeLabel.text = "\(downloaded) / \(total)"
        } else {
            sizeLabel.text = "\(downloaded) / 大小未知"
        }

        if let progress = task.progress {
            progressView.isHidden = false
            progressView.progress = Float(progress)
            indeterminateIndicator.stopAnimating()
            accessibilityValue = "\(Int(progress * 100))%"
        } else {
            progressView.isHidden = true
            if task.state == .waiting || task.state.isInProgress {
                indeterminateIndicator.startAnimating()
            } else {
                indeterminateIndicator.stopAnimating()
            }
            accessibilityValue = task.state.localizedTitle
        }

        if !hasArtwork {
            switch task.state {
            case .failed:
                iconView.image = UIImage(systemName: "exclamationmark.circle.fill")
                iconView.tintColor = AppColors.danger
            case .cancelled:
                iconView.image = UIImage(systemName: "xmark.circle")
                iconView.tintColor = AppColors.secondaryText
            case .completed:
                iconView.image = UIImage(systemName: fallbackSymbol(for: task))
                iconView.tintColor = AppColors.accent
            default:
                iconView.image = UIImage(systemName: "arrow.down.doc")
                iconView.tintColor = AppColors.accent
            }
        }
        accessibilityLabel = "\(task.fileName)，\(task.state.localizedTitle)，\(sizeLabel.text ?? "")"
    }

    private func updateArtworkSourceIfNeeded(
        for task: DownloadTaskModel,
        fileURL: URL?
    ) {
        let taskChanged = representedTaskID != task.id
        let sourceChanged = representedThumbnailURL != task.thumbnailURL
            || representedFileURL != fileURL
        guard taskChanged || sourceChanged else { return }

        thumbnailToken?.cancel()
        thumbnailToken = nil
        posterToken?.cancel()
        posterToken = nil
        representedTaskID = task.id
        representedThumbnailURL = task.thumbnailURL
        representedFileURL = fileURL
        if taskChanged {
            hasArtwork = false
            iconView.image = nil
        }

        guard let fileURL else {
            loadPosterIfAvailable(for: task)
            return
        }
        thumbnailToken = FileThumbnailLoader.shared.load(
            fileURL: fileURL,
            size: CGSize(width: 112, height: 112),
            scale: UIScreen.main.scale
        ) { [weak self] image in
            guard let self,
                  self.representedTaskID == task.id,
                  self.representedFileURL == fileURL
            else { return }
            guard let image else {
                if !self.hasArtwork {
                    self.loadPosterIfAvailable(for: task)
                }
                return
            }
            self.hasArtwork = true
            self.iconView.image = image
            self.iconView.tintColor = nil
        }
    }

    private func loadPosterIfAvailable(for task: DownloadTaskModel) {
        guard let url = task.thumbnailURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(task.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        let scale = UIScreen.main.scale
        posterToken = ResourceThumbnailLoader.shared.load(
            ResourceThumbnailRequest(
                resourceID: task.resourceID ?? task.id,
                tabID: task.id,
                request: request,
                // Match the resource sheet's request dimensions so a poster
                // already shown there is reused immediately from cache.
                targetPixelSize: CGSize(width: 80 * scale, height: 64 * scale),
                allowsDiskCache: true
            )
        ) { [weak self] image in
            guard let self,
                  self.representedTaskID == task.id,
                  self.representedThumbnailURL == url,
                  let image
            else { return }
            self.hasArtwork = true
            self.iconView.image = image
            self.iconView.tintColor = nil
        }
    }

    private func fallbackSymbol(for task: DownloadTaskModel) -> String {
        switch task.resourceType {
        case .video, .hls: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }

    private func configureView() {
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24)
        iconView.tintColor = AppColors.accent
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.backgroundColor = AppColors.accentFill
        iconView.layer.cornerRadius = AppRadius.control
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2

        statusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AppColors.secondaryText
        statusLabel.numberOfLines = 2

        sizeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        sizeLabel.adjustsFontForContentSizeCategory = true
        sizeLabel.textColor = AppColors.secondaryText
        sizeLabel.textAlignment = .right

        progressView.progressTintColor = AppColors.accent
        progressView.trackTintColor = AppColors.progressTrack
        indeterminateIndicator.color = AppColors.accent
        indeterminateIndicator.hidesWhenStopped = true

        let statusRow = UIStackView(
            arrangedSubviews: [indeterminateIndicator, statusLabel, sizeLabel]
        )
        statusRow.axis = .horizontal
        statusRow.spacing = 8

        let details = UIStackView(arrangedSubviews: [nameLabel, statusRow, progressView])
        details.axis = .vertical
        details.spacing = 8

        let stack = UIStackView(arrangedSubviews: [iconView, details])
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

            iconView.widthAnchor.constraint(
                equalToConstant: AppMetrics.primaryButtonHeight
            ),
            iconView.heightAnchor.constraint(
                equalToConstant: AppMetrics.primaryButtonHeight
            ),

            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14)
        ])
    }
}
