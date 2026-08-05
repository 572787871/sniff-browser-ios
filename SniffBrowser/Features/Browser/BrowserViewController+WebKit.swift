import UIKit
import WebKit

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
      if !tab.isPrivate, let url = lastRequestedURLs[tab.id] ?? webView.url ?? tab.url {
        ContentBlockManager.shared.logManager.addEntry(
          .init(
            url: url.absoluteString,
            host: url.host ?? "",
            resourceType: "Document",
            status: "加载中"
          )
        )
      }
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
      resourceSniffingService.restoreActiveSniffingAfterNavigation(tabID: tab.id)
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
      ContentBlockManager.shared.logManager.addEntry(
        .init(
          url: url.absoluteString,
          host: url.host ?? "",
          resourceType: "Document",
          status: "完成"
        )
      )
    }
    WebPageThemeColorService.requestCurrentTheme(in: webView)
    resourceSniffingService.requestIncrementalScan(tabID: tab.id, reason: "didFinish")
    if webView === activeWebView {
      synchronizeActiveState()
      Task { [weak self] in
        await self?.tabManager.captureSnapshot(for: tab.id)
      }
    }
  }

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
    if let tab = tabManager.tabs.first(where: { $0.webView === webView }),
       !tab.isPrivate,
       let url = webView.url {
      ContentBlockManager.shared.logManager.addEntry(
        .init(
          url: url.absoluteString,
          host: url.host ?? "",
          resourceType: "Document",
          status: "失败",
          isBlocked: (error as NSError).code == NSURLErrorCancelled
        )
      )
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
    guard canPresentPermissionAlert() else {
      decisionHandler(.deny)
      return
    }
    presentPermissionAlert(
      title: "“\(host)”请求使用\(permission.displayName)",
      message: "允许该网站使用\(permission.displayName)吗？你可以稍后在浏览器设置中修改。",
      remember: { allowed in
        store.setDecision(
          allowed ? .allow : .deny,
          for: host,
          permission: permission
        )
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
    if let cameraDecision, let microphoneDecision {
      decisionHandler(
        cameraDecision == .allow && microphoneDecision == .allow ? .grant : .deny
      )
      return
    }
    guard canPresentPermissionAlert() else {
      decisionHandler(.deny)
      return
    }
    presentPermissionAlert(
      title: "“\(host)”请求使用摄像头和麦克风",
      message: "允许该网站使用摄像头和麦克风吗？你可以稍后在浏览器设置中修改。",
      remember: { allowed in
        let decision: WebsitePermissionDecision = allowed ? .allow : .deny
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
    remember: @escaping (Bool) -> Void,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: "允许", style: .default) { _ in
        remember(true)
        decisionHandler(.grant)
      }
    )
    alert.addAction(
      UIAlertAction(title: "拒绝", style: .destructive) { _ in
        remember(false)
        decisionHandler(.deny)
      }
    )
    alert.addAction(
      UIAlertAction(title: "仅本次拒绝", style: .cancel) { _ in
        decisionHandler(.deny)
      }
    )
    present(alert, animated: true)
  }
}
