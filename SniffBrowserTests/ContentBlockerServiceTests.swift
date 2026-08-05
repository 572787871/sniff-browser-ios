import WebKit
import XCTest
@testable import SniffBrowser

final class ContentBlockerServiceTests: XCTestCase {
    func testBundledRulesAreValidAndCompile() async throws {
        let bundle = Bundle(for: ContentBlockerService.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "content-blocker-rules", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let rules = try XCTUnwrap(object as? [[String: Any]])

        XCTAssertFalse(rules.isEmpty)
        XCTAssertLessThanOrEqual(rules.count, 50_000)

        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let identifier = "test.adblock.\(UUID().uuidString)"
        let ruleList = await compile(json, identifier: identifier, store: store)
        XCTAssertNotNil(
            ruleList,
            "内置规则未能通过 WKContentRuleList 编译"
        )
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
