import UIKit
import WebKit

@MainActor
protocol BrowserRouting: AnyObject {
  func showResources(_ controller: ResourceSnifferViewController)
  func showTabs(_ controller: TabOverviewViewController)
  func returnToBrowser()
  func showFavorites()
  func showHistory()
  func showDownloads()
  func showFiles()
  func showUserCenter()
  func showSettings()
  func showMoreDestination(
    _ destination: BrowserMenuDestination,
    in navigationController: UINavigationController
  )
}

@MainActor
final class BrowserViewController: UIViewController {
  weak var router: BrowserRouting?

  let viewModel: BrowserViewModel
  let tabManager: BrowserTabManager
  let favoriteService: FavoriteService
  let historyService: HistoryService
  let contentBlockerService: ContentBlockerService
  let resourceStore: TabResourceStore
  let resourceSniffingService: WebResourceSniffingService
  let downloadCenter: DownloadCenter
  let downloadRequestContextBuilder = DownloadRequestContextBuilder()
  let addressBar = AddressBarView()
  let toolbar = BrowserToolbar(frame: .zero)
  let contentView = UIView()
  let topChromeBackgroundView = UIView()
  let newTabView = NewTabView()
  let errorView = BrowserErrorView()
  private let searchOverlayBackgroundView = AppPageBackgroundView()
  private let quickLinksScrollView = UIScrollView()
  private let quickLinksStack = UIStackView()
  private let searchHistoryTableView = UITableView(frame: .zero, style: .plain)
  private let searchHistoryEmptyLabel = UILabel()
  lazy var externalURLHandler = ExternalURLHandler(presenter: self)

  var observations: [NSKeyValueObservation] = []
  var chromeScrollController = BrowserChromeScrollController()
  var lastFailedURLs: [UUID: URL] = [:]
  var lastRequestedURLs: [UUID: URL] = [:]
  weak var tabOverviewController: TabOverviewViewController?
  var isPreparingTabOverview = false
  var pendingTabTransitionSnapshot: BrowserTabTransitionSnapshot?
  /// 已经在进入总览前完成的 WKWebView 视口截图。只缓存 UIImage，绝不
  /// 复用参与过动画的 UIView，保证黑色页面和重复转场都从冻结画面开始。
  var pendingTabTransitionImage: UIImage?
  var tabTransitionCoverView: TabPageSnapshotView?
  var tabTransitionCoverID: UUID?
  var tabTransitionRequiresPageLoad = false
  /// 标签总览每次都会创建新的 Controller，因此滚动位置保存在持久的
  /// Browser 层；普通与无痕互不覆盖。
  var standardTabOverviewScrollOffset: CGFloat = 0
  var privateTabOverviewScrollOffset: CGFloat = 0
  var pageChromeForegroundStyle: BrowserChromeForegroundStyle?
  private var currentChromeState: BrowserChromeState = .expanded
  private var resolvedPageChromeBackgroundColor: UIColor = AppColors.background
  var elementHideInjected: [ObjectIdentifier: Bool] = [:]
  var blockedElementCounterHandler: BlockedElementCounterHandler?
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var activeResourceObservationToken: UUID?
  private var searchHistoryItems: [HistoryItem] = []
  private var searchHistoryQuery = ""
  private var searchSuggestionContext = BrowserSearchSuggestionContext.webPage
  private var isSearchHistoryVisible = false
  private var isSearchSuggestionsPinned = false
  private var quickLinksHeightConstraint: NSLayoutConstraint?
  private var isWaitingToRefreshNewTabSnapshot = false
  private var activeWebViewConstraints: [NSLayoutConstraint] = []

  struct TabTransitionScrollState {
    let tabID: UUID
    let contentOffset: CGPoint
    let contentInset: UIEdgeInsets
    let adjustedContentInset: UIEdgeInsets
  }

  /// 点击标签卡片时暂存目标 WebView 的可视文档位置。重新挂载或 Chrome
  /// 布局可能短暂改变 adjustedContentInset，交接前会按文档坐标恢复。
  var tabTransitionScrollState: TabTransitionScrollState?

  var activeTab: BrowserTab? {
    tabManager.selectedTab
  }

  var activeWebView: WKWebView? {
    activeTab?.webView
  }

  init(
    viewModel: BrowserViewModel,
    tabManager: BrowserTabManager,
    favoriteService: FavoriteService,
    historyService: HistoryService,
    contentBlockerService: ContentBlockerService,
    resourceStore: TabResourceStore,
    downloadCenter: DownloadCenter
  ) {
    self.viewModel = viewModel
    self.tabManager = tabManager
    self.favoriteService = favoriteService
    self.historyService = historyService
    self.contentBlockerService = contentBlockerService
    self.resourceStore = resourceStore
    self.downloadCenter = downloadCenter
    resourceSniffingService = WebResourceSniffingService(
      store: resourceStore
    )
    super.init(nibName: nil, bundle: nil)
  }

  convenience init(downloadCenter: DownloadCenter) {
    self.init(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: downloadCenter
    )
  }

  convenience init() {
    self.init(downloadCenter: .shared)
  }

  required init?(coder: NSCoder) {
    viewModel = BrowserViewModel()
    tabManager = BrowserTabManager()
    favoriteService = .shared
    historyService = .shared
    contentBlockerService = .shared
    let resolvedResourceStore = TabResourceStore()
    resourceStore = resolvedResourceStore
    downloadCenter = .shared
    resourceSniffingService = WebResourceSniffingService(
      store: resolvedResourceStore
    )
    super.init(coder: coder)
  }

  deinit {
    let center = NotificationCenter.default
    lifecycleObservers.forEach { center.removeObserver($0) }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    configureActions()
    configureLifecycleObservers()
    observeContentBlockerChanges()
    observeNewTabBackgroundChanges()
    refreshNewTabFavorites()
    attachSelectedTab()
    contentBlockerService.loadIfNeeded()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // 设置页修改新标签页选项后，回到浏览器时立即生效。
    newTabView.refreshContentPreferences()
    refreshNewTabFavorites()
    updateBrowserChromeVisibility()
  }

  private func observeContentBlockerChanges() {
    let observer = NotificationCenter.default.addObserver(
      forName: .contentBlockerDidChange,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        let reloadActivePage =
          notification.userInfo?[ContentBlockerService.reloadActivePageUserInfoKey]
            as? Bool ?? true
        self?.reapplyContentRules(reloadActivePage: reloadActivePage)
      }
    }
    lifecycleObservers.append(observer)
  }

  private func observeNewTabBackgroundChanges() {
    let observer = NotificationCenter.default.addObserver(
      forName: .newTabBackgroundDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.setNeedsStatusBarAppearanceUpdate()
      }
    }
    lifecycleObservers.append(observer)
  }

  private func reapplyContentRules(reloadActivePage: Bool) {
    for tab in tabManager.tabs {
      guard let webView = tab.webView else { continue }
      let host = webView.url?.host ?? tab.url?.host
      let changed = contentBlockerService.applyRules(
        to: webView,
        tabID: tab.id,
        host: host
      )
      if changed, reloadActivePage, tab.id == activeTab?.id {
        webView.reload()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateBrowserTopSafeArea()
    updateActiveWebViewInsets()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    updateBrowserTopSafeArea()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    if let pageChromeForegroundStyle {
      return pageChromeForegroundStyle.statusBarStyle
    }
    if isShowingNewTab, !isSearchOverlayActive, newTabView.showsPhotoBackground {
      return .lightContent
    }
    return traitCollection.userInterfaceStyle == .dark
      ? .lightContent
      : .darkContent
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    Task { [weak self] in
      await self?.tabManager.handleMemoryPressure()
      self?.refreshTabOverview()
    }
  }

  @discardableResult
  func openNewTab(isPrivate: Bool = false) -> Bool {
    createNewTab(isPrivate: isPrivate, initialURL: nil)
  }

  @discardableResult
  func openNewTab(with url: URL, isPrivate: Bool) -> Bool {
    createNewTab(isPrivate: isPrivate, initialURL: url)
  }

  @discardableResult
  private func createNewTab(
    isPrivate: Bool,
    initialURL: URL?
  ) -> Bool {
    captureActiveNewTabSnapshot()
    do {
      _ = try tabManager.createTab(isPrivate: isPrivate)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      attachSelectedTab()
      if let initialURL {
        load(initialURL)
      }
      Task { [weak self] in
        guard let self else { return }
        await self.tabManager.enforceResidentWebViewLimit()
      }
      return true
    } catch BrowserTabManager.ManagerError.maximumTabCountReached {
      presentMaximumTabsMessage()
    } catch {
      presentMaximumTabsMessage()
    }
    return false
  }

  func showPrivateTabFromExternalRoute() {
    _ = openNewTab(isPrivate: true)
  }

  func reloadActivePageAfterClearingWebsiteData() {
    activeWebView?.reload()
  }

  private func configureView() {
    view.backgroundColor = AppColors.background

    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.backgroundColor = AppColors.background
    contentView.clipsToBounds = true
    newTabView.translatesAutoresizingMaskIntoConstraints = false
    errorView.translatesAutoresizingMaskIntoConstraints = false
    errorView.isHidden = true

    view.addSubview(contentView)
    contentView.addSubview(newTabView)
    contentView.addSubview(errorView)
    topChromeBackgroundView.backgroundColor = AppColors.background
    topChromeBackgroundView.isUserInteractionEnabled = false
    topChromeBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topChromeBackgroundView)
    view.addSubview(addressBar)
    searchOverlayBackgroundView.isUserInteractionEnabled = false
    searchOverlayBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(searchOverlayBackgroundView)
    configureQuickLinksView()
    view.addSubview(quickLinksScrollView)
    configureSearchHistoryView()
    view.addSubview(searchHistoryTableView)
    view.addSubview(toolbar)

    addressBar.isHidden = true
    topChromeBackgroundView.isHidden = true
    searchOverlayBackgroundView.isHidden = true
    quickLinksScrollView.isHidden = true
    searchHistoryTableView.isHidden = true

    NSLayoutConstraint.activate([
      contentView.topAnchor.constraint(equalTo: view.topAnchor),
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      newTabView.topAnchor.constraint(equalTo: contentView.topAnchor),
      newTabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      newTabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      newTabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      errorView.topAnchor.constraint(
        equalTo: contentView.safeAreaLayoutGuide.topAnchor
      ),
      errorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      errorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      errorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      topChromeBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
      topChromeBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topChromeBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topChromeBackgroundView.bottomAnchor.constraint(
        equalTo: addressBar.bottomAnchor,
        constant: AppSpacing.xs
      ),

      addressBar.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: AppSpacing.xxs
      ),
      addressBar.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: AppSpacing.md
      ),
      addressBar.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -AppSpacing.md
      ),

      searchOverlayBackgroundView.topAnchor.constraint(
        equalTo: addressBar.bottomAnchor
      ),
      searchOverlayBackgroundView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      searchOverlayBackgroundView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      searchOverlayBackgroundView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),

      quickLinksScrollView.topAnchor.constraint(
        equalTo: addressBar.bottomAnchor
      ),
      quickLinksScrollView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      quickLinksScrollView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),

      searchHistoryTableView.topAnchor.constraint(
        equalTo: quickLinksScrollView.bottomAnchor
      ),
      searchHistoryTableView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      searchHistoryTableView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      searchHistoryTableView.bottomAnchor.constraint(
        equalTo: toolbar.topAnchor,
        constant: -AppSpacing.xs
      ),

      toolbar.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: AppSpacing.md
      ),
      toolbar.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -AppSpacing.md
      ),
      toolbar.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -AppSpacing.xxs
      ),
    ])

    let dismissEditingGesture = UITapGestureRecognizer(
      target: self,
      action: #selector(contentTapped)
    )
    dismissEditingGesture.cancelsTouchesInView = false
    dismissEditingGesture.delegate = self
    contentView.addGestureRecognizer(dismissEditingGesture)

    registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
      (controller: BrowserViewController, _) in
      controller.applyPageTheme(
        controller.activeTab?.pageThemeColor,
        animated: false
      )
    }
  }

  private func configureQuickLinksView() {
    quickLinksScrollView.translatesAutoresizingMaskIntoConstraints = false
    quickLinksScrollView.backgroundColor = .clear
    quickLinksScrollView.showsHorizontalScrollIndicator = false
    quickLinksScrollView.alwaysBounceHorizontal = true
    quickLinksScrollView.accessibilityIdentifier = "browser.searchFavorites"
    quickLinksScrollView.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: AppSpacing.xs,
      leading: AppSpacing.md,
      bottom: AppSpacing.xs,
      trailing: AppSpacing.md
    )

    quickLinksStack.translatesAutoresizingMaskIntoConstraints = false
    quickLinksStack.axis = .horizontal
    quickLinksStack.alignment = .fill
    quickLinksStack.spacing = AppSpacing.sm
    quickLinksScrollView.addSubview(quickLinksStack)

    let heightConstraint = quickLinksScrollView.heightAnchor
      .constraint(equalToConstant: 0)
    quickLinksHeightConstraint = heightConstraint
    NSLayoutConstraint.activate([
      quickLinksStack.topAnchor.constraint(
        equalTo: quickLinksScrollView.contentLayoutGuide.topAnchor,
        constant: AppSpacing.xs
      ),
      quickLinksStack.leadingAnchor.constraint(
        equalTo: quickLinksScrollView.contentLayoutGuide.leadingAnchor,
        constant: AppSpacing.md
      ),
      quickLinksStack.trailingAnchor.constraint(
        equalTo: quickLinksScrollView.contentLayoutGuide.trailingAnchor,
        constant: -AppSpacing.md
      ),
      quickLinksStack.bottomAnchor.constraint(
        equalTo: quickLinksScrollView.contentLayoutGuide.bottomAnchor,
        constant: -AppSpacing.xs
      ),
      quickLinksStack.heightAnchor.constraint(equalToConstant: 76),
      heightConstraint,
    ])
  }

  private func configureSearchHistoryView() {
    searchHistoryTableView.translatesAutoresizingMaskIntoConstraints = false
    searchHistoryTableView.backgroundColor = .clear
    searchHistoryTableView.separatorColor = AppColors.browserChromeSeparator
    searchHistoryTableView.separatorInset = UIEdgeInsets(
      top: 0,
      left: 72,
      bottom: 0,
      right: AppSpacing.lg
    )
    searchHistoryTableView.rowHeight = 72
    searchHistoryTableView.estimatedRowHeight = 72
    searchHistoryTableView.keyboardDismissMode = .none
    searchHistoryTableView.alwaysBounceVertical = true
    searchHistoryTableView.showsVerticalScrollIndicator = false
    searchHistoryTableView.register(
      BrowserSearchHistoryCell.self,
      forCellReuseIdentifier: BrowserSearchHistoryCell.reuseIdentifier
    )
    searchHistoryTableView.dataSource = self
    searchHistoryTableView.delegate = self
    searchHistoryTableView.accessibilityIdentifier = "browser.searchHistory"

    searchHistoryEmptyLabel.textAlignment = .center
    searchHistoryEmptyLabel.numberOfLines = 0
    searchHistoryEmptyLabel.textColor = AppColors.secondaryText
    searchHistoryEmptyLabel.font = AppTypography.body
    searchHistoryEmptyLabel.adjustsFontForContentSizeCategory = true
    searchHistoryTableView.backgroundView = searchHistoryEmptyLabel
  }

  private var isShowingNewTab: Bool {
    !newTabView.isHidden && errorView.isHidden
  }

  private var isSearchOverlayActive: Bool {
    isSearchHistoryVisible || isSearchSuggestionsPinned
  }

  private func updateBrowserChromeVisibility() {
    let shouldShowAddressBar =
      !isShowingNewTab || addressBar.isEditing || isSearchSuggestionsPinned
    addressBar.isHidden = !shouldShowAddressBar
    topChromeBackgroundView.isHidden = !shouldShowAddressBar

    if addressBar.isEditing || isSearchSuggestionsPinned {
      if !isSearchHistoryVisible {
        showSearchHistory(
          for: isShowingNewTab ? .newTab : .webPage
        )
      } else {
        searchHistoryTableView.isHidden = false
        quickLinksScrollView.isHidden =
          quickLinksHeightConstraint?.constant == 0
      }
    } else {
      hideSearchHistory()
    }
  }

  private func showSearchHistory(
    for context: BrowserSearchSuggestionContext
  ) {
    searchSuggestionContext = context
    isSearchHistoryVisible = true
    searchOverlayBackgroundView.isHidden = false
    applyPageTheme(activeTab?.pageThemeColor, animated: false)
    let initialQuery = BrowserSearchSuggestionPolicy.initialHistoryQuery(
      for: context,
      title: viewModel.state.title,
      url: viewModel.state.url ?? activeWebView?.url
    )
    searchHistoryQuery = initialQuery
    reloadQuickLinks()
    reloadSearchHistory(matching: initialQuery)
    view.layoutIfNeeded()
    searchHistoryTableView.isHidden = false
  }

  private func hideSearchHistory() {
    isSearchHistoryVisible = false
    isSearchSuggestionsPinned = false
    searchHistoryQuery = ""
    searchOverlayBackgroundView.isHidden = true
    searchHistoryTableView.isHidden = true
    quickLinksScrollView.isHidden = true
    quickLinksHeightConstraint?.constant = 0
    applyPageTheme(activeTab?.pageThemeColor, animated: false)
  }

  private func reloadSearchHistory(matching query: String) {
    let allEntries = activeTab?.isPrivate == true
      ? []
      : ((try? historyService.allEntries()) ?? [])
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matchingEntries: [HistoryItem]
    if normalizedQuery.isEmpty {
      matchingEntries = allEntries
    } else {
      matchingEntries = allEntries.filter { item in
        item.title.localizedCaseInsensitiveContains(normalizedQuery)
          || item.host.localizedCaseInsensitiveContains(normalizedQuery)
          || item.url.absoluteString.localizedCaseInsensitiveContains(normalizedQuery)
      }
    }

    searchHistoryItems = Array(matchingEntries.prefix(12))
    if activeTab?.isPrivate == true {
      searchHistoryEmptyLabel.text = "无痕模式不显示历史记录"
      searchHistoryEmptyLabel.textColor = AppColors.privateBrowsingDescription
    } else {
      searchHistoryEmptyLabel.text = normalizedQuery.isEmpty
        ? "暂无历史记录"
        : "没有匹配的历史记录"
      searchHistoryEmptyLabel.textColor = AppColors.secondaryText
    }
    searchHistoryEmptyLabel.isHidden = !searchHistoryItems.isEmpty
    searchHistoryTableView.reloadData()
  }

  private func reloadQuickLinks() {
    quickLinksStack.arrangedSubviews.forEach { view in
      quickLinksStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    guard BrowserSearchSuggestionPolicy.showsFavorites(
      in: searchSuggestionContext
    ) else {
      quickLinksHeightConstraint?.constant = 0
      quickLinksScrollView.isHidden = true
      return
    }

    var links: [BrowserQuickLink] = []
    var seenURLs = Set<URL>()
    let favorites = (try? favoriteService.allFavorites()) ?? []
    for favorite in favorites where seenURLs.insert(favorite.url).inserted {
      links.append(
        BrowserQuickLink(
          title: favorite.title,
          subtitle: favorite.host,
          url: favorite.url,
          symbolName: "star.fill"
        )
      )
    }

    let visibleLinks = Array(links.prefix(8))
    visibleLinks.forEach { link in
      let button = makeQuickLinkButton(link)
      quickLinksStack.addArrangedSubview(button)
    }

    let hasLinks = !visibleLinks.isEmpty
    quickLinksHeightConstraint?.constant = hasLinks ? 92 : 0
    quickLinksScrollView.isHidden = !hasLinks
    if hasLinks {
      quickLinksScrollView.setContentOffset(.zero, animated: false)
    }
  }

  private func makeQuickLinkButton(_ link: BrowserQuickLink) -> UIButton {
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: link.symbolName)
    configuration.title = link.title
    configuration.subtitle = link.subtitle
    configuration.imagePlacement = .leading
    configuration.imagePadding = AppSpacing.xs
    configuration.cornerStyle = .medium
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingMiddle
    configuration.baseForegroundColor = AppColors.primaryText
    configuration.baseBackgroundColor = AppColors.surface
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: AppSpacing.xs,
      leading: AppSpacing.sm,
      bottom: AppSpacing.xs,
      trailing: AppSpacing.sm
    )

    let button = UIButton(configuration: configuration)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.accessibilityLabel = "\(link.title)，\(link.subtitle)"
    button.accessibilityHint = "打开快捷网页"
    button.addAction(
      UIAction { [weak self] _ in
        self?.openQuickLink(link)
      },
      for: .touchUpInside
    )
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 156),
      button.heightAnchor.constraint(equalToConstant: 76),
    ])
    return button
  }

  private func openQuickLink(_ link: BrowserQuickLink) {
    addressBar.setInput(link.url.absoluteString)
    addressBar.submitInput()
  }

  /// The root browser hides the system navigation bar so its own address bar
  /// receives touches directly. Keep this fallback for transition frames where
  /// UIKit may briefly report the navigation bar as visible.
  private func updateBrowserTopSafeArea() {
    guard let navigationController else { return }
    let navigationBarHeight = navigationController.isNavigationBarHidden
      ? 0
      : navigationController.navigationBar.bounds.height
    let desiredTopInset = -max(0, navigationBarHeight)
    guard abs(additionalSafeAreaInsets.top - desiredTopInset) > 0.5 else {
      return
    }

    var insets = additionalSafeAreaInsets
    insets.top = desiredTopInset
    additionalSafeAreaInsets = insets
  }

  private func configureActions() {
    addressBar.delegate = self
    toolbar.toolbarDelegate = self
    toolbar.setSnifferState(resourceCount: 0, activationState: .disabled)
    newTabView.delegate = self
    newTabView.onVisualContentDidChange = { [weak self] in
      self?.refreshNewTabSnapshotAfterVisualUpdate()
    }
    errorView.onRetry = { [weak self] in
      self?.retryLastRequest()
    }
    viewModel.onStateChange = { [weak self] state in
      self?.render(state)
    }
    tabManager.onTabsChanged = { [weak self] in
      guard let self else { return }
      self.toolbar.update(
        canGoBack: self.viewModel.state.canGoBack,
        canGoForward: self.viewModel.state.canGoForward,
        tabCount: self.tabManager.count
      )
      self.refreshTabOverview()
    }
    tabManager.onTabClosed = { [weak self] tabID in
      self?.resourceSniffingService.tabClosed(tabID: tabID)
    }
  }

  private func configureLifecycleObservers() {
    let center = NotificationCenter.default
    lifecycleObservers.append(
      center.addObserver(
        forName: .favoriteItemsDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshNewTabFavorites()
        }
      }
    )
    lifecycleObservers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.tabManager.synchronizeSelectedTabFromWebView()
          if self.tabTransitionCoverView == nil {
            if self.activeTab?.url == nil, !self.newTabView.isHidden {
              self.captureActiveNewTabSnapshot()
            } else if let id = self.activeTab?.id {
              await self.tabManager.captureSnapshot(for: id)
            }
          }
          self.tabManager.persistSession()
        }
      }
    )
  }

  func refreshNewTabFavorites() {
    newTabView.updateFavorites(
      (try? favoriteService.allFavorites()) ?? []
    )
  }

  private func refreshNewTabSnapshotAfterVisualUpdate() {
    guard activeTab?.url == nil,
          !newTabView.isHidden
    else {
      return
    }

    // favicon 回调可能恰好落在标签页空间转场的中间帧。等转场结束后
    // 再刷新缩略图，避免总览卡片在动画过程中重新布局或替换图标。
    if let coordinator = navigationController?.transitionCoordinator {
      guard !isWaitingToRefreshNewTabSnapshot else { return }
      isWaitingToRefreshNewTabSnapshot = true
      coordinator.animate(alongsideTransition: nil) { [weak self] _ in
        guard let self else { return }
        self.isWaitingToRefreshNewTabSnapshot = false
        self.refreshNewTabSnapshotAfterVisualUpdate()
      }
      return
    }

    refreshNewTabSnapshotsForOverview()
    refreshTabOverview()
  }

  func configureWebView(_ webView: WKWebView) {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.backgroundColor = AppColors.background
    webView.scrollView.backgroundColor = AppColors.background
    webView.underPageBackgroundColor = AppColors.background
    webView.allowsBackForwardNavigationGestures = true
    webView.allowsLinkPreview = true
    webView.scrollView.keyboardDismissMode = .interactive
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    let userContentController = webView.configuration.userContentController
    userContentController.removeScriptMessageHandler(
      forName: WebPageThemeColorService.messageHandlerName
    )
    userContentController.add(
      WeakScriptMessageHandler(delegate: self),
      name: WebPageThemeColorService.messageHandlerName
    )
    userContentController.removeScriptMessageHandler(
      forName: ResourceSniffingScriptProvider.messageHandlerName
    )
    userContentController.add(
      WeakScriptMessageHandler(delegate: self),
      name: ResourceSniffingScriptProvider.messageHandlerName
    )
    if let tab = tabManager.tabs.first(where: { $0.webView === webView }) {
      resourceSniffingService.register(
        tabID: tab.id,
        webView: webView,
        isPrivate: tab.isPrivate
      )
    }

    if webView.scrollView.refreshControl == nil {
      let refreshControl = UIRefreshControl()
      refreshControl.tintColor = AppColors.secondaryText
      refreshControl.accessibilityLabel = "重新载入网页"
      refreshControl.addTarget(
        self,
        action: #selector(refreshControlChanged(_:)),
        for: .valueChanged
      )
      webView.scrollView.refreshControl = refreshControl
    }
  }

  func attachSelectedTab() {
    removeTabTransitionCover(animated: false)
    observations.removeAll()
    resourceStore.removeObserver(activeResourceObservationToken)
    activeResourceObservationToken = nil
    NSLayoutConstraint.deactivate(activeWebViewConstraints)
    activeWebViewConstraints.removeAll()
    contentView.subviews.compactMap { $0 as? WKWebView }.forEach {
      $0.layer.removeAllAnimations()
      if $0.layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
        let position = $0.layer.position
        $0.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        $0.layer.position = position
      }
      $0.transform = .identity
      $0.layer.transform = CATransform3DIdentity
      $0.scrollView.layer.removeAllAnimations()
      $0.scrollView.transform = .identity
      $0.removeFromSuperview()
    }

    guard let tab = activeTab else { return }
    tab.activate()
    guard let webView = tab.webView else { return }
    configureWebView(webView)
    applyPageTheme(tab.pageThemeColor, animated: false)
    activeResourceObservationToken = resourceStore.observe(tabID: tab.id) {
      [weak self, weak tab] snapshot in
      guard let self, let tab else { return }
      tab.updateResourceSummary(
        count: snapshot.resources.count,
        scanState: snapshot.scanState,
        lastScanAt: snapshot.lastScanAt,
        activationState: snapshot.activationState
      )
      guard self.activeTab?.id == snapshot.tabID else { return }
      self.toolbar.setSnifferState(
        resourceCount: snapshot.resources.count,
        activationState: snapshot.activationState
      )
    }
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.layer.removeAllAnimations()
    webView.transform = .identity
    webView.layer.transform = CATransform3DIdentity
    webView.scrollView.layer.removeAllAnimations()
    webView.scrollView.transform = .identity
    contentView.insertSubview(webView, at: 0)
    activeWebViewConstraints = [
      webView.topAnchor.constraint(
        equalTo: contentView.safeAreaLayoutGuide.topAnchor
      ),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ]
    NSLayoutConstraint.activate(activeWebViewConstraints)

    bindActiveWebView(webView)
    newTabView.setPrivateMode(tab.isPrivate)
    searchHistoryTableView.overrideUserInterfaceStyle = .unspecified
    quickLinksScrollView.overrideUserInterfaceStyle = .unspecified
    applyChromeState(.expanded, animated: false)
    chromeScrollController.reset()

    let hasPage = tab.url != nil || webView.url != nil
    webView.isHidden = !hasPage
    newTabView.isHidden = hasPage
    errorView.isHidden = true
    if webView.url == nil, !webView.isLoading, let restoredURL = tab.url {
      lastRequestedURLs[tab.id] = restoredURL
      webView.load(URLRequest(url: restoredURL))
    }
    toolbar.update(
      canGoBack: webView.canGoBack,
      canGoForward: webView.canGoForward,
      tabCount: tabManager.count
    )
    synchronizeActiveState()
    updateBrowserChromeVisibility()
    view.setNeedsLayout()
  }

  private func bindActiveWebView(_ webView: WKWebView) {
    observations = [
      webView.observe(\.title, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeActiveState() }
      },
      webView.observe(\.url, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in
          guard let self else { return }
          self.synchronizeActiveState()
          if let activeWebView = self.activeWebView {
            WebPageThemeColorService.requestCurrentTheme(in: activeWebView)
          }
        }
      },
      webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeActiveState() }
      },
      webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeActiveState() }
      },
      webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeActiveState() }
      },
      webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeActiveState() }
      },
      webView.scrollView.observe(\.contentOffset, options: [.new]) {
        [weak self, weak webView] _, _ in
        // UIScrollView 的 contentOffset 由 UIKit 在主线程更新。直接在
        // MainActor 隔离域处理，避免高速滚动时为每一帧创建 Task。
        MainActor.assumeIsolated {
          guard let self, let webView, webView === self.activeWebView else {
            return
          }
          self.handleScroll(in: webView)
        }
      },
    ]
  }

  func synchronizeActiveState() {
    guard let tab = activeTab, let webView = tab.webView else {
      viewModel.resetToNewTab()
      return
    }
    tab.synchronizeFromWebView()
    if tab.url == nil, webView.url == nil, !webView.isLoading {
      viewModel.resetToNewTab()
      toolbar.update(
        canGoBack: false,
        canGoForward: false,
        tabCount: tabManager.count
      )
      return
    }
    viewModel.update(
      title: webView.title,
      url: webView.url ?? tab.url,
      isLoading: webView.isLoading,
      progress: webView.estimatedProgress,
      canGoBack: webView.canGoBack,
      canGoForward: webView.canGoForward
    )
    if webView.isLoading {
      applyChromeState(.expanded, animated: true)
      chromeScrollController.reset()
    }
  }

  private func render(_ state: BrowserViewState) {
    addressBar.apply(
      AddressBarState(
        url: state.url,
        isLoading: state.isLoading,
        progress: state.progress,
        isEditing: addressBar.isEditing
      )
    )
    toolbar.update(
      canGoBack: state.canGoBack,
      canGoForward: state.canGoForward,
      tabCount: tabManager.count
    )
    updateBrowserChromeVisibility()
  }

  func applyPageTheme(
    _ color: WebPageThemeColor?,
    animated: Bool
  ) {
    let isPrivate = activeTab?.isPrivate == true
    let effectivePageTheme = isSearchOverlayActive
      ? nil
      : BrowserChromeThemeResolver.effectivePageTheme(
        color,
        interfaceStyle: traitCollection.userInterfaceStyle
      )
    let foregroundStyle = effectivePageTheme.map {
      ContrastColorResolver.foregroundStyle(for: $0)
    }
    pageChromeForegroundStyle = foregroundStyle
    let resolvedBackground = isSearchOverlayActive
      ? AppColors.browserCanvas
      : (effectivePageTheme?.uiColor ?? AppColors.background)
    resolvedPageChromeBackgroundColor = resolvedBackground

    let changes = {
      self.view.backgroundColor = resolvedBackground
      self.topChromeBackgroundView.backgroundColor = self.currentChromeState
        .showsTopBackdrop ? resolvedBackground : .clear
      self.activeWebView?.backgroundColor = resolvedBackground
      self.activeWebView?.scrollView.backgroundColor = resolvedBackground
      self.activeWebView?.underPageBackgroundColor = resolvedBackground
      self.addressBar.setPrivateMode(isPrivate)
      self.addressBar.applyPageTheme(
        isPrivate ? nil : effectivePageTheme,
        foregroundStyle: foregroundStyle
      )
      self.toolbar.setPrivateMode(false)
      self.toolbar.applyPageTheme(
        effectivePageTheme,
        foregroundStyle: foregroundStyle
      )
      self.setNeedsStatusBarAppearanceUpdate()
    }
    guard animated, !UIAccessibility.isReduceMotionEnabled else {
      changes()
      return
    }
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState],
      animations: changes
    )
  }

  func resetPageTheme(for webView: WKWebView) {
    guard let tab = tabManager.tabs.first(where: { $0.webView === webView })
    else {
      return
    }
    tab.updatePageThemeColor(nil)
    if webView === activeWebView {
      applyPageTheme(nil, animated: false)
    }
  }

  private func navigate(to input: String) {
    guard let url = viewModel.resolve(input) else {
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      return
    }
    load(url)
  }

  func load(_ url: URL) {
    guard let tab = activeTab, let webView = tab.webView else { return }
    lastRequestedURLs[tab.id] = url
    lastFailedURLs[tab.id] = nil
    resetPageTheme(for: webView)
    view.endEditing(true)
    errorView.isHidden = true
    newTabView.isHidden = true
    webView.isHidden = false
    hideSearchHistory()
    updateBrowserChromeVisibility()
    applyChromeState(.expanded, animated: true)
    webView.load(URLRequest(url: url))
  }

  private func retryLastRequest() {
    guard let tab = activeTab, let webView = tab.webView else { return }
    if let failedURL = lastFailedURLs[tab.id] {
      load(failedURL)
    } else {
      webView.reload()
    }
  }

  private func updateActiveWebViewInsets() {
    guard let scrollView = activeWebView?.scrollView else { return }
    let target = UIEdgeInsets(
      top: AppMetrics.addressBarHeight + AppSpacing.sm,
      left: 0,
      bottom: AppMetrics.toolbarHeight
        + view.safeAreaInsets.bottom
        + AppSpacing.sm,
      right: 0
    )
    guard scrollView.contentInset != target else { return }
    let oldOffset = scrollView.contentOffset
    let oldAdjustedTopInset = scrollView.adjustedContentInset.top
    let wasAtTop = oldOffset.y <= -oldAdjustedTopInset + 2
    let documentY = oldOffset.y + oldAdjustedTopInset
    scrollView.contentInset = target
    scrollView.verticalScrollIndicatorInsets = target
    // contentInset 变化会让 UIKit 自动修正 contentOffset。顶部页面继续
    // 停在顶部；已经滚动的页面则按 adjusted inset 换算回同一文档位置，
    // 避免标签切换/Chrome 布局期间出现“向上跳一下”的视觉跳变。
    let targetY = wasAtTop
      ? -scrollView.adjustedContentInset.top
      : documentY - scrollView.adjustedContentInset.top
    scrollView.setContentOffset(
      CGPoint(x: oldOffset.x, y: targetY),
      animated: false
    )
  }

  private func handleScroll(in webView: WKWebView) {
    let canCollapse = viewModel.state.url != nil
      && !viewModel.state.isLoading
      && !addressBar.isEditing
    guard let state = chromeScrollController.update(
      contentOffsetY: webView.scrollView.contentOffset.y,
      adjustedTopInset: webView.scrollView.adjustedContentInset.top,
      canCollapse: canCollapse
    ) else {
      return
    }
    applyChromeState(state, animated: true)
  }

  func applyChromeState(
    _ state: BrowserChromeState,
    animated: Bool
  ) {
    let isCompact = state == .compact
    currentChromeState = state
    let changes = {
      self.topChromeBackgroundView.backgroundColor = state.showsTopBackdrop
        ? self.resolvedPageChromeBackgroundColor
        : .clear
    }
    addressBar.setCompact(isCompact, animated: animated)
    toolbar.setCollapsed(isCompact, animated: animated)
    guard animated, !UIAccessibility.isReduceMotionEnabled else {
      changes()
      return
    }
    UIView.animate(
      withDuration: 0.20,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
      animations: changes
    )
  }

  @objc private func contentTapped() {
    isSearchSuggestionsPinned = false
    view.endEditing(true)
    if !addressBar.isEditing {
      updateBrowserChromeVisibility()
    }
  }

  @objc private func refreshControlChanged(_ sender: UIRefreshControl) {
    activeWebView?.reload()
  }
}

extension BrowserViewController: AddressBarDelegate {
  func addressBar(_ addressBar: AddressBarView, didSubmit text: String) {
    navigate(to: text)
  }

  func addressBar(_ addressBar: AddressBarView, didChangeText text: String) {
    guard isSearchHistoryVisible else { return }
    searchHistoryQuery = text
    reloadSearchHistory(matching: text)
  }

  func addressBarDidRequestReload(_ addressBar: AddressBarView) {
    if activeWebView?.isHidden != false {
      addressBar.beginEditing()
    } else {
      activeWebView?.reload()
    }
  }

  func addressBarDidRequestStop(_ addressBar: AddressBarView) {
    activeWebView?.stopLoading()
  }

  func addressBarDidRequestDismissSearch(_ addressBar: AddressBarView) {
    isSearchSuggestionsPinned = false
  }

  func addressBarDidBeginEditing(_ addressBar: AddressBarView) {
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
    showSearchHistory(
      for: isShowingNewTab ? .newTab : .webPage
    )
  }

  func addressBarDidEndEditing(_ addressBar: AddressBarView) {
    chromeScrollController.reset()
    if isSearchSuggestionsPinned {
      searchHistoryTableView.isHidden = false
      quickLinksScrollView.isHidden =
        quickLinksHeightConstraint?.constant == 0
      return
    }
    updateBrowserChromeVisibility()
  }
}

extension BrowserViewController: NewTabViewDelegate {
  func newTabViewDidBeginEditing(_ view: NewTabView) {
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
    guard view === newTabView, isShowingNewTab else { return }
    addressBar.isHidden = false
    topChromeBackgroundView.isHidden = false
    addressBar.beginEditing()
  }

  func newTabView(_ view: NewTabView, didSubmit text: String) {
    navigate(to: text)
  }

  func newTabView(_ view: NewTabView, didSelect action: NewTabQuickAction) {
    switch action {
    case .downloads:
      router?.showDownloads()
    case .files:
      router?.showFiles()
    case .favorites:
      router?.showFavorites()
    case .history:
      router?.showHistory()
    }
  }

  func newTabView(_ view: NewTabView, didSelect favorite: FavoriteItem) {
    guard view === newTabView else { return }
    load(favorite.url)
  }
}

extension BrowserViewController: UITableViewDataSource, UITableViewDelegate {
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === searchHistoryTableView,
          addressBar.isEditing
    else {
      return
    }

    let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
    guard velocity.y < 0 else { return }
    isSearchSuggestionsPinned = true
    addressBar.endEditing(true)
  }

  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    guard tableView === searchHistoryTableView else { return 0 }
    return searchHistoryItems.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    guard tableView === searchHistoryTableView,
          let cell = tableView.dequeueReusableCell(
            withIdentifier: BrowserSearchHistoryCell.reuseIdentifier,
            for: indexPath
          ) as? BrowserSearchHistoryCell,
          searchHistoryItems.indices.contains(indexPath.row)
    else {
      return UITableViewCell()
    }
    cell.configure(with: searchHistoryItems[indexPath.row])
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard tableView === searchHistoryTableView,
          searchHistoryItems.indices.contains(indexPath.row)
    else {
      return
    }
    let item = searchHistoryItems[indexPath.row]
    tableView.deselectRow(at: indexPath, animated: true)
    addressBar.setInput(item.url.absoluteString)
    addressBar.submitInput()
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    guard tableView === searchHistoryTableView,
          searchHistoryItems.indices.contains(indexPath.row)
    else {
      return nil
    }

    let item = searchHistoryItems[indexPath.row]
    let deleteAction = UIContextualAction(
      style: .destructive,
      title: "删除"
    ) { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }

      do {
        guard try self.historyService.removeEntry(id: item.id) != nil else {
          completion(false)
          return
        }
        self.reloadSearchHistory(matching: self.searchHistoryQuery)
        self.reloadQuickLinks()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        completion(true)
      } catch {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        completion(false)
      }
    }
    deleteAction.image = UIImage(systemName: "trash")

    let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }
}

extension BrowserViewController: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    var candidate: UIView? = touch.view
    while let view = candidate, view !== contentView {
      if view is UIControl || view is UITextField {
        return false
      }
      if view is WKWebView {
        return false
      }
      candidate = view.superview
    }
    return true
  }
}

extension BrowserViewController: BrowserToolbarDelegate {
  func browserToolbar(
    _ toolbar: BrowserToolbar,
    didSelect action: BrowserToolbarAction,
    sourceView: UIView
  ) {
    switch action {
    case .back:
      activeWebView?.goBack()
    case .forward:
      activeWebView?.goForward()
    case .sniff:
      guard let tab = activeTab else { return }
      let viewModel = ResourceSnifferViewModel(
        tabID: tab.id,
        pageTitle: self.viewModel.state.title,
        pageURL: self.viewModel.state.url,
        isPrivate: tab.isPrivate,
        store: resourceStore,
        service: resourceSniffingService,
        downloadCenter: downloadCenter,
        requestContextProvider: { [weak self, weak webView = tab.webView] url in
          guard let self else {
            return DownloadRequestContext(targetURL: url, pageURL: nil, headers: [:])
          }
          return await self.downloadRequestContextBuilder.build(
            targetURL: url,
            pageURL: self.viewModel.state.url,
            webView: webView
          )
        }
      )
      let controller = ResourceSnifferViewController(viewModel: viewModel)
      router?.showResources(controller)
    case .tabs:
      showTabs()
    case .more:
      presentMoreMenu()
    }
  }
}

private final class BrowserSearchHistoryCell: UITableViewCell {
  static let reuseIdentifier = "BrowserSearchHistoryCell"

  private let iconView = UIImageView(
    image: UIImage(systemName: "clock.arrow.circlepath")
  )
  private let titleLabel = UILabel()
  private let hostLabel = UILabel()
  private let arrowView = UIImageView(
    image: UIImage(systemName: "arrow.up.left")
  )

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func configure(with item: HistoryItem) {
    titleLabel.text = item.title
    hostLabel.text = item.host
    accessibilityLabel = "\(item.title)，\(item.host)"
  }

  private func configure() {
    selectionStyle = .default
    backgroundColor = .clear
    selectedBackgroundView = UIView()
    selectedBackgroundView?.backgroundColor = AppColors.browserChromeSelection

    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.tintColor = AppColors.secondaryText
    iconView.contentMode = .scaleAspectFit
    iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 25,
      weight: .regular
    )
    contentView.addSubview(iconView)

    AppTypography.configure(titleLabel, style: .body)
    titleLabel.textColor = AppColors.primaryText
    titleLabel.numberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(titleLabel)

    AppTypography.configure(hostLabel, style: .subheadline)
    hostLabel.textColor = AppColors.secondaryText
    hostLabel.numberOfLines = 1
    hostLabel.lineBreakMode = .byTruncatingMiddle
    hostLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(hostLabel)

    arrowView.translatesAutoresizingMaskIntoConstraints = false
    arrowView.tintColor = AppColors.accent
    arrowView.contentMode = .scaleAspectFit
    arrowView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 22,
      weight: .regular
    )
    contentView.addSubview(arrowView)

    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: AppSpacing.xl
      ),
      iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 28),
      iconView.heightAnchor.constraint(equalToConstant: 28),

      titleLabel.leadingAnchor.constraint(
        equalTo: iconView.trailingAnchor,
        constant: AppSpacing.lg
      ),
      titleLabel.trailingAnchor.constraint(
        equalTo: arrowView.leadingAnchor,
        constant: -AppSpacing.sm
      ),
      titleLabel.topAnchor.constraint(
        equalTo: contentView.topAnchor,
        constant: AppSpacing.sm
      ),

      hostLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      hostLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      hostLabel.topAnchor.constraint(
        equalTo: titleLabel.bottomAnchor,
        constant: AppSpacing.xxs
      ),
      hostLabel.bottomAnchor.constraint(
        equalTo: contentView.bottomAnchor,
        constant: -AppSpacing.sm
      ),

      arrowView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -AppSpacing.xl
      ),
      arrowView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      arrowView.widthAnchor.constraint(equalToConstant: 28),
      arrowView.heightAnchor.constraint(equalToConstant: 28),
      contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
    ])

    isAccessibilityElement = true
    accessibilityTraits = .button
  }
}

private struct BrowserQuickLink {
  let title: String
  let subtitle: String
  let url: URL
  let symbolName: String
}
