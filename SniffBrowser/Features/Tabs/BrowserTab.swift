import UIKit
import WebKit

enum BrowserTabLifecycleState: Equatable {
    case active
    case inactive
    case suspended
}

@MainActor
final class BrowserTab: Identifiable {
    typealias WebViewFactory = @MainActor (_ isPrivate: Bool) -> WKWebView

    let id: UUID
    let isPrivate: Bool

    private(set) var title: String
    private(set) var url: URL?
    private(set) var lastVisitedDate: Date
    private(set) var snapshot: UIImage?
    private(set) var lifecycleState: BrowserTabLifecycleState
    private(set) var webView: WKWebView?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var estimatedProgress = 0.0
    private(set) var isLoading = false
    private(set) var pageThemeColor: WebPageThemeColor?
    private(set) var detectedResourceCount = 0
    private(set) var lastResourceScanAt: Date?
    private(set) var resourceScanState: ResourceScanState = .idle

    private let webViewFactory: WebViewFactory

    init(
        id: UUID = UUID(),
        title: String = "新标签页",
        url: URL? = nil,
        isPrivate: Bool = false,
        lastVisitedDate: Date = Date(),
        snapshot: UIImage? = nil,
        lifecycleState: BrowserTabLifecycleState = .inactive,
        createsWebView: Bool = true,
        webViewFactory: @escaping WebViewFactory = BrowserTab.makeWebView
    ) {
        self.id = id
        self.title = title.isEmpty ? "新标签页" : title
        self.url = url
        self.isPrivate = isPrivate
        self.lastVisitedDate = lastVisitedDate
        self.snapshot = snapshot
        self.lifecycleState = lifecycleState
        self.webViewFactory = webViewFactory
        webView = createsWebView ? webViewFactory(isPrivate) : nil
    }

    func update(title: String?, url: URL?, visitedAt: Date = Date()) {
        if let title, !title.isEmpty {
            self.title = title
        }
        self.url = url
        lastVisitedDate = visitedAt
    }

    func synchronizeFromWebView(visitedAt: Date = Date()) {
        guard let webView else { return }
        update(title: webView.title, url: webView.url ?? url, visitedAt: visitedAt)
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
    }

    func activate(visitedAt: Date = Date()) {
        let wasSuspended = webView == nil
        if wasSuspended {
            webView = webViewFactory(isPrivate)
        }
        lifecycleState = .active
        lastVisitedDate = visitedAt

        synchronizeNavigationState()
    }

    func deactivate(visitedAt: Date = Date()) {
        synchronizeFromWebView(visitedAt: visitedAt)
        lifecycleState = webView == nil ? .suspended : .inactive
    }

    func suspend(snapshot: UIImage?) {
        guard lifecycleState != .active else { return }
        synchronizeFromWebView(visitedAt: lastVisitedDate)
        if let snapshot {
            self.snapshot = snapshot
        }
        webView?.stopLoading()
        webView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
        lifecycleState = .suspended
    }

    func updateSnapshot(_ snapshot: UIImage?) {
        self.snapshot = snapshot
    }

    func updatePageThemeColor(_ color: WebPageThemeColor?) {
        pageThemeColor = color
    }

    func updateResourceSummary(
        count: Int,
        scanState: ResourceScanState,
        lastScanAt: Date?
    ) {
        detectedResourceCount = max(0, count)
        resourceScanState = scanState
        lastResourceScanAt = lastScanAt
    }

    private func synchronizeNavigationState() {
        guard let webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
    }

    static func makeWebView(isPrivate: Bool) -> WKWebView {
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserConfiguration.makeWebViewConfiguration(
                isPrivate: isPrivate
            )
        )
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        return webView
    }
}
