import UIKit

/// 在导航状态改变前冻结的当前网页视觉与坐标。
/// 快照视图只作为转场替身，不会移动或重挂真正的 WKWebView。
@MainActor
final class BrowserTabTransitionSnapshot {
  let contentView: UIView
  let contentSize: CGSize

  private let fullFrame: CGRect
  private let visibleFrame: CGRect
  private weak var sourceCoordinateSpace: UIView?

  init(
    contentView: UIView,
    contentSize: CGSize,
    fullFrame: CGRect,
    visibleFrame: CGRect,
    sourceCoordinateSpace: UIView
  ) {
    self.contentView = contentView
    self.contentSize = contentSize
    self.fullFrame = fullFrame
    self.visibleFrame = visibleFrame
    self.sourceCoordinateSpace = sourceCoordinateSpace
  }

  func frames(in coordinateSpace: UIView) -> (
    full: CGRect,
    visible: CGRect
  )? {
    guard let sourceCoordinateSpace else { return nil }
    return (
      sourceCoordinateSpace.convert(fullFrame, to: coordinateSpace),
      sourceCoordinateSpace.convert(visibleFrame, to: coordinateSpace)
    )
  }
}

extension BrowserViewController {
  func showTabs() {
    guard !isPreparingTabOverview else { return }
    refreshNewTabSnapshotsForOverview()

    // 放大转场仍在用缓存图遮住重新加载的 WebView 时，继续复用这张有效图，
    // 避免截取到遮罩下方尚未渲染的白页。
    if tabTransitionCoverView != nil {
      presentTabOverview()
      return
    }

    // 网页稳定时刷新当前快照，使动画终点卡片与用户刚看到的滚动位置一致。
    // 页面仍在加载且已有可用图时直接使用旧图，避免等待不完整的截图。
    if let tab = activeTab,
       let webView = tab.webView,
       !webView.isHidden,
       webView.bounds.width > 0,
       webView.bounds.height > 0,
       (tab.snapshot == nil || !webView.isLoading) {
      let tabID = tab.id
      isPreparingTabOverview = true
      Task { [weak self] in
        guard let self else { return }
        _ = await self.tabManager.captureSnapshot(for: tabID)
        self.isPreparingTabOverview = false
        guard self.activeTab?.id == tabID else { return }
        self.presentTabOverview()
      }
      return
    }

    presentTabOverview()
  }

  /// 在 push 导航改变安全区之前冻结网页，确保动画从用户点击时看到的
  /// 原始位置开始，而不是从导航栏布局完成后的新位置开始。
  func prepareTabTransitionSnapshot() {
    guard let coordinateSpace = view.window ?? view else { return }
    pendingTabTransitionSnapshot = makeTabTransitionSnapshot(
      in: coordinateSpace,
      fallbackImage: tabTransitionCoverView?.image ?? activeTab?.snapshot
    )
  }

  func consumeTabTransitionSnapshot(
    in coordinateSpace: UIView,
    fallbackImage: UIImage?
  ) -> BrowserTabTransitionSnapshot? {
    defer { pendingTabTransitionSnapshot = nil }
    return pendingTabTransitionSnapshot ?? makeTabTransitionSnapshot(
      in: coordinateSpace,
      fallbackImage: fallbackImage
    )
  }

  func discardTabTransitionSnapshot() {
    pendingTabTransitionSnapshot = nil
  }

  func makeTabTransitionSnapshot(
    in coordinateSpace: UIView,
    fallbackImage: UIImage?
  ) -> BrowserTabTransitionSnapshot? {
    view.layoutIfNeeded()
    let content = tabTransitionContentView()
    content.layoutIfNeeded()
    let fullFrame = content.convert(content.bounds, to: coordinateSpace)
    let visibleFrame = tabTransitionContentFrame(in: coordinateSpace)
    guard fullFrame.width > 0,
          fullFrame.height > 0,
          visibleFrame.width > 0,
          visibleFrame.height > 0
    else { return nil }

    let snapshotView: UIView
    let contentSize: CGSize
    // 原生主页包含 UIScrollView、UIButton.Configuration 和动态约束。
    // 不把这套层级快照直接交给转场，避免主页从标签页返回时抓到
    // Auto Layout 尚未完成的中间帧；网页仍然使用 WKWebView 的实时快照。
    if content === newTabView,
       let stableNewTabImage = activeTab?.snapshot
        ?? fallbackImage
        ?? renderNewTabSnapshot() {
      // 进入总览前已经把主页渲染到 activeTab.snapshot。优先复用这张图，
      // 让正在缩小的网页和落点卡片使用同一份像素，避免 favicon 或布局
      // 在转场中途发生跳变。
      snapshotView = TabPageSnapshotView(image: stableNewTabImage)
      contentSize = stableNewTabImage.size
    } else if tabTransitionCoverView == nil,
              let liveSnapshot = content.snapshotView(afterScreenUpdates: false) {
      snapshotView = liveSnapshot
      contentSize = content.bounds.size
    } else if let fallbackImage {
      snapshotView = TabPageSnapshotView(image: fallbackImage)
      contentSize = fallbackImage.size
    } else {
      return nil
    }

    snapshotView.backgroundColor = AppColors.surface
    snapshotView.isUserInteractionEnabled = false
    snapshotView.isAccessibilityElement = false
    snapshotView.accessibilityIdentifier = "browser.tabTransitionSnapshot"
    return BrowserTabTransitionSnapshot(
      contentView: snapshotView,
      contentSize: contentSize,
      fullFrame: fullFrame,
      visibleFrame: visibleFrame,
      sourceCoordinateSpace: coordinateSpace
    )
  }

  /// 返回缓存图对应的完整页面区域，用于让转场图和底层遮罩保持同一缩放比例。
  func tabTransitionFullContentFrame(in coordinateSpace: UIView) -> CGRect {
    view.layoutIfNeeded()
    let content = tabTransitionContentView()
    return content.convert(content.bounds, to: coordinateSpace)
  }

  /// 返回实际参与缩放的可见网页区域；顶部地址栏和底部工具栏留给
  /// 页面间交叉淡化，不会被网页图片突然覆盖。
  func tabTransitionContentFrame(in coordinateSpace: UIView) -> CGRect {
    var frame = tabTransitionFullContentFrame(in: coordinateSpace)
    if !addressBar.isHidden {
      let addressFrame = addressBar.convert(addressBar.bounds, to: coordinateSpace)
      let visibleTop = min(frame.maxY, max(frame.minY, addressFrame.maxY))
      frame.size.height = max(1, frame.maxY - visibleTop)
      frame.origin.y = visibleTop
    }
    if !toolbar.isHidden {
      let toolbarFrame = toolbar.convert(toolbar.bounds, to: coordinateSpace)
      frame.size.height = max(
        1,
        min(frame.maxY, toolbarFrame.minY) - frame.minY
      )
    }
    return frame
  }

  /// 返回当前目标主页的稳定位图，供卡片展开时遮住真实主页，直到
  /// 转场完成。已有总览缩略图时必须复用它，保证卡片与网页内容连续。
  func makeTabTransitionImage(
    for tabID: UUID,
    fallbackImage: UIImage?
  ) -> UIImage? {
    if let fallbackImage {
      return fallbackImage
    }
    guard activeTab?.id == tabID,
          activeTab?.url == nil,
          !newTabView.isHidden
    else { return nil }

    view.setNeedsLayout()
    view.layoutIfNeeded()
    contentView.setNeedsLayout()
    contentView.layoutIfNeeded()
    return renderNewTabSnapshot() ?? fallbackImage
  }

  func setTabTransitionPageHidden(_ hidden: Bool) {
    tabTransitionContentView().alpha = hidden ? 0 : 1
    tabTransitionCoverView?.alpha = hidden ? 0 : 1
  }

  func setTabTransitionChromeAlpha(_ alpha: CGFloat) {
    topChromeBackgroundView.alpha = alpha
    addressBar.alpha = alpha
    toolbar.alpha = alpha
  }

  /// 在恢复中的 WKWebView 上方保留标签页缓存图，直到网页完成渲染。
  func installTabTransitionCover(image: UIImage) {
    let selectedTabRequiresLoad = tabTransitionRequiresPageLoad
    removeTabTransitionCover(animated: false)
    view.layoutIfNeeded()

    let content = tabTransitionContentView()
    let coverView = TabPageSnapshotView(image: image)
    coverView.frame = content.convert(content.bounds, to: contentView)
    coverView.backgroundColor = AppColors.surface
    coverView.isAccessibilityElement = false
    coverView.accessibilityIdentifier = "browser.tabTransitionCover"
    contentView.addSubview(coverView)

    tabTransitionCoverView = coverView
    tabTransitionCoverID = UUID()
    tabTransitionRequiresPageLoad = selectedTabRequiresLoad
      || activeWebView?.isLoading == true
  }

  /// 已经驻留并完成显示的页面可以立即淡出缓存图；重新创建的 WebView
  /// 则等待 didFinish，超时后也会自动释放，避免永久遮挡错误页面。
  func completeTabTransitionCover() {
    guard tabTransitionCoverView != nil else { return }
    if !newTabView.isHidden {
      DispatchQueue.main.async { [weak self] in
        self?.removeTabTransitionCover(animated: true)
      }
      return
    }
    if !tabTransitionRequiresPageLoad,
       let webView = activeWebView,
       webView.url != nil,
       !webView.isLoading {
      DispatchQueue.main.async { [weak self] in
        self?.removeTabTransitionCover(animated: true)
      }
      return
    }

    let expectedID = tabTransitionCoverID
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
      guard let self,
            self.tabTransitionCoverID == expectedID
      else { return }
      self.removeTabTransitionCover(animated: true)
    }
  }

  func removeTabTransitionCover(animated: Bool) {
    guard let cover = tabTransitionCoverView else {
      tabTransitionCoverID = nil
      tabTransitionRequiresPageLoad = false
      return
    }
    tabTransitionCoverView = nil
    tabTransitionCoverID = nil
    tabTransitionRequiresPageLoad = false

    let remove = {
      cover.removeFromSuperview()
    }
    guard animated, view.window != nil else {
      remove()
      return
    }
    UIView.animate(
      withDuration: 0.16,
      delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
      animations: {
        cover.alpha = 0
      },
      completion: { _ in remove() }
    )
  }

  private func tabTransitionContentView() -> UIView {
    if let webView = activeWebView, !webView.isHidden {
      return webView
    }
    if !newTabView.isHidden {
      return newTabView
    }
    return contentView
  }

  private func presentTabOverview() {
    prepareTabTransitionSnapshot()
    let controller = TabOverviewViewController(items: makeTabItems())
    tabOverviewController = controller
    configureTabOverviewActions(controller)
    router?.showTabs(controller)

    Task { [weak self, weak controller] in
      guard let self, let controller else { return }
      for tab in self.tabManager.tabs where tab.snapshot == nil {
        _ = await self.tabManager.loadSnapshotIfAvailable(for: tab.id)
      }
      controller.update(items: self.makeTabItems())
    }
  }

  /// WKWebView 无法截取原生的新标签页，因此在进入标签页总览前直接渲染主页。
  func captureActiveNewTabSnapshot() {
    guard let tab = activeTab,
          tab.url == nil,
          !newTabView.isHidden,
          newTabView.bounds.width > 0,
          newTabView.bounds.height > 0
    else { return }

    guard let image = renderNewTabSnapshot() else { return }
    tab.updateSnapshot(image)
  }

  /// 总览打开前重绘所有原生主页标签，修复旧版本留下的空白快照，
  /// 同时让背景、收藏入口和无痕配色始终保持最新。
  func refreshNewTabSnapshotsForOverview() {
    let newTabs = tabManager.tabs.filter {
      $0.url == nil
        && $0.webView?.url == nil
        && lastRequestedURLs[$0.id] == nil
    }
    guard !newTabs.isEmpty else { return }

    let activeMode = activeTab?.isPrivate == true
    let wasHidden = newTabView.isHidden
    refreshNewTabFavorites()
    if wasHidden {
      contentView.sendSubviewToBack(newTabView)
    }

    for isPrivate in [false, true]
    where newTabs.contains(where: { $0.isPrivate == isPrivate }) {
      newTabView.setPrivateMode(isPrivate)
      newTabView.isHidden = false
      guard let image = renderNewTabSnapshot() else { continue }
      newTabs
        .filter { $0.isPrivate == isPrivate }
        .forEach { $0.updateSnapshot(image) }
    }

    newTabView.setPrivateMode(activeMode)
    newTabView.isHidden = wasHidden
  }

  private func renderNewTabSnapshot() -> UIImage? {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    contentView.setNeedsLayout()
    contentView.layoutIfNeeded()
    guard newTabView.bounds.width > 0,
          newTabView.bounds.height > 0
    else {
      return nil
    }

    newTabView.setNeedsLayout()
    newTabView.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat.preferred()
    // 主页截图会同时用于卡片缩略图和卡片→网页的放大转场。
    // 固定 1x 会让文字和 favicon 在放大到全屏时出现明显模糊。
    format.scale = max(
      1,
      newTabView.window?.screen.scale ?? UIScreen.main.scale
    )
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(
      size: newTabView.bounds.size,
      format: format
    )
    return renderer.image { context in
      let rendered = newTabView.drawHierarchy(
        in: newTabView.bounds,
        afterScreenUpdates: true
      )
      if !rendered {
        newTabView.layer.render(in: context.cgContext)
      }
    }
  }

  func makeTabItems() -> [TabOverviewItem] {
    tabManager.tabs.map { tab in
      TabOverviewItem(
        id: tab.id,
        title: tab.title,
        url: tab.url,
        thumbnail: tab.snapshot,
        isSelected: tab.id == tabManager.selectedTabID,
        isPrivate: tab.isPrivate
      )
    }
  }

  func configureTabOverviewActions(_ controller: TabOverviewViewController) {
    controller.onSelectTab = { [weak self] id in
      self?.selectTab(id: id, returnsToBrowser: true)
    }
    controller.onCloseTab = { [weak self] id in
      self?.closeTab(id: id)
    }
    controller.onNewTab = { [weak self, weak controller] isPrivate in
      guard let self,
            self.openNewTab(isPrivate: isPrivate)
      else {
        return
      }
      controller?.disableNextSpatialTransition()
      self.router?.returnToBrowser()
    }
    controller.onCloseOtherTabs = { [weak self] id in
      self?.closeOtherTabs(keeping: id)
    }
    controller.onCloseAllNormalTabs = { [weak self] in
      self?.closeAllNormalTabs()
    }
    controller.onCloseAllTabs = { [weak self] isPrivate in
      self?.closeAllTabs(isPrivate: isPrivate)
    }
    controller.onCopyTabURL = { _, url in
      UIPasteboard.general.url = url
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    controller.onShareTab = { [weak self] id, url in
      self?.shareTab(id: id, url: url)
    }
    controller.favoriteActionStateProvider = { [weak self] url in
      guard let self else {
        return FavoriteActionState(isEnabled: false, isFavorite: false)
      }
      return (try? self.favoriteService.actionState(for: url))
        ?? FavoriteActionState(isEnabled: false, isFavorite: false)
    }
    controller.onToggleFavorite = { [weak self] id in
      self?.toggleTabFavorite(id: id)
    }
    controller.onDone = { [weak self] in
      self?.router?.returnToBrowser()
    }
  }

  func selectTab(id: UUID, returnsToBrowser: Bool) {
    captureActiveNewTabSnapshot()
    let requiresPageReload = tabManager.tabs.first {
      $0.id == id
    }.map {
      $0.url != nil && $0.webView == nil
    } ?? false
    guard tabManager.selectTab(id: id) != nil else { return }
    attachSelectedTab()
    tabTransitionRequiresPageLoad = requiresPageReload
    if returnsToBrowser {
      router?.returnToBrowser()
    }
    Task { [weak self] in
      guard let self else { return }
      await self.tabManager.enforceResidentWebViewLimit()
    }
  }

  func closeTab(id: UUID) {
    let wasSelected = tabManager.selectedTabID == id
    guard tabManager.closeTab(id: id) != nil else { return }
    lastRequestedURLs[id] = nil
    lastFailedURLs[id] = nil
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    if wasSelected {
      attachSelectedTab()
      tabOverviewController?.selectMode(
        isPrivate: tabManager.selectedTab?.isPrivate == true
      )
    }
    refreshTabOverview()
  }

  func closeOtherTabs(keeping id: UUID) {
    guard let reference = tabManager.tabs.first(where: { $0.id == id }) else {
      return
    }
    let closingIDs = tabManager.tabs
      .filter { $0.id != id && $0.isPrivate == reference.isPrivate }
      .map(\.id)
    closingIDs.forEach {
      tabManager.closeTab(id: $0)
      lastRequestedURLs[$0] = nil
      lastFailedURLs[$0] = nil
    }
    if tabManager.selectedTabID != id {
      _ = tabManager.selectTab(id: id)
      attachSelectedTab()
    }
    tabOverviewController?.selectMode(isPrivate: reference.isPrivate)
    refreshTabOverview()
  }

  func closeAllNormalTabs() {
    let selectedWasNormal = activeTab?.isPrivate == false
    let closingIDs = tabManager.tabs.filter { !$0.isPrivate }.map(\.id)
    closingIDs.forEach {
      tabManager.closeTab(id: $0)
      lastRequestedURLs[$0] = nil
      lastFailedURLs[$0] = nil
    }
    if selectedWasNormal {
      attachSelectedTab()
      tabOverviewController?.selectMode(
        isPrivate: tabManager.selectedTab?.isPrivate == true
      )
    }
    refreshTabOverview()
  }

  func closeAllTabs(isPrivate: Bool) {
    let selectedWasThisMode = activeTab?.isPrivate == isPrivate
    let closingIDs = tabManager.tabs.filter { $0.isPrivate == isPrivate }.map(\.id)
    tabManager.closeAllTabs(isPrivate: isPrivate)
    closingIDs.forEach {
      lastRequestedURLs[$0] = nil
      lastFailedURLs[$0] = nil
    }
    if selectedWasThisMode {
      attachSelectedTab()
      tabOverviewController?.selectMode(
        isPrivate: tabManager.selectedTab?.isPrivate == true
      )
    }
    refreshTabOverview()
  }

  func refreshTabOverview() {
    tabOverviewController?.update(items: makeTabItems())
  }

  func shareTab(id: UUID, url: URL?) {
    guard let tab = tabManager.tabs.first(where: { $0.id == id }),
          let url = url ?? tab.url
    else {
      return
    }
    presentShare(title: tab.title, url: url)
  }

  func shareCurrentPage() {
    guard let url = viewModel.state.url else { return }
    presentShare(title: viewModel.state.title, url: url)
  }

  @discardableResult
  func openFavoriteURL(
    _ url: URL,
    inNewNormalTab: Bool
  ) -> Bool {
    if inNewNormalTab {
      return openNewTab(with: url, isPrivate: false)
    }

    if activeTab?.isPrivate == true {
      guard let normalTab = tabManager.tabs
        .filter({ !$0.isPrivate })
        .max(by: { $0.lastVisitedDate < $1.lastVisitedDate })
      else {
        return openNewTab(with: url, isPrivate: false)
      }
      selectTab(id: normalTab.id, returnsToBrowser: false)
    }
    load(url)
    return true
  }

  func toggleTabFavorite(id: UUID) {
    guard let tab = tabManager.tabs.first(where: { $0.id == id }) else {
      return
    }
    do {
      let result = try favoriteService.toggleFavorite(
        title: tab.title,
        url: tab.url
      )
      let message: String
      switch result {
      case .added:
        message = tab.isPrivate
          ? "已主动保存到收藏夹；不会写入浏览历史"
          : "已添加到收藏夹"
      case .removed:
        message = "已从收藏夹移除"
      }
      refreshNewTabFavorites()
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      UIAccessibility.post(
        notification: .announcement,
        argument: message
      )
    } catch {
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      let alert = UIAlertController(
        title: "无法更新收藏夹",
        message: error.localizedDescription,
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "好", style: .default))
      let presenter = navigationController?.topViewController ?? self
      presenter.present(alert, animated: true)
    }
  }

  func presentShare(title: String, url: URL) {
    let controller = UIActivityViewController(
      activityItems: [title, url],
      applicationActivities: nil
    )
    let presenter = navigationController?.topViewController ?? self
    presenter.present(controller, animated: true)
  }

  func presentMoreMenu() {
    let favoriteURL = currentPageURLForFavorite()
    let favoriteActionState = (
      try? favoriteService.actionState(for: favoriteURL)
    ) ?? FavoriteActionState(isEnabled: false, isFavorite: false)
    let controller = BrowserMoreMenuViewController(
      state: BrowserMoreMenuState(
        hasCurrentPage: viewModel.state.url != nil,
        downloadSummary: nil,
        fileSummary: nil,
        accountSummary: "游客模式",
        favoriteActionState: favoriteActionState
      )
    )
    controller.onQuickAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .newTab: self.openNewTab()
      case .share: self.shareCurrentPage()
      case .favorite: self.toggleFavoriteForCurrentPage()
      case .reload: self.activeWebView?.reload()
      }
    }
    controller.onSelectDestination = { [weak self, weak controller] destination in
      guard let self,
            let navigation = controller?.navigationController
      else { return }
      self.router?.showMoreDestination(
        destination,
        in: navigation
      )
    }
    let navigation = BrowserMoreNavigationController(root: controller)
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = AppRadius.sheet
      sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }
    present(navigation, animated: true)
  }

  func currentPageURLForFavorite() -> URL? {
    guard errorView.isHidden,
          newTabView.isHidden,
          let url = viewModel.state.url
    else {
      return nil
    }
    return url
  }

  func toggleFavoriteForCurrentPage() {
    do {
      let result = try favoriteService.toggleFavorite(
        title: viewModel.state.title,
        url: currentPageURLForFavorite()
      )
      let message: String
      switch result {
      case .added:
        message = activeTab?.isPrivate == true
          ? "已主动保存到收藏夹；不会写入浏览历史"
          : "已添加到收藏夹"
      case .removed:
        message = "已从收藏夹移除"
      }
      refreshNewTabFavorites()
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      showTransientBrowserFeedback(message)
    } catch {
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      let alert = UIAlertController(
        title: "无法更新收藏夹",
        message: error.localizedDescription,
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "好", style: .default))
      present(alert, animated: true)
    }
  }

  func showTransientBrowserFeedback(_ message: String) {
    let feedbackView = AppMaterialView(
      style: .systemMaterial,
      fallbackColor: AppColors.chromeFallback
    )
    feedbackView.layer.cornerRadius = AppRadius.control
    feedbackView.layer.cornerCurve = .continuous
    feedbackView.clipsToBounds = true
    feedbackView.translatesAutoresizingMaskIntoConstraints = false

    let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    imageView.tintColor = AppColors.success
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = message
    label.font = AppTypography.subheadline
    label.textColor = AppColors.primaryText
    label.adjustsFontForContentSizeCategory = true
    label.translatesAutoresizingMaskIntoConstraints = false

    feedbackView.contentView.addSubview(imageView)
    feedbackView.contentView.addSubview(label)
    view.addSubview(feedbackView)
    NSLayoutConstraint.activate([
      feedbackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      feedbackView.topAnchor.constraint(
        equalTo: addressBar.bottomAnchor,
        constant: AppSpacing.sm
      ),
      feedbackView.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.leadingAnchor,
        constant: AppSpacing.lg
      ),
      feedbackView.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -AppSpacing.lg
      ),
      feedbackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      imageView.leadingAnchor.constraint(
        equalTo: feedbackView.contentView.leadingAnchor,
        constant: AppSpacing.sm
      ),
      imageView.centerYAnchor.constraint(
        equalTo: feedbackView.contentView.centerYAnchor
      ),
      imageView.widthAnchor.constraint(equalToConstant: 19),
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
      label.leadingAnchor.constraint(
        equalTo: imageView.trailingAnchor,
        constant: AppSpacing.xs
      ),
      label.trailingAnchor.constraint(
        equalTo: feedbackView.contentView.trailingAnchor,
        constant: -AppSpacing.sm
      ),
      label.topAnchor.constraint(
        equalTo: feedbackView.contentView.topAnchor,
        constant: AppSpacing.xs
      ),
      label.bottomAnchor.constraint(
        equalTo: feedbackView.contentView.bottomAnchor,
        constant: -AppSpacing.xs
      ),
    ])
    feedbackView.alpha = 0
    feedbackView.transform = CGAffineTransform(translationX: 0, y: -8)
    UIAccessibility.post(notification: .announcement, argument: message)
    AppAppearance.animate {
      feedbackView.alpha = 1
      feedbackView.transform = .identity
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      AppAppearance.animate(
        duration: AppAppearance.quickAnimationDuration,
        animations: {
          feedbackView.alpha = 0
          feedbackView.transform = CGAffineTransform(
            translationX: 0,
            y: -6
          )
        },
        completion: { _ in feedbackView.removeFromSuperview() }
      )
    }
  }

  func presentMaximumTabsMessage() {
    let alert = UIAlertController(
      title: "标签页已达上限",
      message: "最多可同时保留 30 个标签页。请先关闭不再使用的标签页。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    let presenter = navigationController?.topViewController ?? self
    presenter.present(alert, animated: true)
  }
}
