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
        XCTAssertEqual(playlist.mergedSegmentFileExtension, "ts")
        XCTAssertTrue(playlist.requiresTransportStreamExport)
        XCTAssertEqual(playlist.outputFileExtension, "mp4")
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
        XCTAssertEqual(playlist.mergedSegmentFileExtension, "mp4")
        XCTAssertFalse(playlist.requiresTransportStreamExport)
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

    func testParsesLiveStandardAES128WithoutMisclassifyingItAsDRM() throws {
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
        XCTAssertFalse(playlist.hasUnsupportedEncryption)
        XCTAssertEqual(playlist.segments.first?.encryption?.keyURL.absoluteString,
                       "https://media.example.com/key.bin")
    }

    func testParsesSupportedAES128WithExplicitIVAndMediaSequence() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/video/index.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:27
        #EXT-X-KEY:METHOD=AES-128,URI="keys/current.key",IV=0x000102030405060708090A0B0C0D0E0F
        #EXTINF:6,
        segment.ts
        #EXT-X-ENDLIST
        """
        guard case let .media(playlist) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected media playlist") }

        XCTAssertFalse(playlist.hasUnsupportedEncryption)
        XCTAssertTrue(playlist.isEncrypted)
        XCTAssertEqual(playlist.segments.first?.mediaSequence, 27)
        XCTAssertEqual(
            playlist.segments.first?.encryption?.keyURL.absoluteString,
            "https://media.example.com/video/keys/current.key"
        )
        XCTAssertEqual(
            playlist.segments.first?.encryption?.initializationVector,
            Data((0...15).map { UInt8($0) })
        )
    }

    func testRejectsSampleAESAsUnsupportedProtectedMedia() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example.com/video.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://license"
        #EXTINF:6,
        segment.ts
        #EXT-X-ENDLIST
        """
        guard case let .media(playlist) = try HLSPlaylistParser().parse(text, sourceURL: url)
        else { return XCTFail("Expected media playlist") }
        XCTAssertTrue(playlist.hasUnsupportedEncryption)
    }

    func testHLSDisplaySizeDoesNotUsePlaylistContentLength() throws {
        let candidate = ResourceCandidate(
            originalURLString: "https://media.example.com/video.m3u8",
            pageURLString: "https://example.com/watch",
            pageTitle: "Video",
            mimeType: "application/vnd.apple.mpegurl",
            estimatedSize: 9_216,
            duration: 120,
            width: 1280,
            height: 720,
            bitrate: nil,
            thumbnailURLString: nil,
            detectionSource: .dom,
            elementType: "video",
            headersHint: [:]
        )
        let resource = try XCTUnwrap(ResourceClassifier().makeResource(
            from: candidate,
            tabID: UUID()
        ))

        XCTAssertEqual(resource.resourceType, .hls)
        XCTAssertNil(resource.estimatedSize)
    }

    func testDecryptsStandardAES128CBCSegment() throws {
        let cipher = try XCTUnwrap(Data(hexadecimal:
            "b88518137cfbcab25479a1d023edeafba9f953ef687d3cb4f03bc732eadac43a"
        ))
        let key = try XCTUnwrap(Data(hexadecimal: "000102030405060708090a0b0c0d0e0f"))
        let iv = try XCTUnwrap(Data(hexadecimal: "101112131415161718191a1b1c1d1e1f"))

        let decrypted = try HLSAssetDownloadService.decryptAES128CBC(
            data: cipher,
            key: key,
            iv: iv
        )
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "SniffBrowser HLS AES-128")
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

private extension Data {
    init?(hexadecimal: String) {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
