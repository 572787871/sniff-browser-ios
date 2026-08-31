import PhotosUI
import SwiftUI
import UIKit

/// 新标签页设置页，控制新标签页上显示的信息。
final class NewTabSettingsViewController: BaseViewController {
    private let backgroundStore = NewTabBackgroundStore.shared
    private let swiftUIStore = NewTabSettingsSwiftUIStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "新标签页"
        installSwiftUI(
            NewTabSettingsSwiftUIScreen(
                store: swiftUIStore,
                onShowGallery: { [weak self] in
                    guard let self else { return }
                    self.navigationController?.pushViewController(
                        NewTabBackgroundGalleryViewController(store: self.backgroundStore),
                        animated: true
                    )
                },
                onChoosePhoto: { [weak self] in
                    self?.presentBackgroundPicker()
                },
                onRemovePhoto: { [weak self] in
                    self?.removeBackgroundPhoto()
                }
            ),
            in: contentView
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        swiftUIStore.refresh()
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
            swiftUIStore.refresh()
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
                    self.swiftUIStore.refresh()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    self.presentBackgroundError(message: "照片保存失败，请检查设备存储空间。")
                }
            }
        }
    }
}

@MainActor
private final class NewTabBackgroundGalleryViewController:
    BaseViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout {
    private enum Item: Hashable {
        case defaultPaper
        case preset(NewTabBackgroundPreset)
        case custom

        var selection: NewTabBackgroundSelection {
            switch self {
            case .defaultPaper: return .none
            case let .preset(preset): return .preset(preset)
            case .custom: return .custom
            }
        }

        var title: String { selection.title }
    }

    private let store: NewTabBackgroundStore
    private let collectionView: UICollectionView

    private var items: [Item] {
        var values: [Item] = [.defaultPaper]
        values.append(contentsOf: NewTabBackgroundPreset.allCases.map(Item.preset))
        if store.hasCustomImage {
            values.append(.custom)
        }
        return values
    }

    init(store: NewTabBackgroundStore) {
        self.store = store
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = AppSpacing.sm
        layout.minimumLineSpacing = AppSpacing.lg
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(title: "主页背景", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCollectionView()
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset = UIEdgeInsets(
            top: AppSpacing.md,
            left: AppSpacing.lg,
            bottom: AppSpacing.xxl,
            right: AppSpacing.lg
        )
        collectionView.register(
            NewTabBackgroundOptionCell.self,
            forCellWithReuseIdentifier: NewTabBackgroundOptionCell.reuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: NewTabBackgroundOptionCell.reuseIdentifier,
            for: indexPath
        ) as? NewTabBackgroundOptionCell else {
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        let image = store.previewImage(
            for: item.selection,
            size: CGSize(width: 240, height: 320)
        )
        cell.configure(
            title: item.title,
            image: image,
            isDefault: item == .defaultPaper,
            isSelected: store.selection == item.selection
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let item = items[indexPath.item]
        switch item {
        case .defaultPaper:
            store.selectDefault()
        case let .preset(preset):
            store.selectPreset(preset)
        case .custom:
            _ = store.selectCustomImage()
        }
        collectionView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let usableWidth = collectionView.bounds.width
            - collectionView.contentInset.left
            - collectionView.contentInset.right
            - AppSpacing.sm
        return CGSize(width: max(1, floor(usableWidth / 2)), height: 236)
    }
}

private final class NewTabBackgroundOptionCell: UICollectionViewCell {
    static let reuseIdentifier = "NewTabBackgroundOptionCell"

    private let previewView = UIImageView()
    private let defaultSymbolView = UIImageView(
        image: UIImage(systemName: "doc.plaintext")
    )
    private let checkmarkView = UIImageView(
        image: UIImage(systemName: "checkmark.circle.fill")
    )
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        image: UIImage?,
        isDefault: Bool,
        isSelected: Bool
    ) {
        titleLabel.text = title
        previewView.image = image
        previewView.backgroundColor = isDefault ? AppColors.background : AppColors.tertiarySurface
        defaultSymbolView.isHidden = !isDefault
        checkmarkView.isHidden = !isSelected
        previewView.layer.borderWidth = isSelected ? 2 : AppMetrics.separatorHeight
        previewView.layer.borderColor = (
            isSelected ? AppColors.accent : AppColors.separator
        ).resolvedColor(with: traitCollection).cgColor
        accessibilityLabel = title
        accessibilityValue = isSelected ? "已选择" : nil
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }

    override var isHighlighted: Bool {
        didSet {
            let updates = {
                self.contentView.transform = self.isHighlighted
                    && !UIAccessibility.isReduceMotionEnabled
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                    : .identity
                self.contentView.alpha = self.isHighlighted ? 0.76 : 1
            }
            guard !UIAccessibility.isReduceMotionEnabled else {
                updates()
                return
            }
            UIView.animate(
                withDuration: 0.14,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: updates
            )
        }
    }

    private func configureView() {
        isAccessibilityElement = true
        contentView.layer.cornerCurve = .continuous

        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = AppRadius.card
        previewView.layer.cornerCurve = .continuous
        previewView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewView)

        defaultSymbolView.tintColor = AppColors.tertiaryText
        defaultSymbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 30,
            weight: .light
        )
        defaultSymbolView.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(defaultSymbolView)

        checkmarkView.tintColor = AppColors.accent
        checkmarkView.backgroundColor = AppColors.surface
        checkmarkView.layer.cornerRadius = 11
        checkmarkView.clipsToBounds = true
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(checkmarkView)

        AppTypography.configure(titleLabel, style: .subheadline, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewView.heightAnchor.constraint(equalToConstant: 198),

            defaultSymbolView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            defaultSymbolView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            checkmarkView.topAnchor.constraint(equalTo: previewView.topAnchor, constant: AppSpacing.sm),
            checkmarkView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -AppSpacing.sm),
            checkmarkView.widthAnchor.constraint(equalToConstant: 22),
            checkmarkView.heightAnchor.constraint(equalTo: checkmarkView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: AppSpacing.xs),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
}
