import Foundation
import XCTest
@testable import SniffBrowser

final class DownloadFileStorageTests: XCTestCase {
    func testStoresFilesByTypeAndRenamesConflicts() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = try fixture.storage.storeDownloadedFile(
            from: try temporaryFile(in: fixture.root, name: "first.tmp"),
            preferredFileName: "movie.mp4",
            resourceType: .video
        )
        let second = try fixture.storage.storeDownloadedFile(
            from: try temporaryFile(in: fixture.root, name: "second.tmp"),
            preferredFileName: "movie.mp4",
            resourceType: .video
        )

        XCTAssertTrue(first.relativePath.hasPrefix("Downloads/Videos/"))
        XCTAssertEqual(first.fileURL.lastPathComponent, "movie.mp4")
        XCTAssertEqual(second.fileURL.lastPathComponent, "movie 2.mp4")
    }

    func testAllResourceTypesUseExpectedDirectories() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let expected: [(ResourceType, String)] = [
            (.video, "Videos"), (.audio, "Audio"), (.image, "Images"),
            (.document, "Documents"), (.subtitle, "Subtitles"),
            (.archive, "Archives"), (.hls, "Videos"), (.other, "Other")
        ]

        for (index, pair) in expected.enumerated() {
            let stored = try fixture.storage.storeDownloadedFile(
                from: try temporaryFile(in: fixture.root, name: "\(index).tmp"),
                preferredFileName: "file-\(index)",
                resourceType: pair.0
            )
            XCTAssertTrue(stored.relativePath.contains("/\(pair.1)/"))
        }
    }

    func testRejectsPathTraversalWhenResolving() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertNil(fixture.storage.fileURL(relativePath: "../secret"))
        XCTAssertNil(fixture.storage.fileURL(relativePath: "/etc/passwd"))
    }

    func testHLSAssetPackageReportsRecursiveByteCount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = fixture.root.appendingPathComponent(
            "Offline.movpkg",
            isDirectory: true
        )
        let media = package.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.createDirectory(
            at: media,
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 12).write(
            to: package.appendingPathComponent("manifest")
        )
        try Data(repeating: 2, count: 30).write(
            to: media.appendingPathComponent("segment")
        )

        let stored = try fixture.storage.storeHLSAssetPackage(
            from: package,
            preferredFileName: "Offline"
        )

        XCTAssertEqual(stored.byteCount, 42)
        XCTAssertTrue(stored.relativePath.hasPrefix("Container/"))
    }

    func testStoresSelfContainedHLSVideoPackageInVideosDirectory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let work = fixture.root.appendingPathComponent("work", isDirectory: true)
        let media = work.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("#EXTM3U\n#EXT-X-ENDLIST\n".utf8).write(
            to: work.appendingPathComponent("index.m3u8")
        )
        try Data(repeating: 7, count: 128).write(
            to: media.appendingPathComponent("segment-000000.ts")
        )

        let stored = try fixture.storage.storeHLSVideoPackage(
            from: work,
            preferredFileName: "Sample.m3u8"
        )

        XCTAssertTrue(stored.relativePath.hasPrefix("Downloads/Videos/"))
        XCTAssertEqual(stored.fileURL.pathExtension, "sniffhls")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: stored.fileURL.appendingPathComponent("index.m3u8").path
        ))
        XCTAssertEqual(stored.byteCount, 151)
    }

    private func makeFixture() throws -> (root: URL, storage: DownloadFileStorage) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (
            root,
            DownloadFileStorage(documentsURL: documents, applicationSupportURL: support)
        )
    }

    private func temporaryFile(in root: URL, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("payload".utf8).write(to: url)
        return url
    }
}
