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

        XCTAssertEqual(configuration.statusTitle, "未开始")
        XCTAssertEqual(configuration.primaryTitle, "开始嗅探")
        XCTAssertEqual(
            configuration.detail,
            "点击开始嗅探后检测当前页面资源"
        )
        XCTAssertTrue(configuration.helper.contains("手动开启"))
        XCTAssertEqual(configuration.filters.map(\.count), [0, 0, 0, 0])
        XCTAssertFalse(configuration.showsResultControls)

        let empty = ResourceSnifferEmptyConfiguration(
            state: makeState(
                tabID: tabID,
                resources: [],
                activationState: .disabled,
                hasStarted: false
            )
        )
        XCTAssertEqual(empty.title, "尚未发现资源")
        XCTAssertEqual(empty.message, "开始嗅探后将在此显示结果")
        XCTAssertNil(empty.actionTitle)
        XCTAssertNil(empty.secondaryActionTitle)
    }

    @MainActor
    func testActivePresentationGroupsHLSWithVideo() throws {
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
                hasStarted: true
            ),
            selectedFilter: .image
        )

        XCTAssertEqual(configuration.statusTitle, "嗅探中")
        XCTAssertEqual(configuration.primaryTitle, "停止嗅探")
        XCTAssertEqual(configuration.filters.map(\.count), [3, 1, 1, 1])
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

        XCTAssertEqual(configuration.statusTitle, "已停止")
        XCTAssertEqual(configuration.filters.map(\.count), [1, 0, 0, 1])
        XCTAssertEqual(configuration.detail, "已停止新增，当前结果仍然保留")
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

        XCTAssertTrue(configuration.helper.contains("无痕结果只保留本次会话"))
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
    func testFailedScanKeepsResultsAndExposesRetryState() throws {
        let tabID = UUID()
        let state = makeState(
            tabID: tabID,
            resources: [try resource(type: .video, tabID: tabID)],
            activationState: .active,
            hasStarted: true,
            scanState: .failed,
            errorMessage: "扫描等待超时"
        )
        let chrome = ResourceSnifferChromeConfiguration(
            state: state,
            selectedFilter: .all
        )
        let empty = ResourceSnifferEmptyConfiguration(state: state)

        XCTAssertEqual(chrome.statusTitle, "检测失败")
        XCTAssertTrue(chrome.detail.contains("扫描等待超时"))
        XCTAssertTrue(chrome.showsResultControls)
        XCTAssertEqual(empty.title, "页面检测失败")
        XCTAssertEqual(empty.actionTitle, "重新扫描页面")
    }

    @MainActor
    private func makeState(
        tabID: UUID,
        resources: [DetectedResource],
        isPrivate: Bool = false,
        activationState: SniffingActivationState,
        hasStarted: Bool,
        scanState: ResourceScanState? = nil,
        errorMessage: String? = nil
    ) -> ResourceSnifferViewModel.State {
        ResourceSnifferViewModel.State(
            tabID: tabID,
            pageTitle: "Example",
            pageURL: URL(string: "https://example.com/article"),
            isPrivate: isPrivate,
            resources: resources,
            scanState: scanState ?? (activationState == .active ? .completed : .idle),
            lastScanAt: nil,
            errorMessage: errorMessage,
            activationState: activationState,
            hasStarted: hasStarted
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
