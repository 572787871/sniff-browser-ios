import Foundation
import XCTest
@testable import SniffBrowser

final class HLSResourcePresentationTests: XCTestCase {
    func testQualityLabelsPreferHumanReadableVideoHeights() {
        XCTAssertEqual(
            HLSQualityLabel.make(width: 1_920, height: 1_080, bitrate: 5_000_000),
            "1080p"
        )
        XCTAssertEqual(
            HLSQualityLabel.make(width: 3_840, height: 2_160, bitrate: nil),
            "4K"
        )
        XCTAssertEqual(
            HLSQualityLabel.make(width: nil, height: nil, bitrate: 2_500_000),
            "2.5 Mbps"
        )
    }

    func testReadableTitleReplacesGenericMasterName() {
        XCTAssertEqual(
            HLSResourceMetadataResolver.readableTitle(
                pageTitle: "Example Video",
                existingName: "master.m3u8"
            ),
            "Example Video"
        )
    }

    func testHLSMetadataMergeUpgradesTitleWithQuality() throws {
        let tabID = UUID()
        let url = try XCTUnwrap(URL(string: "https://media.example.com/master.m3u8"))
        let existing = DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            sourcePageTitle: "Example Video",
            fileName: "Example Video.m3u8",
            fileExtension: "m3u8",
            mimeType: "application/vnd.apple.mpegurl",
            resourceType: .hls,
            detectionSource: .performance,
            tabID: tabID
        )
        let enriched = DetectedResource(
            canonicalURL: url,
            originalURLString: url.absoluteString,
            sourcePageTitle: "Example Video",
            fileName: "Example Video - 1080p.m3u8",
            fileExtension: "m3u8",
            mimeType: "application/vnd.apple.mpegurl",
            resourceType: .hls,
            estimatedSize: 120_000_000,
            duration: 300,
            width: 1_920,
            height: 1_080,
            bitrate: 3_200_000,
            detectionSource: .manualScan,
            tabID: tabID
        )

        let merged = ResourceDeduplicator().merge(
            existing: existing,
            incoming: enriched
        )

        XCTAssertEqual(merged.fileName, "Example Video - 1080p.m3u8")
        XCTAssertEqual(merged.height, 1_080)
        XCTAssertEqual(merged.estimatedSize, 120_000_000)
    }

    func testMainDocumentWithVideoHintIsNotAResource() throws {
        let pageURL = "https://example.com/view_video.php?id=123"
        let candidate = ResourceCandidate(
            originalURLString: pageURL,
            pageURLString: pageURL,
            pageTitle: "Example Video",
            mimeType: "video/mp4",
            estimatedSize: nil,
            duration: 120,
            width: 1_280,
            height: 720,
            bitrate: nil,
            thumbnailURLString: nil,
            detectionSource: .mediaEvent,
            elementType: "video",
            headersHint: [:]
        )

        XCTAssertNil(ResourceClassifier().makeResource(
            from: candidate,
            tabID: UUID()
        ))
    }

    func testDirectMP4MainDocumentRemainsDownloadable() throws {
        let pageURL = "https://media.example.com/video.mp4"
        let candidate = ResourceCandidate(
            originalURLString: pageURL,
            pageURLString: pageURL,
            pageTitle: "Example Video",
            mimeType: "video/mp4",
            estimatedSize: 1_024,
            duration: 12,
            width: 640,
            height: 360,
            bitrate: nil,
            thumbnailURLString: nil,
            detectionSource: .navigationResponse,
            elementType: "video",
            headersHint: [:]
        )

        XCTAssertEqual(
            ResourceClassifier().makeResource(
                from: candidate,
                tabID: UUID()
            )?.resourceType,
            .video
        )
    }

    func testRemotePlaylistRewriterPreservesTagsAndProxiesResources() throws {
        let baseURL = try XCTUnwrap(
            URL(string: "https://media.example.com/hls/master.m3u8")
        )
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="keys/current.key"
        #EXTINF:6,
        segments/one.ts
        """

        let rewritten = RemoteHLSPlaylistRewriter.rewrite(
            playlist,
            baseURL: baseURL
        ) { remoteURL in
            URL(string: "http://127.0.0.1/resource?url=\(remoteURL.lastPathComponent)")
        }

        XCTAssertTrue(rewritten.contains("URI=\"http://127.0.0.1/resource?url=current.key\""))
        XCTAssertTrue(rewritten.contains("http://127.0.0.1/resource?url=one.ts"))
        XCTAssertTrue(rewritten.contains("#EXTINF:6,"))
    }
}
