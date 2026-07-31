import WebKit

@MainActor
enum BrowserConfiguration {
  static func makeWebViewConfiguration(
    isPrivate: Bool = false
  ) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.allowsInlineMediaPlayback = true
    configuration.preferences.isElementFullscreenEnabled = true
    configuration.userContentController.addUserScript(
      WebPageThemeColorService.userScript
    )
    configuration.userContentController.addUserScript(
      ResourceSniffingScriptProvider.userScript
    )
    return configuration
  }
}
