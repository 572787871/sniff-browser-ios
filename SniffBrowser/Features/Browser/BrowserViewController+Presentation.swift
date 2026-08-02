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

  func presentAddFavoriteDialog() {
    let alert = UIAlertController(title: "添加收藏", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "名称"
      textField.text = self.viewModel.state.title
      textField.autocapitalizationType = .sentences
    }
    alert.addTextField { textField in
      textField.placeholder = "网址"
      textField.text = self.viewModel.state.url?.absoluteString ?? ""
      textField.keyboardType = .URL
    }
    let saveAction = UIAlertAction(title: "保存", style: .default) { [weak self] _ in
      guard let self else { return }
      let title = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? ""
      let urlString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? ""
      let url = URL(string: urlString) ?? self.viewModel.state.url
      do {
        try FavoriteService.shared.addFavorite(title: title.isEmpty ? nil : title, url: url)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        let errorAlert = UIAlertController(
          title: "无法添加收藏",
          message: error.localizedDescription,
          preferredStyle: .alert
        )
        errorAlert.addAction(UIAlertAction(title: "好", style: .default))
        self.present(errorAlert, animated: true)
      }
    }
    alert.addAction(saveAction)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let presenter = navigationController?.topViewController ?? self
    presenter.present(alert, animated: true)
  }

  func presentFavoriteContextMenu(for item: FavoriteItem, at point: CGPoint) {
    let alert = UIAlertController(title: item.title, message: item.host, preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "在新标签页中打开", style: .default) { [weak self] _ in
      self?.openNewTab(with: item.url, isPrivate: false)
      self?.router?.returnToBrowser()
    })
    alert.addAction(UIAlertAction(title: "在无痕标签页中打开", style: .default) { [weak self] _ in
      self?.openNewTab(with: item.url, isPrivate: true)
      self?.router?.returnToBrowser()
    })
    alert.addAction(UIAlertAction(title: "编辑收藏", style: .default) { [weak self] _ in
      self?.presentEditFavoriteDialog(for: item)
    })
    alert.addAction(UIAlertAction(title: "删除收藏", style: .destructive) { [weak self] _ in
      do {
        try FavoriteService.shared.removeFavorite(id: item.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
      }
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = newTabView
      popover.sourceRect = CGRect(origin: point, size: .zero)
    }
    let presenter = navigationController?.topViewController ?? self
    presenter.present(alert, animated: true)
  }

  func presentEditFavoriteDialog(for item: FavoriteItem) {
    let alert = UIAlertController(title: "编辑收藏", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.text = item.title
      textField.placeholder = "名称"
    }
    alert.addTextField { textField in
      textField.text = item.url.absoluteString
      textField.placeholder = "网址"
      textField.keyboardType = .URL
    }
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
      guard let self else { return }
      let newTitle = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? item.title
      let newURLString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? item.url.absoluteString
      do {
        try FavoriteService.shared.removeFavorite(id: item.id)
        if let newURL = URL(string: newURLString) {
          try FavoriteService.shared.addFavorite(title: newTitle, url: newURL)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
      }
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let presenter = navigationController?.topViewController ?? self
    presenter.present(alert, animated: true)
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
    controller.onSelectDestination = { [weak self] destination in
      switch destination {
      case .downloads: self?.router?.showDownloads()
      case .files: self?.router?.showFiles()
      case .favorites: self?.router?.showFavorites()
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
