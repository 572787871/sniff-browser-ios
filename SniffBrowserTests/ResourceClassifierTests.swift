import Foundation
import XCTest
@testable import SniffBrowser

final class ResourceClassifierTests: XCTestCase {
    private let classifier = ResourceClassifier()

    func testClassifiesCommonExtensions() throws {
        XCTAssertEqual(try classify("https://example.com/movie.mp4"), .video)
        XCTAssertEqual(try classify("https://example.com/master.m3u8"), .hls)
        XCTAssertEqual(try classify("https://example.com/audio.mp3"), .audio)
        XCTAssertEqual(try classify("https://example.com/report.pdf"), .document)
        XCTAssertEqual(try classify("https://example.com/subtitle.vtt"), .subtitle)
        XCTAssertEqual(try classify("https://example.com/photo.jpg"), .image)
    }

    func testMIMETypeClassifiesURLWithoutExtension() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/resource?id=1"))
        XCTAssertEqual(
            classifier.classify(
                mimeType: "video/mp4; charset=binary",
                url: url,
                elementType: nil
            ),
            .video
        )
    }

    func testMIMETypeTakesPriorityOverWrongExtension() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/file.txt"))
        XCTAssertEqual(
            classifier.classify(
                mimeType: "audio/mpeg",
                url: url,
                elementType: nil
            ),
            .audio
        )
    }

    func testOrdinaryWebPageIsNotAResource() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        XCTAssertNil(
            classifier.classify(
                mimeType: "text/html",
                url: url,
                elementType: "a"
            )
        )
    }

    func testStandaloneDASHFragmentIsHiddenFromResourceResults() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/segment_1.m4s"))
        let candidate = ResourceCandidate(
            originalURLString: url.absoluteString,
            pageURLString: "https://example.com/watch",
            pageTitle: "Example",
            mimeType: "video/iso.segment",
            estimatedSize: 4_096,
            duration: nil,
            width: nil,
            height: nil,
            bitrate: nil,
            thumbnailURLString: nil,
            detectionSource: .performance,
            elementType: "video",
            headersHint: [:]
        )

        XCTAssertNil(classifier.makeResource(from: candidate, tabID: UUID()))
    }

    private func classify(_ rawURL: String) throws -> ResourceType? {
        classifier.classify(
            mimeType: nil,
            url: try XCTUnwrap(URL(string: rawURL)),
            elementType: nil
        )
    }
}
