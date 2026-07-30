import Foundation

enum SearchEngine: String, CaseIterable, Codable {
  case google
  case bing
  case duckDuckGo
  case baidu

  var displayName: String {
    switch self {
    case .google: return "Google"
    case .bing: return "Bing"
    case .duckDuckGo: return "DuckDuckGo"
    case .baidu: return "百度"
    }
  }

  func searchURL(for query: String) -> URL? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let endpoint: String
    let key: String
    switch self {
    case .google:
      endpoint = "https://www.google.com/search"
      key = "q"
    case .bing:
      endpoint = "https://www.bing.com/search"
      key = "q"
    case .duckDuckGo:
      endpoint = "https://duckduckgo.com/"
      key = "q"
    case .baidu:
      endpoint = "https://www.baidu.com/s"
      key = "wd"
    }
    var components = URLComponents(string: endpoint)
    components?.queryItems = [URLQueryItem(name: key, value: trimmed)]
    return components?.url
  }
}
