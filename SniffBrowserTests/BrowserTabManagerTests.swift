import UIKit
import XCTest
@testable import SniffBrowser

final class BrowserTabManagerTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private var storageKey = ""

    override func setUp() {
        super.setUp()
        suiteName = "BrowserTabManagerTests.\(UUID().uuidString)"
        storageKey = "session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testManagerCreatesOneSelectedNormalTabInitially() throws {
        let manager = try makeManager()

        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.normalTabCount, 1)
        XCTAssertEqual(manager.privateTabCount, 0)
        XCTAssertEqual(manager.selectedTab?.lifecycleState, .active)
        XCTAssertNotNil(manager.selectedTab?.webView)
    }

    @MainActor
    func testTabsOwnIndependentWebViewsAndCanSwitch() throws {
        let manager = try makeManager()
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab(select: false)

        XCTAssertNotNil(first.webView)
        XCTAssertNil(second.webView)
        XCTAssertEqual(manager.selectedTabID, first.id)

        let selected = manager.selectTab(id: second.id)
        let firstWebView = try XCTUnwrap(first.webView)
        let secondWebView = try XCTUnwrap(second.webView)

        XCTAssertEqual(selected?.id, second.id)
        XCTAssertFalse(firstWebView === secondWebView)
        XCTAssertEqual(second.lifecycleState, .active)
        XCTAssertEqual(first.lifecycleState, .inactive)
    }

    @MainActor
    func testClosingSelectedTabSelectsRemainingTab() throws {
        let manager = try makeManager()
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab()

        XCTAssertEqual(manager.selectedTabID, second.id)
        manager.closeTab(id: second.id)

        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.selectedTabID, first.id)
        XCTAssertEqual(first.lifecycleState, .active)
    }

    @MainActor
    func testClosingLastTabAutomaticallyCreatesNewNormalTab() throws {
        let manager = try makeManager()
        let originalID = try XCTUnwrap(manager.selectedTabID)

        manager.closeTab(id: originalID)

        XCTAssertEqual(manager.count, 1)
        XCTAssertNotEqual(manager.selectedTabID, originalID)
        XCTAssertFalse(try XCTUnwrap(manager.selectedTab).isPrivate)
    }

    @MainActor
    func testClosingLastNormalTabWhilePrivateTabExistsCreatesBlankNormalTab() throws {
        let manager = try makeManager()
        let normalID = try XCTUnwrap(manager.selectedTabID)
        let privateTab = try manager.createTab(isPrivate: true, select: false)

        manager.closeTab(id: normalID)

        XCTAssertEqual(manager.normalTabCount, 1)
        XCTAssertEqual(manager.privateTabCount, 1)
        XCTAssertFalse(try XCTUnwrap(manager.selectedTab).isPrivate)
        XCTAssertNotEqual(manager.selectedTabID, privateTab.id)
    }

    @MainActor
    func testMaximumTabCountIsThirty() throws {
        let manager = try makeManager()
        for _ in 1..<BrowserTabManager.absoluteMaximumTabCount {
            _ = try manager.createTab(select: false)
        }

        XCTAssertEqual(manager.count, 30)
        do {
            _ = try manager.createTab()
            XCTFail("超过 30 个标签页时应拒绝新建")
        } catch {
            XCTAssertEqual(
                error as? BrowserTabManager.ManagerError,
                .maximumTabCountReached
            )
        }
        XCTAssertEqual(manager.count, 30)
    }

    @MainActor
    func testPrivateTabsUseNonPersistentStoreAndAreNotRestored() throws {
        let manager = try makeManager()
        let normalTab = try XCTUnwrap(manager.selectedTab)
        let privateTab = try manager.createTab(isPrivate: true)

        XCTAssertTrue(
            try XCTUnwrap(normalTab.webView)
                .configuration.websiteDataStore.isPersistent
        )
        XCTAssertFalse(
            try XCTUnwrap(privateTab.webView)
                .configuration.websiteDataStore.isPersistent
        )
        XCTAssertEqual(manager.privateTabCount, 1)

        let restored = try makeManager()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.normalTabCount, 1)
        XCTAssertEqual(restored.privateTabCount, 0)
        XCTAssertEqual(restored.selectedTabID, normalTab.id)
    }

    @MainActor
    func testNormalTabsRestoreMetadataOrderAndSelection() throws {
        let manager = try makeManager()
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab(select: false)
        manager.updateTab(
            id: first.id,
            title: "首页",
            url: try XCTUnwrap(URL(string: "https://example.com"))
        )
        manager.updateTab(
            id: second.id,
            title: "文档",
            url: try XCTUnwrap(URL(string: "https://example.com/docs"))
        )
        manager.selectTab(id: second.id)

        let restored = try makeManager()

        XCTAssertEqual(restored.tabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(restored.tabs.map(\.title), ["首页", "文档"])
        XCTAssertEqual(restored.selectedTabID, second.id)
        XCTAssertNotNil(restored.selectedTab?.webView)
        XCTAssertNil(restored.tabs.first(where: { $0.id == first.id })?.webView)
    }

    @MainActor
    func testCountSeparatesNormalAndPrivateTabs() throws {
        let manager = try makeManager()
        _ = try manager.createTab(select: false)
        _ = try manager.createTab(isPrivate: true, select: false)
        _ = try manager.createTab(isPrivate: true, select: false)

        XCTAssertEqual(manager.count, 4)
        XCTAssertEqual(manager.normalTabCount, 2)
        XCTAssertEqual(manager.privateTabCount, 2)
    }

    @MainActor
    func testSelectedTabMetadataKeepsCurrentAddressInSync() throws {
        let manager = try makeManager()
        let tabID = try XCTUnwrap(manager.selectedTabID)
        let address = try XCTUnwrap(URL(string: "https://example.com/current"))

        manager.updateTab(id: tabID, title: "当前页面", url: address)

        XCTAssertEqual(manager.selectedTab?.url, address)
        XCTAssertEqual(manager.selectedTab?.title, "当前页面")
    }

    @MainActor
    func testSwitchingTabsPreservesIndependentAddresses() throws {
        let manager = try makeManager()
        let first = try XCTUnwrap(manager.selectedTab)
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        manager.updateTab(id: first.id, title: "第一页", url: firstURL)

        let second = try manager.createTab()
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        manager.updateTab(id: second.id, title: "第二页", url: secondURL)

        _ = manager.selectTab(id: first.id)
        XCTAssertEqual(manager.selectedTab?.url, firstURL)
        XCTAssertEqual(manager.selectedTab?.title, "第一页")

        _ = manager.selectTab(id: second.id)
        XCTAssertEqual(manager.selectedTab?.url, secondURL)
        XCTAssertEqual(manager.selectedTab?.title, "第二页")
    }

    @MainActor
    func testTabCountPublishesAfterCreationAndClosure() throws {
        let manager = try makeManager()
        var publishedCounts: [Int] = []
        manager.onTabsChanged = {
            publishedCounts.append(manager.count)
        }

        let second = try manager.createTab(select: false)
        manager.closeTab(id: second.id)

        XCTAssertEqual(publishedCounts, [2, 1])
    }

    @MainActor
    func testMemoryPressureSuspendsOnlyInactiveTabsAndKeepsSnapshots() async throws {
        let snapshotService = SnapshotServiceStub()
        let manager = try makeManager(snapshotService: snapshotService)
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab()
        let third = try manager.createTab()

        await manager.handleMemoryPressure()

        XCTAssertNil(first.webView)
        XCTAssertNil(second.webView)
        XCTAssertNotNil(third.webView)
        XCTAssertEqual(first.lifecycleState, .suspended)
        XCTAssertEqual(second.lifecycleState, .suspended)
        XCTAssertEqual(third.lifecycleState, .active)
        XCTAssertNotNil(first.snapshot)
        XCTAssertNotNil(second.snapshot)
        XCTAssertNil(third.snapshot)
        XCTAssertEqual(Set(snapshotService.capturedIDs), Set([first.id, second.id]))
    }

    @MainActor
    func testResidentWebViewLimitSuspendsLeastRecentlyUsedInactiveTab() async throws {
        let snapshotService = SnapshotServiceStub()
        let manager = try makeManager(
            snapshotService: snapshotService,
            maximumResidentWebViewCount: 2
        )
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab()
        let third = try manager.createTab()
        manager.updateTab(
            id: first.id,
            title: nil,
            url: nil,
            visitedAt: Date(timeIntervalSince1970: 1)
        )
        manager.updateTab(
            id: second.id,
            title: nil,
            url: nil,
            visitedAt: Date(timeIntervalSince1970: 2)
        )
        manager.updateTab(
            id: third.id,
            title: nil,
            url: nil,
            visitedAt: Date(timeIntervalSince1970: 3)
        )

        let suspendedIDs = await manager.enforceResidentWebViewLimit()

        XCTAssertEqual(suspendedIDs, [first.id])
        XCTAssertEqual(manager.residentWebViewCount, 2)
        XCTAssertNil(first.webView)
        XCTAssertNotNil(second.webView)
        XCTAssertNotNil(third.webView)
        XCTAssertEqual(manager.selectedTabID, third.id)
    }

    @MainActor
    func testProactiveSnapshotDoesNotSuspendTab() async throws {
        let snapshotService = SnapshotServiceStub()
        let manager = try makeManager(snapshotService: snapshotService)
        let tab = try XCTUnwrap(manager.selectedTab)

        let snapshot = await manager.captureSnapshot(for: tab.id)

        XCTAssertNotNil(snapshot)
        XCTAssertNotNil(tab.snapshot)
        XCTAssertNotNil(tab.webView)
        XCTAssertEqual(tab.lifecycleState, .active)
        XCTAssertEqual(snapshotService.capturedIDs, [tab.id])
    }

    @MainActor
    func testCloseAllTabsRemovesNormalTabsAndKeepsPrivateTabs() throws {
        let manager = try makeManager()
        let normalTab = try XCTUnwrap(manager.selectedTab)
        let privateTab = try manager.createTab(isPrivate: true, select: false)
        _ = try manager.createTab(select: false)

        XCTAssertEqual(manager.count, 3)
        XCTAssertEqual(manager.normalTabCount, 2)
        XCTAssertEqual(manager.privateTabCount, 1)

        manager.closeAllTabs(isPrivate: false)

        // A new normal tab is auto-created since all normal tabs were closed
        XCTAssertEqual(manager.normalTabCount, 1)
        XCTAssertEqual(manager.privateTabCount, 1)
        XCTAssertEqual(manager.count, 2)
        XCTAssertFalse(try XCTUnwrap(manager.selectedTab).isPrivate)
    }

    @MainActor
    func testCloseAllTabsRemovesPrivateTabsAndKeepsNormalTabs() throws {
        let manager = try makeManager()
        let normalTab = try XCTUnwrap(manager.selectedTab)
        _ = try manager.createTab(isPrivate: true, select: false)
        _ = try manager.createTab(isPrivate: true, select: false)

        XCTAssertEqual(manager.count, 3)
        XCTAssertEqual(manager.privateTabCount, 2)

        manager.closeAllTabs(isPrivate: true)

        XCTAssertEqual(manager.privateTabCount, 0)
        XCTAssertEqual(manager.normalTabCount, 1)
        XCTAssertEqual(manager.count, 1)
    }

    @MainActor
    func testCloseAllTabsWhenLastNormalTabClosesCreatesNewNormalTab() throws {
        let manager = try makeManager()

        manager.closeAllTabs(isPrivate: false)

        XCTAssertEqual(manager.count, 1)
        XCTAssertFalse(try XCTUnwrap(manager.selectedTab).isPrivate)
    }

    @MainActor
    func testCloseAllTabsUpdatesSelectionWhenSelectedTabIsClosed() throws {
        let manager = try makeManager()
        let privateTab = try manager.createTab(isPrivate: true, select: false)
        let normalTab = try XCTUnwrap(manager.selectedTab)

        XCTAssertEqual(manager.selectedTabID, normalTab.id)

        manager.closeAllTabs(isPrivate: false)

        // A new normal tab is created since all normal tabs were closed
        XCTAssertEqual(manager.count, 2)
        XCTAssertEqual(manager.privateTabCount, 1)
        XCTAssertEqual(manager.normalTabCount, 1)
        // Selection should be on the new normal tab
        XCTAssertFalse(try XCTUnwrap(manager.selectedTab).isPrivate)
    }

    @MainActor
    func testSuspendTabRejectsCurrentTabAndSuspendsInactiveTab() async throws {
        let snapshotService = SnapshotServiceStub()
        let manager = try makeManager(snapshotService: snapshotService)
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try manager.createTab()

        let didSuspendCurrentTab = await manager.suspendTab(id: second.id)
        let didSuspendInactiveTab = await manager.suspendTab(id: first.id)

        XCTAssertFalse(didSuspendCurrentTab)
        XCTAssertTrue(didSuspendInactiveTab)
        XCTAssertNil(first.webView)
        XCTAssertNotNil(first.snapshot)
        XCTAssertNotNil(second.webView)
    }

    @MainActor
    private func makeManager(
        snapshotService: TabSnapshotProviding? = nil,
        maximumResidentWebViewCount: Int =
            BrowserTabManager.defaultMaximumResidentWebViewCount
    ) throws -> BrowserTabManager {
        let defaults = try XCTUnwrap(defaults)
        return BrowserTabManager(
            maximumResidentWebViewCount: maximumResidentWebViewCount,
            sessionStore: BrowserTabSessionStore(
                defaults: defaults,
                storageKey: storageKey
            ),
            snapshotService: snapshotService ?? SnapshotServiceStub()
        )
    }
}

@MainActor
private final class SnapshotServiceStub: TabSnapshotProviding {
    private(set) var capturedIDs: [UUID] = []

    func captureAndStore(tab: BrowserTab) async -> UIImage? {
        capturedIDs.append(tab.id)
        return UIImage()
    }

    func loadSnapshot(for tabID: UUID) async -> UIImage? {
        nil
    }

    func removeSnapshot(for tabID: UUID) {}
}
