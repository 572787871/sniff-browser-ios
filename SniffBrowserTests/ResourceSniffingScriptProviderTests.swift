import XCTest
@testable import SniffBrowser

final class ResourceSniffingScriptProviderTests: XCTestCase {
  func testScriptScansLazyLoadedImageURLsAndPictureSources() {
    let source = ResourceSniffingScriptProvider.source

    [
      "z-image-loader-url",
      "data-src",
      "data-original",
      "data-lazy-src",
      "data-srcset",
      "data-lazy-srcset",
    ].forEach { attribute in
      XCTAssertTrue(source.contains("\"\(attribute)\""), attribute)
    }
    XCTAssertTrue(source.contains("parentTag === \"picture\""))
    XCTAssertTrue(source.contains("...lazyImageURLAttributes"))
    XCTAssertTrue(source.contains("...lazyImageSrcsetAttributes"))
    XCTAssertTrue(source.contains("data:image\\/") || source.contains("data:image/"))
    XCTAssertTrue(source.contains("backgroundImage"))
  }
}
