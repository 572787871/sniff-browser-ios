import AVFoundation
import AVKit
import QuickLook
import UIKit

@MainActor
final class FileManagerViewController: BaseViewController {
    enum Category: Int, CaseIterable {
        case all, video, audio, image, document

        var title: String {
            switch self {
            case .all: return "全部"
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            case .document: return "文档"
            }
        }

        func includes(_ task: DownloadTaskModel) -> Bool {
            switch self {
            case .all: return true
            case .video: return task.resourceType == .video || task.resourceType == .hls
            case .audio: return task.resourceType == .audio
            case .image: return task.resourceType == .image
            case .document:
                return [.document, .subtitle, .archive, .other]
                    .contains(task.resourceType)
            }
        }
    }

    enum SortOrder { case name, date, size }

    var onImportFiles: (() -> Void)?
    var onCreateFolder: (() -> Void)?
    var onReturnToBrowser: (() -> Void)? {
        didSet { updateEmptyState() }
    }
    var onSortOrderChanged: ((SortOrder) -> Void)?

    private let downloadCenter: DownloadCenter
    private let searchController = UISearchController(searchResultsController: nil)
    private let categoryControl = UISegmentedControl(items: Category.allCases.map(\.title))
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView(configuration: .init(
        symbolName: "folder",
        title: "文件库为空",
        message: "下载完成的文件会安全地保存在应用资料库中，并按类型整理。",
        actionTitle: nil,
        secondaryActionTitle: "前往浏览器"
    ))
    private var selectedCategory = Category.all
    private var sortOrder = SortOrder.date
    private var searchText = ""
    private var observer: NSObjectProtocol?
    private var previewDataSource: FilePreviewDataSource?

    private var visibleTasks: [DownloadTaskModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = downloadCenter.tasks.filter {
            $0.state == .completed
                && selectedCategory.includes($0)
                && (query.isEmpty || $0.fileName.localizedCaseInsensitiveContains(query))
                && downloadCenter.fileURL(for: $0.id) != nil
        }
        return values.sorted { lhs, rhs in
            switch sortOrder {
            case .name:
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            case .date:
                return (lhs.completedAt ?? lhs.updatedAt) > (rhs.completedAt ?? rhs.updatedAt)
            case .size:
                return lhs.downloadedSize > rhs.downloadedSize
            }
        }
    }

    init(downloadCenter: DownloadCenter) {
        self.downloadCenter = downloadCenter
        super.init(title: "文件", prefersLargeTitle: true)
    }

    convenience init() {
        self.init(downloadCenter: .shared)
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureContent()
        observer = NotificationCenter.default.addObserver(
            forName: .downloadTasksDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadContent() }
        }
        Task { [weak self] in
            await self?.downloadCenter.reloadTasks()
            self?.reloadContent()
        }
    }

    func setSortOrder(_ order: SortOrder) {
        sortOrder = order
        reloadContent()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索文件"
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down"),
            menu: UIMenu(title: "排序方式", options: .singleSelection, children: [
                sortAction("名称", .name),
                sortAction("日期", .date, selected: true),
                sortAction("大小", .size)
            ])
        )
    }

    private func configureContent() {
        categoryControl.selectedSegmentIndex = 0
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(categoryControl)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 104
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(FileLibraryCell.self, forCellReuseIdentifier: FileLibraryCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)

        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            categoryControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            categoryControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyState.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        updateEmptyState()
    }

    private func sortAction(_ title: String, _ order: SortOrder, selected: Bool = false) -> UIAction {
        UIAction(title: title, state: selected ? .on : .off) { [weak self] _ in
            self?.setSortOrder(order)
            self?.onSortOrderChanged?(order)
        }
    }

    private func reloadContent() {
        tableView.reloadData()
        let empty = visibleTasks.isEmpty
        tableView.isHidden = empty
        emptyState.isHidden = !empty
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard isViewLoaded else { return }
        emptyState.configure(
            .init(
                symbolName: "folder",
                title: searchText.isEmpty ? "文件库为空" : "没有匹配的文件",
                message: searchText.isEmpty
                    ? "下载完成的文件会安全地保存在应用资料库中，并按类型整理。"
                    : "请尝试其他关键词或文件类型。",
                actionTitle: nil,
                secondaryActionTitle: searchText.isEmpty ? "前往浏览器" : nil
            ),
            action: nil,
            secondaryAction: onReturnToBrowser
        )
    }

    @objc private func categoryChanged() {
        selectedCategory = Category(rawValue: categoryControl.selectedSegmentIndex) ?? .all
        reloadContent()
    }

    private func open(_ task: DownloadTaskModel) {
        guard let url = downloadCenter.fileURL(for: task.id) else { return }
        if task.downloadKind == .hlsAsset || [.video, .audio].contains(task.resourceType) {
            Task { [weak self] in
                do {
                    let playbackURL = url.pathExtension.lowercased() == "sniffhls"
                        ? try await HLSLocalPlaybackServer.shared.playbackURL(for: url)
                        : url
                    guard let self else { return }
                    let player = AVPlayerViewController()
                    player.player = AVPlayer(url: playbackURL)
                    self.present(player, animated: true) { player.player?.play() }
                } catch {
                    self?.presentError(error)
                }
            }
        } else {
            let source = FilePreviewDataSource(url: url)
            previewDataSource = source
            let preview = QLPreviewController()
            preview.dataSource = source
            present(preview, animated: true)
        }
    }

    private func share(_ task: DownloadTaskModel) {
        guard let url = downloadCenter.fileURL(for: task.id) else { return }
        // For HLS video packages, offer to merge into a single MP4 before sharing
        if url.pathExtension.lowercased() == "sniffhls" {
            let alert = UIAlertController(
                title: "导出视频",
                message: "可选择将视频片段合并为单个 MP4 文件后再导出，或直接导出原始包。",
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "合并为 MP4 并导出", style: .default) { [weak self] _ in
                self?.mergeAndShareHLSVideo(packageURL: url, fileName: task.fileName)
            })
            alert.addAction(UIAlertAction(title: "直接导出原始包", style: .default) { _ in
                present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            // For iPad: set popover source
            if let popover = alert.popoverPresentationController,
               let sourceView = navigationController?.view {
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            present(alert, animated: true)
            return
        }
        present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }

    private func mergeAndShareHLSVideo(packageURL: URL, fileName: String) {
        let playlistURL = packageURL.appendingPathComponent("index.m3u8")
        guard FileManager.default.fileExists(atPath: playlistURL.path) else {
            let alert = UIAlertController(title: "无法合并", message: "视频包数据不完整。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        let loadingAlert = UIAlertController(title: "正在合并视频…", message: "请稍候，正在将视频片段合并为 MP4 文件。", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let asset = AVAsset(url: playlistURL)
                guard let exportSession = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    loadingAlert.dismiss(animated: true) {
                        self.showMergeError()
                    }
                    return
                }
                let tempDir = FileManager.default.temporaryDirectory
                let safeName = (fileName as NSString).deletingPathExtension
                let outputURL = tempDir.appendingPathComponent("\(safeName).mp4")
                // Remove any existing file at the output path
                try? FileManager.default.removeItem(at: outputURL)

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mp4
                exportSession.shouldOptimizeForNetworkUse = true

                await exportSession.export()
                loadingAlert.dismiss(animated: true)

                guard exportSession.status == .completed else {
                    // Passthrough may fail for some codecs; fall back to highest quality
                    if exportSession.status == .failed || exportSession.status == .cancelled {
                        try? FileManager.default.removeItem(at: outputURL)
                        self.fallbackMergeAndShare(asset: asset, outputURL: outputURL, fileName: fileName)
                        return
                    }
                    self.showMergeError()
                    return
                }
                let activityVC = UIActivityViewController(
                    activityItems: [outputURL],
                    applicationActivities: nil
                )
                activityVC.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: outputURL)
                }
                if let popover = activityVC.popoverPresentationController,
                   let sourceView = self.navigationController?.view {
                    popover.sourceView = sourceView
                    popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                self.present(activityVC, animated: true)
            } catch {
                loadingAlert.dismiss(animated: true) {
                    self.showMergeError()
                }
            }
        }
    }

    private func fallbackMergeAndShare(asset: AVAsset, outputURL: URL, fileName: String) {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            showMergeError()
            return
        }
        let loadingAlert = UIAlertController(title: "正在合并视频…", message: "高质量转码中，可能需要较长时间。", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: outputURL)
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            await exportSession.export()

            loadingAlert.dismiss(animated: true)
            guard exportSession.status == .completed else {
                self.showMergeError()
                return
            }
            let activityVC = UIActivityViewController(
                activityItems: [outputURL],
                applicationActivities: nil
            )
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: outputURL)
            }
            if let popover = activityVC.popoverPresentationController,
               let sourceView = self.navigationController?.view {
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            self.present(activityVC, animated: true)
        }
    }

    private func showMergeError() {
        let alert = UIAlertController(
            title: "合并失败",
            message: "无法将视频片段合并为 MP4 文件，请尝试直接导出原始包。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func promptRename(_ task: DownloadTaskModel) {
        let alert = UIAlertController(title: "重命名", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = (task.fileName as NSString).deletingPathExtension }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            do { try self.downloadCenter.renameCompletedTask(id: task.id, to: text) }
            catch { self.presentError(error) }
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ task: DownloadTaskModel) {
        let alert = UIAlertController(
            title: "删除文件？",
            message: "文件和下载记录都会被删除，此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            Task { [weak self] in
                do { try await self?.downloadCenter.deleteTask(id: task.id, deleteFile: true) }
                catch { self?.presentError(error) }
            }
        })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "无法完成操作", message: DownloadErrorMapper.message(for: error), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension FileManagerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        reloadContent()
    }
}

extension FileManagerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleTasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: FileLibraryCell.reuseID,
            for: indexPath
        ) as? FileLibraryCell else { return UITableViewCell() }
        let task = visibleTasks[indexPath.row]
        cell.configure(task: task, fileURL: downloadCenter.fileURL(for: task.id))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(visibleTasks[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let task = visibleTasks[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "打开", image: UIImage(systemName: "play")) { _ in self?.open(task) },
                UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in self?.share(task) },
                UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { _ in self?.promptRename(task) },
                UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.confirmDelete(task) }
            ])
        })
    }
}

private final class FileLibraryCell: UITableViewCell {
    static let reuseID = "FileLibraryCell"
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private var thumbnailToken: FileThumbnailToken?
    private var posterToken: ResourceThumbnailToken?
    private var representedID: UUID?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = AppColors.surface
        contentView.layer.cornerRadius = AppRadius.card
        contentView.layer.cornerCurve = .continuous

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = AppRadius.control
        thumbnailView.backgroundColor = AppColors.accentFill
        thumbnailView.tintColor = AppColors.accent
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 2
        metadataLabel.font = .preferredFont(forTextStyle: .caption1)
        metadataLabel.textColor = AppColors.secondaryText
        metadataLabel.numberOfLines = 2
        let labels = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        labels.axis = .vertical
        labels.spacing = 5
        labels.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailView)
        contentView.addSubview(labels)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 72),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),
            labels.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailToken?.cancel()
        thumbnailToken = nil
        posterToken?.cancel()
        posterToken = nil
        representedID = nil
        thumbnailView.image = nil
    }

    func configure(task: DownloadTaskModel, fileURL: URL?) {
        representedID = task.id
        titleLabel.text = task.fileName
        let size = ByteCountFormatter.string(fromByteCount: task.downloadedSize, countStyle: .file)
        let date = (task.completedAt ?? task.updatedAt).formatted(date: .abbreviated, time: .shortened)
        metadataLabel.text = "\(task.downloadKind == .hlsAsset ? "视频" : task.resourceType.localizedTitle) · \(size)\n\(date)"
        thumbnailView.image = UIImage(systemName: symbol(for: task))
        loadPosterIfAvailable(for: task)
        guard let fileURL else { return }
        thumbnailToken = FileThumbnailLoader.shared.load(
            fileURL: fileURL,
            size: CGSize(width: 144, height: 128),
            scale: UIScreen.main.scale
        ) { [weak self] image in
            guard let self, self.representedID == task.id, let image else { return }
            self.thumbnailView.image = image
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
                // Reuse the exact thumbnail cached by ResourceItemCell.
                targetPixelSize: CGSize(width: 80 * scale, height: 64 * scale),
                allowsDiskCache: true
            )
        ) { [weak self] image in
            guard let self,
                  self.representedID == task.id,
                  let image
            else { return }
            self.thumbnailView.image = image
        }
    }

    private func symbol(for task: DownloadTaskModel) -> String {
        if task.downloadKind == .hlsAsset { return "play.rectangle.on.rectangle" }
        switch task.resourceType {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        case .hls: return "play.rectangle.on.rectangle"
        case .other: return "doc"
        }
    }
}

private final class FilePreviewDataSource: NSObject, QLPreviewControllerDataSource {
    let url: URL
    init(url: URL) { self.url = url }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        url as NSURL
    }
}
