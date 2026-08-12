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

        XCTAssertEqual(
            controller.summaryAccessibilityLabels,
            ["下载，2", "文件，4", "收藏，6", "历史，8"]
        )
    }

    @MainActor
    func testUserCenterInitialLayoutIsCompleteWithZeroCounts() {
        let controller = UserCenterViewController()
        layout(controller)
        XCTAssertEqual(controller.displayedCounts, UserCenterCounts())
        XCTAssertEqual(
            controller.summaryAccessibilityLabels,
            ["下载，0", "文件，0", "收藏，0", "历史，0"]
        )
        XCTAssertFalse(controller.children.isEmpty)
    }

    @MainActor
    func testCountUpdatePublishesIntoExistingSwiftUIStore() {
        let controller = UserCenterViewController()
        layout(controller)

        controller.update(
            counts: UserCenterCounts(
                downloads: 1,
                files: 2,
                favorites: 3,
                history: 4
            )
        )
        XCTAssertEqual(
            controller.summaryAccessibilityLabels,
            ["下载，1", "文件，2", "收藏，3", "历史，4"]
        )
    }

    @MainActor
    func testUserCenterDoesNotContainDuplicateBrowserSettingsEntry() {
        let controller = UserCenterViewController()
        layout(controller)
        let rowLabels = controller.menuAccessibilityLabels
        XCTAssertEqual(
            rowLabels,
            [
                "数据同步，登录后可用",
                "隐私与安全，网站权限与浏览数据",
                "关于嗅探浏览器，版本与许可信息"
            ]
        )
        XCTAssertFalse(rowLabels.contains { $0.contains("浏览器设置") })
    }

    @MainActor
    private func layout(_ controller: UIViewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

}
