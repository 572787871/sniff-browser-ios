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

        controller.selectDestination(.downloadPreferences)

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
    func testMoreDestinationsStayInsideSheetNavigationStack() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = AppCoordinator(window: window)
        coordinator.start()
        let menu = BrowserMoreMenuViewController(state: BrowserMoreMenuState(
            hasCurrentPage: true,
            downloadSummary: nil,
            fileSummary: nil,
            accountSummary: "游客模式"
        ))
        let sheetNavigation = BrowserMoreNavigationController(root: menu)

        coordinator.showMoreDestination(
            .downloads,
            in: sheetNavigation
        )
        let downloads = try XCTUnwrap(
            sheetNavigation.topViewController as? DownloadManagerViewController
        )
        downloads.onRoute?(.downloadSettings)

        XCTAssertEqual(sheetNavigation.modalPresentationStyle, .pageSheet)
        XCTAssertTrue(sheetNavigation.viewControllers.first === menu)
        XCTAssertTrue(
            sheetNavigation.topViewController
                is DownloadSettingsViewController
        )

        sheetNavigation.popViewController(animated: false)
        XCTAssertTrue(sheetNavigation.topViewController === downloads)
    }

    @MainActor
    func testDownloadSettingsPageContainsOnlyPersistedPolicyRows() throws {
        let controller = DownloadSettingsViewController()
        layout(controller)
        XCTAssertEqual(
            DownloadSettingsViewController.policyAccessibilityIdentifiers,
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
            self.findControl(
                accessibilityIdentifier: accessibilityIdentifier,
                in: $0
            )
        }.first
    }

}
