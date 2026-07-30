import XCTest
@testable import SniffBrowser

final class URLNormalizerTests: XCTestCase {
  func testResolvesCompleteHTTPSURLWithoutChangingIt() {
    let result = URLNormalizer.resolve("https://example.com/path?q=value")

    XCTAssertEqual(result?.absoluteString, "https://example.com/path?q=value")
  }

  func testResolvesCompleteHTTPURLWithoutUpgradingIt() {
    let result = URLNormalizer.resolve("http://example.com/article")

    XCTAssertEqual(result?.absoluteString, "http://example.com/article")
  }

  func testAddsHTTPSchemeToDomainWithoutProtocol() {
    let result = URLNormalizer.resolve("example.com/path")

    XCTAssertEqual(result?.absoluteString, "https://example.com/path")
  }

  func testTurnsOrdinaryWordsIntoGoogleSearch() {
    let result = URLNormalizer.resolve("native iOS browser")
    let components = result.flatMap {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)
    }

    XCTAssertEqual(components?.scheme, "https")
    XCTAssertEqual(components?.host, "www.google.com")
    XCTAssertEqual(queryValue(named: "q", in: components), "native iOS browser")
  }

  func testTurnsChineseWordsIntoGoogleSearchWithoutLosingCharacters() {
    let result = URLNormalizer.resolve("苹果 浏览器")
    let components = result.flatMap {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)
    }

    XCTAssertEqual(components?.host, "www.google.com")
    XCTAssertEqual(queryValue(named: "q", in: components), "苹果 浏览器")
  }

  func testReturnsNilForEmptyInput() {
    XCTAssertNil(URLNormalizer.resolve(""))
    XCTAssertNil(URLNormalizer.resolve(" \n\t "))
  }

  func testReturnsNilForMalformedOrUnsupportedExplicitURL() {
    XCTAssertNil(URLNormalizer.resolve("https://"))
    XCTAssertNil(URLNormalizer.resolve("ftp://example.com/file"))
    XCTAssertNil(URLNormalizer.resolve("https://example.com/\u{0000}"))
  }

  private func queryValue(
    named name: String,
    in components: URLComponents?
  ) -> String? {
    components?.queryItems?.first(where: { $0.name == name })?.value
  }
}
