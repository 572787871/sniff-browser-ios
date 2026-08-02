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
      [.downloads, .files, .favorites, .history, .userCenter, .settings]
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
    XCTAssertFalse(state.isEnabled(.favorite))
    XCTAssertFalse(state.isEnabled(.share))
    XCTAssertFalse(state.isEnabled(.reload))
    XCTAssertNil(state.detail(for: .downloads))
    XCTAssertNil(state.detail(for: .files))
    XCTAssertEqual(state.detail(for: .userCenter), "游客模式")
  }

  func testFavoriteQuickActionReflectsCurrentPageState() {
    let state = BrowserMoreMenuState(
      hasCurrentPage: true,
      downloadSummary: nil,
      fileSummary: nil,
      accountSummary: "游客模式",
      favoriteActionState: FavoriteActionState(
        isEnabled: true,
        isFavorite: true
      )
    )

    XCTAssertTrue(state.isEnabled(.favorite))
    XCTAssertEqual(state.title(for: .favorite), "取消收藏")
    XCTAssertEqual(state.symbolName(for: .favorite), "star.fill")
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
