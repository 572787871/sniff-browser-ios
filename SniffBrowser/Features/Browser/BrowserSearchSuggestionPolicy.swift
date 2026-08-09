import Foundation

enum BrowserSearchSuggestionContext: Equatable {
  case newTab
  case webPage
}

struct BrowserSearchSuggestionPolicy {
  private static let searchQueryNames = Set([
    "q",
    "query",
    "search",
    "keyword",
    "keywords",
    "wd",
    "text",
  ])

  static func showsFavorites(
    in context: BrowserSearchSuggestionContext
  ) -> Bool {
    context == .webPage
  }

  static func initialHistoryQuery(
    for context: BrowserSearchSuggestionContext,
    title: String?,
    url: URL?
  ) -> String {
    guard context == .webPage else { return "" }

    if let url,
       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let query = components.queryItems?.first(where: {
         searchQueryNames.contains($0.name.lowercased())
           && $0.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
       })?.value
    {
      return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let normalizedTitle = title?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !normalizedTitle.isEmpty,
       normalizedTitle != "网页",
       normalizedTitle != "新标签页",
       normalizedTitle.localizedCaseInsensitiveCompare(url?.host ?? "") != .orderedSame
    {
      return normalizedTitle
    }

    return url?.host ?? ""
  }
}
