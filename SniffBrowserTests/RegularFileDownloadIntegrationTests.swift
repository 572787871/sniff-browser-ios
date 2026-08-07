import Foundation
import XCTest
@testable import SniffBrowser

/// 真实网络集成测试：验证常规文件（图片/文档/文本）的下载校验与存储链路。
final class RegularFileDownloadIntegrationTests: XCTestCase {

    private var storage: DownloadFileStorage!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegularDownload-\(UUID().uuidString)", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("AppSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storage = DownloadFileStorage(documentsURL: documents, applicationSupportURL: support)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func download(_ urlString: String) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(URL(string: urlString))
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        return try await URLSession.shared.data(for: request)
    }

    private func validateAndStore(
        data: Data,
        response: URLResponse,
        name: String,
        type: ResourceType
    ) throws -> StoredDownloadFile {
        // 模拟 BackgroundFileDownloadService 的临时文件路径
        let temp = root.appendingPathComponent("tmp-\(UUID().uuidString)")
        try data.write(to: temp)
        try DownloadResponseValidator.validate(response: response, filePrefix: data.prefix(256))
        let fileName = BackgroundFileDownloadService.fileNameWithFallbackExtension(
            name,
            mimeType: response.mimeType
        )
        return try storage.storeDownloadedFile(
            from: temp,
            preferredFileName: fileName,
            resourceType: type
        )
    }

    func testImagePNGDownloadStoresCorrectly() async throws {
        let (data, response) = try await download(
            "https://www.w3.org/Icons/w3c_home.png"
        )
        let stored = try validateAndStore(
            data: data,
            response: response,
            name: "photo",
            type: .image
        )
        XCTAssertEqual(stored.fileURL.pathExtension, "png")
        XCTAssertTrue(stored.relativePath.hasPrefix("Images/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual([UInt8](data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testPDFDownloadStoresCorrectly() async throws {
        let (data, response) = try await download(
            "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"
        )
        let stored = try validateAndStore(
            data: data,
            response: response,
            name: "dummy",
            type: .document
        )
        XCTAssertEqual(stored.fileURL.pathExtension, "pdf")
        XCTAssertTrue(stored.relativePath.hasPrefix("Documents/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual([UInt8](data.prefix(4)), [0x25, 0x50, 0x44, 0x46]) // %PDF
    }

    func testTextFileDownloadStoresCorrectly() async throws {
        let (data, response) = try await download(
            "https://raw.githubusercontent.com/FFmpeg/FFmpeg/n7.1/LICENSE.md"
        )
        let stored = try validateAndStore(
            data: data,
            response: response,
            name: "license.md",
            type: .document
        )
        XCTAssertTrue(stored.relativePath.hasPrefix("Documents/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual(stored.fileURL.pathExtension, "md")
    }
}

    func testGoogleHostedPNGDownloadStoresCorrectly() async throws {
        let (data, response) = try await download(
            "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"
        )
        let stored = try validateAndStore(
            data: data,
            response: response,
            name: "googlelogo",
            type: .image
        )
        XCTAssertEqual(stored.fileURL.pathExtension, "png")
        XCTAssertTrue(stored.relativePath.hasPrefix("Images/"))
        XCTAssertEqual([UInt8](data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
