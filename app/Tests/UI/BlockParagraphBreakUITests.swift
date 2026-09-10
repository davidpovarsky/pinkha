import XCTest

final class BlockParagraphBreakUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTitleReturnBlockParagraphSoftBreakAndExplicitAddBlockRemainDistinct() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-data"]
        app.launch()
        let leaf = app.staticTexts["Seeded Leaf 1"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 10)); leaf.tap()

        let title = app.textViews.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        title.typeKey(.return, modifierFlags: [])
        XCTAssertGreaterThanOrEqual(app.textViews.count, 2, "Return in title must create the first block")

        let block = app.textViews.element(boundBy: max(0, app.textViews.count - 1))
        block.tap(); block.typeText("פסקה ראשונה")
        let countBeforeParagraph = app.textViews.count
        block.typeKey(.return, modifierFlags: [])
        block.typeText("פסקה שנייה")
        XCTAssertEqual(app.textViews.count, countBeforeParagraph, "Return inside a block must not create a block")
        block.typeKey(.return, modifierFlags: .shift)
        block.typeText("שורה צמודה")
        XCTAssertEqual(app.textViews.count, countBeforeParagraph, "Shift+Return must stay in the same block")

        app.buttons["Hide Keyboard"].tap()
        app.staticTexts["New block"].tap()
        XCTAssertTrue(app.staticTexts["Add a block"].waitForExistence(timeout: 3)); app.staticTexts["Text"].tap()
        XCTAssertGreaterThan(app.textViews.count, countBeforeParagraph, "The explicit Add Block UI must create a block")
    }

    override func tearDown() {
        if testRun?.hasSucceeded == false {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways; add(attachment)
        }
        super.tearDown()
    }
}
