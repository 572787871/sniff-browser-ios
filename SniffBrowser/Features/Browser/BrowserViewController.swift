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
  lazy var externalURLHandler = ExternalURLHandler(presenter: self)

  var observations: [NSKeyValueObservation] = []
  var chromeScrollController = BrowserChromeScrollController()
  var lastFailedURLs: [UUID: URL] = [:]
  var lastRequestedURLs: [UUID: URL] = [:]
  weak var tabOverviewController: TabOverviewViewController?
  var pageChromeForegroundStyle: BrowserChromeForegroundStyle?
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var activeResourceObservationToken: UUID?

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
    attachSelectedTab()
    contentBlockerService.loadIfNeeded()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // 设置页修改新标签页选项后，回到浏览器时立即生效。
    newTabView.refreshContentPreferences()
  }

  private func observeContentBlockerChanges() {
    let observer = NotificationCenter.default.addObserver(
      forName: .contentBlockerDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reapplyContentRules()
      }
    }
    lifecycleObservers.append(observer)
  }

  private func reapplyContentRules() {
    for tab in tabManager.tabs {
      guard let webView = tab.webView else { continue }
      let host = webView.url?.host ?? tab.url?.host
      let changed = contentBlockerService.applyRules(
        to: webView,
        tabID: tab.id,
        host: host
      )
      if changed, tab.id == activeTab?.id {
        webView.reload()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateActiveWebViewInsets()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    if let pageChromeForegroundStyle {
      return pageChromeForegroundStyle.statusBarStyle
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
    let previousID = activeTab?.id
    do {
      let newTab = try tabManager.createTab(isPrivate: isPrivate)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      attachSelectedTab()
      if let initialURL {
        load(initialURL)
      }
      Task { [weak self] in
        guard let self else { return }
        if let previousID, previousID != newTab.id {
          await self.tabManager.captureSnapshot(for: previousID)
        }
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
    view.addSubview(toolbar)

    NSLayoutConstraint.activate([
      contentView.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor
      ),
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      newTabView.topAnchor.constraint(equalTo: contentView.topAnchor),
      newTabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      newTabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      newTabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      errorView.topAnchor.constraint(equalTo: contentView.topAnchor),
      errorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      errorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      errorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      topChromeBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
      topChromeBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topChromeBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topChromeBackgroundView.bottomAnchor.constraint(
        equalTo: addressBar.bottomAnchor,
        constant: AppSpacing.xxs
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
  }

  private func configureActions() {
    addressBar.delegate = self
    toolbar.toolbarDelegate = self
    toolbar.setSnifferState(resourceCount: 0, activationState: .disabled)
    newTabView.delegate = self
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
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.tabManager.synchronizeSelectedTabFromWebView()
          if let id = self.activeTab?.id {
            await self.tabManager.captureSnapshot(for: id)
          }
          self.tabManager.persistSession()
        }
      }
    )
  }

  func configureWebView(_ webView: WKWebView) {
    webView.navigationDelegate = self
    webView.uiDelegate = self
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
    observations.removeAll()
    resourceStore.removeObserver(activeResourceObservationToken)
    activeResourceObservationToken = nil
    contentView.subviews.compactMap { $0 as? WKWebView }.forEach {
      $0.removeFromSuperview()
    }

    guard let tab = activeTab else { return }
    tab.activate()
    guard let webView = tab.webView else { return }
    applyPageTheme(tab.pageThemeColor, animated: false)
    configureWebView(webView)
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
    contentView.insertSubview(webView, at: 0)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])

    bindActiveWebView(webView)
    newTabView.setPrivateMode(tab.isPrivate)
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
  }

  func applyPageTheme(
    _ color: WebPageThemeColor?,
    animated: Bool
  ) {
    let isPrivate = activeTab?.isPrivate == true
    let foregroundStyle: BrowserChromeForegroundStyle? = isPrivate
      ? .light
      : color.map { ContrastColorResolver.foregroundStyle(for: $0) }
    pageChromeForegroundStyle = foregroundStyle
    let resolvedBackground = isPrivate
      ? AppColors.privateBrowsingChrome
      : (color?.uiColor ?? AppColors.background)

    let changes = {
      self.view.backgroundColor = resolvedBackground
      self.topChromeBackgroundView.backgroundColor = resolvedBackground
      self.addressBar.setPrivateMode(isPrivate)
      self.addressBar.applyPageTheme(
        isPrivate ? nil : color,
        foregroundStyle: foregroundStyle
      )
      self.toolbar.setPrivateMode(isPrivate)
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
      applyPageTheme(nil, animated: true)
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
    errorView.isHidden = true
    newTabView.isHidden = true
    webView.isHidden = false
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
    let wasAtTop = scrollView.contentOffset.y
      <= -scrollView.adjustedContentInset.top + 2
    scrollView.contentInset = target
    scrollView.verticalScrollIndicatorInsets = target
    if wasAtTop {
      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: -target.top),
        animated: false
      )
    }
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
    addressBar.setCompact(isCompact, animated: animated)
    toolbar.setCollapsed(isCompact, animated: animated)
  }

  @objc private func contentTapped() {
    view.endEditing(true)
  }

  @objc private func refreshControlChanged(_ sender: UIRefreshControl) {
    activeWebView?.reload()
  }
}

extension BrowserViewController: AddressBarDelegate {
  func addressBar(_ addressBar: AddressBarView, didSubmit text: String) {
    navigate(to: text)
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

  func addressBarDidBeginEditing(_ addressBar: AddressBarView) {
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
  }

  func addressBarDidEndEditing(_ addressBar: AddressBarView) {
    chromeScrollController.reset()
  }
}

extension BrowserViewController: NewTabViewDelegate {
  func newTabViewDidBeginEditing(_ view: NewTabView) {
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
  }

  func newTabView(_ view: NewTabView, didSubmit text: String) {
    navigate(to: text)
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
