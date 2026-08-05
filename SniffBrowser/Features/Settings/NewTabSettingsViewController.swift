import UIKit

/// 新标签页设置页，控制新标签页上显示的信息。
final class NewTabSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let preferences = BrowserPreferences()

    private enum Row: Int, CaseIterable {
        case welcome
        case date
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "新标签页"
        configureTableView()
    }

    private func configureTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.register(
            SettingsToggleCell.self,
            forCellReuseIdentifier: SettingsToggleCell.reuseIdentifier
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

extension NewTabSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "新标签页内容"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "新标签页保持轻量、无广告，这些选项只控制页面上显示的信息。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsToggleCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsToggleCell else {
            return UITableViewCell()
        }
        guard let row = Row(rawValue: indexPath.row) else { return cell }
        switch row {
        case .welcome:
            cell.configure(
                title: "显示问候语",
                subtitle: "在新标签页顶部显示欢迎文字",
                symbol: "text.bubble",
                isOn: preferences.newTabShowsWelcome,
                accessibilityIdentifier: "newTab.showWelcome"
            ) { [weak self] enabled in
                self?.preferences.newTabShowsWelcome = enabled
            }
        case .date:
            cell.configure(
                title: "显示日期",
                subtitle: "在新标签页显示今天的日期",
                symbol: "calendar",
                isOn: preferences.newTabShowsDate,
                accessibilityIdentifier: "newTab.showDate"
            ) { [weak self] enabled in
                self?.preferences.newTabShowsDate = enabled
            }
        }
        return cell
    }
}
