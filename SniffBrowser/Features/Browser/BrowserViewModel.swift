import Foundation

struct BrowserViewState: Equatable {
  var title = "新标签页"
  var url: URL?
  var isLoading = false
  var progress = 0.0
  var canGoBack = false
  var canGoForward = false

  var isSecure: Bool {
    url?.scheme?.lowercased() == "https"
  }

  var isInsecure: Bool {
    url?.scheme?.lowercased() == "http"
  }
}

@MainActor
final class BrowserViewModel {
  private(set) var state = BrowserViewState() {
    didSet {
      guard oldValue != state else { return }
      onStateChange?(state)
    }
  }

  var onStateChange: ((BrowserViewState) -> Void)?
  private let preferences: BrowserPreferences

  init(preferences: BrowserPreferences = BrowserPreferences()) {
    self.preferences = preferences
  }

  func resolve(_ input: String) -> URL? {
    URLNormalizer.resolve(input, searchEngine: preferences.searchEngine)
  }

  func update(
    title: String?,
    url: URL?,
    isLoading: Bool,
    progress: Double,
    canGoBack: Bool,
    canGoForward: Bool
  ) {
    state.title = title?.isEmpty == false ? title ?? "网页" : "网页"
    state.url = url
    state.isLoading = isLoading
    state.progress = min(1, max(0, progress))
    state.canGoBack = canGoBack
    state.canGoForward = canGoForward
  }

  func resetToNewTab() {
    state = BrowserViewState()
  }
}
