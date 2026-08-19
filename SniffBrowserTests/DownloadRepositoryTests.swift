import Foundation
import XCTest
@testable import SniffBrowser

final class DownloadRepositoryTests: XCTestCase {
    func testTasksPersistAndRestoreWithoutSensitiveHeaders() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DownloadRepository(fileURL: root.appendingPathComponent("tasks.json"))
        let timestamp = Date(timeIntervalSince1970: 100)
        let task = DownloadTaskModel(
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/movie.mp4?signature=private")),
            thumbnailURL: try XCTUnwrap(URL(string: "https://example.com/poster.jpg")),
            fileName: "movie.mp4",
            resourceType: .video,
            state: .paused,
            downloadedSize: 1_024,
            createdAt: timestamp,
            updatedAt: timestamp,
            thumbnailLocalPath: "AppSupport/Thumbnails/movie.jpg",
            mediaDuration: 12.5,
            mediaWidth: 1_920,
            mediaHeight: 1_080,
            resumeDataRelativePath: "Downloads/ResumeData/id.resume"
        )

        try await repository.save([task])
        let restored = try await repository.load()

        XCTAssertEqual(restored, [task])
        XCTAssertEqual(restored.first?.thumbnailURL?.lastPathComponent, "poster.jpg")
        XCTAssertEqual(
            restored.first?.thumbnailLocalPath,
            "AppSupport/Thumbnails/movie.jpg"
        )
        XCTAssertEqual(restored.first?.mediaDuration, 12.5)
        XCTAssertEqual(restored.first?.mediaWidth, 1_920)
        XCTAssertEqual(restored.first?.mediaHeight, 1_080)
        let data = try Data(contentsOf: root.appendingPathComponent("tasks.json"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("authorization"))
    }

    func testEmptyRepositoryReturnsNoTasks() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DownloadRepository(fileURL: root.appendingPathComponent("missing.json"))

        let tasks = try await repository.load()
        XCTAssertTrue(tasks.isEmpty)
    }

    func testHiddenDownloadHistoryStatePersistsWithoutRemovingFileMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DownloadRepository(fileURL: root.appendingPathComponent("tasks.json"))
        let task = DownloadTaskModel(
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/movie.mp4")),
            fileName: "movie.mp4",
            resourceType: .video,
            state: .completed,
            downloadedSize: 4_096,
            destinationRelativePath: "Downloads/Videos/movie.mp4",
            isHiddenFromDownloadHistory: true
        )

        try await repository.save([task])
        let loaded = try await repository.load()
        let restored = try XCTUnwrap(loaded.first)

        XCTAssertEqual(restored.isHiddenFromDownloadHistory, true)
        XCTAssertEqual(
            restored.destinationRelativePath,
            "Downloads/Videos/movie.mp4"
        )
    }

    func testLegacyTaskPayloadMigratesWithoutLosingRecord() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("tasks.json")
        let id = UUID()
        let json = """
        [{
          "id":"\(id.uuidString)",
          "sourceURL":"https://example.com/legacy.mp4",
          "fileName":"legacy.mp4",
          "state":"completed",
          "expectedSize":2048,
          "downloadedSize":2048,
          "createdAt":"1970-01-01T00:01:40Z",
          "updatedAt":"1970-01-01T00:01:41Z",
          "destinationRelativePath":"Downloads/Videos/legacy.mp4"
        }]
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let repository = DownloadRepository(fileURL: fileURL)
        let restoredTasks = try await repository.load()
        let task = try XCTUnwrap(restoredTasks.first)

        XCTAssertEqual(task.id, id)
        XCTAssertEqual(task.resourceType, .video)
        XCTAssertEqual(task.downloadKind, .regularFile)
        XCTAssertEqual(task.displayURL, "example.com")
        XCTAssertEqual(task.completedAt, task.updatedAt)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
