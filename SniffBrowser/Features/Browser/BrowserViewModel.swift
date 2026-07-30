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
    let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "网页"
    state = BrowserViewState(
      title: resolvedTitle,
      url: url,
      isLoading: isLoading,
      progress: min(1, max(0, progress)),
      canGoBack: canGoBack,
      canGoForward: canGoForward
    )
  }

  func resetToNewTab() {
    state = BrowserViewState()
  }
}
