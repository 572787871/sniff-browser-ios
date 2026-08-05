import Foundation
import XCTest
@testable import SniffBrowser

final class WebsitePermissionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: WebsitePermissionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "WebsitePermissionStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = WebsitePermissionStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testReturnsNilForUndecidedPermission() {
        XCTAssertNil(store.decision(for: "example.com", permission: .camera))
    }

    func testSavesAndReadsDecision() {
        store.setDecision(.allow, for: "example.com", permission: .camera)
        store.setDecision(.deny, for: "example.com", permission: .microphone)

        XCTAssertEqual(
            store.decision(for: "example.com", permission: .camera),
            .allow
        )
        XCTAssertEqual(
            store.decision(for: "example.com", permission: .microphone),
            .deny
        )
        XCTAssertNil(store.decision(for: "example.com", permission: .location))
    }

    func testUpdatingDecisionReplacesPreviousValue() {
        store.setDecision(.deny, for: "example.com", permission: .location)
        store.setDecision(.allow, for: "example.com", permission: .location)

        XCTAssertEqual(
            store.decision(for: "example.com", permission: .location),
            .allow
        )
        XCTAssertEqual(try XCTUnwrap(store.sites().first).permissions.count, 1)
    }

    func testDifferentSitesAreKeptSeparately() {
        store.setDecision(.allow, for: "example.com", permission: .camera)
        store.setDecision(.deny, for: "other.org", permission: .camera)

        XCTAssertEqual(
            store.decision(for: "example.com", permission: .camera),
            .allow
        )
        XCTAssertEqual(
            store.decision(for: "other.org", permission: .camera),
            .deny
        )
        XCTAssertEqual(store.sites().count, 2)
    }

    func testRemoveSiteClearsAllPermissionsForThatSite() {
        store.setDecision(.allow, for: "example.com", permission: .camera)
        store.setDecision(.allow, for: "other.org", permission: .camera)

        store.removeSite(host: "example.com")

        XCTAssertNil(store.decision(for: "example.com", permission: .camera))
        XCTAssertEqual(store.sites().map(\.host), ["other.org"])
    }

    func testRemoveAllClearsEverything() {
        store.setDecision(.allow, for: "example.com", permission: .camera)
        store.removeAll()

        XCTAssertTrue(store.sites().isEmpty)
    }

    func testNewStoreInstanceRestoresDecisionsFromDefaults() {
        store.setDecision(.allow, for: "example.com", permission: .location)

        let restoredStore = WebsitePermissionStore(defaults: defaults)

        XCTAssertEqual(
            restoredStore.decision(for: "example.com", permission: .location),
            .allow
        )
    }
}
