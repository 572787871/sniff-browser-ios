import Foundation
import UIKit
import XCTest
@testable import SniffBrowser

final class ResourceThumbnailLoaderTests: XCTestCase {
    private var retainedTokens: [ResourceThumbnailToken] = []

    override func tearDown() {
        retainedTokens.removeAll()
        ThumbnailURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testHLSPreviewIdentityIgnoresRotatingSignatureButKeepsVariant() throws {
        let first = try XCTUnwrap(URL(
            string: "https://cdn.example.com/video.m3u8?quality=720&auth_key=one"
        ))
        let second = try XCTUnwrap(URL(
            string: "https://cdn.example.com/video.m3u8?quality=720&auth_key=two"
        ))
        let differentVariant = try XCTUnwrap(URL(
            string: "https://cdn.example.com/video.m3u8?quality=1080&auth_key=two"
        ))

        XCTAssertEqual(
            RemoteMediaThumbnailLoader.previewIdentity(for: first),
            RemoteMediaThumbnailLoader.previewIdentity(for: second)
        )
        XCTAssertNotEqual(
            RemoteMediaThumbnailLoader.previewIdentity(for: first),
            RemoteMediaThumbnailLoader.previewIdentity(for: differentVariant)
        )
    }

    @MainActor
    func testMediaPreviewWorkIdentityIsScopedToTab() {
        let firstTab = UUID()
        let secondTab = UUID()
        let cacheKey = "normal|https://cdn.example.com/video.m3u8|240x192"

        XCTAssertEqual(
            RemoteMediaThumbnailLoader.previewWorkIdentity(
                tabID: firstTab,
                cacheKey: cacheKey
            ),
            RemoteMediaThumbnailLoader.previewWorkIdentity(
                tabID: firstTab,
                cacheKey: cacheKey
            )
        )
        XCTAssertNotEqual(
            RemoteMediaThumbnailLoader.previewWorkIdentity(
                tabID: firstTab,
                cacheKey: cacheKey
            ),
            RemoteMediaThumbnailLoader.previewWorkIdentity(
                tabID: secondTab,
                cacheKey: cacheKey
            )
        )
    }

    @MainActor
    func testLoadsAndDownsamplesImageThenUsesMemoryCache() async throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(data: Self.onePixelPNG, mimeType: "image/png")
        let request = try makeRequest(url: "https://example.com/photo.png")

        let first = await load(fixture.loader, request: request, allowsDiskCache: true)
        let second = await load(fixture.loader, request: request, allowsDiskCache: true)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(ThumbnailURLProtocol.requestCount, 1)
    }

    @MainActor
    func testRejectsImageLargerThanConfiguredLimit() async throws {
        let fixture = try makeFixture(maximumBytes: 4)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(data: Self.onePixelPNG, mimeType: "image/png")

        let image = await load(
            fixture.loader,
            request: try makeRequest(url: "https://example.com/too-large.png"),
            allowsDiskCache: false
        )

        XCTAssertNil(image)
    }

    @MainActor
    func testPrivateThumbnailDoesNotWriteDiskCache() async throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(data: Self.onePixelPNG, mimeType: "image/png")

        _ = await load(
            fixture.loader,
            request: try makeRequest(url: "https://example.com/private.png"),
            allowsDiskCache: false
        )

        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(files.isEmpty)
    }

    @MainActor
    func testPrivateRequestDoesNotReuseNormalTabCacheEntry() async throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(data: Self.onePixelPNG, mimeType: "image/png")
        let request = try makeRequest(url: "https://example.com/scoped.png")

        _ = await load(fixture.loader, request: request, allowsDiskCache: true)
        _ = await load(fixture.loader, request: request, allowsDiskCache: false)

        XCTAssertEqual(ThumbnailURLProtocol.requestCount, 2)
    }

    @MainActor
    func testLoadsInlineImageWithoutStartingAURLSessionRequest() async throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let dataURL = try XCTUnwrap(URL(string: "data:image/png;base64,AAAA"))
        let request = ResourceThumbnailRequest(
            resourceID: UUID(),
            tabID: UUID(),
            request: URLRequest(url: dataURL),
            targetPixelSize: CGSize(width: 80, height: 80),
            allowsDiskCache: false,
            inlineData: Self.onePixelPNG
        )

        let image = await withCheckedContinuation { continuation in
            let token = fixture.loader.load(request) { image in
                continuation.resume(returning: image)
            }
            retainedTokens.append(token)
        }

        XCTAssertNotNil(image)
        XCTAssertEqual(ThumbnailURLProtocol.requestCount, 0)
    }

    @MainActor
    func testRejectsHTMLReturnedForAnImageURL() async throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(
            data: Data("<html>blocked</html>".utf8),
            mimeType: "text/html"
        )

        let image = await load(
            fixture.loader,
            request: try makeRequest(url: "https://example.com/protected-image"),
            allowsDiskCache: false
        )

        XCTAssertNil(image)
        XCTAssertEqual(ThumbnailURLProtocol.requestCount, 1)
    }

    @MainActor
    func testCancellationSuppressesCompletion() throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(
            data: Self.onePixelPNG,
            mimeType: "image/png",
            delay: 0.5
        )
        let completion = expectation(description: "cancelled completion")
        completion.isInverted = true
        let request = ResourceThumbnailRequest(
            resourceID: UUID(),
            tabID: UUID(),
            request: try makeRequest(url: "https://example.com/slow.png"),
            targetPixelSize: CGSize(width: 80, height: 80),
            allowsDiskCache: false
        )

        let token = fixture.loader.load(request) { _ in completion.fulfill() }
        token.cancel()

        wait(for: [completion], timeout: 0.7)
    }

    @MainActor
    func testClosingTabCancelsItsPendingThumbnailRequests() throws {
        let fixture = try makeFixture(maximumBytes: 5 * 1_024 * 1_024)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ThumbnailURLProtocol.configure(
            data: Self.onePixelPNG,
            mimeType: "image/png",
            delay: 0.5
        )
        let tabID = UUID()
        let completion = expectation(description: "closed tab completion")
        completion.isInverted = true
        let request = ResourceThumbnailRequest(
            resourceID: UUID(),
            tabID: tabID,
            request: try makeRequest(url: "https://example.com/closing.png"),
            targetPixelSize: CGSize(width: 80, height: 80),
            allowsDiskCache: false
        )

        retainedTokens.append(fixture.loader.load(request) { _ in
            completion.fulfill()
        })
        fixture.loader.cancelRequests(for: tabID)

        wait(for: [completion], timeout: 0.7)
    }

    @MainActor
    private func load(
        _ loader: ResourceThumbnailLoader,
        request: URLRequest,
        allowsDiskCache: Bool
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let token = loader.load(
                ResourceThumbnailRequest(
                    resourceID: UUID(),
                    tabID: UUID(),
                    request: request,
                    targetPixelSize: CGSize(width: 80, height: 80),
                    allowsDiskCache: allowsDiskCache
                )
            ) { image in
                continuation.resume(returning: image)
            }
            retainedTokens.append(token)
        }
    }

    private func makeFixture(
        maximumBytes: Int
    ) throws -> (
        root: URL,
        cacheDirectory: URL,
        loader: ResourceThumbnailLoader
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThumbnailURLProtocol.self]
        let cache = ResourceThumbnailCache(directoryURL: cacheDirectory)
        return (
            root,
            cacheDirectory,
            ResourceThumbnailLoader(
                sessionConfiguration: configuration,
                cache: cache,
                maximumNetworkBytes: maximumBytes
            )
        )
    }

    private func makeRequest(url: String) throws -> URLRequest {
        URLRequest(url: try XCTUnwrap(URL(string: url)))
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private final class ThumbnailURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var responseMIMEType = "image/png"
    private static var responseDelay: TimeInterval = 0
    private static var internalRequestCount = 0
    private var stopped = false

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return internalRequestCount
    }

    static func configure(data: Data, mimeType: String, delay: TimeInterval = 0) {
        lock.lock()
        responseData = data
        responseMIMEType = mimeType
        responseDelay = delay
        internalRequestCount = 0
        lock.unlock()
    }

    static func reset() {
        configure(data: Data(), mimeType: "image/png")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let payload: (Data, String, TimeInterval) = Self.lock.withLock {
            Self.internalRequestCount += 1
            return (Self.responseData, Self.responseMIMEType, Self.responseDelay)
        }
        let deliver = { [weak self] in
            guard let self, !self.stopped, let url = self.request.url else { return }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": payload.1,
                    "Content-Length": "\(payload.0.count)"
                ]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: payload.0)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if payload.2 > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + payload.2, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() { stopped = true }
}
