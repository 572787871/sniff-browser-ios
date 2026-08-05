import UIKit

/// 默认搜索引擎选择页，选择结果立即持久化并用于地址栏与新标签页搜索。
final class SearchEngineSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let preferences = BrowserPreferences()

    private var options: [SearchEngine] {
        SearchEngine.allCases
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "默认搜索引擎"
        configureTableView()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.register(
            SettingsCheckmarkCell.self,
            forCellReuseIdentifier: SettingsCheckmarkCell.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

extension SearchEngineSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "在地址栏或新标签页输入搜索词时，将使用所选搜索引擎。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsCheckmarkCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsCheckmarkCell else {
            return UITableViewCell()
        }
        let option = options[indexPath.row]
        cell.configure(
            title: option.displayName,
            symbol: "magnifyingglass",
            isSelected: option == preferences.searchEngine
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = options[indexPath.row]
        guard option != preferences.searchEngine else { return }
        preferences.searchEngine = option
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
