import UIKit
import WebKit

/// 接收页面 JS 上报的元素隐藏计数。
final class BlockedElementCounterHandler: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "sniffblockerCounter"

    private let onCount: (Int) -> Void

    init(onCount: @escaping (Int) -> Void) {
        self.onCount = onCount
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              let count = message.body as? Int,
              count > 0
        else {
            return
        }
        onCount(count)
    }
}

struct WebVideoLongPressPayload {
  let url: URL
  let mimeType: String?
  let pageURL: URL?
  let pageTitle: String?
  let thumbnailURL: URL?
  let duration: Double?
  let width: Int?
  let height: Int?

  init?(body: Any) {
    guard let values = body as? [String: Any],
          let rawURL = values["url"] as? String,
          rawURL.count <= 8192,
          let url = URL(string: rawURL),
          ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else {
      return nil
    }
    self.url = url
    mimeType = Self.nonEmptyString(values["mimeType"])
    pageURL = Self.nonEmptyString(values["pageURL"]).flatMap(URL.init(string:))
    pageTitle = Self.nonEmptyString(values["pageTitle"])
    thumbnailURL = Self.nonEmptyString(values["thumbnailURL"])
      .flatMap(URL.init(string:))
    duration = Self.positiveDouble(values["duration"])
    width = Self.positiveDouble(values["width"]).map { Int($0.rounded()) }
    height = Self.positiveDouble(values["height"]).map { Int($0.rounded()) }
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let value = value as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return value
  }

  private static func positiveDouble(_ value: Any?) -> Double? {
    let number: Double?
    if let value = value as? NSNumber {
      number = value.doubleValue
    } else if let value = value as? String {
      number = Double(value)
    } else {
      number = nil
    }
    guard let number, number.isFinite, number > 0 else { return nil }
    return number
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

    if let tab = tabManager.tabs.first(where: { $0.webView === webView }),
       navigationAction.targetFrame?.isMainFrame == true {
      lastRequestedURLs[tab.id] = url
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

  func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation?
  ) {
    resetPageTheme(for: webView)
    if let tab = tabManager.tabs.first(where: { $0.webView === webView }) {
      resourceSniffingService.beginNavigation(
        tabID: tab.id,
        pageURL: lastRequestedURLs[tab.id] ?? webView.url ?? tab.url,
        isPrivate: tab.isPrivate
      )
    }
    guard webView === activeWebView else { return }
    errorView.isHidden = true
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    didCommit navigation: WKNavigation?
  ) {
    WebPageThemeColorService.requestCurrentTheme(in: webView)
    if let tab = tabManager.tabs.first(where: { $0.webView === webView }) {
      contentBlockerService.applyRules(
        to: webView,
        tabID: tab.id,
        host: webView.url?.host
      )
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    webView.scrollView.refreshControl?.endRefreshing()
    guard let tab = tabManager.tabs.first(where: { $0.webView === webView })
    else {
      return
    }
    tabManager.updateTab(
      id: tab.id,
      title: webView.title,
      url: webView.url
    )
    if !tab.isPrivate, let url = webView.url {
      _ = try? historyService.recordVisit(title: webView.title, url: url)
    }
    if !tab.isPrivate {
      ContentBlockManager.shared.statisticsManager.recordPageLoad()
    }
    if !tab.isPrivate {
      injectElementHideCounter(into: webView, tab: tab)
    }
    WebPageThemeColorService.requestCurrentTheme(in: webView)
    resourceSniffingService.requestIncrementalScan(tabID: tab.id, reason: "didFinish")
    if webView === activeWebView {
      removeTabTransitionCover(animated: true)
      synchronizeActiveState()
      Task { [weak self] in
        await self?.tabManager.captureSnapshot(for: tab.id)
      }
    }
  }

  /// 在页面加载完成后统计被 css-display-none 规则隐藏的广告元素数量。
  private func injectElementHideCounter(
    into webView: WKWebView,
    tab: BrowserTab
  ) {
    guard ContentBlockerService.shared.isEnabled else { return }
    guard let host = webView.url?.host else { return }
    let selectors = ContentBlockerService.shared.cosmeticSelectors(for: host)
    guard !selectors.isEmpty else { return }

    let identifier = ObjectIdentifier(webView)
    if elementHideInjected[identifier] != true {
      let handler = BlockedElementCounterHandler { count in
        Task { @MainActor in
          ContentBlockManager.shared.statisticsManager.recordBlockedElements(count)
        }
      }
      blockedElementCounterHandler = handler
      webView.configuration.userContentController.add(
        handler,
        name: BlockedElementCounterHandler.messageHandlerName
      )
      elementHideInjected[identifier] = true
    }

    guard let data = try? JSONSerialization.data(withJSONObject: selectors),
          let selectorsJSON = String(data: data, encoding: .utf8)
    else {
      return
    }
    let script = Self.elementHideCounterScript.replacingOccurrences(
      of: "__SELECTORS__",
      with: selectorsJSON
    )
    webView.evaluateJavaScript(script)
  }

  private static let elementHideCounterScript = """
  (function() {
    var selectors = __SELECTORS__;
    var prev = 0;
    function run() {
      var n = 0;
      for (var i = 0; i < selectors.length; i++) {
        try {
          var els = document.querySelectorAll(selectors[i]);
          for (var j = 0; j < els.length; j++) {
            var el = els[j];
            var style = window.getComputedStyle(el);
            if (el.getClientRects().length === 0
                || style.display === 'none'
                || style.visibility === 'hidden') {
              n++;
            }
          }
        } catch (e) {}
      }
      var delta = n - prev;
      prev = n;
      if (delta > 0) {
        window.webkit.messageHandlers.sniffblockerCounter.postMessage(delta);
      }
    }
    run();
    setTimeout(run, 2000);
    setTimeout(run, 5000);
  })();
  """

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if let tab = tabManager.tabs.first(where: { $0.webView === webView }) {
      resourceSniffingService.captureNavigationResponse(
        tabID: tab.id,
        response: navigationResponse.response,
        pageTitle: webView.title
      )
    }
    decisionHandler(.allow)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    handleNavigationFailure(error, in: webView)
    // 主框架导航被规则取消时计入拦截统计（近似值，WebKit 公开 API 限制）。
    if (error as NSError).code == NSURLErrorCancelled {
      ContentBlockManager.shared.statisticsManager.recordBlockedRequest()
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation?,
    withError error: Error
  ) {
    handleNavigationFailure(error, in: webView)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    if webView === activeWebView {
      webView.reload()
      return
    }
    guard let tab = tabManager.tabs.first(where: { $0.webView === webView })
    else {
      return
    }
    Task { [weak self] in
      _ = await self?.tabManager.suspendTab(id: tab.id)
    }
  }

  private func handleNavigationFailure(_ error: Error, in webView: WKWebView) {
    webView.scrollView.refreshControl?.endRefreshing()
    if (error as? URLError)?.code == .cancelled {
      return
    }
    guard let tab = tabManager.tabs.first(where: { $0.webView === webView })
    else {
      return
    }
    let failingURL = (error as NSError)
      .userInfo[NSURLErrorFailingURLErrorKey] as? URL
    lastFailedURLs[tab.id] =
      failingURL ?? lastRequestedURLs[tab.id] ?? webView.url

    guard webView === activeWebView else { return }
    removeTabTransitionCover(animated: false)
    errorView.apply(BrowserErrorMapper.map(error))
    errorView.isHidden = false
  }
}

extension BrowserViewController: WKScriptMessageHandler {
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.frameInfo.isMainFrame,
          let webView = message.webView,
          let tab = tabManager.tabs.first(where: { $0.webView === webView })
    else {
      return
    }

    if message.name == ResourceSniffingScriptProvider.messageHandlerName {
      resourceSniffingService.handleMessageBody(
        message.body,
        tabID: tab.id,
        isPrivate: tab.isPrivate
      )
      return
    }

    if message.name == WebVideoLongPressScriptProvider.messageHandlerName {
      guard webView === activeWebView,
            tab.id == activeTab?.id,
            let payload = WebVideoLongPressPayload(body: message.body)
      else { return }
      handleLongPressedVideo(payload, tab: tab, webView: webView)
      return
    }

    if message.name == WebPageThemeColorService.messageHandlerName {
      let candidates: [String]
      if let array = message.body as? [String] {
        candidates = array
      } else if let value = message.body as? String {
        candidates = [value]
      } else {
        candidates = []
      }
      let color = WebPageThemeColorParser.firstUsable(in: candidates)
      tab.updatePageThemeColor(color)
      if webView === activeWebView {
        applyPageTheme(color, animated: true)
      }
    }
  }

  private func handleLongPressedVideo(
    _ payload: WebVideoLongPressPayload,
    tab: BrowserTab,
    webView: WKWebView
  ) {
    let mimeType: String
    if payload.url.pathExtension.lowercased() == "m3u8"
        || payload.mimeType?.lowercased().contains("mpegurl") == true {
      mimeType = "application/vnd.apple.mpegurl"
    } else {
      mimeType = payload.mimeType ?? "video/mp4"
    }
    let candidate = ResourceCandidate(
      originalURLString: payload.url.absoluteString,
      pageURLString: (payload.pageURL ?? webView.url)?.absoluteString,
      pageTitle: payload.pageTitle ?? webView.title,
      mimeType: mimeType,
      estimatedSize: nil,
      duration: payload.duration,
      width: payload.width,
      height: payload.height,
      bitrate: nil,
      thumbnailURLString: payload.thumbnailURL?.absoluteString,
      detectionSource: .mediaEvent,
      elementType: "source-video",
      headersHint: [:]
    )
    guard let detected = ResourceClassifier().makeResource(
      from: candidate,
      tabID: tab.id
    ) else {
      showVideoDownloadFailure("未能识别当前视频的真实下载地址。")
      return
    }
    let resource = resourceStore.resources(for: tab.id).first {
      $0.canonicalURL == detected.canonicalURL
    } ?? detected

    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let beginDownload = { [weak self, weak webView] in
      guard let self, let webView else { return }
      self.startLongPressedVideoDownload(resource, webView: webView)
    }
    guard !DownloadComplianceAcknowledgement.hasAcknowledged else {
      beginDownload()
      return
    }

    guard presentedViewController == nil else { return }
    let alert = UIAlertController(
      title: "下载当前视频",
      message: "请仅下载您拥有版权、已经获得授权或网站明确允许保存的内容。应用不支持受 DRM 保护的视频。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "我已了解并下载", style: .default) { _ in
      DownloadComplianceAcknowledgement.hasAcknowledged = true
      beginDownload()
    })
    present(alert, animated: true)
  }

  private func startLongPressedVideoDownload(
    _ resource: DetectedResource,
    webView: WKWebView
  ) {
    Task { [weak self, weak webView] in
      guard let self, let webView else { return }
      do {
        let context = await downloadRequestContextBuilder.build(
          targetURL: resource.canonicalURL,
          pageURL: resource.sourcePageURL ?? webView.url,
          webView: webView
        )
        let result = try await downloadCenter.createDownload(
          resource: resource,
          context: context
        )
        switch result {
        case .created:
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .alreadyDownloading:
          showVideoDownloadFailure("这个视频已经在下载队列中。", title: "已在下载")
        case .fileAlreadyExists:
          showVideoDownloadFailure("这个视频已经下载完成，可前往文件页面查看。", title: "文件已存在")
        }
      } catch {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        showVideoDownloadFailure(DownloadErrorMapper.message(for: error))
      }
    }
  }

  private func showVideoDownloadFailure(
    _ message: String,
    title: String = "无法下载视频"
  ) {
    guard view.window != nil, presentedViewController == nil else { return }
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}

extension BrowserViewController: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard navigationAction.targetFrame == nil,
          let url = navigationAction.request.url
    else {
      return nil
    }
    let isPrivate = tabManager.tabs
      .first(where: { $0.webView === webView })?
      .isPrivate == true
    _ = openNewTab(with: url, isPrivate: isPrivate)
    return nil
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    guard webView === activeWebView,
          presentedViewController == nil,
          view.window != nil
    else {
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
    guard webView === activeWebView,
          presentedViewController == nil,
          view.window != nil
    else {
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
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    let host = origin.host
    switch type {
    case .camera:
      resolveWebsitePermission(.camera, for: host, decisionHandler: decisionHandler)
    case .microphone:
      resolveWebsitePermission(.microphone, for: host, decisionHandler: decisionHandler)
    case .cameraAndMicrophone:
      resolveCameraAndMicrophonePermission(for: host, decisionHandler: decisionHandler)
    @unknown default:
      decisionHandler(.deny)
    }
  }

  func webView(
    _ webView: WKWebView,
    requestGeolocationPermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    resolveWebsitePermission(.location, for: origin.host, decisionHandler: decisionHandler)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    guard webView === activeWebView,
          presentedViewController == nil,
          view.window != nil
    else {
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

  private func resolveWebsitePermission(
    _ permission: WebsitePermission,
    for host: String,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    guard !host.isEmpty else {
      decisionHandler(.deny)
      return
    }
    let store = WebsitePermissionStore.shared
    if let decision = store.decision(for: host, permission: permission) {
      decisionHandler(decision == .allow ? .grant : .deny)
      return
    }
    if store.defaultPolicy(for: permission) == .deny {
      decisionHandler(.deny)
      return
    }
    guard canPresentPermissionAlert() else {
      decisionHandler(.deny)
      return
    }
    presentPermissionAlert(
      title: "“\(host)”请求使用\(permission.displayName)",
      message: "允许该网站使用\(permission.displayName)吗？你可以稍后在浏览器设置中修改。",
      remember: { decision in
        store.setDecision(decision, for: host, permission: permission)
      },
      decisionHandler: decisionHandler
    )
  }

  private func resolveCameraAndMicrophonePermission(
    for host: String,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    guard !host.isEmpty else {
      decisionHandler(.deny)
      return
    }
    let store = WebsitePermissionStore.shared
    let cameraDecision = store.decision(for: host, permission: .camera)
    let microphoneDecision = store.decision(for: host, permission: .microphone)
    if cameraDecision == .deny || microphoneDecision == .deny {
      decisionHandler(.deny)
      return
    }
    if cameraDecision == .allow, microphoneDecision == .allow {
      decisionHandler(.grant)
      return
    }
    if cameraDecision == nil,
       store.defaultPolicy(for: .camera) == .deny {
      decisionHandler(.deny)
      return
    }
    if microphoneDecision == nil,
       store.defaultPolicy(for: .microphone) == .deny {
      decisionHandler(.deny)
      return
    }
    guard canPresentPermissionAlert() else {
      decisionHandler(.deny)
      return
    }
    presentPermissionAlert(
      title: "“\(host)”请求使用摄像头和麦克风",
      message: "允许该网站使用摄像头和麦克风吗？你可以稍后在浏览器设置中修改。",
      remember: { decision in
        store.setDecision(decision, for: host, permission: .camera)
        store.setDecision(decision, for: host, permission: .microphone)
      },
      decisionHandler: decisionHandler
    )
  }

  private func canPresentPermissionAlert() -> Bool {
    view.window != nil && presentedViewController == nil
  }

  private func presentPermissionAlert(
    title: String,
    message: String,
    remember: @escaping (WebsitePermissionDecision) -> Void,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: "允许一次", style: .default) { _ in
        decisionHandler(.grant)
      }
    )
    alert.addAction(
      UIAlertAction(title: "始终允许", style: .default) { _ in
        remember(.allow)
        decisionHandler(.grant)
      }
    )
    alert.addAction(
      UIAlertAction(title: "始终阻止", style: .destructive) { _ in
        remember(.deny)
        decisionHandler(.deny)
      }
    )
    alert.addAction(
      UIAlertAction(title: "暂不允许", style: .cancel) { _ in
        decisionHandler(.deny)
      }
    )
    present(alert, animated: true)
  }
}
