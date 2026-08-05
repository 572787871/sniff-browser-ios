import Foundation

struct BrowserPreferences {
  private enum Key {
    static let searchEngine = "browser.searchEngine"
    static let pullToRefresh = "browser.pullToRefresh"
    static let newTabShowsWelcome = "browser.newTab.showsWelcome"
    static let newTabShowsDate = "browser.newTab.showsDate"
    static let contentBlockingEnabled = "browser.contentBlocking.enabled"
    static let contentBlockingWhitelist = "browser.contentBlocking.whitelist"
    static let contentBlockingAutoUpdate = "browser.contentBlocking.autoUpdate"
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

  var contentBlockingEnabled: Bool {
    get {
      defaults.object(forKey: Key.contentBlockingEnabled) == nil
        ? true
        : defaults.bool(forKey: Key.contentBlockingEnabled)
    }
    nonmutating set {
      defaults.set(newValue, forKey: Key.contentBlockingEnabled)
    }
  }

  var contentBlockingWhitelist: [String] {
    get {
      defaults.stringArray(forKey: Key.contentBlockingWhitelist) ?? []
    }
    nonmutating set {
      defaults.set(
        Array(Set(newValue.map { $0.lowercased() })).sorted(),
        forKey: Key.contentBlockingWhitelist
      )
    }
  }

  var contentBlockingAutoUpdate: Bool {
    get {
      defaults.object(forKey: Key.contentBlockingAutoUpdate) == nil
        ? true
        : defaults.bool(forKey: Key.contentBlockingAutoUpdate)
    }
    nonmutating set {
      defaults.set(newValue, forKey: Key.contentBlockingAutoUpdate)
    }
  }
}
