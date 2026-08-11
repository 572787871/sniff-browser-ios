import UIKit

/// 原生功能页共用的全屏背景。
///
/// 背景来源与新标签页保持一致：用户切换内置背景或自定义照片后，所有
/// 原生页面会同步更新。覆盖层保留足够的纸张色，避免列表文字直接落在
/// 明暗复杂的照片上。
@MainActor
final class AppPageBackgroundView: UIView {
    private let store: NewTabBackgroundStore
    private let imageView = UIImageView()
    private let readabilityWashView = UIView()
    private var backgroundObserver: NSObjectProtocol?

    private(set) var isShowingImage = false

    init(store: NewTabBackgroundStore = .shared) {
        self.store = store
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        store = .shared
        super.init(coder: coder)
        configure()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    func reloadBackground() {
        let image = store.image()
        imageView.image = image
        isShowingImage = image != nil
        imageView.isHidden = !isShowingImage
        readabilityWashView.isHidden = !isShowingImage
    }

    private func configure() {
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = AppColors.background

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        readabilityWashView.translatesAutoresizingMaskIntoConstraints = false
        readabilityWashView.backgroundColor = UIColor { traits in
            AppColors.background.resolvedColor(with: traits).withAlphaComponent(
                traits.userInterfaceStyle == .dark ? 0.48 : 0.34
            )
        }
        addSubview(readabilityWashView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            readabilityWashView.topAnchor.constraint(equalTo: topAnchor),
            readabilityWashView.leadingAnchor.constraint(equalTo: leadingAnchor),
            readabilityWashView.trailingAnchor.constraint(equalTo: trailingAnchor),
            readabilityWashView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        reloadBackground()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: .newTabBackgroundDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadBackground()
            }
        }
    }
}

/// 独立功能页面的统一基类。
///
/// 子类把实际内容添加到 `contentView`，不应替换根视图或自行硬编码页面背景。
class BaseViewController: UIViewController {
    let appBackgroundView = AppPageBackgroundView()
    let contentView = UIView()

    private let initialTitle: String?
    private let prefersLargeTitle: Bool
    private weak var presentedStateView: UIView?

    init(title: String? = nil, prefersLargeTitle: Bool = true) {
        initialTitle = title
        self.prefersLargeTitle = prefersLargeTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialTitle = nil
        prefersLargeTitle = true
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBaseAppearance()
    }

    /// 以全页方式展示统一的 Loading、Empty 或 Error 状态。
    func showStateView(_ stateView: UIView) {
        presentedStateView?.removeFromSuperview()
        presentedStateView = stateView

        stateView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stateView)
        NSLayoutConstraint.activate([
            stateView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func hideStateView() {
        presentedStateView?.removeFromSuperview()
        presentedStateView = nil
    }

    private func configureBaseAppearance() {
        view.backgroundColor = .clear
        navigationItem.title = initialTitle
        navigationItem.largeTitleDisplayMode = prefersLargeTitle ? .always : .never

        appBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appBackgroundView)

        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            appBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            appBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            appBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            appBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
