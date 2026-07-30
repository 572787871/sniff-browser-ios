import XCTest
@testable import SniffBrowser

final class SearchEngineTests: XCTestCase {
  func testGoogleSearchURL() {
    assertSearch(
      engine: .google,
      query: "Swift UIKit",
      expectedHost: "www.google.com",
      expectedPath: "/search",
      expectedQueryKey: "q"
    )
  }

  func testBingSearchURL() {
    assertSearch(
      engine: .bing,
      query: "Swift UIKit",
      expectedHost: "www.bing.com",
      expectedPath: "/search",
      expectedQueryKey: "q"
    )
  }

  func testDuckDuckGoSearchURL() {
    assertSearch(
      engine: .duckDuckGo,
      query: "Swift UIKit",
      expectedHost: "duckduckgo.com",
      expectedPath: "/",
      expectedQueryKey: "q"
    )
  }

  func testBaiduSearchURLPreservesChineseQuery() {
    assertSearch(
      engine: .baidu,
      query: "网页 浏览器",
      expectedHost: "www.baidu.com",
      expectedPath: "/s",
      expectedQueryKey: "wd"
    )
  }

  func testSearchTrimsOuterWhitespace() {
    let components = SearchEngine.google.searchURL(for: "  browser test  ")
      .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

    XCTAssertEqual(
      components?.queryItems?.first(where: { $0.name == "q" })?.value,
      "browser test"
    )
  }

  func testSearchRejectsEmptyQueryForEveryEngine() {
    for engine in SearchEngine.allCases {
      XCTAssertNil(engine.searchURL(for: " \n "), "\(engine) 应拒绝空查询")
    }
  }

  func testDisplayNamesAreStableAndNonempty() {
    XCTAssertEqual(SearchEngine.google.displayName, "Google")
    XCTAssertEqual(SearchEngine.bing.displayName, "Bing")
    XCTAssertEqual(SearchEngine.duckDuckGo.displayName, "DuckDuckGo")
    XCTAssertEqual(SearchEngine.baidu.displayName, "百度")
  }

  private func assertSearch(
    engine: SearchEngine,
    query: String,
    expectedHost: String,
    expectedPath: String,
    expectedQueryKey: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let url = engine.searchURL(for: query),
          let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
          )
    else {
      XCTFail("搜索引擎未生成有效 URL", file: file, line: line)
      return
    }

    XCTAssertEqual(components.scheme, "https", file: file, line: line)
    XCTAssertEqual(components.host, expectedHost, file: file, line: line)
    XCTAssertEqual(components.path, expectedPath, file: file, line: line)
    XCTAssertEqual(
      components.queryItems?
        .first(where: { $0.name == expectedQueryKey })?
        .value,
      query,
      file: file,
      line: line
    )
  }
}
