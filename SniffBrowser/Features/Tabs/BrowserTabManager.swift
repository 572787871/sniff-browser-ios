import Foundation
import UIKit

@MainActor
final class BrowserTabManager {
    enum ManagerError: Error, Equatable {
        case maximumTabCountReached
    }

    nonisolated static let absoluteMaximumTabCount = 30
    nonisolated static let defaultMaximumResidentWebViewCount = 6

    private(set) var tabs: [BrowserTab] = []
    private(set) var selectedTabID: UUID?

    var onTabsChanged: (() -> Void)?
    var onTabClosed: ((UUID) -> Void)?

    private let maximumTabCount: Int
    private let maximumResidentWebViewCount: Int
    private let sessionStore: BrowserTabSessionStore
    private let snapshotService: TabSnapshotProviding
    private let webViewFactory: BrowserTab.WebViewFactory

    var selectedTab: BrowserTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var count: Int {
        tabs.count
    }

    var normalTabCount: Int {
        tabs.lazy.filter { !$0.isPrivate }.count
    }

    var privateTabCount: Int {
        tabs.lazy.filter(\.isPrivate).count
    }

    var residentWebViewCount: Int {
        tabs.lazy.filter { $0.webView != nil }.count
    }

    init(
        maximumTabCount: Int = BrowserTabManager.absoluteMaximumTabCount,
        maximumResidentWebViewCount: Int =
            BrowserTabManager.defaultMaximumResidentWebViewCount,
        sessionStore: BrowserTabSessionStore? = nil,
        snapshotService: TabSnapshotProviding? = nil,
        webViewFactory: @escaping BrowserTab.WebViewFactory = BrowserTab.makeWebView,
        restoresSession: Bool = true
    ) {
        self.maximumTabCount = min(
            max(1, maximumTabCount),
            BrowserTabManager.absoluteMaximumTabCount
        )
        self.maximumResidentWebViewCount = min(
            max(1, maximumResidentWebViewCount),
            self.maximumTabCount
        )
        self.sessionStore = sessionStore ?? BrowserTabSessionStore()
        self.snapshotService = snapshotService ?? TabSnapshotService()
        self.webViewFactory = webViewFactory

        let didRestoreSession = restoresSession && restoreSession()
        if !didRestoreSession {
            _ = createInitialTab()
        }
        persistSession()
    }

    @discardableResult
    func createTab(
        isPrivate: Bool = false,
        select: Bool = true
    ) throws -> BrowserTab {
        guard tabs.count < maximumTabCount else {
            throw ManagerError.maximumTabCountReached
        }

        let tab = BrowserTab(
            isPrivate: isPrivate,
            lifecycleState: select ? .active : .suspended,
            createsWebView: select,
            webViewFactory: webViewFactory
        )
        tabs.append(tab)

        if select {
            selectTabWithoutPublishing(id: tab.id)
        }
        persistAndPublish()
        return tab
    }

    @discardableResult
    func selectTab(id: UUID) -> BrowserTab? {
        guard let tab = selectTabWithoutPublishing(id: id) else { return nil }
        persistAndPublish()
        return tab
    }

    @discardableResult
    func closeTab(id: UUID) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let wasSelected = selectedTabID == id
        let closedTab = tabs.remove(at: index)
        snapshotService.removeSnapshot(for: closedTab.id)
        onTabClosed?(closedTab.id)

        var replacementNormalTab: BrowserTab?
        if !closedTab.isPrivate, !tabs.contains(where: { !$0.isPrivate }) {
            let tab = BrowserTab(
                lifecycleState: wasSelected ? .active : .suspended,
                createsWebView: wasSelected,
                webViewFactory: webViewFactory
            )
            tabs.insert(tab, at: min(index, tabs.count))
            replacementNormalTab = tab
        }

        if tabs.isEmpty {
            _ = createInitialTab()
        } else if wasSelected {
            if let replacementNormalTab {
                selectTabWithoutPublishing(id: replacementNormalTab.id)
            } else {
                let replacementIndex = min(index, tabs.count - 1)
                selectTabWithoutPublishing(id: tabs[replacementIndex].id)
            }
        }

        persistAndPublish()
        return closedTab
    }

    func updateTab(
        id: UUID,
        title: String?,
        url: URL?,
        visitedAt: Date = Date()
    ) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.update(title: title, url: url, visitedAt: visitedAt)
        persistAndPublish()
    }

    func synchronizeSelectedTabFromWebView() {
        guard let selectedTab else { return }
        selectedTab.synchronizeFromWebView()
        persistAndPublish()
    }

    /// 主动更新单个标签页的缩略图，不改变其驻留状态。
    ///
    /// BrowserViewController 可以在标签切换前调用此方法，随后再调用
    /// ``enforceResidentWebViewLimit()`` 执行可等待、可预测的 LRU 清理。
    @discardableResult
    func captureSnapshot(for id: UUID) async -> UIImage? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        let snapshot = await captureSnapshot(for: tab)
        if snapshot != nil {
            onTabsChanged?()
        }
        return snapshot
    }

    /// 为单个非当前标签页生成快照并释放 WKWebView。
    @discardableResult
    func suspendTab(id: UUID) async -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }),
              tab.id != selectedTabID,
              tab.webView != nil
        else {
            return false
        }

        let didSuspend = await captureAndSuspendIfInactive(tab)
        if didSuspend {
            persistAndPublish()
        }
        return didSuspend
    }

    /// 按最近最少使用顺序释放非当前标签页，直到常驻 WKWebView 不超过上限。
    ///
    /// 该方法不会释放当前标签页，并在每次异步快照完成后重新验证标签状态。
    @discardableResult
    func enforceResidentWebViewLimit() async -> [UUID] {
        var suspendedIDs: [UUID] = []

        while residentWebViewCount > maximumResidentWebViewCount {
            guard !Task.isCancelled,
                  let candidate = leastRecentlyUsedInactiveResidentTab()
            else {
                break
            }

            if await captureAndSuspendIfInactive(candidate) {
                suspendedIDs.append(candidate.id)
            }
        }

        if !suspendedIDs.isEmpty {
            persistAndPublish()
        }
        return suspendedIDs
    }

    func persistSession() {
        let normalTabs = tabs.filter { !$0.isPrivate }
        let selectedNormalID: UUID?
        if let selectedTab, !selectedTab.isPrivate {
            selectedNormalID = selectedTab.id
        } else {
            selectedNormalID = normalTabs.max {
                $0.lastVisitedDate < $1.lastVisitedDate
            }?.id
        }

        let records = normalTabs.map {
            BrowserTabSessionRecord(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                lastVisitedDate: $0.lastVisitedDate
            )
        }
        sessionStore.save(
            BrowserTabSession(
                selectedTabID: selectedNormalID,
                tabs: records
            )
        )
    }

    func handleMemoryPressure() async {
        let inactiveTabs = tabs.filter {
            $0.id != selectedTabID && $0.webView != nil
        }.sorted { $0.lastVisitedDate < $1.lastVisitedDate }
        var didSuspendTab = false

        for tab in inactiveTabs {
            if Task.isCancelled {
                break
            }
            if await captureAndSuspendIfInactive(tab) {
                didSuspendTab = true
            }
        }
        if didSuspendTab {
            persistAndPublish()
        }
    }

    func loadSnapshotIfAvailable(for id: UUID) async -> UIImage? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        if let snapshot = tab.snapshot {
            return snapshot
        }
        let snapshot = await snapshotService.loadSnapshot(for: id)
        tab.updateSnapshot(snapshot)
        return snapshot
    }

    private func restoreSession() -> Bool {
        guard let session = sessionStore.load(), !session.tabs.isEmpty else {
            return false
        }

        var restoredIDs = Set<UUID>()
        let records = session.tabs.prefix(maximumTabCount).filter {
            restoredIDs.insert($0.id).inserted
        }
        tabs = records.map {
            BrowserTab(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                isPrivate: false,
                lastVisitedDate: $0.lastVisitedDate,
                lifecycleState: .suspended,
                createsWebView: false,
                webViewFactory: webViewFactory
            )
        }
        guard !tabs.isEmpty else {
            return false
        }

        let selectedID: UUID?
        if let requestedID = session.selectedTabID,
           tabs.contains(where: { $0.id == requestedID }) {
            selectedID = requestedID
        } else {
            selectedID = tabs.max {
                $0.lastVisitedDate < $1.lastVisitedDate
            }?.id
        }
        if let selectedID {
            selectTabWithoutPublishing(id: selectedID)
        }
        return true
    }

    @discardableResult
    private func createInitialTab() -> BrowserTab {
        let tab = BrowserTab(
            lifecycleState: .active,
            webViewFactory: webViewFactory
        )
        tabs = [tab]
        selectedTabID = tab.id
        return tab
    }

    @discardableResult
    private func selectTabWithoutPublishing(id: UUID) -> BrowserTab? {
        guard let nextTab = tabs.first(where: { $0.id == id }) else {
            return nil
        }
        if selectedTabID != id {
            selectedTab?.deactivate()
        }
        selectedTabID = id
        nextTab.activate()
        return nextTab
    }

    private func captureSnapshot(for tab: BrowserTab) async -> UIImage? {
        let snapshot = await snapshotService.captureAndStore(tab: tab)
        guard tabs.contains(where: { $0 === tab }) else {
            snapshotService.removeSnapshot(for: tab.id)
            return nil
        }
        tab.updateSnapshot(snapshot)
        return snapshot
    }

    private func captureAndSuspendIfInactive(_ tab: BrowserTab) async -> Bool {
        guard tab.id != selectedTabID, tab.webView != nil else {
            return false
        }

        let snapshot = await captureSnapshot(for: tab)
        guard tabs.contains(where: { $0 === tab }),
              tab.id != selectedTabID,
              tab.webView != nil
        else {
            return false
        }
        tab.suspend(snapshot: snapshot)
        return true
    }

    private func leastRecentlyUsedInactiveResidentTab() -> BrowserTab? {
        tabs
            .filter { $0.id != selectedTabID && $0.webView != nil }
            .min { $0.lastVisitedDate < $1.lastVisitedDate }
    }

    private func persistAndPublish() {
        persistSession()
        onTabsChanged?()
    }
}
