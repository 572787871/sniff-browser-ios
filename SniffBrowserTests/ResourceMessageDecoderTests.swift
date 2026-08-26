import Foundation
import XCTest
@testable import SniffBrowser

final class ResourceMessageDecoderTests: XCTestCase {
    private let decoder = ResourceMessageDecoder()

    func testDecodesValidBatch() throws {
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com/page",
            "pageTitle": "Example",
            "candidates": [[
                "url": "https://cdn.example.com/video.mp4",
                "mimeType": "video/mp4",
                "contentLength": 1_024,
                "source": "fetch"
            ]]
        ])

        XCTAssertEqual(batch.kind, .batch)
        XCTAssertEqual(batch.candidates.count, 1)
        XCTAssertEqual(batch.candidates.first?.detectionSource, .fetch)
        XCTAssertEqual(batch.candidates.first?.estimatedSize, 1_024)
    }

    func testDecodesSafeVideoThumbnailURL() throws {
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com/page",
            "candidates": [[
                "url": "https://cdn.example.com/video.mp4",
                "thumbnailURL": "https://cdn.example.com/poster.jpg",
                "mimeType": "video/mp4"
            ]]
        ])

        XCTAssertEqual(
            batch.candidates.first?.thumbnailURLString,
            "https://cdn.example.com/poster.jpg"
        )
    }

    func testDecodesBoundedInlineVideoFrameThumbnail() throws {
        let dataURL = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2Q=="
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com/page",
            "candidates": [[
                "url": "https://cdn.example.com/video.m3u8",
                "thumbnailURL": dataURL,
                "mimeType": "application/vnd.apple.mpegurl"
            ]]
        ])

        XCTAssertEqual(
            batch.candidates.first?.thumbnailURLString,
            dataURL
        )
    }

    func testRejectsNonImageInlineThumbnail() throws {
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com/page",
            "candidates": [[
                "url": "https://cdn.example.com/video.mp4",
                "thumbnailURL": "data:text/html;base64,PGgxPkJhZDwvaDE+",
                "mimeType": "video/mp4"
            ]]
        ])

        XCTAssertNil(batch.candidates.first?.thumbnailURLString)
    }

    func testMissingAndInvalidURLsAreRejected() throws {
        let batch = try decode([
            "kind": "batch",
            "candidates": [
                ["mimeType": "video/mp4"],
                ["url": "not a url"],
                ["url": ""]
            ]
        ])
        XCTAssertTrue(batch.candidates.isEmpty)
    }

    func testUnsafeSchemesAreRejected() throws {
        let batch = try decode([
            "kind": "batch",
            "candidates": [
                ["url": "javascript:alert(1)"],
                ["url": "data:video/mp4;base64,AAAA"],
                ["url": "about:blank"]
            ]
        ])
        XCTAssertTrue(batch.candidates.isEmpty)
    }

    func testBlobIsSafelyDecodedButFilteredFromDownloadableResources() throws {
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com",
            "candidates": [[
                "url": "blob:https://example.com/id",
                "mimeType": "video/mp4",
                "source": "mediaEvent",
                "elementType": "video"
            ]]
        ])
        let candidate = try XCTUnwrap(batch.candidates.first)
        XCTAssertNil(
            ResourceClassifier().makeResource(
                from: candidate,
                tabID: UUID()
            ),
            "Blob playback handles must not appear as duplicate downloadable videos"
        )
    }

    func testInlineImageDataURLIsAcceptedAndClassifiedAsImage() throws {
        let dataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let batch = try decode([
            "kind": "batch",
            "pageURL": "https://example.com/page",
            "candidates": [[
                "url": dataURL,
                "mimeType": "image/png",
                "elementType": "img"
            ]]
        ])

        let candidate = try XCTUnwrap(batch.candidates.first)
        let resource = try XCTUnwrap(
            ResourceClassifier().makeResource(from: candidate, tabID: UUID())
        )
        XCTAssertEqual(resource.resourceType, .image)
        XCTAssertFalse(resource.isPotentiallyDownloadable)
    }

    func testOverlongURLAndWrongFieldTypesAreRejected() throws {
        let batch = try decode([
            "kind": "batch",
            "candidates": [
                ["url": "https://example.com/" + String(
                    repeating: "a",
                    count: ResourceMessageDecoder.maximumURLLength
                )],
                ["url": 42]
            ]
        ])
        XCTAssertTrue(batch.candidates.isEmpty)
    }

    func testBatchCountIsLimited() throws {
        let values = (0..<600).map {
            ["url": "https://example.com/file-\($0).mp4"]
        }
        let batch = try decode([
            "kind": "batch",
            "candidates": values
        ])
        XCTAssertEqual(
            batch.candidates.count,
            ResourceMessageDecoder.maximumBatchCount
        )
    }

    private func decode(_ object: [String: Any]) throws -> ResourceMessageBatch {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try decoder.decode(data)
    }
}
