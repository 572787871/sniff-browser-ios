import WebKit

enum BrowserConfiguration {
  static func makeWebViewConfiguration() -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.allowsInlineMediaPlayback = true
    configuration.preferences.isElementFullscreenEnabled = true
    return configuration
  }
}
