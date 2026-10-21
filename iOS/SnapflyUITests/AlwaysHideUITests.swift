import XCTest

/// Always Hide driven on the simulator as the owner would use it, in
/// German: adding a name, choosing a kind from the list and going back,
/// both kinds of rule, an empty rule that cannot be saved, turning a rule
/// off, deleting with a swipe, and the screen with nothing yet. The app
/// holds a made-up set in memory alone (`-SnapflyAlwaysHide`), so nothing
/// is kept.
final class AlwaysHideUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SnapflyAlwaysHide", state, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    /// Waits until the element's label reads as expected, as a row settles.
    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func wait(for query: XCUIElementQuery, count: Int, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "count == %d", count), evaluatedWith: query)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func hasFocus(_ element: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let focused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }

    private func gone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let away = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [away], timeout: timeout) == .completed
    }

    /// Scrolls until the element can be tapped, as a finger would.
    private func reveal(_ element: XCUIElement, in container: XCUIElement) {
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            container.swipeUp(velocity: .slow)
        }
    }

    func testWithNothingYetItOffersTheNameAndTwoKindsOfRule() {
        let app = launch("empty")
        XCTAssertTrue(app.buttons["always-hide-add-name"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["always-hide-template-word"].exists)
        XCTAssertTrue(app.buttons["always-hide-template-label"].exists)
        XCTAssertFalse(app.buttons["always-hide-edit"].exists, "nothing to edit yet")
        XCTAssertFalse(app.buttons.matching(identifier: "always-hide-detail").firstMatch.exists)
    }

    func testANameIsAddedFromItsTwoFields() {
        let app = launch("empty")
        let add = app.buttons["always-hide-add-name"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let given = app.textFields["always-hide-field-given"]
        XCTAssertTrue(given.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(given), "the first field is focused as the sheet opens")
        XCTAssertFalse(app.buttons["always-hide-save-detail"].isEnabled, "nothing typed yet")
        given.typeText("Max\n")
        let surname = app.textFields["always-hide-field-surname"]
        XCTAssertTrue(hasFocus(surname), "Return goes on to the next field")
        surname.typeText("Mustermann")
        XCTAssertTrue(app.buttons["always-hide-save-detail"].isEnabled)
        // Return on the last field adds it.
        surname.typeText("\n")
        let row = app.buttons.matching(identifier: "always-hide-detail").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Max Mustermann"), row.label)
    }

    func testAKindIsChosenFromTheListAndTheWayBackLeadsToIt() {
        let app = launch("filled")
        let add = app.buttons["always-hide-add-detail"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let address = app.buttons["always-hide-kind-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["always-hide-kind-name"].exists)
        XCTAssertTrue(app.buttons["always-hide-kind-card"].exists)
        XCTAssertTrue(app.buttons["always-hide-kind-account"].exists)
        address.tap()
        let street = app.textFields["always-hide-field-street"]
        XCTAssertTrue(street.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(street), "the kind's first field is focused")
        app.buttons["always-hide-back"].tap()
        XCTAssertTrue(app.buttons["always-hide-kind-address"].waitForExistence(timeout: 5), "back at the list")
        app.buttons["always-hide-close"].tap()
        XCTAssertTrue(gone(app.buttons["always-hide-kind-address"]), "the close button closes the sheet")
    }

    func testAWordAndALabelAreAddedAsRulesAndAnEmptyOneCannotBe() {
        let app = launch("empty")
        let word = app.buttons["always-hide-template-word"]
        XCTAssertTrue(word.waitForExistence(timeout: 15))
        word.tap()
        let text = app.textFields["always-hide-rule-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(text))
        XCTAssertFalse(app.buttons["always-hide-save-rule"].isEnabled, "an empty rule is never saved")
        text.typeText("   ")
        XCTAssertFalse(app.buttons["always-hide-save-rule"].isEnabled, "spaces alone are no rule either")
        text.typeText("Musterfirma")
        XCTAssertTrue(app.descendants(matching: .any)["always-hide-preview"].exists)
        app.buttons["always-hide-save-rule"].tap()
        let rules = app.buttons.matching(identifier: "always-hide-rule")
        XCTAssertTrue(wait(for: rules, count: 1))
        XCTAssertTrue(rules.element(boundBy: 0).label.contains("Musterfirma"), rules.element(boundBy: 0).label)
        XCTAssertTrue(rules.element(boundBy: 0).label.contains("Wort · überall im Bild"), rules.element(boundBy: 0).label)

        app.buttons["always-hide-add-rule"].tap()
        let kind = app.segmentedControls["always-hide-rule-kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        kind.buttons["Nach Bezeichnung"].tap()
        let label = app.textFields["always-hide-rule-text"]
        label.tap()
        label.typeText("Kundennummer")
        let reach = app.segmentedControls["always-hide-reach"]
        XCTAssertTrue(reach.waitForExistence(timeout: 2))
        XCTAssertTrue(reach.buttons["Automatisch"].isSelected, "Automatic first, as before")
        reach.buttons["Nächste Zeile"].tap()
        app.buttons["always-hide-save-rule"].tap()
        XCTAssertTrue(wait(for: rules, count: 2))
        XCTAssertTrue(rules.element(boundBy: 1).label.contains("Kundennummer"), rules.element(boundBy: 1).label)
        XCTAssertTrue(rules.element(boundBy: 1).label.contains("Bezeichnung · Nächste Zeile"), rules.element(boundBy: 1).label)
        XCTAssertTrue(wait(for: app.staticTexts["always-hide-active-count"], label: "2 aktiv"))
    }

    func testARuleIsTurnedOffAndOnAgainAndTheCountFollows() {
        let app = launch("filled")
        XCTAssertTrue(app.buttons.matching(identifier: "always-hide-detail").firstMatch.waitForExistence(timeout: 15))
        // The rules stand below the details: scrolled to, as a finger would.
        let rule = app.switches.matching(identifier: "always-hide-rule-switch").firstMatch
        reveal(rule, in: app.collectionViews.firstMatch)
        XCTAssertTrue(rule.isHittable)
        let count = app.staticTexts["always-hide-active-count"]
        XCTAssertTrue(count.exists)
        // As many as the switches that are on.
        let on = app.switches.matching(identifier: "always-hide-rule-switch").allElementsBoundByIndex
            .filter { ($0.value as? String) == "1" }.count
        XCTAssertEqual(count.label, "\(on) aktiv")
        XCTAssertEqual(count.label, "2 aktiv")
        XCTAssertEqual(rule.value as? String, "1")
        XCTAssertTrue(rule.label.contains("Musterfirma"), "the switch says whose it is: \(rule.label)")
        rule.tap()
        XCTAssertTrue(wait(for: count, label: "1 aktiv"))
        XCTAssertEqual(rule.value as? String, "0")
        rule.tap()
        XCTAssertTrue(wait(for: count, label: "2 aktiv"))
    }

    func testADetailIsDeletedWithASwipe() {
        let app = launch("filled")
        let details = app.buttons.matching(identifier: "always-hide-detail")
        XCTAssertTrue(details.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(details.count, 4)
        let card = details.element(boundBy: 2)
        XCTAssertTrue(card.label.contains("4242"), card.label)
        XCTAssertFalse(card.label.contains("4242 4242"), "a card shows by its last four digits: \(card.label)")
        card.swipeLeft()
        let delete = app.buttons["Löschen"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(wait(for: details, count: 3))
        XCTAssertFalse(details.allElementsBoundByIndex.contains { $0.label.contains("4242") })
    }
}
