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
        store.upsert([try resource(tabID: tabID, name: "old.mp4")], tabID: tabID)

        store.beginNavigation(
            tabID: tabID,
            pageURL: try XCTUnwrap(URL(string: "https://example.com/new")),
            isPrivate: false
        )

        XCTAssertTrue(store.resources(for: tabID).isEmpty)
        XCTAssertEqual(store.snapshot(for: tabID).scanState, .installing)
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
        store.upsert([try resource(tabID: tabID, name: "one.mp4")], tabID: tabID)
        store.removeObserver(token)

        XCTAssertEqual(counts, [0, 1])
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
}
