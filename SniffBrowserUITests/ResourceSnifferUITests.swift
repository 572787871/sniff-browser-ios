import XCTest

final class ResourceSnifferUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()
    }

    func testBrowserLaunchesWithResourceToolbarEntry() {
        let snifferButton = app.buttons["browser.toolbar.sniffer"]
        XCTAssertTrue(
            snifferButton.waitForExistence(timeout: 8),
            "浏览器工具栏应提供资源嗅探入口"
        )
    }

    func testToolbarEntryStartsSniffingWithoutSecondAction() {
        let snifferButton = app.buttons["browser.toolbar.sniffer"]
        guard snifferButton.waitForExistence(timeout: 8) else {
            XCTFail("资源嗅探入口未出现")
            return
        }

        snifferButton.tap()

        let title = app.staticTexts["sniffer.title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "点击工具栏按钮后应打开资源嗅探面板"
        )
        XCTAssertFalse(
            app.buttons["sniffer.primary-action"].exists,
            "资源面板不应再要求二次点击开始嗅探"
        )

        let status = app.staticTexts["sniffer.status"]
        XCTAssertTrue(
            status.waitForExistence(timeout: 5),
            "资源面板应显示嗅探状态"
        )
        XCTAssertFalse(
            status.label.contains("未开始"),
            "打开资源面板后应立即尝试启动嗅探"
        )
    }

    func testAutomaticResourceSniffingKeepsThePanelAlive() {
        let snifferButton = app.buttons["browser.toolbar.sniffer"]
        guard snifferButton.waitForExistence(timeout: 8) else {
            XCTFail("资源嗅探入口未出现")
            return
        }
        snifferButton.tap()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "自动开始嗅探后应用不应退出"
        )
        XCTAssertTrue(
            app.staticTexts["sniffer.title"].waitForExistence(timeout: 5),
            "启动完成或失败后资源面板都应保持显示"
        )
    }
}
