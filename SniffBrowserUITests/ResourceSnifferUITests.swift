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

    func testResourcePanelRequiresExplicitStart() {
        let snifferButton = app.buttons["browser.toolbar.sniffer"]
        guard snifferButton.waitForExistence(timeout: 8) else {
            XCTFail("资源嗅探入口未出现")
            return
        }

        snifferButton.tap()

        let startButton = app.buttons["sniffer.primary-action"]
        XCTAssertTrue(
            startButton.waitForExistence(timeout: 5),
            "资源嗅探面板应先显示开始嗅探按钮"
        )
        XCTAssertEqual(startButton.label, "开始嗅探")
        XCTAssertFalse(
            app.staticTexts["嗅探中"].exists,
            "未点击开始前不应进入嗅探中状态"
        )
    }
}
