import UIKit
import XCTest
@testable import SniffBrowser

final class TabOverviewLayoutTests: XCTestCase {
    func testSnapshotViewportExcludesNativeChromeInsets() {
        let rect = TabSnapshotViewportGeometry.visibleRect(
            bounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            contentInset: UIEdgeInsets(top: 112, left: 0, bottom: 94, right: 0)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 112, width: 390, height: 638))
    }

    func testSnapshotViewportClampsOversizedInsets() {
        let rect = TabSnapshotViewportGeometry.visibleRect(
            bounds: CGRect(x: 0, y: 0, width: 100, height: 80),
            contentInset: UIEdgeInsets(top: 100, left: 0, bottom: 100, right: 0)
        )

        XCTAssertEqual(rect.width, 100)
        XCTAssertGreaterThanOrEqual(rect.height, 1)
        XCTAssertLessThanOrEqual(rect.maxY, 80)
    }

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
            metrics.previewSize.height / metrics.previewSize.width,
            TabOverviewGridLayoutMetrics.minimumPortraitPreviewHeightToWidthRatio
        )
        XCTAssertEqual(
            metrics.itemSize.height - metrics.previewSize.height,
            TabOverviewGridLayoutMetrics.metadataAreaHeight,
            accuracy: 0.001
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

    func testPersistedPagingOffsetsInitializeIndependentlyAndNormalizeValues() {
        let state = TabOverviewPagingState(
            selectedMode: .privateBrowsing,
            standardScrollOffset: 428,
            privateScrollOffset: -30
        )

        XCTAssertEqual(state.scrollOffset(for: .standard), 428)
        XCTAssertEqual(state.scrollOffset(for: .privateBrowsing), 0)
    }

    func testRestoredBottomTabIsMovedOnlyEnoughToBecomeFullyVisible() {
        let offset = TabOverviewScrollRestorationGeometry.resolvedOffset(
            savedOffset: 500,
            minimumOffset: 0,
            maximumOffset: 800,
            viewportHeight: 400,
            selectedItemFrame: CGRect(x: 0, y: 850, width: 170, height: 300)
        )

        XCTAssertEqual(offset, 766, accuracy: 0.001)
    }

    func testRestorationDoesNotJumpToASelectedTabOutsideSavedViewport() {
        let offset = TabOverviewScrollRestorationGeometry.resolvedOffset(
            savedOffset: 160,
            minimumOffset: 0,
            maximumOffset: 900,
            viewportHeight: 400,
            selectedItemFrame: CGRect(x: 0, y: 900, width: 170, height: 300)
        )

        XCTAssertEqual(offset, 160, accuracy: 0.001)
    }

    func testTransitionImageFramesKeepOneAspectRatioAtBothEndpoints() {
        let imageSize = CGSize(width: 390, height: 844)
        let sourceFrame = TabOverviewTransitionGeometry.pageFillFrame(
            contentSize: imageSize,
            containerSize: CGSize(width: 170, height: 260)
        )
        let targetFrame = TabOverviewTransitionGeometry.clippedPageFrame(
            contentSize: imageSize,
            fullContainerFrame: CGRect(x: 0, y: 50, width: 390, height: 794),
            clippedTo: CGRect(x: 0, y: 130, width: 390, height: 620)
        )

        XCTAssertEqual(
            sourceFrame.width / imageSize.width,
            sourceFrame.height / imageSize.height,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            targetFrame.width / imageSize.width,
            targetFrame.height / imageSize.height,
            accuracy: 0.000_1
        )
    }

    func testPortraitPageFillKeepsFullWidthAndCropsOnlyBelowTheVisibleTop() {
        let containerSize = CGSize(width: 170, height: 260)
        let frame = TabOverviewTransitionGeometry.pageFillFrame(
            contentSize: CGSize(width: 390, height: 844),
            containerSize: containerSize
        )

        XCTAssertEqual(frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(frame.width, containerSize.width, accuracy: 0.001)
        XCTAssertGreaterThan(frame.height, containerSize.height)
        XCTAssertEqual(frame.minY, 0, accuracy: 0.001)
        XCTAssertGreaterThan(frame.maxY, containerSize.height)
    }

    func testPageFillNeverLeavesBlankEdgesForLandscapeSnapshots() {
        let containerSize = CGSize(width: 250, height: 170)
        let frame = TabOverviewTransitionGeometry.pageFillFrame(
            contentSize: CGSize(width: 844, height: 390),
            containerSize: containerSize
        )

        XCTAssertGreaterThanOrEqual(frame.width, containerSize.width)
        XCTAssertGreaterThanOrEqual(frame.height, containerSize.height)
        XCTAssertLessThanOrEqual(frame.minX, 0)
        XCTAssertEqual(frame.minY, 0, accuracy: 0.001)
    }

    func testPageLayoutsAlwaysUseOneUniformScale() {
        let contentSize = CGSize(width: 390, height: 844)
        let layout = TabOverviewTransitionGeometry.pageFillLayout(
            contentSize: contentSize,
            containerSize: CGSize(width: 170, height: 260)
        )
        let frame = layout.frame(contentSize: contentSize)

        XCTAssertEqual(
            frame.width / contentSize.width,
            frame.height / contentSize.height,
            accuracy: 0.000_1
        )
        XCTAssertEqual(frame.width / contentSize.width, layout.scale, accuracy: 0.000_1)
    }

    func testClippedPageFrameKeepsTheSamePixelsAsTheFullBrowserCover() {
        let fullFrame = CGRect(x: 0, y: 50, width: 390, height: 794)
        let clippedFrame = CGRect(x: 0, y: 130, width: 390, height: 620)
        let fullImageFrame = TabOverviewTransitionGeometry.pageFillFrame(
            contentSize: CGSize(width: 390, height: 844),
            containerSize: fullFrame.size
        )
        let clippedImageFrame = TabOverviewTransitionGeometry.clippedPageFrame(
            contentSize: CGSize(width: 390, height: 844),
            fullContainerFrame: fullFrame,
            clippedTo: clippedFrame
        )

        XCTAssertEqual(clippedImageFrame.width, fullImageFrame.width, accuracy: 0.001)
        XCTAssertEqual(clippedImageFrame.height, fullImageFrame.height, accuracy: 0.001)
        XCTAssertEqual(
            clippedFrame.minY + clippedImageFrame.minY,
            fullFrame.minY + fullImageFrame.minY,
            accuracy: 0.001
        )
    }
}
