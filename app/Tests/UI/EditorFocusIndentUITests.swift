import XCTest

final class EditorFocusIndentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchLeaf() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let leaf = app.staticTexts["Seeded Leaf 1"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 10)); leaf.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    private func editableBlock(in app: XCUIApplication) -> XCUIElement {
        app.textViews.element(boundBy: max(1, app.textViews.count - 1))
    }

    func testSystemKeyboardDismissalDoesNotReacquireEditorFocus() throws {
        let app = launchLeaf()
        let editor = editableBlock(in: app)
        editor.tap(); editor.typeText("system-dismiss-focus")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let systemDismiss = app.keyboards.firstMatch.buttons["Hide keyboard"]
        guard systemDismiss.waitForExistence(timeout: 2) else {
            throw XCTSkip("This simulator keyboard does not expose the system dismissal key to XCTest")
        }
        systemDismiss.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1),
                       "editor reclaimed first responder after system dismissal")
    }

    func testLinkAlertOwnsTypingWithoutLeakingIntoBlock() {
        let app = launchLeaf()
        let editor = editableBlock(in: app)
        editor.tap(); editor.typeText("document-before-overlay")
        let link = app.buttons["Add Link"]
        XCTAssertTrue(link.waitForExistence(timeout: 3)); link.tap()
        let field = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap()
        let marker = "overlay-focus-123"
        field.typeText(marker)
        XCTAssertTrue((field.value as? String)?.contains(marker) == true)
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertFalse((editor.value as? String)?.contains(marker) == true)
    }

    func testRepeatedAccessoryAndNativeResponderTransitionsDoNotCrashOrLeak() {
        let app = launchLeaf()
        let editor = editableBlock(in: app)
        for cycle in 0..<10 {
            editor.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let link = app.buttons["Add Link"]
            XCTAssertTrue(link.waitForExistence(timeout: 3)); link.tap()
            let field = app.alerts.firstMatch.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap()
            field.typeText("overlay-\(cycle)")
            app.alerts.firstMatch.buttons["Cancel"].tap()
            XCTAssertFalse((editor.value as? String)?.contains("overlay-\(cycle)") == true)
        }
        editor.tap()
        let hide = app.buttons["Hide Keyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 3)); hide.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    }

    func testParagraphIndentToolbarPersistsAndDoesNotCreateBlock() {
        let app = launchLeaf()
        let editor = editableBlock(in: app)
        editor.tap(); editor.typeText("indent-first")
        editor.typeKey(.return, modifierFlags: [])
        editor.typeText("indent-second")
        let blockCount = app.textViews.count
        let increase = app.buttons["Increase paragraph indent"]
        XCTAssertTrue(increase.waitForExistence(timeout: 3)); increase.tap()
        XCTAssertEqual(app.textViews.count, blockCount)
        let decrease = app.buttons["Decrease paragraph indent"]
        XCTAssertTrue(decrease.isEnabled)
        app.buttons["Hide Keyboard"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        editor.tap()
        XCTAssertTrue(decrease.waitForExistence(timeout: 3))
        XCTAssertTrue(decrease.isEnabled, "paragraph indent was not retained after save/refocus")
        decrease.tap()
        XCTAssertFalse(decrease.isEnabled)
        XCTAssertEqual(app.textViews.count, blockCount)
    }

    func testBlockHierarchyActionsOnlyAppearWhenValid() {
        let app = launchLeaf()
        XCTAssertGreaterThan(app.textViews.count, 1)
        let firstRoot = app.textViews.element(boundBy: 1)
        firstRoot.swipeLeft()
        XCTAssertFalse(app.buttons["Outdent"].exists,
                       "a root block must not offer structural outdent")

        app.staticTexts["New block"].tap()
        XCTAssertTrue(app.staticTexts["Add a block"].waitForExistence(timeout: 3))
        app.staticTexts["Text"].tap()
        let secondRoot = app.textViews.element(boundBy: app.textViews.count - 1)
        secondRoot.tap(); secondRoot.typeText("second-root-for-indent")
        app.buttons["Hide Keyboard"].tap()
        secondRoot.swipeRight()
        let indent = app.buttons["Indent"]
        XCTAssertTrue(indent.waitForExistence(timeout: 3)); indent.tap()
        XCTAssertFalse(app.alerts["Error"].waitForExistence(timeout: 1))
    }

    override func tearDown() {
        if testRun?.hasSucceeded == false {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways; add(attachment)
        }
        super.tearDown()
    }
}
