import Foundation
import XCTest
@testable import SniffBrowser

final class SniffingActivationTests: XCTestCase {
    @MainActor
    func testNewTabStartsDisabledAndRejectsReports() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        store.prepare(tabID: tabID, isPrivate: false)

        store.upsert([try resource(tabID: tabID)], tabID: tabID)

        XCTAssertEqual(store.activationState(for: tabID), .disabled)
        XCTAssertTrue(store.resources(for: tabID).isEmpty)
    }

    @MainActor
    func testActivationIsPerTabAndKeepsExistingResultsWhenStopped() throws {
        let store = TabResourceStore()
        let activeID = UUID()
        let disabledID = UUID()
        store.prepare(tabID: activeID, isPrivate: false)
        store.prepare(tabID: disabledID, isPrivate: false)

        store.beginActivation(tabID: activeID)
        store.completeActivation(tabID: activeID)
        store.upsert([try resource(tabID: activeID)], tabID: activeID)
        store.beginStopping(tabID: activeID)
        store.completeStopping(tabID: activeID)
        store.upsert([try resource(tabID: activeID, name: "ignored.mp4")], tabID: activeID)

        XCTAssertEqual(store.activationState(for: activeID), .disabled)
        XCTAssertEqual(store.resources(for: activeID).map(\.fileName), ["movie.mp4"])
        XCTAssertEqual(store.activationState(for: disabledID), .disabled)
    }

    @MainActor
    func testNavigationDoesNotEnableDisabledTab() {
        let store = TabResourceStore()
        let tabID = UUID()
        store.prepare(tabID: tabID, isPrivate: false)

        store.beginNavigation(
            tabID: tabID,
            pageURL: URL(string: "https://example.com/next"),
            isPrivate: false
        )

        XCTAssertEqual(store.activationState(for: tabID), .disabled)
        XCTAssertEqual(store.snapshot(for: tabID).scanState, .idle)
    }

    @MainActor
    func testNavigationEndsThePreviousPageActivation() throws {
        let store = TabResourceStore()
        let tabID = UUID()
        store.prepare(tabID: tabID, isPrivate: false)
        store.beginActivation(tabID: tabID)
        store.completeActivation(tabID: tabID)
        store.upsert([try resource(tabID: tabID)], tabID: tabID)

        store.beginNavigation(
            tabID: tabID,
            pageURL: URL(string: "https://example.com/next"),
            isPrivate: false
        )

        let snapshot = store.snapshot(for: tabID)
        XCTAssertEqual(snapshot.activationState, .disabled)
        XCTAssertFalse(snapshot.hasStarted)
        XCTAssertTrue(snapshot.resources.isEmpty)
        XCTAssertEqual(snapshot.scanState, .idle)
    }

    @MainActor
    func testRestoredBrowserTabDoesNotRestoreSniffingState() {
        let tab = BrowserTab(
            title: "Example",
            url: URL(string: "https://example.com"),
            createsWebView: false
        )

        XCTAssertFalse(tab.isSniffingEnabled)
        XCTAssertEqual(tab.sniffingState, .disabled)
        XCTAssertEqual(tab.detectedResourceCount, 0)
    }

    private func resource(tabID: UUID, name: String = "movie.mp4") throws -> DetectedResource {
        let url = try XCTUnwrap(URL(string: "https://example.com/\(name)"))
        return DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            fileName: name,
            fileExtension: "mp4",
            resourceType: .video,
            detectionSource: .dom,
            tabID: tabID
        )
    }
}
