import UIKit
import WebKit

@MainActor
protocol BrowserRouting: AnyObject {
  func showResources(pageTitle: String, pageURL: URL?)
  func showTabs(currentItem: TabOverviewItem)
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

  private let viewModel: BrowserViewModel
  private let addressBar = AddressBarView()
  private let toolbar = BrowserToolbar(frame: .zero)
  private let contentView = UIView()
  private let newTabView = NewTabView()
  private let errorView = BrowserErrorView()
  private lazy var webView = WKWebView(
    frame: .zero,
    configuration: BrowserConfiguration.makeWebViewConfiguration()
  )
  private lazy var externalURLHandler = ExternalURLHandler(presenter: self)
  private let refreshControl = UIRefreshControl()
  private var observations: [NSKeyValueObservation] = []
  private let tabID = UUID()
  private var lastFailedURL: URL?
  private var lastRequestedURL: URL?

  init(viewModel: BrowserViewModel? = nil) {
    self.viewModel = viewModel ?? BrowserViewModel()
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    viewModel = BrowserViewModel()
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
    configureWebView()
    configureActions()
    bindWebView()
    showNewTab(replacingWebView: false)
  }

  func openNewTab() {
    showNewTab(replacingWebView: true)
  }

  private func configureView() {
    view.backgroundColor = AppColors.background

    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.backgroundColor = AppColors.background
    contentView.clipsToBounds = true
    webView.translatesAutoresizingMaskIntoConstraints = false
    newTabView.translatesAutoresizingMaskIntoConstraints = false
    errorView.translatesAutoresizingMaskIntoConstraints = false
    errorView.isHidden = true

    view.addSubview(addressBar)
    view.addSubview(contentView)
    view.addSubview(toolbar)
    contentView.addSubview(webView)
    contentView.addSubview(newTabView)
    contentView.addSubview(errorView)

    NSLayoutConstraint.activate([
      addressBar.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: AppSpacing.xs
      ),
      addressBar.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: AppSpacing.sm
      ),
      addressBar.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -AppSpacing.sm
      ),

      contentView.topAnchor.constraint(
        equalTo: addressBar.bottomAnchor,
        constant: AppSpacing.xs
      ),
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(
        equalTo: toolbar.topAnchor,
        constant: -AppSpacing.xs
      ),

      toolbar.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: AppSpacing.sm
      ),
      toolbar.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -AppSpacing.sm
      ),
      toolbar.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -AppSpacing.xs
      ),

      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      newTabView.topAnchor.constraint(equalTo: contentView.topAnchor),
      newTabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      newTabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      newTabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      errorView.topAnchor.constraint(equalTo: contentView.topAnchor),
      errorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      errorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      errorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  private func configureWebView() {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.allowsLinkPreview = true
    webView.scrollView.keyboardDismissMode = .interactive
    webView.scrollView.contentInsetAdjustmentBehavior = .never

    refreshControl.tintColor = AppColors.secondaryText
    refreshControl.accessibilityLabel = "重新载入网页"
    refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
    webView.scrollView.refreshControl = refreshControl
  }

  private func configureActions() {
    addressBar.delegate = self
    toolbar.toolbarDelegate = self
    newTabView.delegate = self
    errorView.onRetry = { [weak self] in
      self?.retryLastRequest()
    }
    viewModel.onStateChange = { [weak self] state in
      self?.render(state)
    }
    toolbar.setMoreMenu(makeMoreMenu())
  }

  private func bindWebView() {
    observations = [
      webView.observe(\.title, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
      webView.observe(\.url, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
      webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
      webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
      webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
      webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.synchronizeState() }
      },
    ]
  }

  private func synchronizeState() {
    viewModel.update(
      title: webView.title,
      url: webView.url,
      isLoading: webView.isLoading,
      progress: webView.estimatedProgress,
      canGoBack: webView.canGoBack,
      canGoForward: webView.canGoForward
    )
  }

  private func render(_ state: BrowserViewState) {
    addressBar.apply(
      AddressBarState(
        url: state.url,
        isLoading: state.isLoading,
        progress: state.progress,
        isEditing: false
      )
    )
    toolbar.update(
      canGoBack: state.canGoBack,
      canGoForward: state.canGoForward,
      tabCount: 1
    )
  }

  private func navigate(to input: String) {
    guard let url = viewModel.resolve(input) else {
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      return
    }
    load(url)
  }

  private func load(_ url: URL) {
    lastRequestedURL = url
    lastFailedURL = nil
    errorView.isHidden = true
    newTabView.isHidden = true
    webView.isHidden = false
    webView.load(URLRequest(url: url))
  }

  private func showNewTab(replacingWebView: Bool = true) {
    if replacingWebView {
      replaceWebView()
    }
    webView.stopLoading()
    webView.isHidden = true
    errorView.isHidden = true
    newTabView.isHidden = false
    viewModel.resetToNewTab()
    toolbar.setMoreMenu(makeMoreMenu())
  }

  private func replaceWebView() {
    observations.removeAll()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()

    webView = WKWebView(
      frame: .zero,
      configuration: BrowserConfiguration.makeWebViewConfiguration()
    )
    webView.translatesAutoresizingMaskIntoConstraints = false
    contentView.insertSubview(webView, at: 0)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: contentView.topAnchor),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    configureWebView()
    bindWebView()
  }

  private func retryLastRequest() {
    if let lastFailedURL {
      load(lastFailedURL)
    } else {
      webView.reload()
    }
  }

  private func makeMoreMenu() -> UIMenu {
    let hasPage = viewModel.state.url != nil
    return UIMenu(children: [
      UIMenu(options: .displayInline, children: [
        UIAction(
          title: "新建标签页",
          image: UIImage(systemName: "plus.square")
        ) { [weak self] _ in
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          self?.showNewTab()
        },
        UIAction(
          title: "分享当前网页",
          image: UIImage(systemName: "square.and.arrow.up"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.shareCurrentPage()
        },
        UIAction(
          title: "添加收藏",
          image: UIImage(systemName: "star"),
          attributes: hasPage ? [] : [.disabled]
        ) { [weak self] _ in
          self?.router?.showFavorites()
        },
      ]),
      UIMenu(options: .displayInline, children: [
        UIAction(
          title: "历史记录",
          image: UIImage(systemName: "clock.arrow.circlepath")
        ) { [weak self] _ in self?.router?.showHistory() },
        UIAction(
          title: "下载管理",
          image: UIImage(systemName: "arrow.down.circle")
        ) { [weak self] _ in self?.router?.showDownloads() },
        UIAction(
          title: "文件管理",
          image: UIImage(systemName: "folder")
        ) { [weak self] _ in self?.router?.showFiles() },
      ]),
      UIMenu(options: .displayInline, children: [
        UIAction(
          title: "用户中心",
          image: UIImage(systemName: "person.crop.circle")
        ) { [weak self] _ in self?.router?.showUserCenter() },
        UIAction(
          title: "设置",
          image: UIImage(systemName: "gearshape")
        ) { [weak self] _ in self?.router?.showSettings() },
      ]),
    ])
  }

  private func shareCurrentPage() {
    guard let url = viewModel.state.url else { return }
    let controller = UIActivityViewController(
      activityItems: [viewModel.state.title, url],
      applicationActivities: nil
    )
    present(controller, animated: true)
  }

  private func showTabs() {
    let item = TabOverviewItem(
      id: tabID,
      title: viewModel.state.title,
      url: viewModel.state.url,
      isSelected: true,
      isPrivate: false
    )
    guard !webView.isHidden else {
      router?.showTabs(currentItem: item)
      return
    }
    webView.takeSnapshot(with: nil) { [weak self] image, _ in
      Task { @MainActor in
        guard let self else { return }
        var snapshot = item
        snapshot.thumbnail = image
        self.router?.showTabs(currentItem: snapshot)
      }
    }
  }

  @objc private func refresh() {
    webView.reload()
  }
}

extension BrowserViewController: AddressBarDelegate {
  func addressBar(_ addressBar: AddressBarView, didSubmit text: String) {
    navigate(to: text)
  }

  func addressBarDidRequestReload(_ addressBar: AddressBarView) {
    if webView.isHidden {
      addressBar.beginEditing()
    } else {
      webView.reload()
    }
  }

  func addressBarDidRequestStop(_ addressBar: AddressBarView) {
    webView.stopLoading()
  }

  func addressBarDidBeginEditing(_ addressBar: AddressBarView) {}

  func addressBarDidEndEditing(_ addressBar: AddressBarView) {}
}

extension BrowserViewController: NewTabViewDelegate {
  func newTabView(_ view: NewTabView, didSubmit text: String) {
    navigate(to: text)
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
      webView.goBack()
    case .forward:
      webView.goForward()
    case .sniff:
      router?.showResources(
        pageTitle: viewModel.state.title,
        pageURL: viewModel.state.url
      )
    case .tabs:
      showTabs()
    case .more:
      break
    }
  }
}

extension BrowserViewController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url,
          let scheme = url.scheme?.lowercased()
    else {
      decisionHandler(.cancel)
      return
    }
    if navigationAction.targetFrame?.isMainFrame == true {
      lastRequestedURL = url
    }
    if ["about", "blob", "data"].contains(scheme) {
      decisionHandler(.allow)
      return
    }
    if ["http", "https"].contains(scheme) {
      if let host = url.host,
         ["apps.apple.com", "itunes.apple.com"].contains(host) {
        externalURLHandler.requestOpen(url)
        decisionHandler(.cancel)
      } else {
        decisionHandler(.allow)
      }
      return
    }
    externalURLHandler.requestOpen(url)
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation: WKNavigation?) {
    errorView.isHidden = true
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    refreshControl.endRefreshing()
    toolbar.setMoreMenu(makeMoreMenu())
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    refreshControl.endRefreshing()
    if (error as? URLError)?.code == .cancelled {
      return
    }
    let failingURL = (error as NSError)
      .userInfo[NSURLErrorFailingURLErrorKey] as? URL
    lastFailedURL = failingURL ?? lastRequestedURL ?? webView.url
    errorView.apply(BrowserErrorMapper.map(error))
    errorView.isHidden = false
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation?,
    withError error: Error
  ) {
    self.webView(
      webView,
      didFailProvisionalNavigation: navigation,
      withError: error
    )
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.reload()
  }
}

extension BrowserViewController: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil,
       let url = navigationAction.request.url {
      load(url)
    }
    return nil
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    guard presentedViewController == nil, view.window != nil else {
      completionHandler()
      return
    }
    let alert = UIAlertController(
      title: webView.title ?? "网页提示",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default) { _ in
      completionHandler()
    })
    present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard presentedViewController == nil, view.window != nil else {
      completionHandler(false)
      return
    }
    let alert = UIAlertController(
      title: webView.title ?? "网页确认",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
      completionHandler(false)
    })
    alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
      completionHandler(true)
    })
    present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    guard presentedViewController == nil, view.window != nil else {
      completionHandler(nil)
      return
    }
    let alert = UIAlertController(
      title: webView.title ?? "网页输入",
      message: prompt,
      preferredStyle: .alert
    )
    alert.addTextField { textField in
      textField.text = defaultText
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
      completionHandler(nil)
    })
    alert.addAction(UIAlertAction(title: "确定", style: .default) {
      [weak alert] _ in
      completionHandler(alert?.textFields?.first?.text)
    })
    present(alert, animated: true)
  }
}
