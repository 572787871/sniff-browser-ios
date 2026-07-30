import UIKit

@MainActor
final class AppCoordinator: NSObject, BrowserRouting {
  private let window: UIWindow
  private let navigationController: UINavigationController
  private weak var browserViewController: BrowserViewController?

  init(window: UIWindow) {
    self.window = window
    navigationController = UINavigationController()
    super.init()
    navigationController.delegate = self
  }

  func start() {
    let browser = BrowserViewController()
    browser.router = self
    browserViewController = browser
    navigationController.setViewControllers([browser], animated: false)
    navigationController.setNavigationBarHidden(true, animated: false)
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
  }

  func showResources(pageTitle: String, pageURL: URL?) {
    let controller = ResourceSnifferViewController()
    controller.configurePage(title: pageTitle, url: pageURL)
    let navigation = sheetNavigation(root: controller)
    presentSheet(navigation)
  }

  func showTabs(currentItem: TabOverviewItem) {
    let controller = TabOverviewViewController(items: [currentItem])
    controller.onSelectTab = { [weak self] _ in
      self?.navigationController.popViewController(animated: true)
    }
    controller.onCloseTab = { [weak self] _ in
      self?.browserViewController?.openNewTab()
      self?.navigationController.popViewController(animated: true)
    }
    controller.onNewTab = { [weak self] _ in
      self?.browserViewController?.openNewTab()
      self?.navigationController.popViewController(animated: true)
    }
    push(controller)
  }

  func showFavorites() {
    push(FavoritesViewController())
  }

  func showHistory() {
    push(HistoryViewController())
  }

  func showDownloads() {
    push(DownloadManagerViewController())
  }

  func showFiles() {
    push(FileManagerViewController())
  }

  func showUserCenter() {
    let controller = UserCenterViewController()
    controller.onLogin = { [weak self] in
      self?.push(LoginViewController())
    }
    controller.onOpenSettings = { [weak self] in
      self?.showSettings()
    }
    push(controller)
  }

  func showSettings() {
    push(SettingsViewController())
  }

  private func push(_ controller: UIViewController) {
    navigationController.setNavigationBarHidden(false, animated: true)
    navigationController.pushViewController(controller, animated: true)
  }

  private func sheetNavigation(
    root controller: UIViewController
  ) -> UINavigationController {
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak controller] _ in
        controller?.dismiss(animated: true)
      }
    )
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    return navigation
  }

  private func presentSheet(_ navigation: UINavigationController) {
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = AppRadius.sheet
    }
    navigationController.present(navigation, animated: true)
  }
}

extension AppCoordinator: UINavigationControllerDelegate {
  func navigationController(
    _ navigationController: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  ) {
    navigationController.setNavigationBarHidden(
      viewController === browserViewController,
      animated: animated
    )
  }
}
