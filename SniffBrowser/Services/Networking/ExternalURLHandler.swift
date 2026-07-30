import UIKit

@MainActor
final class ExternalURLHandler {
  private weak var presenter: UIViewController?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func requestOpen(_ url: URL) {
    guard let presenter else { return }
    guard UIApplication.shared.canOpenURL(url) else {
      guard presenter.presentedViewController == nil else { return }
      let alert = UIAlertController(
        title: "无法打开链接",
        message: "设备上没有可处理此链接的应用。",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "好", style: .default))
      presenter.present(alert, animated: true)
      return
    }
    guard presenter.presentedViewController == nil else { return }
    let host = url.host ?? url.scheme ?? "外部应用"
    let alert = UIAlertController(
      title: "离开嗅探浏览器？",
      message: "将在其他应用中打开 \(host)。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "继续", style: .default) { _ in
      UIApplication.shared.open(url)
    })
    presenter.present(alert, animated: true)
  }
}
