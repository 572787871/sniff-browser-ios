import Foundation
import XCTest
@testable import SniffBrowser

final class HLSDownloadTests: XCTestCase {
    func testParsesFiniteTransportStreamPlaylistInOrder() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/path/index.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:5.5,
        first.ts
        #EXTINF:4.0,
        second.ts
        #EXT-X-ENDLIST
        """

        guard case let .media(playlist) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected media playlist") }
        XCTAssertTrue(playlist.isEndList)
        XCTAssertFalse(playlist.isEncrypted)
        XCTAssertEqual(playlist.outputFileExtension, "ts")
        XCTAssertEqual(playlist.segments.map(\.url.absoluteString), [
            "https://media.example.com/path/first.ts",
            "https://media.example.com/path/second.ts"
        ])
    }

    func testParsesFMP4InitializationAndByteRanges() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/video.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:3,
        one.m4s
        #EXT-X-BYTERANGE:100@20
        shared.m4s
        #EXT-X-ENDLIST
        """

        guard case let .media(playlist) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected media playlist") }
        XCTAssertEqual(playlist.initializationSegment?.url.lastPathComponent, "init.mp4")
        XCTAssertEqual(playlist.segments.last?.byteRange, HLSByteRange(length: 100, offset: 20))
        XCTAssertEqual(playlist.outputFileExtension, "mp4")
    }

    func testParsesMasterVariantsWithoutTreatingPlaylistAsVideo() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/master.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        360/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080
        1080/index.m3u8
        """

        guard case let .master(variants) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected master playlist") }
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants.last?.height, 1080)
        XCTAssertEqual(variants.last?.url.absoluteString, "https://media.example.com/1080/index.m3u8")
    }

    func testMarksLiveAndEncryptedMediaForRejection() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/live.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
        #EXTINF:6,
        segment.ts
        """
        guard case let .media(playlist) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected media playlist") }
        XCTAssertFalse(playlist.isEndList)
        XCTAssertTrue(playlist.isEncrypted)
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
