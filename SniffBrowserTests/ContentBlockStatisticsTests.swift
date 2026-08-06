import XCTest
@testable import SniffBrowser

@MainActor
final class ContentBlockStatisticsTests: XCTestCase {
    func testRangeSummariesAggregateDailyHistory() {
        let manager = StatisticsManager(store: ContentBlockStore())
        manager.reset()
        manager.recordBlockedElements(3)
        manager.recordBlockedElements(4)
        manager.recordPageLoad()

        let today = manager.summary(for: .today)
        XCTAssertEqual(today.todayBlocked, 7)
        XCTAssertEqual(today.todayPageLoads, 1)

        let all = manager.summary(for: .all)
        XCTAssertEqual(all.todayBlocked, 7)
        XCTAssertEqual(all.todayPageLoads, 1)
        XCTAssertEqual(all.ruleCount, today.ruleCount)
    }

    func testSparklineSeriesFollowRangeSize() {
        let manager = StatisticsManager(store: ContentBlockStore())
        // “今日”范围的最小趋势窗口为 7 天，保证卡片趋势图有足够曲线。
        XCTAssertEqual(manager.sparkline(for: .today, kind: .blocked).count, 7)
        XCTAssertEqual(manager.sparkline(for: .week, kind: .pageLoads).count, 7)
        XCTAssertEqual(manager.sparkline(for: .month, kind: .blocked).count, 30)
        XCTAssertEqual(manager.sparkline(for: .today, kind: .ruleCount).count, 7)
        XCTAssertEqual(
            manager.sparkline(for: .week, kind: .filterCount).count,
            7
        )
    }

    func testMetricTitlesFollowSelectedRange() {
        XCTAssertEqual(StatisticsRange.today.metricTitle(for: .blocked), "今日拦截")
        XCTAssertEqual(StatisticsRange.week.metricTitle(for: .pageLoads), "近7日访问")
        XCTAssertEqual(StatisticsRange.month.metricTitle(for: .blocked), "近30日拦截")
        XCTAssertEqual(StatisticsRange.all.metricTitle(for: .pageLoads), "累计访问")
    }
}
