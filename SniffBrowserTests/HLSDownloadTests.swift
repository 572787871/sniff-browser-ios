import Foundation
import XCTest
@testable import SniffBrowser

final class HLSDownloadTests: XCTestCase {
    func testEligibleVODIsAccepted() {
        XCTAssertNoThrow(try HLSDownloadEligibility.validate(
            isPlayable: true,
            isProtected: false,
            durationSeconds: 120,
            isDurationIndefinite: false
        ))
    }

    func testLiveAndProtectedStreamsAreRejected() {
        XCTAssertThrowsError(try HLSDownloadEligibility.validate(
            isPlayable: true,
            isProtected: false,
            durationSeconds: .infinity,
            isDurationIndefinite: true
        )) { XCTAssertEqual($0 as? DownloadCenterError, .liveHLSUnsupported) }

        XCTAssertThrowsError(try HLSDownloadEligibility.validate(
            isPlayable: true,
            isProtected: true,
            durationSeconds: 120,
            isDurationIndefinite: false
        )) { XCTAssertEqual($0 as? DownloadCenterError, .protectedMediaUnsupported) }
    }

    func testHLSResourceCreatesHLSDownloadKind() throws {
        let resource = DetectedResource(
            canonicalURL: try XCTUnwrap(URL(string: "https://example.com/master.m3u8")),
            originalURLString: "https://example.com/master.m3u8",
            fileName: "master.m3u8",
            fileExtension: "m3u8",
            mimeType: "application/vnd.apple.mpegurl",
            resourceType: .hls,
            detectionSource: .dom,
            tabID: UUID()
        )

        XCTAssertEqual(resource.resourceType, .hls)
        XCTAssertTrue(resource.isPotentiallyDownloadable)
    }
}
