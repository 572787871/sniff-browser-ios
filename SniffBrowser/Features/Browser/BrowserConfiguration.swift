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
    // Modern players often pause the main video for a pre-roll or source
    // negotiation, then resume it asynchronously after the original tap.
    // Treat that continuation as part of the page's playback flow instead of
    // requiring a second user gesture.
    configuration.mediaTypesRequiringUserActionForPlayback = []
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
