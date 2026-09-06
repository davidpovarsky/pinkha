import XCTest

final class TorahAssociationsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchLeaf() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-data", "--ui-test-torah-provider"]
        app.launch()
        let leaf = app.staticTexts["Seeded Leaf 1"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 10)); leaf.tap()
        XCTAssertTrue(app.buttons["torahLinksButton"].waitForExistence(timeout: 8))
        return app
    }

    private func add(_ kind: String, query: String, result: String, app: XCUIApplication) {
        app.buttons["torahAddAssociationButton"].tap()
        let kindButton = app.buttons["torahAssociationKind\(kind)"]
        XCTAssertTrue(kindButton.waitForExistence(timeout: 3)); kindButton.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText(query)
        let row = app.staticTexts[result]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.otherElements["torahAssociationSheet"].waitForExistence(timeout: 5))
    }

    func testLeafAddsPersistsAndDeletesReferenceTopicAndWord() {
        let app = launchLeaf()
        app.buttons["torahLinksButton"].tap()
        add("Ref", query: "בראשית א:א", result: "בראשית א׳:א׳ — Genesis 1:1", app: app)
        add("Topic", query: "תפילה", result: "תפילה", app: app)

        app.buttons["torahAddAssociationButton"].tap()
        app.buttons["torahAssociationKindWord"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("בשעריך")
        let lexical = app.staticTexts["שַׁעַר"].firstMatch
        XCTAssertTrue(lexical.waitForExistence(timeout: 5)); lexical.tap()
        XCTAssertTrue(app.staticTexts["בשעריך"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()
        app.buttons["torahLinksButton"].tap()
        XCTAssertTrue(app.staticTexts["בראשית א׳:א׳"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["תפילה"].exists)
        XCTAssertTrue(app.staticTexts["בשעריך"].exists)

        let topic = app.staticTexts["תפילה"]
        topic.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3)); app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["תפילה"].waitForExistence(timeout: 1))
        app.buttons["Done"].tap(); app.buttons["torahLinksButton"].tap()
        XCTAssertFalse(app.staticTexts["תפילה"].exists)
    }

    func testBlockSwipeAndContextMenuOpenTheSamePersistedTarget() {
        let app = launchLeaf()
        app.staticTexts["New block"].tap()
        XCTAssertTrue(app.staticTexts["Add a block"].waitForExistence(timeout: 3))
        app.staticTexts["Text"].tap()
        let editor = app.textViews.lastMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Block Torah target")
        editor.swipeLeft()
        let swipeAction = app.buttons["blockTorahLinksSwipeAction"]
        XCTAssertTrue(swipeAction.waitForExistence(timeout: 3)); swipeAction.tap()
        add("Ref", query: "Genesis 1:1", result: "בראשית א׳:א׳ — Genesis 1:1", app: app)
        app.buttons["Done"].tap()

        editor.press(forDuration: 1.0)
        let contextAction = app.buttons["blockTorahLinksContextMenu"]
        XCTAssertTrue(contextAction.waitForExistence(timeout: 3)); contextAction.tap()
        XCTAssertTrue(app.staticTexts["בראשית א׳:א׳"].waitForExistence(timeout: 5))
    }

    override func tearDown() {
        if testRun?.hasSucceeded == false {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }
}
