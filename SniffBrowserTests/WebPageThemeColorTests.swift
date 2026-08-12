import UIKit
import XCTest
@testable import SniffBrowser

final class WebPageThemeColorTests: XCTestCase {
  func testParsesShortAndLongHexColors() {
    XCTAssertEqual(
      WebPageThemeColorParser.parse("#0af"),
      WebPageThemeColor(red: 0, green: 10.0 / 15.0, blue: 1)
    )
    XCTAssertEqual(
      WebPageThemeColorParser.parse("#336699"),
      WebPageThemeColor(
        red: 51.0 / 255.0,
        green: 102.0 / 255.0,
        blue: 153.0 / 255.0
      )
    )
  }

  func testParsesRGBAndRGBAColors() {
    XCTAssertEqual(
      WebPageThemeColorParser.parse("rgb(12, 34, 56)"),
      WebPageThemeColor(
        red: 12.0 / 255.0,
        green: 34.0 / 255.0,
        blue: 56.0 / 255.0
      )
    )
    XCTAssertEqual(
      WebPageThemeColorParser.parse("rgba(10, 20, 30, 0.9)"),
      WebPageThemeColor(
        red: 10.0 / 255.0,
        green: 20.0 / 255.0,
        blue: 30.0 / 255.0,
        alpha: 0.9
      )
    )
  }

  func testTransparentAndLowAlphaColorsFallBack() {
    XCTAssertNil(WebPageThemeColorParser.parse("transparent"))
    XCTAssertNil(
      WebPageThemeColorParser.parseUsable("rgba(10, 20, 30, 0.2)")
    )
  }

  func testInvalidColorsFallBack() {
    XCTAssertNil(WebPageThemeColorParser.parse("not-a-color"))
    XCTAssertNil(WebPageThemeColorParser.parse("rgb(500, 0, 0)"))
    XCTAssertNil(WebPageThemeColorParser.parse("#12"))
  }

  func testInvalidOrLowAlphaThemeColorFallsBackToPageBackground() {
    XCTAssertEqual(
      WebPageThemeColorParser.firstUsable(
        in: [
          "not-a-color",
          "rgba(255, 0, 0, 0.2)",
          "rgb(12, 34, 56)"
        ]
      ),
      WebPageThemeColor(
        red: 12.0 / 255.0,
        green: 34.0 / 255.0,
        blue: 56.0 / 255.0
      )
    )
  }

  func testDarkBackgroundUsesLightForeground() {
    XCTAssertEqual(
      ContrastColorResolver.foregroundStyle(
        for: WebPageThemeColor(red: 0.04, green: 0.05, blue: 0.06)
      ),
      .light
    )
  }

  func testLightBackgroundUsesDarkForeground() {
    XCTAssertEqual(
      ContrastColorResolver.foregroundStyle(
        for: WebPageThemeColor(red: 0.95, green: 0.96, blue: 0.97)
      ),
      .dark
    )
  }

  func testDarkAppearanceRejectsLightPageTheme() {
    let lightPage = WebPageThemeColor(red: 0.96, green: 0.96, blue: 0.96)

    XCTAssertNil(
      BrowserChromeThemeResolver.effectivePageTheme(
        lightPage,
        interfaceStyle: .dark
      )
    )
    XCTAssertEqual(
      BrowserChromeThemeResolver.pageCanvasTheme(lightPage),
      lightPage
    )
  }

  func testDarkAppearanceKeepsDarkPageTheme() {
    let darkPage = WebPageThemeColor(red: 0.04, green: 0.05, blue: 0.06)

    XCTAssertEqual(
      BrowserChromeThemeResolver.effectivePageTheme(
        darkPage,
        interfaceStyle: .dark
      ),
      darkPage
    )
  }

  func testLightAppearanceKeepsDarkPageTheme() {
    let darkPage = WebPageThemeColor(red: 0.04, green: 0.05, blue: 0.06)

    XCTAssertEqual(
      BrowserChromeThemeResolver.effectivePageTheme(
        darkPage,
        interfaceStyle: .light
      ),
      darkPage
    )
  }
}
