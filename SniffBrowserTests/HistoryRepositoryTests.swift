import Foundation
import XCTest
@testable import SniffBrowser

final class HistoryRepositoryTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HistoryRepositoryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        fileURL = temporaryDirectoryURL
            .appendingPathComponent("history.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        fileURL = nil
        try super.tearDownWithError()
    }

    func testRecordingVisitPersistsRealPageMetadata() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = makeService(now: { date })
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        let item = try XCTUnwrap(
            service.recordVisit(title: "示例文章", url: url)
        )

        XCTAssertEqual(item.title, "示例文章")
        XCTAssertEqual(item.url.absoluteString, "https://example.com/article")
        XCTAssertEqual(item.host, "example.com")
        XCTAssertEqual(item.visitedAt, date)
        XCTAssertEqual(try service.allEntries(), [item])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRecentDuplicateVisitUpdatesLatestEntry() throws {
        var currentDate = Date(timeIntervalSince1970: 100)
        let service = makeService(now: { currentDate })
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))

        let first = try XCTUnwrap(
            service.recordVisit(title: "旧标题", url: url)
        )

        currentDate = Date(timeIntervalSince1970: 120)
        let second = try XCTUnwrap(
            service.recordVisit(title: "新标题", url: url)
        )

        XCTAssertEqual(try service.count(), 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.title, "新标题")
        XCTAssertEqual(second.visitedAt, currentDate)
    }

    func testDistinctVisitsCreateSeparateEntries() throws {
        let service = makeService()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/two"))

        _ = try service.recordVisit(title: "第一页", url: firstURL)
        _ = try service.recordVisit(title: "第二页", url: secondURL)

        XCTAssertEqual(try service.count(), 2)
    }

    func testFragmentAndPortAreNormalizedBeforeRecording() throws {
        let service = makeService()
        let url = try XCTUnwrap(
            URL(string: "HTTPS://EXAMPLE.COM:443/path#section")
        )

        let item = try XCTUnwrap(service.recordVisit(title: "归一化", url: url))

        XCTAssertEqual(item.url.absoluteString, "https://example.com/path")
        XCTAssertEqual(item.host, "example.com")
    }

    func testNonHTTPURLIsIgnored() throws {
        let service = makeService()
        let url = try XCTUnwrap(URL(string: "file:///tmp/example.html"))

        XCTAssertNil(try service.recordVisit(title: "本地文件", url: url))
        XCTAssertEqual(try service.count(), 0)
    }

    func testRemovingEntryUpdatesRepository() throws {
        let service = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let item = try XCTUnwrap(service.recordVisit(title: "示例", url: url))

        let removed = try service.removeEntry(id: item.id)

        XCTAssertEqual(removed, item)
        XCTAssertEqual(try service.count(), 0)
    }

    func testClearAllRemovesEveryEntry() throws {
        let service = makeService()
        _ = try service.recordVisit(
            title: "第一页",
            url: try XCTUnwrap(URL(string: "https://example.com/one"))
        )
        _ = try service.recordVisit(
            title: "第二页",
            url: try XCTUnwrap(URL(string: "https://example.com/two"))
        )

        try service.clearAll()

        XCTAssertEqual(try service.count(), 0)
        XCTAssertTrue(try service.allEntries().isEmpty)
    }

    func testNewServiceInstanceRestoresHistoryFromDisk() throws {
        let firstService = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/restored"))
        let saved = try XCTUnwrap(
            firstService.recordVisit(title: "恢复测试", url: url)
        )

        let restoredService = makeService()

        XCTAssertEqual(try restoredService.allEntries(), [saved])
        XCTAssertEqual(try restoredService.count(), 1)
    }

    private func makeService(
        now: @escaping () -> Date = Date.init
    ) -> HistoryService {
        let repository = HistoryRepository(
            fileURL: fileURL,
            fileManager: .default
        )
        return HistoryService(
            repository: repository,
            notificationCenter: .default,
            now: now
        )
    }
}
