import Foundation
import XCTest
@testable import SniffBrowser

final class ResourceDeduplicatorTests: XCTestCase {
    private let deduplicator = ResourceDeduplicator()

    func testCanonicalURLRemovesFragmentAndNormalizesHostAndPort() throws {
        let raw = try XCTUnwrap(
            URL(string: "HTTPS://EXAMPLE.COM:443/video.mp4#chapter")
        )
        XCTAssertEqual(
            ResourceDeduplicator.canonicalURL(for: raw)?.absoluteString,
            "https://example.com/video.mp4"
        )
    }

    func testSignedParametersArePreserved() throws {
        let raw = try XCTUnwrap(URL(
            string: "https://example.com/video.mp4?token=a%2Bb&signature=x%2Fy&expires=9&utm_source=test"
        ))
        let canonical = try XCTUnwrap(
            ResourceDeduplicator.canonicalURL(for: raw)
        )
        let value = canonical.absoluteString
        XCTAssertTrue(value.contains("token=a%2Bb"))
        XCTAssertTrue(value.contains("signature=x%2Fy"))
        XCTAssertTrue(value.contains("expires=9"))
        XCTAssertFalse(value.contains("utm_source"))
    }

    func testMultipleSourcesMergeAndCompleteMetadata() throws {
        let tabID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/video.mp4"))
        let first = makeResource(
            url: url,
            tabID: tabID,
            source: .performance
        )
        let second = makeResource(
            url: url,
            tabID: tabID,
            source: .mediaEvent,
            mimeType: "video/mp4",
            size: 4_096,
            width: 1_920,
            height: 1_080
        )

        let merged = deduplicator.merge(existing: first, incoming: second)

        XCTAssertEqual(merged.id, first.id)
        XCTAssertEqual(merged.detectionSource, .mediaEvent)
        XCTAssertEqual(merged.mimeType, "video/mp4")
        XCTAssertEqual(merged.estimatedSize, 4_096)
        XCTAssertEqual(merged.width, 1_920)
        XCTAssertEqual(merged.height, 1_080)
        XCTAssertEqual(merged.detectedAt, first.detectedAt)
    }

    private func makeResource(
        url: URL,
        tabID: UUID,
        source: DetectionSource,
        mimeType: String? = nil,
        size: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) -> DetectedResource {
        DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            fileName: "video.mp4",
            fileExtension: "mp4",
            mimeType: mimeType,
            resourceType: .video,
            estimatedSize: size,
            width: width,
            height: height,
            detectionSource: source,
            detectedAt: Date(timeIntervalSince1970: 10),
            lastSeenAt: Date(timeIntervalSince1970: 20),
            tabID: tabID
        )
    }
}
