import Foundation
import WebKit

private enum ProcessedResourceMessage: Sendable {
    case valid(
        ResourceMessageBatch,
        [DetectedResource],
        tabID: UUID,
        isPrivate: Bool
    )
    case invalid
}

@MainActor
final class WebResourceSniffingService: ResourceSniffingService {
    private final class WeakWebView {
        weak var value: WKWebView?

        init(_ value: WKWebView) {
            self.value = value
        }
    }

    private struct TabContext {
        let webView: WeakWebView
        let isPrivate: Bool
        var expectedPageURL: URL?
    }

    private struct PendingScan {
        let tabID: UUID
        let continuation: CheckedContinuation<[DetectedResource], Error>
    }

    let store: TabResourceStore

    private var contexts: [UUID: TabContext] = [:]
    private var pendingScans: [UUID: PendingScan] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var nextMessageSequence = 0
    private var nextSequenceToApply = 0
    private var processedMessages: [Int: ProcessedResourceMessage] = [:]
    private let logger = AppLogger(.sniffer)
    private let decoder = ResourceMessageDecoder()
    private let resolver = ResourceMetadataResolver()

    init(store: TabResourceStore) {
        self.store = store
    }

    func register(tabID: UUID, webView: WKWebView, isPrivate: Bool) {
        contexts[tabID] = TabContext(
            webView: WeakWebView(webView),
            isPrivate: isPrivate,
            expectedPageURL: webView.url
        )
        store.prepare(tabID: tabID, isPrivate: isPrivate)
    }

    func unregister(tabID: UUID) {
        contexts[tabID] = nil
    }

    func tabClosed(tabID: UUID) {
        if let webView = contexts[tabID]?.webView.value {
            webView.evaluateJavaScript(
                "(() => window.\(ResourceSniffingScriptProvider.bridgeName)?.dispose?.() === true)();"
            )
        }
        unregister(tabID: tabID)
        ResourceThumbnailLoader.shared.cancelRequests(for: tabID)
        let scans = pendingScans.filter { $0.value.tabID == tabID }.map(\.key)
        scans.forEach {
            finishPendingScan(
                scanID: $0,
                result: .failure(ResourceSniffingError.tabUnavailable)
            )
        }
        store.remove(tabID: tabID)
    }

    func beginNavigation(
        tabID: UUID,
        pageURL: URL?,
        isPrivate: Bool
    ) {
        contexts[tabID]?.expectedPageURL = pageURL
        store.beginNavigation(
            tabID: tabID,
            pageURL: pageURL,
            isPrivate: isPrivate
        )
        logger.debug("主文档导航 host=\(pageURL?.host ?? "unknown")")
    }

    func activationState(for tabID: UUID) -> SniffingActivationState {
        store.activationState(for: tabID)
    }

    func enableSniffing(for tabID: UUID) async throws {
        guard contexts[tabID] != nil else {
            throw ResourceSniffingError.tabUnavailable
        }
        guard let webView = contexts[tabID]?.webView.value else {
            throw ResourceSniffingError.webViewUnavailable
        }
        if store.activationState(for: tabID) == .active {
            return
        }

        store.beginActivation(tabID: tabID)
        do {
            let enabled = try await evaluateBoolean(
                ResourceSniffingScriptProvider.enableInvocation,
                in: webView
            )
            guard enabled else {
                throw ResourceSniffingError.scriptUnavailable
            }
            _ = try await scanResources(for: tabID)
            store.completeActivation(tabID: tabID)
        } catch {
            store.failActivation(
                tabID: tabID,
                message: error.localizedDescription
            )
            throw error
        }
    }

    func disableSniffing(for tabID: UUID) async {
        guard store.activationState(for: tabID) != .disabled else { return }
        store.beginStopping(tabID: tabID)
        if let webView = contexts[tabID]?.webView.value {
            _ = try? await evaluateBoolean(
                ResourceSniffingScriptProvider.disableInvocation,
                in: webView
            )
        }
        let scans = pendingScans.filter { $0.value.tabID == tabID }.map(\.key)
        scans.forEach {
            finishPendingScan(scanID: $0, result: .failure(CancellationError()))
        }
        store.completeStopping(tabID: tabID)
    }

    func restoreActiveSniffingAfterNavigation(tabID: UUID) {
        guard store.activationState(for: tabID).isEnabled,
              let webView = contexts[tabID]?.webView.value
        else { return }
        webView.evaluateJavaScript(
            ResourceSniffingScriptProvider.enableAndIncrementalScanInvocation(
                reason: "navigation"
            )
        ) { [weak self] value, error in
            guard error != nil || (value as? Bool) != true else { return }
            Task { @MainActor [weak self] in
                self?.store.failActivation(
                    tabID: tabID,
                    message: ResourceSniffingError.scriptUnavailable
                        .localizedDescription
                )
            }
        }
    }

    func requestIncrementalScan(tabID: UUID, reason: String) {
        guard store.activationState(for: tabID).isEnabled else { return }
        guard let webView = contexts[tabID]?.webView.value else { return }
        store.beginScan(tabID: tabID, scanID: nil, isManual: false)
        webView.evaluateJavaScript(
            ResourceSniffingScriptProvider.incrementalScanInvocation(
                reason: reason
            )
        ) { [weak self] result, error in
            guard error != nil || (result as? Bool) == false else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.error("增量扫描脚本不可用")
                self.store.failScan(
                    tabID: tabID,
                    scanID: nil,
                    message: ResourceSniffingError.scriptUnavailable
                        .localizedDescription
                )
            }
        }
    }

    func captureNavigationResponse(
        tabID: UUID,
        response: URLResponse,
        pageTitle: String?
    ) {
        guard store.activationState(for: tabID).isEnabled else { return }
        guard let url = response.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return
        }
        let candidate = ResourceCandidate(
            originalURLString: url.absoluteString,
            pageURLString: contexts[tabID]?.webView.value?.url?.absoluteString,
            pageTitle: pageTitle,
            mimeType: response.mimeType,
            estimatedSize: response.expectedContentLength > 0
                ? response.expectedContentLength
                : nil,
            duration: nil,
            width: nil,
            height: nil,
            bitrate: nil,
            thumbnailURLString: nil,
            detectionSource: .navigationResponse,
            elementType: nil,
            headersHint: response.mimeType.map {
                ["content-type": $0]
            } ?? [:]
        )
        let resources = resolver.resolve(candidates: [candidate], tabID: tabID)
        store.upsert(resources, tabID: tabID)
    }

    func handleMessageBody(_ body: Any, tabID: UUID, isPrivate: Bool) {
        guard store.activationState(for: tabID).isEnabled else { return }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              data.count <= 2_000_000
        else {
            logger.error("拒绝无效或过大的资源消息")
            return
        }

        let decoder = decoder
        let resolver = resolver
        let sequence = nextMessageSequence
        nextMessageSequence += 1
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                () -> ProcessedResourceMessage in
                do {
                    let batch = try decoder.decode(data)
                    let resources = resolver.resolve(
                        candidates: batch.candidates,
                        tabID: tabID
                    )
                    return .valid(
                        batch,
                        resources,
                        tabID: tabID,
                        isPrivate: isPrivate
                    )
                } catch {
                    return .invalid
                }
            }.value

            guard let self else { return }
            self.processedMessages[sequence] = result
            self.drainProcessedMessages()
        }
    }

    func scanResources(for tabID: UUID) async throws -> [DetectedResource] {
        guard contexts[tabID] != nil else {
            throw ResourceSniffingError.tabUnavailable
        }
        guard let webView = contexts[tabID]?.webView.value else {
            throw ResourceSniffingError.webViewUnavailable
        }
        guard store.activationState(for: tabID).isEnabled else {
            throw ResourceSniffingError.scriptUnavailable
        }

        let previousScanIDs = pendingScans
            .filter { $0.value.tabID == tabID }
            .map(\.key)
        previousScanIDs.forEach {
            finishPendingScan(
                scanID: $0,
                result: .failure(CancellationError())
            )
        }

        let scanID = UUID()
        store.beginScan(tabID: tabID, scanID: scanID, isManual: true)
        logger.debug("手动扫描开始 tab=\(tabID.uuidString.prefix(8))")

        return try await withCheckedThrowingContinuation { continuation in
            pendingScans[scanID] = PendingScan(
                tabID: tabID,
                continuation: continuation
            )
            timeoutTasks[scanID] = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(6))
                } catch {
                    return
                }
                guard let self, self.pendingScans[scanID] != nil else { return }
                self.store.failScan(
                    tabID: tabID,
                    scanID: scanID,
                    message: ResourceSniffingError.scanTimedOut.localizedDescription
                )
                self.finishPendingScan(
                    scanID: scanID,
                    result: .failure(ResourceSniffingError.scanTimedOut)
                )
            }
            webView.evaluateJavaScript(
                ResourceSniffingScriptProvider.manualScanInvocation(
                    scanID: scanID
                )
            ) { [weak self] value, error in
                guard error != nil || (value as? Bool) != true else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.store.failScan(
                        tabID: tabID,
                        scanID: scanID,
                        message: ResourceSniffingError.scriptUnavailable
                            .localizedDescription
                    )
                    self.finishPendingScan(
                        scanID: scanID,
                        result: .failure(
                            error == nil
                                ? ResourceSniffingError.scriptUnavailable
                                : ResourceSniffingError.scriptFailure
                        )
                    )
                }
            }
        }
    }

    func resources(for tabID: UUID) -> [DetectedResource] {
        store.resources(for: tabID)
    }

    func resetResources(for tabID: UUID) {
        store.reset(tabID: tabID)
    }

    private func apply(
        batch: ResourceMessageBatch,
        resources: [DetectedResource],
        tabID: UUID,
        isPrivate: Bool
    ) {
        guard store.activationState(for: tabID).isEnabled else { return }
        guard messageBelongsToCurrentPage(batch, tabID: tabID) else {
            return
        }
        let pageURL = batch.pageURLString.flatMap(URL.init(string:))
        if let context = contexts[tabID],
           context.webView.value?.isLoading != true {
            let resolvedPageURL = context.webView.value?.url ?? pageURL
            contexts[tabID]?.expectedPageURL = resolvedPageURL
        }
        store.reconcilePageIfNeeded(
            tabID: tabID,
            pageURL: pageURL,
            isPrivate: isPrivate
        )

        switch batch.kind {
        case .scriptReady:
            break
        case .batch:
            store.upsert(resources, tabID: tabID)
        case .scanComplete:
            let isManual = batch.scanID != nil
            store.completeScan(
                tabID: tabID,
                scanID: batch.scanID,
                isManual: isManual
            )
            logger.debug(
                "扫描完成 count=\(store.resources(for: tabID).count)"
            )
            if let scanID = batch.scanID {
                finishPendingScan(
                    scanID: scanID,
                    result: .success(store.resources(for: tabID))
                )
            }
        case .scanFailed:
            let message = ResourceSniffingError.scriptFailure.localizedDescription
            store.failScan(
                tabID: tabID,
                scanID: batch.scanID,
                message: message
            )
            if let scanID = batch.scanID {
                finishPendingScan(
                    scanID: scanID,
                    result: .failure(ResourceSniffingError.scriptFailure)
                )
            }
        }
    }

    private func messageBelongsToCurrentPage(
        _ batch: ResourceMessageBatch,
        tabID: UUID
    ) -> Bool {
        guard let messageURL = batch.pageURLString.flatMap(URL.init(string:)),
              let context = contexts[tabID]
        else {
            return true
        }
        let currentURL: URL?
        if context.webView.value?.isLoading == true {
            currentURL = context.expectedPageURL
        } else {
            currentURL = context.webView.value?.url ?? context.expectedPageURL
        }
        guard let currentURL else { return true }
        return pageIdentity(messageURL) == pageIdentity(currentURL)
    }

    private func pageIdentity(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.fragment = nil
        components.host = components.host?.lowercased()
        return components.string ?? url.absoluteString
    }

    private func drainProcessedMessages() {
        while let result = processedMessages.removeValue(
            forKey: nextSequenceToApply
        ) {
            nextSequenceToApply += 1
            switch result {
            case let .valid(batch, resources, tabID, isPrivate):
                apply(
                    batch: batch,
                    resources: resources,
                    tabID: tabID,
                    isPrivate: isPrivate
                )
            case .invalid:
                logger.error("资源消息解码失败")
            }
        }
    }

    private func finishPendingScan(
        scanID: UUID,
        result: Result<[DetectedResource], Error>
    ) {
        guard let pending = pendingScans.removeValue(forKey: scanID) else {
            return
        }
        timeoutTasks.removeValue(forKey: scanID)?.cancel()
        pending.continuation.resume(with: result)
    }

    private func evaluateBoolean(
        _ script: String,
        in webView: WKWebView
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? Bool == true)
                }
            }
        }
    }
}
