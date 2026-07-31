import XCTest
@testable import SniffBrowser

final class BrowserPresentationModelTests: XCTestCase {
  func testBottomSheetContainsExpectedQuickActionsAndDestinations() {
    XCTAssertEqual(
      BrowserQuickAction.allCases,
      [.newTab, .share, .favorite, .reload]
    )
    XCTAssertEqual(
      BrowserMenuDestination.allCases,
      [.downloads, .files, .history, .userCenter, .settings]
    )
  }

  func testPageActionsAreDisabledOnNewTabWithoutFakeStatusCounts() {
    let state = BrowserMoreMenuState(
      hasCurrentPage: false,
      downloadSummary: nil,
      fileSummary: nil,
      accountSummary: "游客模式"
    )

    XCTAssertTrue(state.isEnabled(.newTab))
    XCTAssertTrue(state.isEnabled(.favorite))
    XCTAssertFalse(state.isEnabled(.share))
    XCTAssertFalse(state.isEnabled(.reload))
    XCTAssertNil(state.detail(for: .downloads))
    XCTAssertNil(state.detail(for: .files))
    XCTAssertEqual(state.detail(for: .userCenter), "游客模式")
  }

  func testChromeRequiresStableScrollDirectionBeforeTransition() {
    var controller = BrowserChromeScrollController()

    XCTAssertNil(
      controller.update(
        contentOffsetY: 0,
        adjustedTopInset: 0,
        canCollapse: true
      )
    )
    XCTAssertNil(
      controller.update(
        contentOffsetY: 18,
        adjustedTopInset: 0,
        canCollapse: true
      )
    )
    XCTAssertEqual(
      controller.update(
        contentOffsetY: 52,
        adjustedTopInset: 0,
        canCollapse: true
      ),
      .compact
    )
    XCTAssertEqual(controller.state, .compact)

    XCTAssertEqual(
      controller.update(
        contentOffsetY: 12,
        adjustedTopInset: 0,
        canCollapse: true
      ),
      .expanded
    )
  }

  func testChromeExpandsWhenCollapsingIsUnavailable() {
    var controller = BrowserChromeScrollController()
    _ = controller.update(
      contentOffsetY: 20,
      adjustedTopInset: 0,
      canCollapse: true
    )
    _ = controller.update(
      contentOffsetY: 60,
      adjustedTopInset: 0,
      canCollapse: true
    )

    XCTAssertEqual(
      controller.update(
        contentOffsetY: 80,
        adjustedTopInset: 0,
        canCollapse: false
      ),
      .expanded
    )
  }
}
