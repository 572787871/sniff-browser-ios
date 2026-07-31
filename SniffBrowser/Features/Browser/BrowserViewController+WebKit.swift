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
    guard webView === activeWebView else { return }
    errorView.isHidden = true
    chromeScrollController.reset()
    applyChromeState(.expanded, animated: true)
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
    if webView === activeWebView {
      synchronizeActiveState()
      Task { [weak self] in
        await self?.tabManager.captureSnapshot(for: tab.id)
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    handleNavigationFailure(error, in: webView)
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
}
