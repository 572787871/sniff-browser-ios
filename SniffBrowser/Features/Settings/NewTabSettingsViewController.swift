import PhotosUI
import UIKit

/// 新标签页设置页，控制新标签页上显示的信息。
final class NewTabSettingsViewController: BaseViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let preferences = BrowserPreferences()
    private let backgroundStore = NewTabBackgroundStore.shared

    private enum Section: Int, CaseIterable {
        case content
        case background
    }

    private enum ContentRow: Int, CaseIterable {
        case welcome
        case date
    }

    private enum BackgroundRow {
        case choose
        case remove
    }

    private var backgroundRows: [BackgroundRow] {
        backgroundStore.hasImage ? [.choose, .remove] : [.choose]
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
        tableView.register(
            GlassSummaryCell.self,
            forCellReuseIdentifier: GlassSummaryCell.reuseIdentifier
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
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .content: return ContentRow.allCases.count
        case .background: return backgroundRows.count
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .content: return "新标签页内容"
        case .background: return "主页背景"
        case nil: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .content:
            return "新标签页保持轻量、无广告，这些选项只控制页面上显示的信息。"
        case .background:
            return "所选照片会压缩后保存在本机应用沙盒中，不会上传。"
        case nil:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .background {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GlassSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? GlassSummaryCell else {
                return UITableViewCell()
            }
            switch backgroundRows[indexPath.row] {
            case .choose:
                cell.configure(
                    title: backgroundStore.hasImage ? "更换背景照片" : "选择背景照片",
                    subtitle: backgroundStore.hasImage ? "当前已设置自定义主页背景" : "从系统照片选择器选取",
                    symbol: "photo.on.rectangle.angled",
                    tint: AppColors.accent
                )
                cell.accessibilityIdentifier = "newTab.background.choose"
            case .remove:
                cell.configure(
                    title: "移除背景照片",
                    subtitle: "恢复默认纸张背景",
                    symbol: "photo.badge.minus",
                    tint: AppColors.danger,
                    titleColor: AppColors.danger
                )
                cell.accessibilityIdentifier = "newTab.background.remove"
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsToggleCell.reuseIdentifier,
            for: indexPath
        ) as? SettingsToggleCell else {
            return UITableViewCell()
        }
        guard let row = ContentRow(rawValue: indexPath.row) else { return cell }
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .background else { return }
        switch backgroundRows[indexPath.row] {
        case .choose:
            presentBackgroundPicker()
        case .remove:
            removeBackgroundPhoto()
        }
    }

    private func presentBackgroundPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func removeBackgroundPhoto() {
        do {
            try backgroundStore.remove()
            tableView.reloadSections(IndexSet(integer: Section.background.rawValue), with: .automatic)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            presentBackgroundError(message: "无法移除背景照片，请稍后重试。")
        }
    }

    private func presentBackgroundError(message: String) {
        let alert = UIAlertController(
            title: "背景照片未更新",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension NewTabSettingsViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            presentBackgroundError(message: "无法读取所选照片，请选择另一张图片。")
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let image = object as? UIImage else {
                    self.presentBackgroundError(message: "无法读取所选照片，请选择另一张图片。")
                    return
                }
                do {
                    try self.backgroundStore.save(image)
                    self.tableView.reloadSections(
                        IndexSet(integer: Section.background.rawValue),
                        with: .automatic
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    self.presentBackgroundError(message: "照片保存失败，请检查设备存储空间。")
                }
            }
        }
    }
}
