import UIKit

@MainActor
final class AppCoordinator: NSObject, BrowserRouting {
  private let window: UIWindow
  private let navigationController: UINavigationController
  private let websiteDataManager = WebsiteDataManager()
  private let favoriteService = FavoriteService.shared
  private let historyService = HistoryService.shared
  private let downloadCenter = DownloadCenter.shared
  private weak var browserViewController: BrowserViewController?
  private weak var userCenterViewController: UserCenterViewController?
  private var favoriteChangeObserver: NSObjectProtocol?
  private var historyChangeObserver: NSObjectProtocol?
  private var downloadChangeObserver: NSObjectProtocol?

  init(window: UIWindow) {
    self.window = window
    navigationController = UINavigationController()
    super.init()
    favoriteChangeObserver = favoriteService.observeChanges { [weak self] in
      Task { @MainActor in
        self?.refreshUserCenterCounts()
      }
    }
    historyChangeObserver = historyService.observeChanges { [weak self] in
      Task { @MainActor in
        self?.refreshUserCenterCounts()
      }
    }
    downloadChangeObserver = NotificationCenter.default.addObserver(
      forName: .downloadTasksDidChange,
      object: downloadCenter,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refreshUserCenterCounts()
      }
    }
  }

  deinit {
    if let favoriteChangeObserver {
      favoriteService.removeChangeObserver(favoriteChangeObserver)
    }
    if let historyChangeObserver {
      historyService.removeChangeObserver(historyChangeObserver)
    }
    if let downloadChangeObserver {
      NotificationCenter.default.removeObserver(downloadChangeObserver)
    }
  }

  func start() {
    let browser = BrowserViewController(downloadCenter: downloadCenter)
    browser.router = self
    browserViewController = browser
    navigationController.setViewControllers([browser], animated: false)
    navigationController.setNavigationBarHidden(true, animated: false)
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
    Task { [downloadCenter] in
      await downloadCenter.reloadTasks()
    }
  }

  func showResources(_ controller: ResourceSnifferViewController) {
    let navigation = sheetNavigation(root: controller)
    controller.onReturnToPage = { [weak navigation] in
      navigation?.dismiss(animated: true)
    }
    controller.onShowDownloads = { [weak self, weak navigation] in
      navigation?.dismiss(animated: true) {
        self?.showDownloads()
      }
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
    controller.onOpenFavorite = { [weak self] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: false
      ) == true else {
        return
      }
      self?.returnToBrowser()
    }
    controller.onOpenFavoriteInNewTab = { [weak self] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: true
      ) == true else {
        return
      }
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
    controller.onOpenHistoryItem = { [weak self] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: false
      ) == true else {
        return
      }
      self?.returnToBrowser()
    }
    push(controller)
  }

  func showDownloads() {
    let controller = DownloadManagerViewController(manager: downloadCenter)
    controller.onBrowseForDownloads = { [weak self] in
      self?.returnToBrowser()
    }
    controller.onRoute = { [weak self] route in
      self?.navigate(to: route)
    }
    push(controller)
  }

  func showFiles() {
    let controller = FileManagerViewController(downloadCenter: downloadCenter)
    controller.onImportFiles = nil
    controller.onCreateFolder = nil
    controller.onSortOrderChanged = { [weak controller] order in
      controller?.setSortOrder(order)
    }
    controller.onReturnToBrowser = { [weak self] in
      self?.returnToBrowser()
    }
    push(controller)
  }

  func showUserCenter() {
    let controller = UserCenterViewController(counts: currentUserCenterCounts())
    userCenterViewController = controller
    controller.onLogin = { [weak self] in
      self?.push(LoginViewController())
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
      case .privacy, .about:
        self?.showSettings()
      }
    }
    push(controller)
  }

  private func currentUserCenterCounts() -> UserCenterCounts {
    UserCenterCounts(
      downloads: downloadCenter.tasks.filter {
        $0.isHiddenFromDownloadHistory != true
      }.count,
      files: downloadCenter.tasks.filter { $0.state == .completed }.count,
      favorites: (try? favoriteService.count()) ?? 0,
      history: (try? historyService.count()) ?? 0
    )
  }

  private func refreshUserCenterCounts() {
    userCenterViewController?.update(counts: currentUserCenterCounts())
  }

  func showSettings() {
    let controller = SettingsViewController()
    controller.onRoute = { [weak self] route in
      self?.navigate(to: route)
    }
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

  func navigate(to route: AppRoute) {
    switch route {
    case .downloadSettings:
      push(DownloadSettingsViewController())
    }
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


