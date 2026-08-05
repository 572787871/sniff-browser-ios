import WebKit
import XCTest
@testable import SniffBrowser

final class ContentBlockerServiceTests: XCTestCase {
    func testBundledRulesAreValidAndCompileInChunks() async throws {
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
        let chunkSize = 100
        let chunkCount = Int(ceil(Double(rules.count) / Double(chunkSize)))
        var failedChunks: [Int] = []
        for index in 0..<chunkCount {
            let slice = Array(rules.dropFirst(index * chunkSize).prefix(chunkSize))
            let jsonData = try JSONSerialization.data(withJSONObject: slice)
            let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
            let identifier = "test.adblock.\(UUID().uuidString).\(index)"
            let ruleList = await compile(json, identifier: identifier, store: store)
            if ruleList == nil {
                failedChunks.append(index)
            }
        }
        XCTAssertTrue(
            failedChunks.isEmpty,
            "内置规则分块编译失败：\(failedChunks)"
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
