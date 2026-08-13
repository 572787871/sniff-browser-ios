import Foundation

@MainActor
final class TabResourceStore {
    typealias Observer = @MainActor (TabResourceSnapshot) -> Void
    private static let maximumResourcesPerTab = 500

    private struct Bucket {
        var pageKey: String?
        var isPrivate = false
        var resourcesByURL: [String: DetectedResource] = [:]
        var scanState: ResourceScanState = .idle
        var lastScanAt: Date?
        var errorMessage: String?
        var manualScanID: UUID?
        var manualSeenKeys: Set<String> = []
        var activationState: SniffingActivationState = .disabled
        var hasStarted = false
    }

    private struct Observation {
        let tabID: UUID
        let callback: Observer
    }

    private var buckets: [UUID: Bucket] = [:]
    private var observations: [UUID: Observation] = [:]
    private let deduplicator = ResourceDeduplicator()

    func prepare(tabID: UUID, isPrivate: Bool) {
        if buckets[tabID] == nil {
            buckets[tabID] = Bucket(isPrivate: isPrivate)
        } else {
            buckets[tabID]?.isPrivate = isPrivate
        }
    }

    func beginNavigation(
        tabID: UUID,
        pageURL: URL?,
        isPrivate: Bool
    ) {
        var bucket = buckets[tabID] ?? Bucket()
        bucket.pageKey = pageKey(for: pageURL)
        bucket.isPrivate = isPrivate
        bucket.resourcesByURL.removeAll(keepingCapacity: true)
        // Activation is scoped to the current document. A navigation must not
        // inherit the previous page's listener or make the next page look as if
        // it was already scanned.
        bucket.activationState = .disabled
        bucket.scanState = .idle
        bucket.lastScanAt = nil
        bucket.errorMessage = nil
        bucket.manualScanID = nil
        bucket.manualSeenKeys.removeAll()
        bucket.hasStarted = false
        buckets[tabID] = bucket
        notify(tabID)
    }

    func beginActivation(tabID: UUID) {
        var bucket = buckets[tabID] ?? Bucket()
        bucket.activationState = .starting
        bucket.scanState = .installing
        bucket.errorMessage = nil
        bucket.hasStarted = true
        buckets[tabID] = bucket
        notify(tabID)
    }

    func completeActivation(tabID: UUID) {
        guard var bucket = buckets[tabID] else { return }
        bucket.activationState = .active
        buckets[tabID] = bucket
        notify(tabID)
    }

    func beginStopping(tabID: UUID) {
        guard var bucket = buckets[tabID] else { return }
        bucket.activationState = .stopping
        buckets[tabID] = bucket
        notify(tabID)
    }

    func completeStopping(tabID: UUID) {
        guard var bucket = buckets[tabID] else { return }
        bucket.activationState = .disabled
        bucket.scanState = .idle
        bucket.errorMessage = nil
        bucket.manualScanID = nil
        bucket.manualSeenKeys.removeAll(keepingCapacity: true)
        buckets[tabID] = bucket
        notify(tabID)
    }

    func failActivation(tabID: UUID, message: String) {
        var bucket = buckets[tabID] ?? Bucket()
        bucket.activationState = .failed
        bucket.scanState = .failed
        bucket.errorMessage = message
        buckets[tabID] = bucket
        notify(tabID)
    }

    func activationState(for tabID: UUID) -> SniffingActivationState {
        buckets[tabID]?.activationState ?? .disabled
    }

    func reconcilePageIfNeeded(
        tabID: UUID,
        pageURL: URL?,
        isPrivate: Bool
    ) {
        let nextPageKey = pageKey(for: pageURL)
        guard var bucket = buckets[tabID] else {
            buckets[tabID] = Bucket(
                pageKey: nextPageKey,
                isPrivate: isPrivate
            )
            return
        }
        bucket.isPrivate = isPrivate
        if let nextPageKey, let currentPageKey = bucket.pageKey,
           nextPageKey != currentPageKey {
            bucket.pageKey = nextPageKey
            bucket.resourcesByURL.removeAll(keepingCapacity: true)
            bucket.manualSeenKeys.removeAll()
            bucket.manualScanID = nil
            bucket.lastScanAt = nil
            bucket.errorMessage = nil
            bucket.activationState = .disabled
            bucket.scanState = .idle
            bucket.hasStarted = false
        } else if bucket.pageKey == nil {
            bucket.pageKey = nextPageKey
        }
        buckets[tabID] = bucket
    }

    func beginScan(tabID: UUID, scanID: UUID?, isManual: Bool) {
        var bucket = buckets[tabID] ?? Bucket()
        guard bucket.activationState.isEnabled else { return }
        bucket.errorMessage = nil
        if isManual {
            bucket.scanState = .scanning
            bucket.manualScanID = scanID
            bucket.manualSeenKeys.removeAll(keepingCapacity: true)
        }
        buckets[tabID] = bucket
        if isManual { notify(tabID) }
    }

    func upsert(_ resources: [DetectedResource], tabID: UUID) {
        guard !resources.isEmpty else { return }
        var bucket = buckets[tabID] ?? Bucket()
        guard bucket.activationState.isEnabled else { return }
        for resource in resources.prefix(ResourceMessageDecoder.maximumBatchCount) {
            let key = resource.canonicalURL.absoluteString
            if let existing = bucket.resourcesByURL[key] {
                bucket.resourcesByURL[key] = deduplicator.merge(
                    existing: existing,
                    incoming: resource
                )
            } else {
                bucket.resourcesByURL[key] = resource
            }
            if bucket.manualScanID != nil {
                bucket.manualSeenKeys.insert(key)
            }
        }
        if bucket.resourcesByURL.count > Self.maximumResourcesPerTab {
            let retained = sortedResources(in: bucket)
                .prefix(Self.maximumResourcesPerTab)
            bucket.resourcesByURL = Dictionary(
                uniqueKeysWithValues: retained.map {
                    ($0.canonicalURL.absoluteString, $0)
                }
            )
        }
        buckets[tabID] = bucket
        notify(tabID)
    }

    func completeScan(tabID: UUID, scanID: UUID?, isManual: Bool) {
        guard var bucket = buckets[tabID] else { return }
        let shouldNotify = isManual
            || bucket.scanState != .completed
            || bucket.errorMessage != nil
        if isManual {
            guard scanID == bucket.manualScanID else { return }
            bucket.resourcesByURL = bucket.resourcesByURL.filter {
                bucket.manualSeenKeys.contains($0.key)
            }
            bucket.manualScanID = nil
            bucket.manualSeenKeys.removeAll(keepingCapacity: true)
        }
        bucket.scanState = .completed
        bucket.lastScanAt = Date()
        bucket.errorMessage = nil
        buckets[tabID] = bucket
        if shouldNotify { notify(tabID) }
    }

    func failScan(tabID: UUID, scanID: UUID?, message: String) {
        guard var bucket = buckets[tabID] else { return }
        if let scanID, let activeID = bucket.manualScanID,
           scanID != activeID {
            return
        }
        bucket.scanState = .failed
        bucket.lastScanAt = Date()
        bucket.errorMessage = message
        bucket.manualScanID = nil
        bucket.manualSeenKeys.removeAll(keepingCapacity: true)
        buckets[tabID] = bucket
        notify(tabID)
    }

    func resources(for tabID: UUID) -> [DetectedResource] {
        sortedResources(in: buckets[tabID])
    }

    func snapshot(for tabID: UUID) -> TabResourceSnapshot {
        let bucket = buckets[tabID]
        return TabResourceSnapshot(
            tabID: tabID,
            resources: sortedResources(in: bucket),
            scanState: bucket?.scanState ?? .idle,
            lastScanAt: bucket?.lastScanAt,
            errorMessage: bucket?.errorMessage,
            activationState: bucket?.activationState ?? .disabled,
            hasStarted: bucket?.hasStarted ?? false
        )
    }

    func remove(tabID: UUID) {
        buckets[tabID] = nil
        observations = observations.filter { $0.value.tabID != tabID }
    }

    func removeAllPrivateTabs() {
        let privateIDs = buckets.compactMap { key, bucket in
            bucket.isPrivate ? key : nil
        }
        privateIDs.forEach(remove(tabID:))
    }

    func reset(tabID: UUID) {
        guard var bucket = buckets[tabID] else { return }
        bucket.resourcesByURL.removeAll(keepingCapacity: true)
        bucket.scanState = bucket.activationState.isEnabled ? .completed : .idle
        bucket.lastScanAt = nil
        bucket.errorMessage = nil
        bucket.manualScanID = nil
        bucket.manualSeenKeys.removeAll(keepingCapacity: true)
        buckets[tabID] = bucket
        notify(tabID)
    }

    @discardableResult
    func observe(tabID: UUID, _ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observations[token] = Observation(tabID: tabID, callback: observer)
        observer(snapshot(for: tabID))
        return token
    }

    func removeObserver(_ token: UUID?) {
        guard let token else { return }
        observations[token] = nil
    }

    private func notify(_ tabID: UUID) {
        let value = snapshot(for: tabID)
        observations.values
            .filter { $0.tabID == tabID }
            .forEach { $0.callback(value) }
    }

    private func sortedResources(in bucket: Bucket?) -> [DetectedResource] {
        guard let bucket else { return [] }
        return bucket.resourcesByURL.values.sorted { lhs, rhs in
            if lhs.resourceType.sortPriority != rhs.resourceType.sortPriority {
                return lhs.resourceType.sortPriority < rhs.resourceType.sortPriority
            }
            if lhs.resourceType == .hls, rhs.resourceType == .hls,
               lhs.detectionSource.confidence != rhs.detectionSource.confidence {
                // The configured/current player source should be visible and
                // thumbnailed before high-resolution pre/post-roll playlists.
                return lhs.detectionSource.confidence
                    > rhs.detectionSource.confidence
            }
            if (lhs.estimatedSize != nil) != (rhs.estimatedSize != nil) {
                return lhs.estimatedSize != nil
            }
            if (lhs.width != nil) != (rhs.width != nil) {
                return lhs.width != nil
            }
            if lhs.resourceType == .hls, rhs.resourceType == .hls {
                let leftHeight = lhs.height ?? 0
                let rightHeight = rhs.height ?? 0
                if leftHeight != rightHeight {
                    return leftHeight > rightHeight
                }
                let leftBitrate = lhs.bitrate ?? 0
                let rightBitrate = rhs.bitrate ?? 0
                if leftBitrate != rightBitrate {
                    return leftBitrate > rightBitrate
                }
            }
            return lhs.detectedAt > rhs.detectedAt
        }
    }

    private func pageKey(for url: URL?) -> String? {
        guard let url, var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.fragment = nil
        components.host = components.host?.lowercased()
        return components.string
    }
}
