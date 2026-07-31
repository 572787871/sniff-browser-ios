import UIKit

extension BrowserViewController {
  func showTabs() {
    let currentTabID = activeTab?.id
    let controller = TabOverviewViewController(items: makeTabItems())
    tabOverviewController = controller
    configureTabOverviewActions(controller)
    router?.showTabs(controller)

    Task { [weak self, weak controller] in
      guard let self, let controller else { return }
      if let currentTabID {
        await self.tabManager.captureSnapshot(for: currentTabID)
      }
      for tab in self.tabManager.tabs where tab.snapshot == nil {
        _ = await self.tabManager.loadSnapshotIfAvailable(for: tab.id)
      }
      controller.update(items: self.makeTabItems())
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
    controller.onNewTab = { [weak self] isPrivate in
      guard let self,
            self.openNewTab(isPrivate: isPrivate)
      else {
        return
      }
      self.router?.returnToBrowser()
    }
    controller.onCloseOtherTabs = { [weak self] id in
      self?.closeOtherTabs(keeping: id)
    }
    controller.onCloseAllNormalTabs = { [weak self] in
      self?.closeAllNormalTabs()
    }
    controller.onCopyTabURL = { _, url in
      UIPasteboard.general.url = url
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    controller.onShareTab = { [weak self] id, url in
      self?.shareTab(id: id, url: url)
    }
    controller.onOpenFavorites = { [weak self] _ in
      self?.router?.showFavorites()
    }
    controller.onDone = { [weak self] in
      self?.router?.returnToBrowser()
    }
  }

  func selectTab(id: UUID, returnsToBrowser: Bool) {
    let previousID = activeTab?.id
    guard tabManager.selectTab(id: id) != nil else { return }
    attachSelectedTab()
    if returnsToBrowser {
      router?.returnToBrowser()
    }
    Task { [weak self] in
      guard let self else { return }
      if let previousID, previousID != id {
        await self.tabManager.captureSnapshot(for: previousID)
      }
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

  func presentShare(title: String, url: URL) {
    let controller = UIActivityViewController(
      activityItems: [title, url],
      applicationActivities: nil
    )
    let presenter = navigationController?.topViewController ?? self
    presenter.present(controller, animated: true)
  }

  func presentMoreMenu() {
    let controller = BrowserMoreMenuViewController(
      state: BrowserMoreMenuState(
        hasCurrentPage: viewModel.state.url != nil,
        downloadSummary: nil,
        fileSummary: nil,
        accountSummary: "游客模式"
      )
    )
    controller.onQuickAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .newTab: self.openNewTab()
      case .share: self.shareCurrentPage()
      case .favorite: self.router?.showFavorites()
      case .reload: self.activeWebView?.reload()
      }
    }
    controller.onSelectDestination = { [weak self] destination in
      switch destination {
      case .downloads: self?.router?.showDownloads()
      case .files: self?.router?.showFiles()
      case .history: self?.router?.showHistory()
      case .userCenter: self?.router?.showUserCenter()
      case .settings: self?.router?.showSettings()
      }
    }
    if let sheet = controller.sheetPresentationController {
      sheet.detents = [.medium()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = AppRadius.sheet
      sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    }
    present(controller, animated: true)
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
