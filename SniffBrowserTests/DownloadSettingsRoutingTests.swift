import UIKit
import XCTest
@testable import SniffBrowser

final class DownloadSettingsRoutingTests: XCTestCase {
    @MainActor
    func testDownloadEmptyStateButtonUsesDownloadSettingsRoute() throws {
        let controller = DownloadManagerViewController()
        var receivedRoutes: [AppRoute] = []
        controller.onRoute = { receivedRoutes.append($0) }
        layout(controller)

        let button = try XCTUnwrap(
            findControl(
                accessibilityIdentifier: "emptyState.secondaryAction",
                in: controller.view
            )
        )
        button.sendActions(for: .touchUpInside)

        XCTAssertEqual(receivedRoutes, [.downloadSettings])
    }

    @MainActor
    func testSettingsHomeUsesSameDownloadSettingsRoute() throws {
        let controller = SettingsViewController()
        var receivedRoutes: [AppRoute] = []
        controller.onRoute = { receivedRoutes.append($0) }
        layout(controller)

        let tableView = try XCTUnwrap(findTableView(in: controller.view))
        controller.tableView(
            tableView,
            didSelectRowAt: IndexPath(row: 0, section: 2)
        )

        XCTAssertEqual(receivedRoutes, [.downloadSettings])
    }

    @MainActor
    func testNativeBackNavigationReturnsToDownloadsPage() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = AppCoordinator(window: window)
        coordinator.start()
        coordinator.showDownloads()
        let navigation = try XCTUnwrap(
            window.rootViewController as? UINavigationController
        )
        let downloads = try XCTUnwrap(
            navigation.topViewController as? DownloadManagerViewController
        )

        coordinator.navigate(to: .downloadSettings)
        let settings = try XCTUnwrap(
            navigation.topViewController as? DownloadSettingsViewController
        )
        settings.loadViewIfNeeded()
        XCTAssertEqual(settings.navigationItem.title, "下载设置")

        navigation.popViewController(animated: false)
        XCTAssertTrue(navigation.topViewController === downloads)
    }

    @MainActor
    func testDownloadSettingsPageContainsOnlyPersistedPolicyRows() throws {
        let controller = DownloadSettingsViewController()
        layout(controller)
        let tableView = try XCTUnwrap(findTableView(in: controller.view))

        XCTAssertEqual(tableView.numberOfSections, 4)
        XCTAssertEqual(
            (0..<tableView.numberOfSections).reduce(0) {
                $0 + tableView.numberOfRows(inSection: $1)
            },
            5
        )

        let identifiers = (0..<tableView.numberOfSections).flatMap { section in
            (0..<tableView.numberOfRows(inSection: section)).compactMap { row in
                tableView.dataSource?
                    .tableView(
                        tableView,
                        cellForRowAt: IndexPath(row: row, section: section)
                    )
                    .accessibilityIdentifier
            }
        }
        XCTAssertEqual(
            Set(identifiers),
            Set([
                "downloadSettings.cellular",
                "downloadSettings.concurrency",
                "downloadSettings.automaticRetry",
                "downloadSettings.completionNotification",
                "downloadSettings.saveLocation"
            ])
        )
    }

    @MainActor
    private func layout(_ controller: UIViewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
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
    private func findTableView(in view: UIView) -> UITableView? {
        if let tableView = view as? UITableView {
            return tableView
        }
        return view.subviews.lazy.compactMap(findTableView(in:)).first
    }
}
