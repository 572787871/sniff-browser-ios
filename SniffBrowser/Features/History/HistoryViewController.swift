import UIKit

final class HistoryViewController: BaseViewController {
    var onStartBrowsing: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }
    var onOpenPrivateTab: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }
    var onOpenHistoryItem: ((HistoryItem) -> Void)?

    private let viewModel = HistoryViewModel()
    private let searchController = UISearchController(searchResultsController: nil)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "clock.arrow.circlepath",
            title: "暂无浏览记录",
            message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。",
            actionTitle: "开始浏览",
            secondaryActionTitle: "新建无痕标签"
        )
    )

    init() {
        super.init(title: "历史记录", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureTable()
        configureEmptyState()
        bindViewModel()
        viewModel.reload()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索网页标题或网址"
        searchController.searchBar.accessibilityLabel = "搜索历史记录"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updateNavigationActions()
    }

    private func updateNavigationActions() {
        let clearAction = UIAction(
            title: "清除浏览记录",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive]
        ) { [weak self] _ in
            self?.confirmClearHistory()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [clearAction])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "历史记录更多操作"
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = AppColors.separator
        tableView.separatorInset = UIEdgeInsets(
            top: 0,
            left: AppSpacing.sm + AppMetrics.primaryButtonHeight + AppSpacing.sm,
            bottom: 0,
            right: AppSpacing.sm
        )
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: AppSpacing.xl,
            right: 0
        )
        tableView.register(
            HistoryCell.self,
            forCellReuseIdentifier: HistoryCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "history.list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        updateEmptyStateActions()
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
        viewModel.onError = { [weak self] error in
            self?.showPersistenceError(error)
        }
    }

    private func render(_ state: HistoryViewState) {
        tableView.reloadData()
        let isEmpty = state.sections.isEmpty
        tableView.isHidden = isEmpty
        emptyState.isHidden = !isEmpty
        guard isEmpty else { return }

        if state.isFiltering {
            emptyState.configure(
                .init(
                    symbolName: "magnifyingglass",
                    title: "未找到记录",
                    message: "没有与“\(state.searchQuery)”匹配的标题或网址。",
                    actionTitle: "清除搜索"
                ),
                action: { [weak self] in
                    self?.searchController.searchBar.text = nil
                    self?.viewModel.updateSearchQuery("")
                }
            )
        } else {
            updateEmptyStateActions()
        }
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    private func updateEmptyStateActions() {
        emptyState.configure(
            .init(
                symbolName: "clock.arrow.circlepath",
                title: "暂无浏览记录",
                message: "访问过的网页会按日期整理在这里；无痕标签页不会留下记录。",
                actionTitle: onStartBrowsing == nil ? nil : "开始浏览",
                secondaryActionTitle: onOpenPrivateTab == nil ? nil : "新建无痕标签"
            ),
            action: actionWithFeedback(onStartBrowsing),
            secondaryAction: actionWithFeedback(onOpenPrivateTab)
        )
    }

    private func confirmClearHistory() {
        let alert = UIAlertController(
            title: "清除全部历史记录？",
            message: "此操作会删除已保存的网页访问记录，且无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
                guard let self, self.viewModel.clearAll() else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        )
        present(alert, animated: true)
    }

    private func showPersistenceError(_ error: Error) {
        guard view.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "无法更新历史记录",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension HistoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.updateSearchQuery(searchController.searchBar.text ?? "")
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.state.sections.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        viewModel.state.sections[section].title
    }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        viewModel.state.sections[section].items.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: HistoryCell.reuseIdentifier,
            for: indexPath
        ) as? HistoryCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.state.sections[indexPath.section].items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onOpenHistoryItem?(
            viewModel.state.sections[indexPath.section].items[indexPath.row]
        )
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = viewModel.state.sections[indexPath.section].items[indexPath.row]
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "删除"
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            let removed = self.viewModel.remove(item)
            if removed {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            completion(removed)
        }
        deleteAction.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

private final class HistoryCell: UITableViewCell {
    static let reuseIdentifier = "HistoryCell"

    private let symbolContainer = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let timeLabel = UILabel()
    private let textStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(with item: HistoryItem) {
        titleLabel.text = item.title
        hostLabel.text = item.host
        timeLabel.text = Self.timeFormatter.string(from: item.visitedAt)
        accessibilityLabel =
            "\(item.title)，\(item.host)，\(timeLabel.text ?? "")"
    }

    private func configureView() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = AppColors.surface
        backgroundConfiguration = background
        selectionStyle = .default

        symbolContainer.backgroundColor = AppColors.accentFill
        symbolContainer.layer.cornerRadius = AppRadius.small
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false

        symbolView.image = UIImage(systemName: "clock.arrow.circlepath")
        symbolView.tintColor = AppColors.accent
        symbolView.contentMode = .scaleAspectFit
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.addSubview(symbolView)

        AppTypography.configure(titleLabel, style: .body, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 2

        AppTypography.configure(hostLabel, style: .subheadline)
        hostLabel.textColor = AppColors.secondaryText
        hostLabel.numberOfLines = 1
        hostLabel.lineBreakMode = .byTruncatingMiddle

        AppTypography.configure(timeLabel, style: .caption1)
        timeLabel.textColor = AppColors.tertiaryText
        timeLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = AppSpacing.xxs
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(hostLabel)
        textStack.addArrangedSubview(timeLabel)

        contentView.addSubview(symbolContainer)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            symbolContainer.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor
            ),
            symbolContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolContainer.widthAnchor.constraint(equalToConstant: 40),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor),

            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 20),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),

            textStack.topAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.topAnchor
            ),
            textStack.leadingAnchor.constraint(
                equalTo: symbolContainer.trailingAnchor,
                constant: AppSpacing.sm
            ),
            textStack.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            textStack.bottomAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.bottomAnchor
            ),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
