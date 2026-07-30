import Foundation

struct BrowserPreferences {
  private enum Key {
    static let searchEngine = "browser.searchEngine"
    static let pullToRefresh = "browser.pullToRefresh"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var searchEngine: SearchEngine {
    get {
      guard let rawValue = defaults.string(forKey: Key.searchEngine),
            let value = SearchEngine(rawValue: rawValue)
      else {
        return .google
      }
      return value
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: Key.searchEngine)
    }
  }

  var pullToRefreshEnabled: Bool {
    get {
      defaults.object(forKey: Key.pullToRefresh) == nil
        ? true
        : defaults.bool(forKey: Key.pullToRefresh)
    }
    nonmutating set {
      defaults.set(newValue, forKey: Key.pullToRefresh)
    }
  }
}
