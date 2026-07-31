import UIKit
import XCTest
@testable import SniffBrowser

final class UserCenterCountsTests: XCTestCase {
    func testDefaultCountsRepresentEmptyLocalRepositories() {
        let counts = UserCenterCounts()

        XCTAssertEqual(counts.downloads, 0)
        XCTAssertEqual(counts.files, 0)
        XCTAssertEqual(counts.favorites, 0)
        XCTAssertEqual(counts.history, 0)
    }

    func testNegativeRepositoryCountsAreClampedToZero() {
        let counts = UserCenterCounts(
            downloads: -1,
            files: -20,
            favorites: -3,
            history: -99
        )

        XCTAssertEqual(counts.downloads, 0)
        XCTAssertEqual(counts.files, 0)
        XCTAssertEqual(counts.favorites, 0)
        XCTAssertEqual(counts.history, 0)
    }

    func testInjectedRepositoryCountsRemainUnchanged() {
        let counts = UserCenterCounts(
            downloads: 2,
            files: 4,
            favorites: 6,
            history: 8
        )

        XCTAssertEqual(counts.downloads, 2)
        XCTAssertEqual(counts.files, 4)
        XCTAssertEqual(counts.favorites, 6)
        XCTAssertEqual(counts.history, 8)
    }

    @MainActor
    func testUserCenterRendersInjectedCountsForAccessibility() {
        let controller = UserCenterViewController(
            counts: UserCenterCounts(
                downloads: 2,
                files: 4,
                favorites: 6,
                history: 8
            )
        )

        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        let labels = accessibilityLabels(in: controller.view)

        XCTAssertTrue(labels.contains("下载，2"))
        XCTAssertTrue(labels.contains("文件，4"))
        XCTAssertTrue(labels.contains("收藏，6"))
        XCTAssertTrue(labels.contains("历史，8"))
    }

    @MainActor
    private func accessibilityLabels(in view: UIView) -> [String] {
        let ownLabel = view.isAccessibilityElement
            ? view.accessibilityLabel.map { [$0] } ?? []
            : []
        return ownLabel + view.subviews.flatMap {
            accessibilityLabels(in: $0)
        }
    }
}
