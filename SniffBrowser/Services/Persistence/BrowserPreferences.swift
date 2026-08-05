import Foundation

struct BrowserPreferences {
  private enum Key {
    static let searchEngine = "browser.searchEngine"
    static let pullToRefresh = "browser.pullToRefresh"
    static let newTabShowsWelcome = "browser.newTab.showsWelcome"
    static let newTabShowsDate = "browser.newTab.showsDate"
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

  var newTabShowsWelcome: Bool {
    get {
      defaults.object(forKey: Key.newTabShowsWelcome) == nil
        ? true
        : defaults.bool(forKey: Key.newTabShowsWelcome)
    }
    nonmutating set {
      defaults.set(newValue, forKey: Key.newTabShowsWelcome)
    }
  }

  var newTabShowsDate: Bool {
    get {
      defaults.object(forKey: Key.newTabShowsDate) == nil
        ? true
        : defaults.bool(forKey: Key.newTabShowsDate)
    }
    nonmutating set {
      defaults.set(newValue, forKey: Key.newTabShowsDate)
    }
  }
}
