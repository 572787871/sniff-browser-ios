import WebKit
import XCTest
@testable import SniffBrowser

final class ContentBlockerRuleBuilderTests: XCTestCase {
    func testBuildsDomainRulesFromFilterText() throws {
        let text = """
        ! Title: Test
        ||ads.example.com^
        ||tracker.net^
        @@||allowed.example^
        ||bad*domain^
        ||nodot^
        || spaced.com^
        ##.ad-banner
        """

        let data = try XCTUnwrap(
            ContentBlockerRuleBuilder.buildJSONData(from: [text])
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(
            (rules[0]["action"] as? [String: Any])?["type"] as? String,
            "block"
        )
        XCTAssertEqual(
            (rules[1]["action"] as? [String: Any])?["type"] as? String,
            "block"
        )
        XCTAssertEqual(
            (rules[2]["action"] as? [String: Any])?["type"] as? String,
            "css-display-none"
        )
        XCTAssertEqual(
            (rules[3]["action"] as? [String: Any])?["type"] as? String,
            "ignore-previous-rules"
        )
        XCTAssertEqual(
            (rules[0]["trigger"] as? [String: Any])?["url-filter"] as? String,
            "^https?://([^/:]+\\.)?ads\\.example\\.com[:/]"
        )
    }

    func testBuildsCosmeticRules() throws {
        let text = """
        ##.ad-banner
        hl365.com##.article-ads-btn
        bad##:has(.x)
        """

        let data = try XCTUnwrap(
            ContentBlockerRuleBuilder.buildJSONData(from: [text])
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        let cosmetics = rules.filter {
            ($0["action"] as? [String: Any])?["type"] as? String
                == "css-display-none"
        }
        XCTAssertEqual(cosmetics.count, 2)
        XCTAssertEqual(
            (cosmetics[0]["trigger"] as? [String: Any])?["url-filter"] as? String,
            ".*"
        )
        XCTAssertNil(
            (cosmetics[0]["trigger"] as? [String: Any])?["if-domain"]
        )
        let scoped = cosmetics[1]
        XCTAssertEqual(
            (scoped["trigger"] as? [String: Any])?["if-domain"] as? [String],
            ["hl365.com"]
        )
        XCTAssertEqual(
            (scoped["action"] as? [String: Any])?["selector"] as? String,
            ".article-ads-btn"
        )
    }

    func testMergesMultipleFilterSources() throws {
        let first = "||ads.example.com^\n"
        let second = "||tracker.net^\n@@||tracker.net^\n"

        let data = try XCTUnwrap(
            ContentBlockerRuleBuilder.buildJSONData(from: [first, second])
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(
            (rules[0]["action"] as? [String: Any])?["type"] as? String,
            "block"
        )
        XCTAssertEqual(
            (rules[1]["action"] as? [String: Any])?["type"] as? String,
            "ignore-previous-rules"
        )
    }

    func testFilterVersionParsing() {
        let version = ContentBlockerRuleBuilder.filterVersion(
            from: "! Version: 2.4.81.60\n||example.com^\n"
        )
        XCTAssertEqual(version, "2.4.81.60")
    }

    func testBuiltRulesCompileWithWebKit() async throws {
        let text = """
        ||ads.example.com^
        ||tracker.net^
        @@||allowed.example^
        """
        let data = try XCTUnwrap(
            ContentBlockerRuleBuilder.buildJSONData(from: [text])
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let identifier = "test.builder.\(UUID().uuidString)"

        let ruleList = await compile(json, identifier: identifier, store: store)

        XCTAssertNotNil(ruleList)
    }

    private func compile(
        _ json: String,
        identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }
}
