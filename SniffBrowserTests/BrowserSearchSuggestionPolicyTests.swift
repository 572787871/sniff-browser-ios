import XCTest
@testable import SniffBrowser

final class BrowserSearchSuggestionPolicyTests: XCTestCase {
  func testNewTabSuggestionsDoNotShowFavoritesOrPreFilterHistory() {
    XCTAssertFalse(
      BrowserSearchSuggestionPolicy.showsFavorites(in: .newTab)
    )
    XCTAssertEqual(
      BrowserSearchSuggestionPolicy.initialHistoryQuery(
        for: .newTab,
        title: "新标签页",
        url: nil
      ),
      ""
    )
  }

  func testWebPageSuggestionsShowFavoritesAndUseSearchQuery() {
    XCTAssertTrue(
      BrowserSearchSuggestionPolicy.showsFavorites(in: .webPage)
    )
    XCTAssertEqual(
      BrowserSearchSuggestionPolicy.initialHistoryQuery(
        for: .webPage,
        title: "你好发音 - Google 搜索",
        url: URL(
          string: "https://www.google.com/search?q=%E4%BD%A0%E5%A5%BD%E5%8F%91%E9%9F%B3"
        )
      ),
      "你好发音"
    )
  }

  func testWebPageSuggestionsFallBackToPageTitle() {
    XCTAssertEqual(
      BrowserSearchSuggestionPolicy.initialHistoryQuery(
        for: .webPage,
        title: "示例文章",
        url: URL(string: "https://example.com/article")
      ),
      "示例文章"
    )
  }
}
