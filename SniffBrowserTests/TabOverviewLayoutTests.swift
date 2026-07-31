import UIKit
import XCTest
@testable import SniffBrowser

final class TabOverviewLayoutTests: XCTestCase {
    func testPortraitGridAlwaysUsesTwoColumns() {
        let compact = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 320, height: 500)
        )
        let tall = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 430, height: 720)
        )

        XCTAssertEqual(compact.columnCount, 2)
        XCTAssertEqual(tall.columnCount, 2)
        XCTAssertEqual(compact.viewportRowCount, 2)
        XCTAssertEqual(tall.viewportRowCount, 2)
        XCTAssertEqual(
            tall.itemSize.width,
            (430 - 16 * 2 - 12) / 2,
            accuracy: 0.001
        )
    }

    func testFourPortraitTabsFitInsideFirstViewport() {
        let containerSize = CGSize(width: 390, height: 640)
        let metrics = TabOverviewGridLayoutMetrics.resolve(
            containerSize: containerSize
        )

        XCTAssertEqual(metrics.firstViewportCapacity, 4)
        XCTAssertLessThanOrEqual(
            metrics.firstViewportContentHeight,
            containerSize.height
        )
        XCTAssertFalse(metrics.requiresVerticalScrolling(itemCount: 4))
        XCTAssertGreaterThanOrEqual(
            TabOverviewGridLayoutMetrics.previewHeightRatio,
            0.68
        )
        XCTAssertLessThanOrEqual(
            TabOverviewGridLayoutMetrics.previewHeightRatio,
            0.72
        )
    }

    func testTallPortraitGridCapsCardHeightWithoutChangingTwoColumnCapacity() {
        let metrics = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 430, height: 900)
        )

        XCTAssertEqual(metrics.columnCount, 2)
        XCTAssertEqual(metrics.viewportRowCount, 2)
        XCTAssertEqual(
            metrics.itemSize.height,
            TabOverviewGridLayoutMetrics.portraitMaximumItemHeight
        )
        XCTAssertEqual(metrics.firstViewportCapacity, 4)
    }

    func testMoreThanFourPortraitTabsRequireVerticalScrolling() {
        let metrics = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 390, height: 640)
        )

        XCTAssertTrue(metrics.requiresVerticalScrolling(itemCount: 5))
        XCTAssertTrue(metrics.requiresVerticalScrolling(itemCount: 30))
    }

    func testLandscapeGridUsesThreeOrFourColumnsBasedOnWidth() {
        let threeColumn = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 780, height: 300)
        )
        let fourColumn = TabOverviewGridLayoutMetrics.resolve(
            containerSize: CGSize(width: 852, height: 300)
        )

        XCTAssertEqual(threeColumn.columnCount, 3)
        XCTAssertEqual(fourColumn.columnCount, 4)
    }

    func testProgrammaticModeSelectionKeepsSingleModeState() {
        var state = TabOverviewPagingState(selectedMode: .standard)

        XCTAssertTrue(state.selectMode(.privateBrowsing))
        XCTAssertEqual(state.selectedMode, .privateBrowsing)
        XCTAssertNil(state.pendingInteractiveMode)

        XCTAssertFalse(state.selectMode(.privateBrowsing))
        XCTAssertEqual(state.selectedMode, .privateBrowsing)
    }

    func testHorizontalSwipeUpdatesModeOnlyAfterCompletedTransition() {
        var state = TabOverviewPagingState(selectedMode: .standard)

        state.beginInteractiveTransition(to: .privateBrowsing)
        XCTAssertEqual(state.selectedMode, .standard)
        XCTAssertEqual(state.pendingInteractiveMode, .privateBrowsing)
        XCTAssertTrue(state.finishInteractiveTransition(completed: true))
        XCTAssertEqual(state.selectedMode, .privateBrowsing)
        XCTAssertNil(state.pendingInteractiveMode)

        state.beginInteractiveTransition(to: .standard)
        XCTAssertFalse(state.finishInteractiveTransition(completed: false))
        XCTAssertEqual(state.selectedMode, .privateBrowsing)
        XCTAssertNil(state.pendingInteractiveMode)
    }

    func testNormalAndPrivatePagesKeepIndependentVerticalOffsets() {
        var state = TabOverviewPagingState(selectedMode: .standard)

        state.saveScrollOffset(128, for: .standard)
        state.selectMode(.privateBrowsing)
        state.saveScrollOffset(376, for: .privateBrowsing)
        state.selectMode(.standard)

        XCTAssertEqual(state.scrollOffset(for: .standard), 128)
        XCTAssertEqual(state.scrollOffset(for: .privateBrowsing), 376)
    }
}
