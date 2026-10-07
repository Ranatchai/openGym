import XCTest

/// Drives the gestures `simctl` cannot: switching tabs, typing into search and scrolling. Set
/// TEST_RUNNER_SCREENSHOT_DIR on the xcodebuild command line to also save PNGs there.
@MainActor
final class ShellUITests: XCTestCase {
    private func launch(language: String = "en") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))"]
        app.launch()
        return app
    }

    private func open(_ tab: String, in app: XCUIApplication) {
        app.buttons[tab].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
    }

    func testSearchFindsBenchPress() {
        let app = launch()
        open("Exercises", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("bench")
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 5))
        save("search")
    }

    func testScrollKeepsTheAccessory() {
        let app = launch()
        open("Exercises", in: app)
        let accessory = app.descendants(matching: .any)["workout-accessory"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        list.swipeUp(velocity: .fast)
        list.swipeUp(velocity: .slow)
        XCTAssertTrue(accessory.exists)
        save("minimized")
    }

    func testThaiPlanTitle() {
        let app = launch(language: "th")
        open("แผน", in: app)
        save("thai-plan")
    }
}
