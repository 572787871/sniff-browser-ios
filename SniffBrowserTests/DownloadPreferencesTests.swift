import XCTest
@testable import SniffBrowser

final class DownloadPreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DownloadPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testDefaultsRepresentUsableDownloadPolicy() {
        let preferences = DownloadPreferences(defaults: defaults)

        XCTAssertTrue(preferences.allowsCellularDownloads)
        XCTAssertEqual(
            preferences.maximumConcurrentDownloads,
            DownloadPreferences.defaultConcurrentDownloadCount
        )
        XCTAssertFalse(preferences.completionNotificationsEnabled)
        XCTAssertTrue(preferences.automaticRetryEnabled)
        XCTAssertFalse(preferences.state.defaultSaveLocationDescription.isEmpty)
    }

    func testSettingsPersistAcrossRepositoryInstances() {
        let preferences = DownloadPreferences(defaults: defaults)
        preferences.allowsCellularDownloads = false
        preferences.maximumConcurrentDownloads = 4
        preferences.completionNotificationsEnabled = true
        preferences.automaticRetryEnabled = false

        let restored = DownloadPreferences(defaults: defaults)

        XCTAssertFalse(restored.allowsCellularDownloads)
        XCTAssertEqual(restored.maximumConcurrentDownloads, 4)
        XCTAssertTrue(restored.completionNotificationsEnabled)
        XCTAssertFalse(restored.automaticRetryEnabled)
    }

    func testConcurrentDownloadCountIsClampedBeforePersistence() {
        let preferences = DownloadPreferences(defaults: defaults)

        preferences.maximumConcurrentDownloads = 99
        XCTAssertEqual(
            preferences.maximumConcurrentDownloads,
            DownloadPreferences.concurrentDownloadRange.upperBound
        )

        preferences.maximumConcurrentDownloads = -10
        XCTAssertEqual(
            preferences.maximumConcurrentDownloads,
            DownloadPreferences.concurrentDownloadRange.lowerBound
        )
    }

    @MainActor
    func testNotificationPreferenceOnlyEnablesAfterSystemAuthorization() async throws {
        let preferences = DownloadPreferences(defaults: defaults)
        let authorizer = DownloadNotificationAuthorizerStub(isAuthorized: false)
        let viewModel = DownloadSettingsViewModel(
            preferences: preferences,
            notificationAuthorizer: authorizer
        )

        let enabled = try await viewModel.setCompletionNotificationsEnabled(true)

        XCTAssertFalse(enabled)
        XCTAssertFalse(preferences.completionNotificationsEnabled)
        XCTAssertEqual(authorizer.requestCount, 1)
    }
}

@MainActor
private final class DownloadNotificationAuthorizerStub:
    DownloadNotificationAuthorizing {
    private let isAuthorized: Bool
    private(set) var requestCount = 0

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        return isAuthorized
    }
}
