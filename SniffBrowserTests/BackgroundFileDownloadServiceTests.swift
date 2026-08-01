import Foundation
import XCTest
@testable import SniffBrowser

final class BackgroundFileDownloadServiceTests: XCTestCase {
    func testAcceptsValidHTTPFileResponseAndUnknownSize() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/file.mp4"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "video/mp4"]
        ))

        XCTAssertNoThrow(try DownloadResponseValidator.validate(response: response, filePrefix: nil))
    }

    func testRejectsHTTPErrorAndHTMLLoginPage() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/file.mp4"))
        let forbidden = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        ))
        XCTAssertThrowsError(
            try DownloadResponseValidator.validate(response: forbidden, filePrefix: nil)
        ) { XCTAssertEqual($0 as? DownloadCenterError, .signedURLExpired) }

        let html = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))
        XCTAssertThrowsError(
            try DownloadResponseValidator.validate(
                response: html,
                filePrefix: Data("<!doctype html><title>Login</title>".utf8)
            )
        ) { XCTAssertEqual($0 as? DownloadCenterError, .unexpectedHTML) }
    }

    func testDownloadRequestKeepsExplicitWebKitContextDeterministic() throws {
        let target = try XCTUnwrap(
            URL(string: "https://cdn.example.com/file.mp4")
        )
        let page = try XCTUnwrap(URL(string: "https://example.com/watch"))
        let context = DownloadRequestContext(
            targetURL: target,
            pageURL: page,
            headers: [
                "Cookie": "session=redacted",
                "Referer": page.absoluteString
            ]
        )

        let request = context.makeRequest()

        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Referer"),
            page.absoluteString
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
    }

    func testProgressAggregatorReportsSmoothedSpeedAndRemainingTime() throws {
        var aggregator = DownloadProgressAggregator()
        let start = Date(timeIntervalSince1970: 100)
        _ = aggregator.update(receivedBytes: 0, expectedBytes: 4_000, now: start)
        let sample = aggregator.update(
            receivedBytes: 1_000,
            expectedBytes: 4_000,
            now: start.addingTimeInterval(1)
        )

        XCTAssertEqual(try XCTUnwrap(sample.speedBytesPerSecond), 1_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sample.estimatedRemainingTime), 3, accuracy: 0.001)
    }

    func testRetryableBackgroundFailureFallsBackButCancellationDoesNot() {
        XCTAssertTrue(FileDownloadTransportPolicy.shouldRetryInForeground(
            URLError(.networkConnectionLost)
        ))
        XCTAssertTrue(FileDownloadTransportPolicy.shouldRetryInForeground(
            URLError(.cannotConnectToHost)
        ))
        XCTAssertFalse(FileDownloadTransportPolicy.shouldRetryInForeground(
            URLError(.cancelled)
        ))
        XCTAssertFalse(FileDownloadTransportPolicy.shouldRetryInForeground(
            URLError(.serverCertificateUntrusted)
        ))
    }
}
