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

    var onImportFiles: (() -> Void)?
    var onCreateFolder: (() -> Void)?
    var onSortOrderChanged: ((SortOrder) -> Void)?

    private let searchController = UISearchController(searchResultsController: nil)
    private let categoryControl = UISegmentedControl(items: Category.allCases.map(\.title))
    private let emptyState = EmptyStateView(
        configuration: .init(
            symbolName: "folder",
            title: "文件库为空",
            message: "下载完成的文件会安全地保存在应用资料库中，并按类型整理。"
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

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: makeActionsMenu()
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "arrow.up.arrow.down"),
                menu: makeSortMenu()
            )
        ]
        navigationItem.rightBarButtonItems?.first?.accessibilityLabel = "文件操作"
        navigationItem.rightBarButtonItems?.last?.accessibilityLabel = "文件排序"
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
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 28),
            emptyState.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            emptyState.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12)
        ])
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
