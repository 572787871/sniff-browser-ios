import UIKit

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

    // 首次没有缩略图时才等待 WebView 截图；已有有效图直接开始转场，
    // 避免每次点击都被截图和磁盘写入延迟阻塞。
    if let tab = activeTab,
       let webView = tab.webView,
       !webView.isHidden,
       tab.snapshot == nil {
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
    guard newTabView.bounds.width > 0,
          newTabView.bounds.height > 0
    else {
      return nil
    }

    newTabView.setNeedsLayout()
    newTabView.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = 1
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
