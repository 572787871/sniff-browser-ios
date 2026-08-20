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
  private var tabOpenTransitionSequence = 0

  init(window: UIWindow) {
    self.window = window
    navigationController = UINavigationController()
    super.init()
    navigationController.delegate = self
    navigationController.interactivePopGestureRecognizer?.isEnabled = false
    popInteraction.navigationController = navigationController
    popGesture.edges = .left
    popGesture.delegate = self
    popGesture.cancelsTouchesInView = true
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
        ResourceThumbnailLoader.shared.clearCache()
        RemoteMediaThumbnailLoader.shared.clearMemoryCache()
        FaviconLoader.shared.clearCache()
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
    // 将边缘返回手势直接挂在当前内容页，而不是只挂在导航控制器外层。
    // UIPageViewController/UICollectionView 会优先占用横向拖动，外层手势
    // 在标签总览里可能永远收不到 began；内容页上的 screen-edge 手势
    // 与 Safari 一样从左边缘连续驱动同一套 pop 空间转场。
    navigation.pushViewController(controller, animated: true)
    if navigation === navigationController {
      // push 完成注册后再访问 view，保证目标控制器在 viewDidLoad 中已经
      // 拿到 navigationController，不改变其他页面原有生命周期。
      controller.loadViewIfNeeded()
      controller.view.addGestureRecognizer(popGesture)
    }
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
      let preferredIdentifier = UISheetPresentationController.Detent.Identifier(
        "resourceSniffer"
      )
      let preferredDetent = UISheetPresentationController.Detent.custom(
        identifier: preferredIdentifier
      ) { context in
        let preferredHeight = context.maximumDetentValue * 0.76
        return min(
          context.maximumDetentValue,
          max(440, preferredHeight)
        )
      }
      sheet.detents = [preferredDetent, .large()]
      sheet.selectedDetentIdentifier = preferredIdentifier
      sheet.prefersGrabberVisible = true
      sheet.prefersScrollingExpandsWhenScrolledToEdge = false
      sheet.preferredCornerRadius = AppRadius.sheet
    }
    navigationController.present(navigation, animated: true)
  }
}

extension AppCoordinator: UINavigationControllerDelegate,
  UIGestureRecognizerDelegate {
  @objc
  private func handlePopGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
    if gesture.state == .began {
      (navigationController.topViewController as? TabOverviewViewController)?
        .captureCurrentTransitionFrameIfNeeded()
    }
    popInteraction.handleGesture(gesture)
  }

  func gestureRecognizerShouldBegin(
    _ gestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    guard gestureRecognizer === popGesture,
          navigationController.viewControllers.count > 1
    else { return gestureRecognizer !== popGesture }
    guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
      return true
    }
    let velocity = panGesture.velocity(in: panGesture.view)
    return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
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
    if !popInteraction.isInteracting,
       fromVC === browserViewController,
       let overview = toVC as? TabOverviewViewController {
      return TabOverviewNavigationAnimator(
        operation: .push,
        overview: overview
      )
    }
    if toVC === browserViewController,
       let overview = fromVC as? TabOverviewViewController {
      overview.captureCurrentTransitionFrameIfNeeded()
      tabOpenTransitionSequence += 1
      return TabOverviewNavigationAnimator(
        operation: .pop,
        overview: overview,
        sequence: tabOpenTransitionSequence
      )
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
  private let sequence: Int?
  private var propertyAnimator: UIViewPropertyAnimator?

  init(
    operation: UINavigationController.Operation,
    overview: TabOverviewViewController,
    sequence: Int? = nil
  ) {
    self.operation = operation
    self.overview = overview
    self.sequence = sequence
    super.init()
  }

  deinit {
    propertyAnimator?.stopAnimation(true)
    propertyAnimator = nil
  }

  func transitionDuration(
    using transitionContext: UIViewControllerContextTransitioning?
  ) -> TimeInterval {
    UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42
  }

  func animateTransition(
    using transitionContext: UIViewControllerContextTransitioning
  ) {
    guard let overview,
          let itemID = overview.transitionItemID
    else {
      PlainHorizontalNavigationAnimator(operation: operation)
        .animateTransition(using: transitionContext)
      return
    }
    if UIAccessibility.isReduceMotionEnabled {
      animateReducedMotion(
        itemID: itemID,
        overview: overview,
        transitionContext: transitionContext
      )
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

  private func animateReducedMotion(
    itemID: UUID,
    overview: TabOverviewViewController,
    transitionContext: UIViewControllerContextTransitioning
  ) {
    var browserWithCover: BrowserViewController?
    if operation == .push,
       let browser = transitionContext.viewController(forKey: .from)
        as? BrowserViewController {
      browser.discardTabTransitionSnapshot()
    }
    if operation == .pop,
       let browser = transitionContext.viewController(forKey: .to)
        as? BrowserViewController,
       let image = overview.transitionImage(for: itemID),
       let toView = transitionContext.view(forKey: .to) {
      toView.frame = transitionContext.finalFrame(for: browser)
      toView.setNeedsLayout()
      toView.layoutIfNeeded()
      browser.installTabTransitionCover(image: image)
      browserWithCover = browser
    }

    PlainHorizontalNavigationAnimator(operation: operation)
      .animateTransition(using: transitionContext)
    if let browserWithCover {
      DispatchQueue.main.asyncAfter(
        deadline: .now() + transitionDuration(using: transitionContext)
      ) {
        browserWithCover.completeTabTransitionCover()
      }
    }
  }

  private func animateShrink(
    itemID: UUID,
    overview: TabOverviewViewController,
    transitionContext: UIViewControllerContextTransitioning
  ) {
    guard let fromView = transitionContext.view(forKey: .from),
          let toView = transitionContext.view(forKey: .to),
          let browser = transitionContext.viewController(forKey: .from)
            as? BrowserViewController,
          let toViewController = transitionContext.viewController(forKey: .to),
          let transitionImage = overview.transitionImage(for: itemID)
    else {
      fallback(using: transitionContext)
      return
    }

    let container = transitionContext.containerView
    guard let transitionWindow = container.window
      ?? fromView.window
      ?? toView.window
    else {
      fallback(using: transitionContext)
      return
    }
    toView.frame = transitionContext.finalFrame(for: toViewController)
    toView.alpha = 1
    container.insertSubview(toView, belowSubview: fromView)
    container.layoutIfNeeded()
    toView.layoutIfNeeded()

    guard let pageSnapshot = browser.consumeTabTransitionSnapshot(
            in: transitionWindow,
            fallbackImage: transitionImage
          ),
          let pageFrames = pageSnapshot.frames(in: transitionWindow),
          pageFrames.visible.width > 0,
          pageFrames.visible.height > 0,
          let targetFrame = overview.transitionFrame(
            for: itemID,
            in: transitionWindow,
            ensureVisible: true
          ),
          targetFrame.width > 0,
          targetFrame.height > 0
    else {
      toView.removeFromSuperview()
      fallback(using: transitionContext)
      return
    }

    let surface = transitionSurface(
      frame: pageFrames.visible,
      cornerRadius: 0
    )
    let transitionContent = pageSnapshot.contentView
    let sourceImageFrame = TabOverviewTransitionGeometry.clippedPageFrame(
      contentSize: pageSnapshot.contentSize,
      fullContainerFrame: pageFrames.full,
      clippedTo: pageFrames.visible
    )
    let targetImageFrame = TabOverviewTransitionGeometry.pageFillFrame(
      contentSize: pageSnapshot.contentSize,
      containerSize: targetFrame.size
    )
    attachTransitionSnapshot(
      transitionContent,
      imageFrame: sourceImageFrame,
      to: surface
    )
    overview.prepareSpatialTransition(enteringOverview: true)
    overview.setTransitionItemHidden(itemID, hidden: true)
    let navigationBar = overview.navigationController?.navigationBar
    navigationBar?.alpha = 0
    transitionWindow.addSubview(surface)
    startTransitionGeometryDiagnostics(
      snapshot: surface,
      sourceFrame: pageFrames.visible,
      targetFrame: targetFrame,
      in: transitionWindow
    )
    browser.debugLogTabTransitionState(
      "TAB TRANSITION START",
      in: transitionWindow
    )
    browser.setTabTransitionPageHidden(true)

    startPropertyAnimator(
      using: transitionContext,
      animations: {
        fromView.alpha = 0
        overview.animateSpatialTransition(enteringOverview: true)
        self.apply(containerFrame: targetFrame, to: surface)
        self.apply(
          containerSize: targetFrame.size,
          imageFrame: targetImageFrame,
          to: transitionContent
        )
        surface.layer.cornerRadius = AppRadius.card
        navigationBar?.alpha = 1
      },
      completion: { completed in
        browser.setTabTransitionPageHidden(false)
        navigationBar?.alpha = 1
        overview.setTransitionItemHidden(itemID, hidden: false)
        self.logTransitionGeometry(
          "TAB SNAPSHOT FINISH \(completed ? "success" : "cancelled")",
          snapshot: surface,
          sourceFrame: pageFrames.visible,
          targetFrame: targetFrame,
          in: transitionWindow
        )
        self.disposeTransitionSurface(surface)
        fromView.alpha = 1
        toView.alpha = 1
        overview.completeSpatialTransition()
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
          let browser = transitionContext.viewController(forKey: .to)
            as? BrowserViewController
    else {
      fallback(using: transitionContext)
      return
    }

    let container = transitionContext.containerView
    guard let transitionWindow = container.window
      ?? fromView.window
      ?? toView.window
    else {
      fallback(using: transitionContext)
      return
    }
    let finalBrowserFrame = transitionContext.finalFrame(for: browser)
    fromView.transform = .identity
    fromView.layer.transform = CATransform3DIdentity
    toView.frame = finalBrowserFrame
    toView.transform = .identity
    toView.layer.transform = CATransform3DIdentity
    toView.alpha = 1
    container.insertSubview(toView, belowSubview: fromView)
    container.layoutIfNeeded()
    toView.layoutIfNeeded()
    // Card selection reattaches the selected WebView while the browser is
    // still off-screen. Normalize that state before reading the target frame;
    // the real WebView is never used as the animated surface.
    browser.normalizeTabTransitionBrowserState()
    browser.debugLogTabTransitionState("TAB OPEN START", in: transitionWindow)
    let transitionImage = browser.makeTabTransitionImage(
      for: itemID,
      fallbackImage: overview.transitionImage(for: itemID)
    )
    let finalFullFrame = browser.tabTransitionSnapshotFullFrame(
      in: transitionWindow
    )
    let finalFrame = browser.tabTransitionContentFrame(in: transitionWindow)
    guard let transitionImage,
          finalFullFrame.width > 0,
          finalFullFrame.height > 0,
          finalFrame.width > 0,
          finalFrame.height > 0,
          let sourceFrame = overview.transitionFrame(
            for: itemID,
            in: transitionWindow,
            ensureVisible: false
          ),
          sourceFrame.width > 0,
          sourceFrame.height > 0
    else {
      toView.removeFromSuperview()
      fallback(using: transitionContext)
      return
    }

    let openLabel = sequence.map { "OPEN #\($0)" } ?? "OPEN"
    overview.debugLogTransitionState(
      "\(openLabel) START",
      itemID: itemID,
      in: transitionWindow
    )
    browser.installTabTransitionCover(image: transitionImage)
    let surface = transitionSurface(
      frame: sourceFrame,
      cornerRadius: AppRadius.card
    )
    let transitionContent = TabPageSnapshotView(image: transitionImage)
    let sourceImageFrame = TabOverviewTransitionGeometry.pageFillFrame(
      contentSize: transitionImage.size,
      containerSize: sourceFrame.size
    )
    let targetImageFrame = TabOverviewTransitionGeometry.clippedPageFrame(
      contentSize: transitionImage.size,
      fullContainerFrame: finalFullFrame,
      clippedTo: finalFrame
    )
    attachTransitionSnapshot(
      transitionContent,
      imageFrame: sourceImageFrame,
      to: surface
    )
    overview.prepareSpatialTransition(enteringOverview: false)
    overview.setTransitionItemHidden(itemID, hidden: true)
    overview.debugLogTransitionState(
      "\(openLabel) CELL AFTER RESET",
      itemID: itemID,
      in: transitionWindow
    )
    browser.setTabTransitionChromeAlpha(0)
    let navigationBar = overview.navigationController?.navigationBar
    navigationBar?.alpha = 1
    transitionWindow.addSubview(surface)
    startTransitionGeometryDiagnostics(
      snapshot: surface,
      sourceFrame: sourceFrame,
      targetFrame: finalFrame,
      in: transitionWindow
    )

    startPropertyAnimator(
      using: transitionContext,
      animations: {
        overview.animateSpatialTransition(enteringOverview: false)
        browser.setTabTransitionChromeAlpha(1)
        self.apply(containerFrame: finalFrame, to: surface)
        self.apply(
          containerSize: finalFrame.size,
          imageFrame: targetImageFrame,
          to: transitionContent
        )
        surface.layer.cornerRadius = 0
        navigationBar?.alpha = 0
      },
      completion: { completed in
        navigationBar?.alpha = 1
        browser.setTabTransitionChromeAlpha(1)
        overview.setTransitionItemHidden(itemID, hidden: false)
        self.logTransitionGeometry(
          "TAB SNAPSHOT FINISH \(completed ? "success" : "cancelled")",
          snapshot: surface,
          sourceFrame: sourceFrame,
          targetFrame: finalFrame,
          in: transitionWindow
        )
        toView.frame = finalBrowserFrame
        toView.transform = .identity
        toView.layer.transform = CATransform3DIdentity
        browser.prepareTabOpenTransitionHandoff()
        browser.debugLogTabTransitionState(
          "TAB TRANSITION BEFORE HANDOFF",
          in: transitionWindow
        )
        // Surface 已经到达最终像素位置。先让同一张 cover 在真实 WebView
        // 上方接管，再销毁 window 上的临时 surface，用户不会看到中间帧。
        self.disposeTransitionSurface(surface)
        fromView.alpha = 1
        toView.alpha = 1
        browser.debugLogTabTransitionState(
          "TAB OPEN FINISH \(completed ? "success" : "cancelled")",
          in: transitionWindow
        )
        overview.completeSpatialTransition()
        overview.debugLogTransitionState(
          "\(openLabel) FINISH \(completed ? "success" : "cancelled")",
          itemID: itemID,
          in: transitionWindow
        )
        if completed {
          browser.finishTabOpenTransition()
        } else {
          browser.clearTabTransitionScrollState()
          browser.removeTabTransitionCover(animated: false)
          toView.removeFromSuperview()
        }
        transitionContext.completeTransition(completed)
      }
    )
  }

  private func fallback(
    using transitionContext: UIViewControllerContextTransitioning
  ) {
    (transitionContext.viewController(forKey: .to) as? BrowserViewController)?
      .clearTabTransitionScrollState()
    (transitionContext.viewController(forKey: .from) as? BrowserViewController)?
      .discardTabTransitionSnapshot()
    (transitionContext.viewController(forKey: .from)
      as? TabOverviewViewController)?.completeSpatialTransition()
    PlainHorizontalNavigationAnimator(operation: operation)
      .animateTransition(using: transitionContext)
  }

  private func startPropertyAnimator(
    using transitionContext: UIViewControllerContextTransitioning,
    animations: @escaping () -> Void,
    completion: @escaping (Bool) -> Void
  ) {
    // A transition animator is normally one-shot. Keep this guard defensive
    // so an interrupted attempt can never be extended with a second set of
    // animations or a stale fractionComplete value.
#if DEBUG
    AppLogger(.navigation).debug(
      "TAB PROPERTY ANIMATOR START existing=\(propertyAnimator != nil)"
    )
#endif
    propertyAnimator?.stopAnimation(true)
    propertyAnimator = nil
    let timing = UISpringTimingParameters(
      dampingRatio: 0.88,
      initialVelocity: CGVector(dx: 0, dy: 0)
    )
    let animator = UIViewPropertyAnimator(
      duration: transitionDuration(using: transitionContext),
      timingParameters: timing
    )
    animator.addAnimations(animations)
    animator.addCompletion { position in
      let completed = position == .end
        && !transitionContext.transitionWasCancelled
      if self.propertyAnimator === animator {
        self.propertyAnimator = nil
      }
      completion(completed)
    }
    propertyAnimator = animator
    animator.startAnimation()
  }

  private func transitionSurface(
    frame: CGRect,
    cornerRadius: CGFloat
  ) -> UIView {
    let surface = UIView()
    surface.translatesAutoresizingMaskIntoConstraints = true
    surface.transform = .identity
    surface.layer.transform = CATransform3DIdentity
    apply(containerFrame: frame, to: surface)
    surface.backgroundColor = AppColors.surface
    surface.isUserInteractionEnabled = false
    surface.layer.cornerCurve = .continuous
    surface.layer.cornerRadius = cornerRadius
    surface.layer.masksToBounds = true
    return surface
  }

  private func disposeTransitionSurface(_ surface: UIView) {
    surface.layer.removeAllAnimations()
    surface.transform = .identity
    surface.layer.transform = CATransform3DIdentity
    surface.subviews.forEach { child in
      child.layer.removeAllAnimations()
      child.transform = .identity
      child.layer.transform = CATransform3DIdentity
      child.removeFromSuperview()
    }
    surface.removeFromSuperview()
  }

  /// 外层窗口只改变 bounds/center；内部 frozen image 使用明确的等比
  /// 起止 frame，固定顶部取景，不随中间容器宽高重新选择铺满比例。
  private func attachTransitionSnapshot(
    _ snapshot: UIView,
    imageFrame: CGRect,
    to surface: UIView
  ) {
    snapshot.translatesAutoresizingMaskIntoConstraints = true
    snapshot.autoresizingMask = []
    snapshot.transform = .identity
    snapshot.layer.transform = CATransform3DIdentity
    snapshot.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    snapshot.isUserInteractionEnabled = false
    surface.addSubview(snapshot)
    snapshot.bounds = surface.bounds
    snapshot.center = CGPoint(
      x: surface.bounds.midX,
      y: surface.bounds.midY
    )
    (snapshot as? TabPageSnapshotView)?.setRenderedImageFrame(imageFrame)
  }

  private func apply(
    containerSize: CGSize,
    imageFrame: CGRect,
    to snapshot: UIView
  ) {
    snapshot.transform = .identity
    snapshot.bounds = CGRect(origin: .zero, size: containerSize)
    snapshot.center = CGPoint(
      x: containerSize.width / 2,
      y: containerSize.height / 2
    )
    (snapshot as? TabPageSnapshotView)?.setRenderedImageFrame(imageFrame)
  }

  private func apply(containerFrame frame: CGRect, to surface: UIView) {
    surface.transform = .identity
    surface.bounds = CGRect(origin: .zero, size: frame.size)
    surface.center = CGPoint(x: frame.midX, y: frame.midY)
  }

  private func startTransitionGeometryDiagnostics(
    snapshot: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect,
    in coordinateSpace: UIView
  ) {
    logTransitionGeometry(
      "TAB SNAPSHOT START",
      snapshot: snapshot,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame,
      in: coordinateSpace
    )
#if DEBUG
    let midpoint = transitionDuration(using: nil) * 0.5
    DispatchQueue.main.asyncAfter(deadline: .now() + midpoint) { [weak snapshot, weak coordinateSpace] in
      guard let snapshot, let coordinateSpace else { return }
      self.logTransitionGeometry(
        "TAB SNAPSHOT MIDPOINT",
        snapshot: snapshot,
        sourceFrame: sourceFrame,
        targetFrame: targetFrame,
        in: coordinateSpace
      )
    }
#endif
  }

  private func logTransitionGeometry(
    _ phase: String,
    snapshot: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect,
    in coordinateSpace: UIView
  ) {
#if DEBUG
    let windowFrame = snapshot.convert(snapshot.bounds, to: coordinateSpace)
    let presentationFrame = snapshot.layer.presentation()?.frame
    AppLogger(.navigation).debug(
      "\(phase) source=\(sourceFrame) target=\(targetFrame) "
        + "frame=\(snapshot.frame) bounds=\(snapshot.bounds) "
        + "center=\(snapshot.center) windowFrame=\(windowFrame) "
        + "presentationFrame=\(String(describing: presentationFrame)) "
        + "transform=\(snapshot.transform) "
        + "superviewFrame=\(String(describing: snapshot.superview?.frame))"
    )
#endif
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
