import Foundation
import UIKit
import XCTest
@testable import SniffBrowser

final class FaviconLoaderTests: XCTestCase {
    private var root: URL!
    private var cacheDirectory: URL!
    private var configuration: URLSessionConfiguration!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        cacheDirectory = root.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocol.self]
        FaviconURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        FaviconURLProtocol.reset()
        super.tearDown()
    }

    func testLoadsFaviconThenServesFromMemoryCache() async throws {
        FaviconURLProtocol.configure(data: Self.onePixelPNG)
        let loader = makeLoader()
        let url = try makeURL("https://example.com/favicon.ico")

        let first = await load(loader, url: url)
        let second = await load(loader, url: url)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(FaviconURLProtocol.requestCount, 1)
    }

    func testFaviconIsPersistedToDiskAndServedWithoutNetworkAgain() async throws {
        FaviconURLProtocol.configure(data: Self.onePixelPNG)
        let url = try makeURL("https://example.com/disk.png")
        let key = FaviconLoader.cacheKey(for: url)

        let firstLoader = makeLoader()
        let first = await load(firstLoader, url: url)
        XCTAssertNotNil(first)
        try await waitForDiskFile(key: key)

        // A fresh loader (empty memory cache) must still be served from disk.
        let secondLoader = makeLoader()
        let second = await load(secondLoader, url: url)

        XCTAssertNotNil(second)
        XCTAssertEqual(FaviconURLProtocol.requestCount, 1)
    }

    func testMemoryOnlyLoaderNeverWritesFaviconToDisk() async throws {
        FaviconURLProtocol.configure(data: Self.onePixelPNG)
        let url = try makeURL("https://private.example/favicon.ico")
        let loader = makeLoader(usesDiskCache: false)

        let image = await load(loader, url: url)

        XCTAssertNotNil(image)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cacheDirectory
                    .appendingPathComponent(FaviconLoader.cacheKey(for: url))
                    .path
            )
        )
    }

    func testConcurrentLoadsShareOneNetworkRequest() async throws {
        FaviconURLProtocol.configure(data: Self.onePixelPNG, delay: 0.3)
        let loader = makeLoader()
        let url = try makeURL("https://example.com/coalesced.png")

        async let first = load(loader, url: url)
        async let second = load(loader, url: url)
        let results = await [first, second]

        XCTAssertEqual(results.compactMap { $0 }.count, 2)
        XCTAssertEqual(FaviconURLProtocol.requestCount, 1)
    }

    func testOversizedResponseIsRejectedAndNotCached() async throws {
        FaviconURLProtocol.configure(
            data: Data(repeating: 0x00, count: 1024)
        )
        let loader = makeLoader(maximumNetworkBytes: 512)
        let url = try makeURL("https://example.com/oversized.png")

        let image = await load(loader, url: url)

        XCTAssertNil(image)
        XCTAssertEqual(FaviconURLProtocol.requestCount, 1)
        let key = FaviconLoader.cacheKey(for: url)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cacheDirectory.appendingPathComponent(key).path
            )
        )
    }

    func testInvalidImageDataIsRejected() async throws {
        FaviconURLProtocol.configure(data: Data("not an image".utf8))
        let loader = makeLoader()

        let image = await load(
            loader,
            url: try makeURL("https://example.com/invalid.png")
        )

        XCTAssertNil(image)
    }

    func testCancelRemovesCallbackWithoutFiringCompletion() async throws {
        FaviconURLProtocol.configure(data: Self.onePixelPNG, delay: 0.5)
        let loader = makeLoader()
        let url = try makeURL("https://example.com/slow.png")
        let completion = expectation(description: "cancelled completion")
        completion.isInverted = true

        let requestID = loader.load(url: url) { _ in completion.fulfill() }
        loader.cancel(url: url, requestID: requestID)

        await fulfillment(of: [completion], timeout: 0.8)
    }

    func testFaviconURLResolution() throws {
        let google = try XCTUnwrap(
            FaviconLoader.faviconURL(
                for: XCTUnwrap(URL(string: "https://example.com/page"))
            )
        )
        XCTAssertEqual(
            google.absoluteString,
            "https://www.google.com/s2/favicons?domain=example.com&sz=64"
        )

        let direct = try XCTUnwrap(
            FaviconLoader.directFaviconURL(
                for: XCTUnwrap(URL(string: "https://example.com:8443/page"))
            )
        )
        XCTAssertEqual(
            direct.absoluteString,
            "https://example.com:8443/favicon.ico"
        )

        let fileURL = try XCTUnwrap(URL(string: "file:///tmp/page"))
        XCTAssertNil(FaviconLoader.faviconURL(for: fileURL))
        XCTAssertNil(FaviconLoader.directFaviconURL(for: fileURL))
    }

    func testCacheKeyIsStableAndURLDerived() throws {
        let first = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let second = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let other = try XCTUnwrap(URL(string: "https://other.example/favicon.ico"))

        XCTAssertEqual(FaviconLoader.cacheKey(for: first), FaviconLoader.cacheKey(for: second))
        XCTAssertNotEqual(FaviconLoader.cacheKey(for: first), FaviconLoader.cacheKey(for: other))
        XCTAssertFalse(
            FaviconLoader.cacheKey(for: first).contains("/")
        )
    }

    private func makeLoader(
        maximumNetworkBytes: Int = FaviconLoader.maximumNetworkBytes,
        usesDiskCache: Bool = true
    ) -> FaviconLoader {
        FaviconLoader(
            directoryURL: cacheDirectory,
            sessionConfiguration: configuration,
            maximumNetworkBytes: maximumNetworkBytes,
            usesDiskCache: usesDiskCache
        )
    }

    private func makeURL(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    @MainActor
    private func load(_ loader: FaviconLoader, url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loader.load(url: url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private func waitForDiskFile(key: String) async throws {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        let written = expectation(description: "disk write")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(2)
            while !FileManager.default.fileExists(atPath: fileURL.path),
                  Date() < deadline {
                usleep(10_000)
            }
            written.fulfill()
        }
        await fulfillment(of: [written], timeout: 2)
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private final class FaviconURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var responseDelay: TimeInterval = 0
    private static var internalRequestCount = 0
    private var stopped = false

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return internalRequestCount
    }

    static func configure(
        data: Data,
        delay: TimeInterval = 0
    ) {
        lock.lock()
        responseData = data
        responseDelay = delay
        internalRequestCount = 0
        lock.unlock()
    }

    static func reset() {
        configure(data: Data())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let payload: (Data, TimeInterval) = Self.lock.withLock {
            Self.internalRequestCount += 1
            return (Self.responseData, Self.responseDelay)
        }
        let deliver = { [weak self] in
            guard let self, !self.stopped, let url = self.request.url else { return }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "image/png",
                    "Content-Length": "\(payload.0.count)"
                ]
            )!
            self.client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            self.client?.urlProtocol(self, didLoad: payload.0)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if payload.1 > 0 {
            DispatchQueue.global().asyncAfter(
                deadline: .now() + payload.1,
                execute: deliver
            )
        } else {
            deliver()
        }
    }

    override func stopLoading() { stopped = true }
}
