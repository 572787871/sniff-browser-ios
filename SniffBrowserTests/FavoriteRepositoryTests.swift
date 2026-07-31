import Foundation
import XCTest
@testable import SniffBrowser

final class FavoriteRepositoryTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "FavoriteRepositoryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        fileURL = temporaryDirectoryURL
            .appendingPathComponent("favorites.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        fileURL = nil
        try super.tearDownWithError()
    }

    func testAddingFavoritePersistsRealPageMetadata() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = makeService(now: { date })
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        let item = try service.addFavorite(title: "示例文章", url: url)

        XCTAssertEqual(item.title, "示例文章")
        XCTAssertEqual(item.url.absoluteString, "https://example.com/article")
        XCTAssertEqual(item.host, "example.com")
        XCTAssertEqual(item.createdAt, date)
        XCTAssertEqual(item.updatedAt, date)
        XCTAssertEqual(try service.allFavorites(), [item])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testEquivalentURLsAreDeduplicatedAndUpdateExistingItem() throws {
        var currentDate = Date(timeIntervalSince1970: 100)
        let service = makeService(now: { currentDate })
        let firstURL = try XCTUnwrap(
            URL(string: "HTTPS://EXAMPLE.COM:443/path#first")
        )
        let first = try service.addFavorite(title: "旧标题", url: firstURL)

        currentDate = Date(timeIntervalSince1970: 200)
        let equivalentURL = try XCTUnwrap(
            URL(string: "https://example.com/path#second")
        )
        let second = try service.addFavorite(
            title: "新标题",
            url: equivalentURL
        )

        XCTAssertEqual(try service.count(), 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.title, "新标题")
        XCTAssertEqual(second.createdAt, first.createdAt)
        XCTAssertEqual(second.updatedAt, currentDate)
        XCTAssertEqual(second.url.absoluteString, "https://example.com/path")
    }

    func testRemovingFavoriteByURLUpdatesRepository() throws {
        let service = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let item = try service.addFavorite(title: "示例", url: url)

        let removed = try service.removeFavorite(for: url)

        XCTAssertEqual(removed, item)
        XCTAssertEqual(try service.count(), 0)
        XCTAssertFalse(try service.isFavorite(url))
    }

    func testNewRepositoryInstanceRestoresFavoritesFromDisk() throws {
        let firstService = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/restored"))
        let saved = try firstService.addFavorite(title: "恢复测试", url: url)

        let restoredService = makeService()

        XCTAssertEqual(try restoredService.allFavorites(), [saved])
        XCTAssertTrue(try restoredService.isFavorite(url))
    }

    func testPersistenceFailureIsThrownAndDoesNotReportSuccess() throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        let blockingFileURL = temporaryDirectoryURL
            .appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockingFileURL)
        let service = FavoriteService(
            repository: FavoriteRepository(
                fileURL: blockingFileURL
                    .appendingPathComponent("favorites.json")
            ),
            notificationCenter: NotificationCenter()
        )

        XCTAssertThrowsError(
            try service.addFavorite(
                title: "保存失败",
                url: try XCTUnwrap(URL(string: "https://example.com/failure"))
            )
        )
    }

    func testInvalidAndInternalURLsCannotBeFavorited() throws {
        let service = makeService()
        let invalidURLs = [
            URL(string: "about:blank"),
            URL(string: "data:text/plain,hello"),
            URL(string: "file:///tmp/page.html"),
            URL(string: "sniff-browser://error")
        ]

        for url in invalidURLs {
            XCTAssertThrowsError(
                try service.addFavorite(title: "不可收藏", url: url)
            )
            XCTAssertEqual(
                try service.actionState(for: url),
                FavoriteActionState(isEnabled: false, isFavorite: false)
            )
        }
        XCTAssertThrowsError(
            try service.addFavorite(title: "空地址", url: nil)
        )
        XCTAssertEqual(try service.count(), 0)
    }

    func testActionStateReflectsAddAndRemoveState() throws {
        let service = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/menu"))

        var state = try service.actionState(for: url)
        XCTAssertTrue(state.isEnabled)
        XCTAssertFalse(state.isFavorite)
        XCTAssertEqual(state.title, "添加收藏")
        XCTAssertEqual(state.systemImageName, "star")

        _ = try service.addFavorite(title: "菜单测试", url: url)
        state = try service.actionState(for: url)
        XCTAssertTrue(state.isFavorite)
        XCTAssertEqual(state.title, "取消收藏")
        XCTAssertEqual(state.systemImageName, "star.fill")

        _ = try service.removeFavorite(for: url)
        XCTAssertFalse(try service.actionState(for: url).isFavorite)
    }

    func testToggleAddsThenRemovesTheSameFavorite() throws {
        let service = makeService()
        let url = try XCTUnwrap(URL(string: "https://example.com/toggle"))

        guard case let .added(addedItem) = try service.toggleFavorite(
            title: "切换测试",
            url: url
        ) else {
            return XCTFail("第一次切换应添加收藏")
        }
        XCTAssertEqual(try service.count(), 1)

        guard case let .removed(removedItem) = try service.toggleFavorite(
            title: "切换测试",
            url: url
        ) else {
            return XCTFail("第二次切换应取消收藏")
        }
        XCTAssertEqual(removedItem, addedItem)
        XCTAssertEqual(try service.count(), 0)
    }

    @MainActor
    func testViewModelCountUpdatesAfterFavoriteChange() async throws {
        let service = makeService()
        let viewModel = FavoritesViewModel(service: service)
        viewModel.reload()
        XCTAssertEqual(viewModel.state.totalCount, 0)

        let countUpdated = expectation(description: "收藏数量实时更新")
        viewModel.onStateChange = { state in
            if state.totalCount == 1 {
                countUpdated.fulfill()
            }
        }
        _ = try service.addFavorite(
            title: "数量测试",
            url: try XCTUnwrap(URL(string: "https://example.com/count"))
        )

        await fulfillment(of: [countUpdated], timeout: 1)
        XCTAssertEqual(viewModel.state.totalCount, 1)
        XCTAssertEqual(viewModel.state.items.count, 1)
    }

    @MainActor
    func testViewModelSearchesTitleHostAndURL() throws {
        let service = makeService()
        _ = try service.addFavorite(
            title: "Swift 文档",
            url: try XCTUnwrap(URL(string: "https://developer.apple.com/swift"))
        )
        _ = try service.addFavorite(
            title: "示例网页",
            url: try XCTUnwrap(URL(string: "https://example.com/article"))
        )
        let viewModel = FavoritesViewModel(service: service)
        viewModel.reload()

        viewModel.updateSearchQuery("APPLE")
        XCTAssertEqual(viewModel.state.items.map(\.title), ["Swift 文档"])

        viewModel.updateSearchQuery("article")
        XCTAssertEqual(viewModel.state.items.map(\.title), ["示例网页"])

        viewModel.updateSearchQuery("")
        XCTAssertEqual(viewModel.state.totalCount, 2)
        XCTAssertEqual(viewModel.state.items.count, 2)
    }

    @MainActor
    func testViewModelDeletionRefreshesListImmediately() throws {
        let service = makeService()
        let item = try service.addFavorite(
            title: "立即删除",
            url: try XCTUnwrap(URL(string: "https://example.com/delete"))
        )
        let viewModel = FavoritesViewModel(service: service)
        viewModel.reload()

        XCTAssertTrue(viewModel.remove(item))

        XCTAssertEqual(viewModel.state.totalCount, 0)
        XCTAssertTrue(viewModel.state.items.isEmpty)
    }

    private func makeService(
        now: @escaping () -> Date = Date.init
    ) -> FavoriteService {
        FavoriteService(
            repository: FavoriteRepository(fileURL: fileURL),
            notificationCenter: NotificationCenter(),
            now: now
        )
    }
}
