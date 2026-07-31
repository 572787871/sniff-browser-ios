import UIKit

final class FileManagerViewController: BaseViewController {
    enum Category: Int, CaseIterable {
        case all
        case video
        case audio
        case image
        case document

        var title: String {
            switch self {
            case .all: return "全部"
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            case .document: return "文档"
            }
        }
    }

    enum SortOrder {
        case name
        case date
        case size
    }

    var onImportFiles: (() -> Void)? {
        didSet { refreshAvailableActions() }
    }
    var onCreateFolder: (() -> Void)? {
        didSet { refreshAvailableActions() }
    }
    var onReturnToBrowser: (() -> Void)? {
        didSet { updateEmptyStateActions() }
    }
    var onSortOrderChanged: ((SortOrder) -> Void)? {
        didSet { refreshAvailableActions() }
    }

    private let searchController = UISearchController(searchResultsController: nil)
    private let categoryControl = UISegmentedControl(items: Category.allCases.map(\.title))
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "folder",
            title: "文件库为空",
            message: "下载完成的文件会安全地保存在应用资料库中，并按类型整理。",
            actionTitle: "从“文件”导入",
            secondaryActionTitle: "前往浏览器"
        )
    )

    init() {
        super.init(title: "文件", prefersLargeTitle: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureCategoryControl()
        configureEmptyState()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索文件或文件夹"
        searchController.searchBar.accessibilityLabel = "搜索文件"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        updateNavigationActions()
    }

    private func updateNavigationActions() {
        var items: [UIBarButtonItem] = []
        if onCreateFolder != nil || onImportFiles != nil {
            let actionsItem = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: makeActionsMenu()
            )
            actionsItem.accessibilityLabel = "文件操作"
            items.append(actionsItem)
        }
        if onSortOrderChanged != nil {
            let sortItem = UIBarButtonItem(
                image: UIImage(systemName: "arrow.up.arrow.down"),
                menu: makeSortMenu()
            )
            sortItem.accessibilityLabel = "文件排序"
            items.append(sortItem)
        }
        navigationItem.rightBarButtonItems = items.isEmpty ? nil : items
    }

    private func configureCategoryControl() {
        categoryControl.selectedSegmentIndex = Category.all.rawValue
        categoryControl.accessibilityLabel = "文件类型"
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(categoryControl)

        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            categoryControl.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            categoryControl.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(
                equalTo: categoryControl.bottomAnchor,
                constant: AppSpacing.xs
            ),
            emptyState.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        updateEmptyStateActions()
    }

    private func refreshAvailableActions() {
        updateEmptyStateActions()
        guard isViewLoaded else { return }
        updateNavigationActions()
    }

    private func updateEmptyStateActions() {
        emptyState.configure(
            .init(
                symbolName: "folder",
                title: "文件库为空",
                message: "下载完成的文件会安全地保存在应用资料库中，并按类型整理。",
                actionTitle: "从“文件”导入",
                secondaryActionTitle: "前往浏览器"
            ),
            action: actionWithFeedback(onImportFiles),
            secondaryAction: actionWithFeedback(onReturnToBrowser)
        )
    }

    private func actionWithFeedback(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }

    private func makeActionsMenu() -> UIMenu {
        let createFolder = UIAction(
            title: "新建文件夹",
            image: UIImage(systemName: "folder.badge.plus"),
            attributes: onCreateFolder == nil ? [.disabled] : []
        ) { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.onCreateFolder?()
        }
        let importFiles = UIAction(
            title: "从“文件”导入",
            image: UIImage(systemName: "square.and.arrow.down"),
            attributes: onImportFiles == nil ? [.disabled] : []
        ) { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.onImportFiles?()
        }
        return UIMenu(children: [createFolder, importFiles])
    }

    private func makeSortMenu() -> UIMenu {
        UIMenu(title: "排序方式", options: .singleSelection, children: [
            sortAction(title: "名称", symbol: "textformat", order: .name, isSelected: true),
            sortAction(title: "日期", symbol: "calendar", order: .date),
            sortAction(title: "大小", symbol: "internaldrive", order: .size)
        ])
    }

    private func sortAction(
        title: String,
        symbol: String,
        order: SortOrder,
        isSelected: Bool = false
    ) -> UIAction {
        UIAction(
            title: title,
            image: UIImage(systemName: symbol),
            attributes: onSortOrderChanged == nil ? [.disabled] : [],
            state: isSelected ? .on : .off
        ) { [weak self] _ in
            self?.onSortOrderChanged?(order)
        }
    }
}
