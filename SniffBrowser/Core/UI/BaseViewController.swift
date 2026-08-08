import UIKit

/// 独立功能页面的统一基类。
///
/// 子类把实际内容添加到 `contentView`，不应替换根视图或自行硬编码页面背景。
class BaseViewController: UIViewController {
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
        view.backgroundColor = AppColors.background
        navigationItem.title = initialTitle
        navigationItem.largeTitleDisplayMode = prefersLargeTitle ? .always : .never

        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
