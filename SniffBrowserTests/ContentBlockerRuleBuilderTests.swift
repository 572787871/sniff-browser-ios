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
            ContentBlockerRuleBuilder.buildJSONData(from: text)
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        XCTAssertEqual(rules.count, 3)
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
            "ignore-previous-rules"
        )
        XCTAssertEqual(
            (rules[0]["trigger"] as? [String: Any])?["url-filter"] as? String,
            "^https?://([^/:]+\\.)?ads\\.example\\.com[:/]"
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
            ContentBlockerRuleBuilder.buildJSONData(from: text)
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
