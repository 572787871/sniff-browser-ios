import UIKit

final class BrowserErrorView: UIView {
  var onRetry: (() -> Void)?

  private let stateView = ErrorStateView(
    configuration: ErrorStateView.Configuration(
      title: "无法打开网页",
      message: "请检查网络连接后重试。"
    )
  )

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func apply(_ error: BrowserDisplayError) {
    let retryAction: (() -> Void)? = error.canRetry
      ? { [weak self] in self?.onRetry?() }
      : nil
    stateView.configure(
      ErrorStateView.Configuration(
        symbolName: error.symbolName,
        title: error.title,
        message: error.message,
        retryTitle: error.canRetry ? "重试" : nil
      ),
      retryAction: retryAction
    )
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = AppColors.background
    stateView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stateView)
    NSLayoutConstraint.activate([
      stateView.topAnchor.constraint(equalTo: topAnchor),
      stateView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stateView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stateView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}
