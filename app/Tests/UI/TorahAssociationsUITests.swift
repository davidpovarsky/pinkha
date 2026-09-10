import XCTest

final class TorahAssociationsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchLeaf(hebrew: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-data", "--ui-test-torah-provider"]
        if hebrew {
            app.launchArguments += ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        } else {
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
        app.launch()
        let leaf = app.staticTexts["Seeded Leaf 1"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 10)); leaf.tap()
        XCTAssertTrue(app.buttons["torahAddLinkButton"].waitForExistence(timeout: 8))
        return app
    }

    private func openSearch(_ kind: String, app: XCUIApplication) {
        let addButtons = app.buttons.matching(identifier: "torahAddLinkButton")
        let add = addButtons.allElementsBoundByIndex.first(where: \.isHittable) ?? addButtons.firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.buttons["torahAssociationKindRef"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["torahAssociationKindWord"].exists)
        XCTAssertTrue(app.buttons["torahAssociationKindTopic"].exists)
        app.buttons["torahAssociationKind\(kind)"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["torah\(kind)SearchSheet"].waitForExistence(timeout: 5))
    }

    private func enter(_ query: String, app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        search.typeText(query)
    }

    private func addFromLeaf(_ kind: String, query: String, resultIdentifier: String, app: XCUIApplication) {
        openSearch(kind, app: app)
        enter(query, app: app)
        let row = app.buttons[resultIdentifier]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["torahAddLinkButton"].waitForExistence(timeout: 5))
    }

    func testHebrewPartialReferenceUsesCompletionKeyAndDismissesWithoutValidationError() {
        let app = launchLeaf()
        openSearch("Ref", app: app)
        enter("ראש הש", app: app)

        XCTAssertFalse(app.buttons["Validate"].exists)
        let result = app.buttons["torahReferenceResult.Rosh Hashanah 16b"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "ראש השנה ט״ז ב׳")
        result.tap()

        XCTAssertFalse(app.alerts["Error"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["torahAddLinkButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ראש השנה ט״ז ב׳"].waitForExistence(timeout: 5))
    }

    func testLeafPreviewLimitsToTwoManagesAllAndRefreshesAfterDelete() {
        let app = launchLeaf()
        addFromLeaf("Ref", query: "ראש הש", resultIdentifier: "torahReferenceResult.Rosh Hashanah 16b", app: app)
        addFromLeaf("Topic", query: "תפילה", resultIdentifier: "torahTopicResult.prayer", app: app)
        addFromLeaf("Word", query: "בשעריך", resultIdentifier: "torahWordResult.BDB|שַׁעַר|1", app: app)

        let previewRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "torahLeafPreviewRow."))
        XCTAssertEqual(previewRows.count, 2)
        let more = app.buttons["torahLeafPreviewMoreButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 3)); XCTAssertEqual(more.label, "+1 more")
        more.tap()

        XCTAssertTrue(app.descendants(matching: .any)["torahAssociationSheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ראש השנה ט״ז ב׳"].exists)
        XCTAssertTrue(app.staticTexts["תפילה"].exists)
        XCTAssertTrue(app.staticTexts["בשעריך"].exists)

        let topic = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "torahAssociationRow.", "תפילה")
        ).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 3))
        let swipeStart = topic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let swipeEnd = topic.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        swipeStart.press(forDuration: 0.2, thenDragTo: swipeEnd)
        let delete = app.buttons["torahDeleteAssociationButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3)); delete.tap()
        XCTAssertFalse(app.staticTexts["תפילה"].waitForExistence(timeout: 1))
        app.buttons["Done"].tap()

        XCTAssertFalse(app.buttons["torahLeafPreviewMoreButton"].waitForExistence(timeout: 1))
        XCTAssertEqual(previewRows.count, 2)
        previewRows.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["torahAssociationSheet"].waitForExistence(timeout: 5))
    }

    func testBlockSwipeAndContextMenuOpenSameTargetWithoutLeakingIntoLeafPreview() {
        let app = launchLeaf()
        app.staticTexts["New block"].tap()
        XCTAssertTrue(app.staticTexts["Add a block"].waitForExistence(timeout: 3))
        app.staticTexts["Text"].tap()
        let editor = app.textViews.element(boundBy: max(0, app.textViews.count - 1))
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Block Torah target")
        app.buttons["Hide Keyboard"].tap()
        editor.swipeLeft()
        let swipeAction = app.buttons["blockTorahLinksSwipeAction"]
        XCTAssertTrue(swipeAction.waitForExistence(timeout: 3)); swipeAction.tap()
        openSearch("Ref", app: app)
        enter("Genesis 1:1", app: app)
        let result = app.buttons["torahReferenceResult.Genesis 1:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["torahAssociationSheet"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        XCTAssertFalse(app.staticTexts["בראשית א׳:א׳"].exists)
        editor.press(forDuration: 1.0)
        let contextAction = app.buttons["blockTorahLinksContextMenu"]
        XCTAssertTrue(contextAction.waitForExistence(timeout: 3)); contextAction.tap()
        XCTAssertTrue(app.staticTexts["בראשית א׳:א׳"].waitForExistence(timeout: 5))
    }

    func testHebrewLocaleShowsLocalizedTopTorahControls() {
        let app = launchLeaf(hebrew: true)
        let add = app.buttons["torahAddLinkButton"]
        XCTAssertEqual(add.label, "הוסף קישור תורני")
        add.tap()
        XCTAssertTrue(app.buttons["torahAssociationKindRef"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["torahAssociationKindRef"].label, "מקור")
        XCTAssertEqual(app.buttons["torahAssociationKindWord"].label, "מילה")
        XCTAssertEqual(app.buttons["torahAssociationKindTopic"].label, "נושא")
    }

    func testInspectorLifecycleDismissesWhenLeafPopped() {
        let app = launchLeaf()
        addFromLeaf("Ref", query: "ראש הש", resultIdentifier: "torahReferenceResult.Rosh Hashanah 16b", app: app)
        let refPreview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "torahLeafPreviewRow.")).firstMatch
        XCTAssertTrue(refPreview.waitForExistence(timeout: 5))

        refPreview.press(forDuration: 1.0)
        let openInspector = app.buttons["Open in Inspector"]
        XCTAssertTrue(openInspector.waitForExistence(timeout: 3))
        openInspector.tap()

        let inspectorClose = app.buttons["Close"]
        let inspectorTitle = app.staticTexts["ראש השנה ט״ז ב׳"]
        let inspectorExists = inspectorClose.waitForExistence(timeout: 5) || inspectorTitle.waitForExistence(timeout: 5)
        XCTAssertTrue(inspectorExists)

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        XCTAssertTrue(app.staticTexts["Seeded Leaf 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(inspectorClose.exists)
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
