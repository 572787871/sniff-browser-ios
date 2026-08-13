import Foundation
import XCTest
@testable import SniffBrowser

final class TabResourceStoreTests: XCTestCase {
    @MainActor
    func testResourcesRemainIsolatedBetweenNormalTabs() throws {
        let store = TabResourceStore()
        let firstID = UUID()
        let secondID = UUID()
        store.prepare(tabID: firstID, isPrivate: false)
        store.prepare(tabID: secondID, isPrivate: false)
        activate(store, tabID: firstID)
        activate(store, tabID: secondID)
        store.upsert([try resource(tabID: firstID, name: "first.mp4")], tabID: firstID)

        XCTAssertEqual(store.resources(for: firstID).count, 1)
        XCTAssertTrue(store.resources(for: secondID).isEmpty)
    }

    @MainActor
    func testPrivateResourcesAreIsolatedAndRemovedWithTab() throws {
        let store = TabResourceStore()
        let firstID = UUID()
        let secondID = UUID()
        store.prepare(tabID: firstID, isPrivate: true)
        store.prepare(tabID: secondID, isPrivate: true)
        activate(store, tabID: firstID)
        activate(store, tabID: secondID)
        store.upsert([try resource(tabID: firstID, name: "private.mp4")], tabID: firstID)

        store.remove(tabID: firstID)

        XCTAssertTrue(store.resources(for: firstID).isEmpty)
        XCTAssertTrue(store.resources(for: secondID).isEmpty)
    }

    @MainActor
    func testNavigationClearsOldPageResourcesAndCount() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        store.prepare(tabID: tabID, isPrivate: false)
        activate(store, tabID: tabID)
        store.upsert([try resource(tabID: tabID, name: "old.mp4")], tabID: tabID)

        store.beginNavigation(
            tabID: tabID,
            pageURL: try XCTUnwrap(URL(string: "https://example.com/new")),
            isPrivate: false
        )

        XCTAssertTrue(store.resources(for: tabID).isEmpty)
        XCTAssertEqual(store.snapshot(for: tabID).scanState, .idle)
    }

    @MainActor
    func testSamePageProcessReloadPreservesResultsWithoutRestartingSniffing() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        let pageURL = try XCTUnwrap(
            URL(string: "https://example.com/watch?id=42#player")
        )
        store.beginNavigation(
            tabID: tabID,
            pageURL: pageURL,
            isPrivate: false
        )
        activate(store, tabID: tabID)
        store.upsert(
            [try resource(tabID: tabID, name: "kept.m3u8")],
            tabID: tabID
        )

        store.beginNavigation(
            tabID: tabID,
            pageURL: try XCTUnwrap(
                URL(string: "https://example.com/watch?id=42")
            ),
            isPrivate: false
        )

        let snapshot = store.snapshot(for: tabID)
        XCTAssertEqual(snapshot.resources.map(\.fileName), ["kept.m3u8"])
        XCTAssertTrue(snapshot.hasStarted)
        XCTAssertEqual(snapshot.activationState, .disabled)
    }

    @MainActor
    func testHLSMetadataResolutionClaimPersistsUntilRefreshOrNewPage() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        let playlistURL = try XCTUnwrap(
            URL(string: "https://cdn.example.com/main.m3u8")
        )
        let firstPage = try XCTUnwrap(URL(string: "https://example.com/first"))
        store.beginNavigation(
            tabID: tabID,
            pageURL: firstPage,
            isPrivate: false
        )

        XCTAssertTrue(store.claimHLSMetadataResolution(
            tabID: tabID,
            url: playlistURL
        ))
        XCTAssertFalse(store.claimHLSMetadataResolution(
            tabID: tabID,
            url: playlistURL
        ))

        store.resetHLSMetadataResolutionClaims(tabID: tabID)
        XCTAssertTrue(store.claimHLSMetadataResolution(
            tabID: tabID,
            url: playlistURL
        ))

        store.beginNavigation(
            tabID: tabID,
            pageURL: try XCTUnwrap(URL(string: "https://example.com/second")),
            isPrivate: false
        )
        XCTAssertTrue(store.claimHLSMetadataResolution(
            tabID: tabID,
            url: playlistURL
        ))
    }

    @MainActor
    func testDuplicateSourcesMergeInsteadOfIncreasingCount() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        let first = try resource(
            tabID: tabID,
            name: "same.mp4",
            source: .performance
        )
        let second = DetectedResource(
            canonicalURL: first.canonicalURL,
            originalURLString: first.originalURLString,
            fileName: first.fileName,
            fileExtension: "mp4",
            mimeType: "video/mp4",
            resourceType: .video,
            estimatedSize: 8_192,
            detectionSource: .fetch,
            tabID: tabID
        )

        activate(store, tabID: tabID)
        store.upsert([first, second], tabID: tabID)

        XCTAssertEqual(store.resources(for: tabID).count, 1)
        XCTAssertEqual(store.resources(for: tabID).first?.estimatedSize, 8_192)
        XCTAssertEqual(store.resources(for: tabID).first?.mimeType, "video/mp4")
    }

    @MainActor
    func testManualScanRemovesResourcesNotSeenAgain() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        let stale = try resource(tabID: tabID, name: "stale.mp4")
        let current = try resource(tabID: tabID, name: "current.mp4")
        activate(store, tabID: tabID)
        store.upsert([stale, current], tabID: tabID)
        let scanID = UUID()

        store.beginScan(tabID: tabID, scanID: scanID, isManual: true)
        store.upsert([current], tabID: tabID)
        store.completeScan(tabID: tabID, scanID: scanID, isManual: true)

        XCTAssertEqual(store.resources(for: tabID).map(\.fileName), ["current.mp4"])
    }

    @MainActor
    func testObserverReceivesRealCountUpdates() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        var counts: [Int] = []
        let token = store.observe(tabID: tabID) {
            counts.append($0.resources.count)
        }
        activate(store, tabID: tabID)
        store.upsert([try resource(tabID: tabID, name: "one.mp4")], tabID: tabID)
        store.removeObserver(token)

        XCTAssertEqual(counts.last, 1)
        XCTAssertTrue(counts.contains(0))
    }

    @MainActor
    func testAutomaticRescanDoesNotPublishTransientScanningState() {
        let store = TabResourceStore()
        let tabID = UUID()
        activate(store, tabID: tabID)
        store.completeScan(tabID: tabID, scanID: nil, isManual: false)
        var states: [ResourceScanState] = []
        let token = store.observe(tabID: tabID) {
            states.append($0.scanState)
        }

        store.beginScan(tabID: tabID, scanID: nil, isManual: false)
        store.completeScan(tabID: tabID, scanID: nil, isManual: false)
        store.removeObserver(token)

        XCTAssertEqual(states, [.completed])
    }

    @MainActor
    func testConfiguredHLSAppearsBeforeHigherResolutionPerformancePlaylist() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        activate(store, tabID: tabID)
        let advertisementURL = try XCTUnwrap(
            URL(string: "https://cdn.example.com/ad.m3u8?auth_key=first")
        )
        let mainURL = try XCTUnwrap(
            URL(string: "https://cdn.example.com/main.m3u8?auth_key=second")
        )
        let advertisement = DetectedResource(
            canonicalURL: advertisementURL,
            originalURLString: advertisementURL.absoluteString,
            fileName: "ad.m3u8",
            fileExtension: "m3u8",
            resourceType: .hls,
            width: 3840,
            height: 2160,
            detectionSource: .performance,
            tabID: tabID
        )
        let main = DetectedResource(
            canonicalURL: mainURL,
            originalURLString: mainURL.absoluteString,
            fileName: "main.m3u8",
            fileExtension: "m3u8",
            resourceType: .hls,
            width: 1280,
            height: 720,
            detectionSource: .mediaEvent,
            tabID: tabID
        )

        store.upsert([advertisement, main], tabID: tabID)

        XCTAssertEqual(store.resources(for: tabID).first?.canonicalURL, mainURL)
    }

    private func resource(
        tabID: UUID,
        name: String,
        source: DetectionSource = .dom
    ) throws -> DetectedResource {
        let url = try XCTUnwrap(URL(string: "https://example.com/\(name)"))
        return DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            fileName: name,
            fileExtension: "mp4",
            resourceType: .video,
            detectionSource: source,
            tabID: tabID
        )
    }

    @MainActor
    private func activate(_ store: TabResourceStore, tabID: UUID) {
        store.beginActivation(tabID: tabID)
        store.completeActivation(tabID: tabID)
    }
}
