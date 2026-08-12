import Foundation
import XCTest
@testable import SniffBrowser

final class ResourceSnifferPresentationTests: XCTestCase {
    @MainActor
    func testInitialPresentationDoesNotExposeResourceCounts() throws {
        let tabID = UUID()
        let configuration = ResourceSnifferChromeConfiguration(
            state: makeState(
                tabID: tabID,
                resources: [try resource(type: .video, tabID: tabID)],
                activationState: .disabled,
                hasStarted: false
            ),
            selectedFilter: .all
        )

        XCTAssertEqual(configuration.statusTitle, "待检测")
        XCTAssertEqual(configuration.primaryTitle, "开始捕获")
        XCTAssertEqual(configuration.filters.map(\.count), [0, 0, 0, 0])
        XCTAssertFalse(configuration.showsResultControls)
    }

    @MainActor
    func testActivePresentationGroupsHLSWithVideoAndShowsImageRefinement() throws {
        let tabID = UUID()
        let resources = [
            try resource(type: .hls, tabID: tabID),
            try resource(type: .audio, tabID: tabID),
            try resource(type: .image, tabID: tabID)
        ]
        let configuration = ResourceSnifferChromeConfiguration(
            state: makeState(
                tabID: tabID,
                resources: resources,
                activationState: .active,
                hasStarted: true,
                imageFilters: [.jpeg, .png]
            ),
            selectedFilter: .image
        )

        XCTAssertEqual(configuration.statusTitle, "捕获中")
        XCTAssertEqual(configuration.primaryTitle, "暂停捕获")
        XCTAssertEqual(configuration.filters.map(\.count), [3, 1, 1, 1])
        XCTAssertTrue(configuration.filters.last?.showsRefinement == true)
        XCTAssertTrue(configuration.filters.last?.isSelected == true)
        XCTAssertEqual(configuration.resultCount, 1)
        XCTAssertTrue(configuration.showsResultControls)
    }

    @MainActor
    func testStoppedPresentationKeepsDiscoveredResourceCounts() throws {
        let tabID = UUID()
        let configuration = ResourceSnifferChromeConfiguration(
            state: makeState(
                tabID: tabID,
                resources: [try resource(type: .image, tabID: tabID)],
                activationState: .disabled,
                hasStarted: true
            ),
            selectedFilter: .all
        )

        XCTAssertEqual(configuration.statusTitle, "已暂停")
        XCTAssertEqual(configuration.filters.map(\.count), [1, 0, 0, 1])
        XCTAssertEqual(configuration.detail, "已暂停新增，当前结果仍然保留")
    }

    @MainActor
    func testPrivatePresentationExplainsSessionOnlyRetention() {
        let configuration = ResourceSnifferChromeConfiguration(
            state: makeState(
                tabID: UUID(),
                resources: [],
                isPrivate: true,
                activationState: .disabled,
                hasStarted: false
            ),
            selectedFilter: .all
        )

        XCTAssertTrue(configuration.helper.contains("无痕结果仅保留在本次会话"))
    }

    @MainActor
    func testStartingEmptyStateDoesNotOfferASecondScanAction() {
        let state = makeState(
            tabID: UUID(),
            resources: [],
            activationState: .starting,
            hasStarted: true
        )
        let configuration = ResourceSnifferEmptyConfiguration(state: state)

        XCTAssertTrue(configuration.isWorking)
        XCTAssertNil(configuration.actionTitle)
    }

    @MainActor
    private func makeState(
        tabID: UUID,
        resources: [DetectedResource],
        isPrivate: Bool = false,
        activationState: SniffingActivationState,
        hasStarted: Bool,
        imageFilters: Set<ImageResourceFormat> = []
    ) -> ResourceSnifferViewModel.State {
        ResourceSnifferViewModel.State(
            tabID: tabID,
            pageTitle: "Example",
            pageURL: URL(string: "https://example.com/article"),
            isPrivate: isPrivate,
            resources: resources,
            scanState: activationState == .active ? .completed : .idle,
            lastScanAt: nil,
            errorMessage: nil,
            activationState: activationState,
            hasStarted: hasStarted,
            imageFilters: imageFilters
        )
    }

    private func resource(
        type: ResourceType,
        tabID: UUID
    ) throws -> DetectedResource {
        let suffix: String
        let mime: String
        switch type {
        case .hls:
            suffix = "stream.m3u8"
            mime = "application/vnd.apple.mpegurl"
        case .audio:
            suffix = "audio.m4a"
            mime = "audio/mp4"
        case .image:
            suffix = "image.jpg"
            mime = "image/jpeg"
        default:
            suffix = "video.mp4"
            mime = "video/mp4"
        }
        let url = try XCTUnwrap(URL(string: "https://example.com/\(suffix)"))
        return DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            fileName: suffix,
            fileExtension: url.pathExtension,
            mimeType: mime,
            resourceType: type,
            detectionSource: .dom,
            tabID: tabID
        )
    }
}
