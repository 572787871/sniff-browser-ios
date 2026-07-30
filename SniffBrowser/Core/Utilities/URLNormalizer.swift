import Foundation

enum URLNormalizer {
  static func resolve(
    _ input: String,
    searchEngine: SearchEngine = .google
  ) -> URL? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      return nil
    }

    if let components = URLComponents(string: value),
       let scheme = components.scheme?.lowercased() {
      guard ["http", "https"].contains(scheme),
            let host = components.host,
            !host.isEmpty
      else {
        return nil
      }
      return components.url
    }

    if isLikelyHost(value),
       let components = URLComponents(string: "https://\(value)"),
       components.host?.isEmpty == false {
      return components.url
    }

    return searchEngine.searchURL(for: value)
  }

  private static func isLikelyHost(_ value: String) -> Bool {
    guard !value.contains(where: \.isWhitespace),
          !value.hasPrefix("."),
          !value.hasSuffix("."),
          !value.contains("://")
    else {
      return false
    }
    if value == "localhost" || value.hasPrefix("localhost:") {
      return true
    }
    guard let host = URLComponents(string: "https://\(value)")?.host else {
      return false
    }
    return host.contains(".") || host.contains(":")
  }
}
