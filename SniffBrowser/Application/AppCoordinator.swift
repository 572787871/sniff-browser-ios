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
  private let popInteraction = NavigationPopInteraction()
  private let popGesture = UIScreenEdgePanGestureRecognizer()

  init(window: UIWindow) {
    self.window = window
    navigationController = UINavigationController()
    super.init()
    navigationController.delegate = self
    navigationController.interactivePopGestureRecognizer?.isEnabled = false
    popInteraction.navigationController = navigationController
    popGesture.edges = .left
    popGesture.addTarget(
      self,
      action: #selector(handlePopGesture(_:))
    )
    navigationController.view.addGestureRecognizer(popGesture)
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
    navigationController.navigationBar.isUserInteractionEnabled = false
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
  }

  func showFavorites() {
    showFavorites(in: navigationController)
  }

  private func showFavorites(in navigation: UINavigationController) {
    let controller = FavoritesViewController()
    controller.onStartBrowsing = { [weak self, weak navigation] in
      self?.returnToBrowser(from: navigation)
    }
    controller.onOpenFavorite = { [weak self, weak navigation] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: false
      ) == true else {
        return
      }
      self?.returnToBrowser(from: navigation)
    }
    controller.onOpenFavoriteInNewTab = { [weak self, weak navigation] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: true
      ) == true else {
        return
      }
      self?.returnToBrowser(from: navigation)
    }
    push(controller, in: navigation)
  }

  func showHistory() {
    showHistory(in: navigationController)
  }

  private func showHistory(in navigation: UINavigationController) {
    let controller = HistoryViewController()
    controller.onStartBrowsing = { [weak self, weak navigation] in
      self?.returnToBrowser(from: navigation)
    }
    controller.onOpenPrivateTab = { [weak self, weak navigation] in
      guard self?.browserViewController?.openNewTab(isPrivate: true) == true
      else {
        return
      }
      self?.returnToBrowser(from: navigation)
    }
    controller.onOpenHistoryItem = { [weak self, weak navigation] item in
      guard self?.browserViewController?.openFavoriteURL(
        item.url,
        inNewNormalTab: false
      ) == true else {
        return
      }
      self?.returnToBrowser(from: navigation)
    }
    push(controller, in: navigation)
  }

  func showDownloads() {
    showDownloads(in: navigationController)
  }

  private func showDownloads(in navigation: UINavigationController) {
    let controller = DownloadManagerViewController(manager: downloadCenter)
    controller.onBrowseForDownloads = { [weak self, weak navigation] in
      self?.returnToBrowser(from: navigation)
    }
    controller.onRoute = { [weak self, weak navigation] route in
      guard let navigation else { return }
      self?.navigate(to: route, in: navigation)
    }
    push(controller, in: navigation)
  }

  func showFiles() {
    showFiles(in: navigationController)
  }

  private func showFiles(in navigation: UINavigationController) {
    let controller = FileManagerViewController(downloadCenter: downloadCenter)
    controller.onImportFiles = nil
    controller.onCreateFolder = nil
    controller.onSortOrderChanged = { [weak controller] order in
      controller?.setSortOrder(order)
    }
    controller.onReturnToBrowser = { [weak self, weak navigation] in
      self?.returnToBrowser(from: navigation)
    }
    push(controller, in: navigation)
  }

  func showUserCenter() {
    showUserCenter(in: navigationController)
  }

  private func showUserCenter(in navigation: UINavigationController) {
    let controller = UserCenterViewController(counts: currentUserCenterCounts())
    userCenterViewController = controller
    controller.onLogin = { [weak self, weak navigation] in
      guard let navigation else { return }
      self?.push(LoginViewController(), in: navigation)
    }
    controller.onSelectDestination = { [weak self, weak navigation] destination in
      guard let self, let navigation else { return }
      switch destination {
      case .login:
        self.push(LoginViewController(), in: navigation)
      case .sync:
        self.push(LoginViewController(), in: navigation)
      case .downloads:
        self.showDownloads(in: navigation)
      case .files:
        self.showFiles(in: navigation)
      case .favorites:
        self.showFavorites(in: navigation)
      case .history:
        self.showHistory(in: navigation)
      case .privacy, .about:
        self.showSettings(in: navigation)
      }
    }
    push(controller, in: navigation)
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
    showSettings(in: navigationController)
  }

  private func showSettings(in navigation: UINavigationController) {
    let controller = SettingsViewController()
    controller.onRoute = { [weak self, weak navigation] route in
      guard let navigation else { return }
      self?.navigate(to: route, in: navigation)
    }
    controller.onClearBrowsingData = { [weak self, weak controller] in
      guard let self else { return }
      Task { @MainActor in
        await self.websiteDataManager.clearAllWebsiteData()
        self.browserViewController?.reloadActivePageAfterClearingWebsiteData()
        controller?.showBrowsingDataClearCompleted()
      }
    }
    push(controller, in: navigation)
  }

  func navigate(to route: AppRoute) {
    navigate(to: route, in: navigationController)
  }

  private func navigate(
    to route: AppRoute,
    in navigation: UINavigationController
  ) {
    switch route {
    case .downloadSettings:
      push(DownloadSettingsViewController(), in: navigation)
    }
  }

  func showMoreDestination(
    _ destination: BrowserMenuDestination,
    in navigationController: UINavigationController
  ) {
    switch destination {
    case .downloads:
      showDownloads(in: navigationController)
    case .files:
      showFiles(in: navigationController)
    case .favorites:
      showFavorites(in: navigationController)
    case .history:
      showHistory(in: navigationController)
    case .userCenter:
      showUserCenter(in: navigationController)
    case .settings:
      showSettings(in: navigationController)
    }
  }

  private func push(_ controller: UIViewController) {
    push(controller, in: navigationController)
  }

  private func push(
    _ controller: UIViewController,
    in navigation: UINavigationController
  ) {
    navigation.pushViewController(controller, animated: true)
  }

  private func returnToBrowser(from navigation: UINavigationController?) {
    guard let navigation else { return }
    if navigation === navigationController {
      returnToBrowser()
    } else {
      navigation.dismiss(animated: true)
    }
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
  @objc
  private func handlePopGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
    popInteraction.handleGesture(gesture)
  }

  func navigationController(
    _ navigationController: UINavigationController,
    interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
  ) -> UIViewControllerInteractiveTransitioning? {
    popInteraction.isInteracting ? popInteraction : nil
  }

  func navigationController(
    _ navigationController: UINavigationController,
    animationControllerFor operation: UINavigationController.Operation,
    from fromVC: UIViewController,
    to toVC: UIViewController
  ) -> UIViewControllerAnimatedTransitioning? {
    if !popInteraction.isInteracting {
      if fromVC === browserViewController,
         let overview = toVC as? TabOverviewViewController {
        return TabOverviewNavigationAnimator(
          operation: .push,
          overview: overview
        )
      }
      if toVC === browserViewController,
         let overview = fromVC as? TabOverviewViewController {
        return TabOverviewNavigationAnimator(
          operation: .pop,
          overview: overview
        )
      }
    }
    return PlainHorizontalNavigationAnimator(operation: operation)
  }

  func navigationController(
    _ navigationController: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  ) {
    let isBrowser = viewController === browserViewController
    navigationController.setNavigationBarHidden(isBrowser, animated: false)
    let appearance = UINavigationBarAppearance()
    if isBrowser {
      appearance.configureWithTransparentBackground()
      appearance.shadowColor = .clear
    } else {
      appearance.configureWithOpaqueBackground()
      appearance.backgroundColor = AppColors.background
      appearance.shadowColor = .clear
      appearance.titleTextAttributes = [
        .foregroundColor: AppColors.primaryText,
        .font: AppTypography.headline,
      ]
      appearance.largeTitleTextAttributes = [
        .foregroundColor: AppColors.primaryText,
        .font: AppTypography.largeTitle,
      ]
    }
    // 根浏览器使用自己的地址栏并隐藏系统导航栏，避免透明导航栏覆盖其触摸区。
    // 进入独立页面后恢复系统导航栏与交互。
    navigationController.navigationBar.isUserInteractionEnabled = !isBrowser
    navigationController.navigationBar.standardAppearance = appearance
    navigationController.navigationBar.compactAppearance = appearance
    navigationController.navigationBar.scrollEdgeAppearance = appearance
  }
}

/// Keeps the browser and its tab card spatially connected in both directions.
private final class TabOverviewNavigationAnimator: NSObject,
  UIViewControllerAnimatedTransitioning {
  private let operation: UINavigationController.Operation
  private weak var overview: TabOverviewViewController?

  init(
    operation: UINavigationController.Operation,
    overview: TabOverviewViewController
  ) {
    self.operation = operation
    self.overview = overview
    super.init()
  }

  func transitionDuration(
    using transitionContext: UIViewControllerContextTransitioning?
  ) -> TimeInterval {
    UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42
  }

  func animateTransition(
    using transitionContext: UIViewControllerContextTransitioning
  ) {
    guard !UIAccessibility.isReduceMotionEnabled,
          let overview,
          let itemID = overview.transitionItemID
    else {
      PlainHorizontalNavigationAnimator(operation: operation)
        .animateTransition(using: transitionContext)
      return
    }

    switch operation {
    case .push:
      animateShrink(
        itemID: itemID,
        overview: overview,
        transitionContext: transitionContext
      )
    case .pop:
      animateExpand(
        itemID: itemID,
        overview: overview,
        transitionContext: transitionContext
      )
    default:
      transitionContext.completeTransition(false)
    }
  }

  private func animateShrink(
    itemID: UUID,
    overview: TabOverviewViewController,
    transitionContext: UIViewControllerContextTransitioning
  ) {
    guard let fromView = transitionContext.view(forKey: .from),
          let toView = transitionContext.view(forKey: .to),
          let fromViewController = transitionContext.viewController(forKey: .from),
          let toViewController = transitionContext.viewController(forKey: .to)
    else {
      fallback(using: transitionContext)
      return
    }
    let movingSource = (fromViewController as? BrowserViewController)?.contentView
      ?? fromView
    guard let movingView = movingSource.snapshotView(afterScreenUpdates: false)
    else {
      fallback(using: transitionContext)
      return
    }

    let container = transitionContext.containerView
    toView.frame = transitionContext.finalFrame(for: toViewController)
    container.addSubview(toView)
    container.layoutIfNeeded()
    toView.layoutIfNeeded()
    guard let targetFrame = overview.transitionFrame(
      for: itemID,
      in: container,
      ensureVisible: true
    ), targetFrame.width > 0, targetFrame.height > 0
    else {
      toView.removeFromSuperview()
      fallback(using: transitionContext)
      return
    }

    let initialFrame = container.convert(movingSource.bounds, from: movingSource)
    let surface = transitionSurface(
      frame: initialFrame,
      cornerRadius: 0
    )
    movingView.frame = surface.bounds
    movingView.autoresizingMask = []
    surface.addSubview(movingView)
    overview.setTransitionItemHidden(itemID, hidden: true)
    let navigationBar = overview.navigationController?.navigationBar
    navigationBar?.alpha = 0
    container.addSubview(surface)

    UIView.animate(
      withDuration: transitionDuration(using: transitionContext),
      delay: 0,
      usingSpringWithDamping: 1,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: {
        surface.frame = targetFrame
        surface.layer.cornerRadius = AppRadius.card
        movingView.frame = Self.aspectFitFrame(
          contentSize: initialFrame.size,
          containerSize: targetFrame.size
        )
        navigationBar?.alpha = 1
      },
      completion: { _ in
        let completed = !transitionContext.transitionWasCancelled
        navigationBar?.alpha = 1
        overview.setTransitionItemHidden(itemID, hidden: false)
        surface.removeFromSuperview()
        if !completed { toView.removeFromSuperview() }
        transitionContext.completeTransition(completed)
      }
    )
  }

  private func animateExpand(
    itemID: UUID,
    overview: TabOverviewViewController,
    transitionContext: UIViewControllerContextTransitioning
  ) {
    guard let fromView = transitionContext.view(forKey: .from),
          let toView = transitionContext.view(forKey: .to),
          let toViewController = transitionContext.viewController(forKey: .to)
    else {
      fallback(using: transitionContext)
      return
    }

    let container = transitionContext.containerView
    toView.frame = transitionContext.finalFrame(for: toViewController)
    container.insertSubview(toView, belowSubview: fromView)
    container.layoutIfNeeded()
    toView.layoutIfNeeded()
    guard let sourceFrame = overview.transitionFrame(
      for: itemID,
      in: container,
      ensureVisible: false
    ), sourceFrame.width > 0, sourceFrame.height > 0
    else {
      toView.removeFromSuperview()
      fallback(using: transitionContext)
      return
    }
    let movingSource = (toViewController as? BrowserViewController)?.contentView
      ?? toView
    guard let movingView = movingSource.snapshotView(afterScreenUpdates: true)
    else {
      toView.removeFromSuperview()
      fallback(using: transitionContext)
      return
    }

    let finalFrame = container.convert(movingSource.bounds, from: movingSource)
    let surface = transitionSurface(
      frame: sourceFrame,
      cornerRadius: AppRadius.card
    )
    movingView.frame = Self.aspectFitFrame(
      contentSize: finalFrame.size,
      containerSize: sourceFrame.size
    )
    movingView.autoresizingMask = []
    surface.addSubview(movingView)
    overview.setTransitionItemHidden(itemID, hidden: true)
    let navigationBar = overview.navigationController?.navigationBar
    navigationBar?.alpha = 1
    container.addSubview(surface)

    UIView.animate(
      withDuration: transitionDuration(using: transitionContext),
      delay: 0,
      usingSpringWithDamping: 1,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: {
        surface.frame = finalFrame
        surface.layer.cornerRadius = 0
        movingView.frame = CGRect(origin: .zero, size: finalFrame.size)
        navigationBar?.alpha = 0
      },
      completion: { _ in
        let completed = !transitionContext.transitionWasCancelled
        navigationBar?.alpha = 1
        overview.setTransitionItemHidden(itemID, hidden: false)
        surface.removeFromSuperview()
        if !completed { toView.removeFromSuperview() }
        transitionContext.completeTransition(completed)
      }
    )
  }

  private func fallback(
    using transitionContext: UIViewControllerContextTransitioning
  ) {
    PlainHorizontalNavigationAnimator(operation: operation)
      .animateTransition(using: transitionContext)
  }

  private func transitionSurface(
    frame: CGRect,
    cornerRadius: CGFloat
  ) -> UIView {
    let surface = UIView(frame: frame)
    surface.backgroundColor = AppColors.surface
    surface.isUserInteractionEnabled = false
    surface.layer.cornerCurve = .continuous
    surface.layer.cornerRadius = cornerRadius
    surface.layer.masksToBounds = true
    return surface
  }

  private static func aspectFitFrame(
    contentSize: CGSize,
    containerSize: CGSize
  ) -> CGRect {
    guard contentSize.width > 0,
          contentSize.height > 0,
          containerSize.width > 0,
          containerSize.height > 0
    else { return CGRect(origin: .zero, size: containerSize) }
    let scale = min(
      containerSize.width / contentSize.width,
      containerSize.height / contentSize.height
    )
    let size = CGSize(
      width: contentSize.width * scale,
      height: contentSize.height * scale
    )
    return CGRect(
      x: (containerSize.width - size.width) / 2,
      y: (containerSize.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }
}

/// A full-width push/pop transition with no parallax, fade, scale, or shadow.
private final class PlainHorizontalNavigationAnimator: NSObject,
  UIViewControllerAnimatedTransitioning {
  private let operation: UINavigationController.Operation

  init(operation: UINavigationController.Operation) {
    self.operation = operation
    super.init()
  }

  func transitionDuration(
    using transitionContext: UIViewControllerContextTransitioning?
  ) -> TimeInterval {
    UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28
  }

  func animateTransition(
    using transitionContext: UIViewControllerContextTransitioning
  ) {
    guard let fromView = transitionContext.view(forKey: .from),
          let toView = transitionContext.view(forKey: .to),
          let toViewController = transitionContext.viewController(forKey: .to)
    else {
      transitionContext.completeTransition(false)
      return
    }

    let container = transitionContext.containerView
    let width = container.bounds.width
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    let duration = transitionDuration(using: transitionContext)
    let navigationBar = transitionContext
      .viewController(forKey: .from)?
      .navigationController?
      .navigationBar

    clearTransitionShadow(on: fromView)
    clearTransitionShadow(on: toView)
    clearTransitionShadow(on: navigationBar)

    switch operation {
    case .push:
      container.addSubview(toView)
      toView.frame = transitionContext.finalFrame(for: toViewController)
      toView.transform = reduceMotion
        ? .identity
        : CGAffineTransform(translationX: width, y: 0)
      toView.alpha = reduceMotion ? 0 : 1
      navigationBar?.transform = reduceMotion
        ? .identity
        : CGAffineTransform(translationX: width, y: 0)

      UIView.animate(
        withDuration: duration,
        delay: 0,
        options: [.curveEaseOut, .allowUserInteraction],
        animations: {
          toView.transform = .identity
          if reduceMotion {
            toView.alpha = 1
          }
          navigationBar?.transform = .identity
        },
        completion: { _ in
          toView.transform = .identity
          toView.alpha = 1
          navigationBar?.transform = .identity
          transitionContext.completeTransition(
            !transitionContext.transitionWasCancelled
          )
        }
      )
    case .pop:
      container.insertSubview(toView, belowSubview: fromView)
      toView.frame = transitionContext.finalFrame(for: toViewController)
      fromView.transform = .identity
      fromView.alpha = 1
      toView.transform = .identity
      toView.alpha = reduceMotion ? 0 : 1
      navigationBar?.transform = .identity

      UIView.animate(
        withDuration: duration,
        delay: 0,
        options: [.curveEaseOut, .allowUserInteraction],
        animations: {
          if reduceMotion {
            fromView.alpha = 0
            toView.alpha = 1
          } else {
            fromView.transform = CGAffineTransform(
              translationX: width,
              y: 0
            )
            navigationBar?.transform = CGAffineTransform(
              translationX: width,
              y: 0
            )
          }
        },
        completion: { _ in
          let completed = !transitionContext.transitionWasCancelled
          fromView.transform = .identity
          fromView.alpha = 1
          toView.transform = .identity
          toView.alpha = 1
          navigationBar?.transform = .identity
          transitionContext.completeTransition(completed)
        }
      )
    default:
      transitionContext.completeTransition(false)
    }
  }

  private func clearTransitionShadow(on view: UIView?) {
    guard let view else { return }
    view.layer.shadowColor = UIColor.clear.cgColor
    view.layer.shadowOpacity = 0
    view.layer.shadowRadius = 0
    view.layer.shadowOffset = .zero
    view.layer.shadowPath = nil
  }
}

/// Drives the same plain horizontal pop transition from the screen edge.
@MainActor
private final class NavigationPopInteraction: UIPercentDrivenInteractiveTransition {
  weak var navigationController: UINavigationController?

  private(set) var isInteracting = false

  func handleGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
    guard let view = gesture.view else { return }

    switch gesture.state {
    case .began:
      guard navigationController?.viewControllers.count ?? 0 > 1 else {
        isInteracting = false
        return
      }
      isInteracting = true
      navigationController?.popViewController(animated: true)
    case .changed:
      let translation = gesture.translation(in: view)
      let progress = min(1, max(0, translation.x / view.bounds.width))
      update(progress)
    case .ended, .cancelled, .failed:
      isInteracting = false
      let translation = gesture.translation(in: view)
      let velocity = gesture.velocity(in: view)
      let shouldFinish = velocity.x > 600
        || translation.x / view.bounds.width > 0.4
      shouldFinish ? finish() : cancel()
    default:
      isInteracting = false
      cancel()
    }
  }
}
