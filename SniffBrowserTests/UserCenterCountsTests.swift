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
    func testUserCenterInitialLayoutIsCompleteWithZeroCounts() throws {
        let controller = UserCenterViewController()
        layout(controller)

        let labels = accessibilityLabels(in: controller.view)
        XCTAssertTrue(labels.contains("登录或注册"))
        XCTAssertTrue(labels.contains("下载，0"))
        XCTAssertTrue(labels.contains("文件，0"))
        XCTAssertTrue(labels.contains("收藏，0"))
        XCTAssertTrue(labels.contains("历史，0"))

        let avatar = try XCTUnwrap(
            findView(
                accessibilityIdentifier: "userCenter.avatar",
                in: controller.view
            ) as? UIImageView
        )
        XCTAssertNotNil(avatar.image)
        XCTAssertFalse(avatar.isHidden)
        XCTAssertGreaterThan(avatar.bounds.height, 0)

        let primaryAction = try XCTUnwrap(
            findControl(
                accessibilityIdentifier: "userCenter.primaryAction",
                in: controller.view
            )
        )
        XCTAssertFalse(primaryAction.isHidden)
        XCTAssertGreaterThanOrEqual(
            primaryAction.bounds.height,
            AppMetrics.minimumTapSize
        )

        let summaryControls = try summaryControls(in: controller.view)
        XCTAssertEqual(summaryControls.count, 4)
        summaryControls.values.forEach {
            XCTAssertFalse($0.isHidden)
            XCTAssertEqual($0.alpha, 1)
            XCTAssertGreaterThan($0.bounds.height, 0)
        }
    }

    @MainActor
    func testCountUpdateOnlyChangesExistingSummaryControls() throws {
        let controller = UserCenterViewController()
        layout(controller)
        let controlsBefore = try summaryControls(in: controller.view)
        let identitiesBefore = controlsBefore.mapValues { ObjectIdentifier($0) }

        controller.update(
            counts: UserCenterCounts(
                downloads: 1,
                files: 2,
                favorites: 3,
                history: 4
            )
        )
        controller.view.layoutIfNeeded()

        let controlsAfter = try summaryControls(in: controller.view)
        XCTAssertEqual(
            controlsAfter.mapValues { ObjectIdentifier($0) },
            identitiesBefore
        )
        XCTAssertEqual(controlsAfter["userCenter.summary.downloads"]?.accessibilityLabel, "下载，1")
        XCTAssertEqual(controlsAfter["userCenter.summary.files"]?.accessibilityLabel, "文件，2")
        XCTAssertEqual(controlsAfter["userCenter.summary.favorites"]?.accessibilityLabel, "收藏，3")
        XCTAssertEqual(controlsAfter["userCenter.summary.history"]?.accessibilityLabel, "历史，4")
    }

    @MainActor
    func testUserCenterDoesNotContainDuplicateBrowserSettingsEntry() throws {
        let controller = UserCenterViewController()
        layout(controller)

        let tableView = try XCTUnwrap(findTableView(in: controller.view))
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 3)
        let rowLabels = (0..<3).compactMap { row in
            tableView.dataSource?
                .tableView(tableView, cellForRowAt: IndexPath(row: row, section: 0))
                .accessibilityLabel
        }

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

    @MainActor
    private func summaryControls(in view: UIView) throws -> [String: UIControl] {
        let identifiers = [
            "userCenter.summary.downloads",
            "userCenter.summary.files",
            "userCenter.summary.favorites",
            "userCenter.summary.history"
        ]
        return try Dictionary(uniqueKeysWithValues: identifiers.map { identifier in
            let control = try XCTUnwrap(
                findControl(accessibilityIdentifier: identifier, in: view)
            )
            return (identifier, control)
        })
    }

    @MainActor
    private func findControl(
        accessibilityIdentifier: String,
        in view: UIView
    ) -> UIControl? {
        if let control = view as? UIControl,
           control.accessibilityIdentifier == accessibilityIdentifier {
            return control
        }
        return view.subviews.lazy.compactMap {
            findControl(
                accessibilityIdentifier: accessibilityIdentifier,
                in: $0
            )
        }.first
    }

    @MainActor
    private func findView(
        accessibilityIdentifier: String,
        in view: UIView
    ) -> UIView? {
        if view.accessibilityIdentifier == accessibilityIdentifier {
            return view
        }
        return view.subviews.lazy.compactMap {
            findView(
                accessibilityIdentifier: accessibilityIdentifier,
                in: $0
            )
        }.first
    }

    @MainActor
    private func findTableView(in view: UIView) -> UITableView? {
        if let tableView = view as? UITableView {
            return tableView
        }
        return view.subviews.lazy.compactMap(findTableView(in:)).first
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
