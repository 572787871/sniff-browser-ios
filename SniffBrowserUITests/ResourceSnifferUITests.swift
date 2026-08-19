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

    func testStartingResourceSnifferKeepsThePanelAlive() {
        let snifferButton = app.buttons["browser.toolbar.sniffer"]
        guard snifferButton.waitForExistence(timeout: 8) else {
            XCTFail("资源嗅探入口未出现")
            return
        }
        snifferButton.tap()

        let startButton = app.buttons["sniffer.primary-action"]
        guard startButton.waitForExistence(timeout: 5) else {
            XCTFail("开始嗅探按钮未出现")
            return
        }
        startButton.tap()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "点击开始嗅探后应用不应退出"
        )
        XCTAssertTrue(
            app.buttons["sniffer.primary-action"].waitForExistence(timeout: 5),
            "启动完成或失败后资源面板都应保持可操作"
        )
    }
}
