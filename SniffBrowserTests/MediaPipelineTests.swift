import XCTest
@testable import SniffBrowser

final class MediaPipelineTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MediaPipelineTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testDetectsByExtension() {
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: URL(string: "https://example.com/video.mp4")!,
                contentType: nil
            ),
            .mp4
        )
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: URL(string: "https://example.com/video.m3u8")!,
                contentType: nil
            ),
            .hls
        )
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: URL(string: "https://example.com/video.mkv")!,
                contentType: nil
            ),
            .mkv
        )
    }

    func testDetectsByContentType() {
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: nil,
                contentType: "application/vnd.apple.mpegurl"
            ),
            .hls
        )
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: nil,
                contentType: "video/webm"
            ),
            .webm
        )
        XCTAssertEqual(
            MediaTypeDetector.detect(
                url: nil,
                contentType: "application/dash+xml"
            ),
            .dash
        )
    }

    func testDetectsByMagicBytes() {
        let mp4 = Data([
            0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
            0x69, 0x73, 0x6F, 0x6D,
        ])
        XCTAssertEqual(
            MediaTypeDetector.detect(url: nil, contentType: nil, magicBytes: mp4),
            .mp4
        )

        let flv = Data([0x46, 0x4C, 0x56, 0x01])
        XCTAssertEqual(
            MediaTypeDetector.detect(url: nil, contentType: nil, magicBytes: flv),
            .flv
        )
    }

    func testCacheManagerCreatesAndRemovesWorkDirectory() throws {
        let taskID = UUID()
        let cache = CacheManager()
        let directory = try cache.makeWorkDirectory(taskID: taskID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        cache.removeWorkDirectory(taskID: taskID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testFileStorageUniqueNaming() throws {
        let storage = FileStorageManager()
        let first = storage.uniqueDestination(
            fileName: "电影.mp4",
            preferredExtension: "mp4"
        )
        try Data().write(to: first)
        let second = storage.uniqueDestination(
            fileName: "电影.mp4",
            preferredExtension: "mp4"
        )
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(second.lastPathComponent.contains("-1"))
    }

    func testStoreFinalFileSkipsMoveWhenSourceIsAlreadyInVideosDirectory() throws {
        let storage = FileStorageManager()
        try FileManager.default.createDirectory(
            at: storage.videosDirectory,
            withIntermediateDirectories: true
        )
        let source = storage.videosDirectory.appendingPathComponent("movie.mp4")
        try Data("video".utf8).write(to: source)

        let stored = try storage.storeFinalFile(
            from: source,
            fileName: "movie.mp4",
            extension: "mp4"
        )

        // 源文件已在最终目录时保持原名，不得改名为 “movie 2.mp4”。
        XCTAssertEqual(stored.path, source.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
    }

    func testPostProcessRejectsInvalidSource() async {
        let invalid = temporaryDirectoryURL.appendingPathComponent("note.txt")
        try? "not a media file".data(using: .utf8)?.write(to: invalid)

        let result = await MediaPipeline.shared.postProcess(
            taskID: UUID(),
            sourceURL: invalid,
            preferredType: .unknown,
            fileName: "note"
        )

        XCTAssertNil(result)
    }
}
