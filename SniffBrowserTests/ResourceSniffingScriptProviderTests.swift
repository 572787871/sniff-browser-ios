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

  func testEmbeddedVideoDoesNotReusePagePreviewArtwork() {
    let source = ResourceSniffingScriptProvider.source

    XCTAssertFalse(source.contains("const pagePreview"))
    XCTAssertFalse(source.contains("thumbnailURL: pagePreview()"))
    XCTAssertTrue(source.contains("element.poster"))
    XCTAssertTrue(source.contains("scanEmbeddedHLSURLs"))
  }

  func testVideoLongPressResolvesPlayerConfigBeforeBlobPlaybackURL() {
    let source = WebVideoLongPressScriptProvider.source

    XCTAssertTrue(source.contains("touchstart"))
    XCTAssertTrue(source.contains("data-config"))
    XCTAssertTrue(source.contains("configuredURL || elementURLs[0]"))
    XCTAssertTrue(source.contains("sniffBrowserVideoLongPress"))
    XCTAssertTrue(source.contains("application/vnd.apple.mpegurl"))
  }

  func testVideoLongPressPayloadAcceptsHTTPAndRejectsBlob() throws {
    let payload = try XCTUnwrap(WebVideoLongPressPayload(body: [
      "url": "https://cdn.example.com/main.m3u8?token=abc",
      "mimeType": "application/vnd.apple.mpegurl",
      "duration": 12.5,
      "width": 1280,
      "height": 720,
    ]))

    XCTAssertEqual(payload.url.host, "cdn.example.com")
    XCTAssertEqual(payload.duration, 12.5)
    XCTAssertEqual(payload.width, 1280)
    XCTAssertNil(WebVideoLongPressPayload(body: [
      "url": "blob:https://example.com/temporary",
    ]))
  }
}
