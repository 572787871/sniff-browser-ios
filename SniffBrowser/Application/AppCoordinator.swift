import UIKit

@MainActor
final class AppCoordinator: NSObject, BrowserRouting {
  private let window: UIWindow
  private let navigationController: UINavigationController
  private let websiteDataManager = WebsiteDataManager()
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
    controller.onReturnToPage = { [weak navigation] in
      navigation?.dismiss(animated: true)
    }
    presentSheet(navigation)
  }

  func showTabs(_ controller: TabOverviewViewController) {
    push(controller)
  }

  func returnToBrowser() {
    navigationController.popToRootViewController(animated: true)
    navigationController.setNavigationBarHidden(true, animated: true)
  }

  func showFavorites() {
    let controller = FavoritesViewController()
    controller.onStartBrowsing = { [weak self] in
      self?.returnToBrowser()
    }
    push(controller)
  }

  func showHistory() {
    let controller = HistoryViewController()
    controller.onStartBrowsing = { [weak self] in
      self?.returnToBrowser()
    }
    controller.onOpenPrivateTab = { [weak self] in
      guard self?.browserViewController?.openNewTab(isPrivate: true) == true
      else {
        return
      }
      self?.returnToBrowser()
    }
    push(controller)
  }

  func showDownloads() {
    let controller = DownloadManagerViewController()
    controller.onBrowseForDownloads = { [weak self] in
      self?.returnToBrowser()
    }
    controller.onOpenDownloadSettings = { [weak self] in
      self?.showSettings()
    }
    push(controller)
  }

  func showFiles() {
    let controller = FileManagerViewController()
    // 文件仓储尚未实现，因此导入、建夹和排序操作保持禁用，避免伪造结果。
    controller.onImportFiles = nil
    controller.onCreateFolder = nil
    controller.onSortOrderChanged = nil
    controller.onReturnToBrowser = { [weak self] in
      self?.returnToBrowser()
    }
    push(controller)
  }

  func showUserCenter() {
    let controller = UserCenterViewController(counts: UserCenterCounts())
    controller.onLogin = { [weak self] in
      self?.push(LoginViewController())
    }
    controller.onOpenSettings = { [weak self] in
      self?.showSettings()
    }
    controller.onSelectDestination = { [weak self] destination in
      switch destination {
      case .login:
        self?.push(LoginViewController())
      case .sync:
        self?.push(LoginViewController())
      case .downloads:
        self?.showDownloads()
      case .files:
        self?.showFiles()
      case .favorites:
        self?.showFavorites()
      case .history:
        self?.showHistory()
      case .settings, .privacy, .about:
        self?.showSettings()
      }
    }
    push(controller)
  }

  func showSettings() {
    let controller = SettingsViewController()
    controller.onClearBrowsingData = { [weak self, weak controller] in
      guard let self else { return }
      Task { @MainActor in
        await self.websiteDataManager.clearAllWebsiteData()
        self.browserViewController?.reloadActivePageAfterClearingWebsiteData()
        controller?.showBrowsingDataClearCompleted()
      }
    }
    push(controller)
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
