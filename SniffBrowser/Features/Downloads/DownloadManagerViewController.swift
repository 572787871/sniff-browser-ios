import UIKit

final class DownloadManagerViewController: BaseViewController {
    var onError: ((Error) -> Void)?

    private enum Scope: Int, CaseIterable {
        case all
        case active
        case paused
        case completed

        var title: String {
            switch self {
            case .all: return "全部"
            case .active: return "进行中"
            case .paused: return "已暂停"
            case .completed: return "已完成"
            }
        }

        func includes(_ state: DownloadState) -> Bool {
            switch self {
            case .all: return true
            case .active: return state == .waiting || state == .downloading
            case .paused: return state == .paused
            case .completed: return state == .completed
            }
        }
    }

    private weak var manager: DownloadManaging?
    private var selectedScope = Scope.all
    private var operationTask: Task<Void, Never>?

    private let scopeControl = UISegmentedControl(items: Scope.allCases.map(\.title))
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "arrow.down.circle",
            title: "暂无下载任务",
            message: "从网页资源列表开始下载后，任务状态会显示在这里。"
        )
    )

    private var visibleTasks: [DownloadTaskModel] {
        guard let tasks = manager?.tasks else { return [] }
        return tasks
            .filter { selectedScope.includes($0.state) }
            .sorted { $0.updatedAt > $1.updatedAt }
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
        updateContent()
        reloadTasks()
    }

    func updateContent() {
        guard isViewLoaded else { return }
        tableView.reloadData()
        let isEmpty = visibleTasks.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            operationTask?.cancel()
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
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 30),
            emptyState.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            emptyState.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12)
        ])
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
                    self?.onError?(error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
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
        visibleTasks.count
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
        cell.configure(task: visibleTasks[indexPath.row])
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let task = visibleTasks[indexPath.row]
        var actions: [UIContextualAction] = []

        switch task.state {
        case .waiting, .downloading:
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
        case .failed:
            let retry = UIContextualAction(style: .normal, title: "重试") { [weak self] _, _, finish in
                self?.perform { manager in try await manager.retryTask(id: task.id) }
                finish(true)
            }
            retry.backgroundColor = AppColors.accent
            retry.image = UIImage(systemName: "arrow.clockwise")
            actions.append(retry)
        case .completed, .cancelled:
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

        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(task: DownloadTaskModel) {
        nameLabel.text = task.fileName
        statusLabel.text = task.state.localizedTitle

        let downloaded = ByteCountFormatter.string(
            fromByteCount: task.downloadedSize,
            countStyle: .file
        )
        if let expected = task.expectedSize {
            let total = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            sizeLabel.text = "\(downloaded) / \(total)"
        } else {
            sizeLabel.text = downloaded
        }

        if let progress = task.progress {
            progressView.isHidden = false
            progressView.progress = Float(progress)
            accessibilityValue = "\(Int(progress * 100))%"
        } else {
            progressView.isHidden = true
            accessibilityValue = task.state.localizedTitle
        }

        switch task.state {
        case .completed:
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            iconView.tintColor = AppColors.success
        case .failed:
            iconView.image = UIImage(systemName: "exclamationmark.circle.fill")
            iconView.tintColor = AppColors.danger
        default:
            iconView.image = UIImage(systemName: "arrow.down.doc")
            iconView.tintColor = AppColors.accent
        }
        accessibilityLabel = "\(task.fileName)，\(task.state.localizedTitle)，\(sizeLabel.text ?? "")"
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
        iconView.contentMode = .center
        iconView.backgroundColor = AppColors.accentFill
        iconView.layer.cornerRadius = AppRadius.control
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2

        statusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AppColors.secondaryText

        sizeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        sizeLabel.adjustsFontForContentSizeCategory = true
        sizeLabel.textColor = AppColors.secondaryText
        sizeLabel.textAlignment = .right

        progressView.progressTintColor = AppColors.accent
        progressView.trackTintColor = AppColors.progressTrack

        let statusRow = UIStackView(arrangedSubviews: [statusLabel, sizeLabel])
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
