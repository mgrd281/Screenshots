import XCTest

/// More driven on the simulator as the owner would use it, in German, on
/// made-up choices held in memory alone (`-SnapflyMore`), so nothing is
/// kept: the hero and the tiles count what is on, and say Protection Off
/// with nothing; a pill turns its kind, the counts and the badge follow;
/// the presets set what the buttons of before set; a group's tab shows that
/// group alone; the look and its switches; and the tab bar stays whole on
/// More, hidden under its pages. The `testRecord…` walks are slow on
/// purpose, for the videos `scripts/more-checks.sh` records, and run only
/// there (`SNAPFLY_RECORD`).
final class MoreUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ state: String, _ more: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-SnapflyMore", state, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + more
        if ProcessInfo.processInfo.environment["SNAPFLY_STILL"] != nil { arguments.append("-SnapflyReduceMotion") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits until the element's label reads as expected, as a count settles.
    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func wait(for element: XCUIElement, value: String, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func selected(_ element: XCUIElement, _ on: Bool = true, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "isSelected == %@", NSNumber(value: on)), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func gone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let away = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [away], timeout: timeout) == .completed
    }

    /// Turns a switch with its words beside it, by the switch itself: a tap
    /// on the words does not.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    private func wait(for element: XCUIElement, containing words: String, timeout: TimeInterval = 5) -> Bool {
        let settled = expectation(for: NSPredicate(format: "label CONTAINS %@", words), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    /// Scrolls until the element can be tapped, as a finger would.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
    }

    // MARK: Checks

    func testTheHeroAndTheTilesCountWhatIsOn() {
        let app = launch("root")
        let count = element(app, "more-hero-count")
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        XCTAssertTrue(count.label.hasPrefix("13 von 22"), count.label)
        let status = element(app, "more-hero-status")
        XCTAssertTrue(status.label.contains("Schutz aktiv"), status.label)
        XCTAssertTrue(status.label.contains("Empfohlen"), status.label)
        XCTAssertTrue(app.buttons["more-tile-covered"].label.contains("13 von 22 aktiv"), app.buttons["more-tile-covered"].label)
        XCTAssertTrue(app.buttons["more-tile-always-hide"].label.contains("2 Angaben · 2 Regeln"),
                      app.buttons["more-tile-always-hide"].label)
        XCTAssertTrue(app.buttons["more-chip-style"].label.contains("Geschwärzt"), app.buttons["more-chip-style"].label)
        XCTAssertTrue(app.buttons["more-chip-details"].label.hasSuffix("2"), app.buttons["more-chip-details"].label)
        XCTAssertTrue(app.buttons["more-chip-rules"].label.hasSuffix("2"), app.buttons["more-chip-rules"].label)
    }

    func testWithNothingCoveredTheHeroSaysProtectionOff() {
        let app = launch("off")
        let status = element(app, "more-hero-status")
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertTrue(status.label.contains("Schutz aus"), status.label)
        XCTAssertTrue(status.label.contains("Keine"), status.label)
        XCTAssertTrue(element(app, "more-hero-count").label.hasPrefix("0 von 22"))
    }

    func testAPillTurnsItsKindAndTheCountsFollow() {
        let app = launch("covered")
        let count = element(app, "more-covered-count")
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        XCTAssertEqual(count.label, "13 von 22")
        let badge = element(app, "more-covered-badge")
        XCTAssertEqual(badge.label, "Empfohlen")
        let amounts = app.buttons["more-pill-amounts"]
        reveal(amounts, in: app)
        XCTAssertFalse(amounts.isSelected)
        amounts.tap()
        XCTAssertTrue(wait(for: count, label: "14 von 22"))
        XCTAssertTrue(selected(amounts))
        XCTAssertTrue(wait(for: badge, label: "Eigene Auswahl"))
        XCTAssertFalse(app.buttons["more-preset-recommended"].isSelected, "no preset while the choice is one's own")
        amounts.tap()
        XCTAssertTrue(wait(for: count, label: "13 von 22"))
        XCTAssertTrue(wait(for: badge, label: "Empfohlen"))
        XCTAssertTrue(selected(app.buttons["more-preset-recommended"]))
    }

    func testThePresetsSetWhatTheButtonsOfBeforeSet() {
        let app = launch("covered")
        let count = element(app, "more-covered-count")
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let badge = element(app, "more-covered-badge")
        app.buttons["more-preset-all"].tap()
        XCTAssertTrue(wait(for: count, label: "22 von 22"))
        XCTAssertTrue(wait(for: badge, label: "Alle"))
        XCTAssertTrue(selected(app.buttons["more-pill-amounts"]))
        XCTAssertTrue(selected(app.buttons["more-pill-names"]))
        app.buttons["more-preset-none"].tap()
        XCTAssertTrue(wait(for: count, label: "0 von 22"))
        XCTAssertTrue(wait(for: badge, label: "Keine"))
        XCTAssertTrue(selected(app.buttons["more-pill-names"], false))
        app.buttons["more-preset-recommended"].tap()
        XCTAssertTrue(wait(for: count, label: "13 von 22"))
        XCTAssertTrue(selected(app.buttons["more-pill-names"]))
        XCTAssertTrue(selected(app.buttons["more-pill-amounts"], false))
    }

    func testAGroupsTabShowsItAloneAndItsButtonTurnsItWhole() {
        let app = launch("covered")
        let count = element(app, "more-covered-count")
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let money = app.buttons["tab-money"]
        XCTAssertTrue(money.label.contains("Geld"), money.label)
        money.tap()
        XCTAssertTrue(selected(money))
        XCTAssertTrue(app.buttons["more-pill-amounts"].waitForExistence(timeout: 3))
        XCTAssertTrue(gone(app.buttons["more-pill-names"]), "the other groups go")
        app.buttons["more-group-all-money"].tap()
        XCTAssertTrue(wait(for: count, label: "14 von 22"))
        XCTAssertTrue(wait(for: money, value: "2 von 2 aktiv"), "\(String(describing: money.value))")
        app.buttons["more-group-all-money"].tap()
        XCTAssertTrue(wait(for: count, label: "12 von 22"))
        app.buttons["tab-all"].tap()
        XCTAssertTrue(app.buttons["more-pill-names"].waitForExistence(timeout: 3))
    }

    func testTheLookAndItsSwitchesAreChosen() {
        let app = launch("style")
        let ink = app.buttons["more-style-ink"]
        XCTAssertTrue(ink.waitForExistence(timeout: 15))
        XCTAssertTrue(ink.isSelected)
        let pixels = app.buttons["more-style-pixels"]
        pixels.tap()
        XCTAssertTrue(selected(pixels))
        XCTAssertFalse(ink.isSelected)
        let strongest = app.switches.matching(identifier: "more-toggle-strongest").firstMatch
        reveal(strongest, in: app)
        XCTAssertEqual(strongest.value as? String, "0")
        flip(strongest)
        XCTAssertTrue(wait(for: strongest, value: "1"))
        let digits = app.switches.matching(identifier: "more-toggle-digits").firstMatch
        XCTAssertTrue(wait(for: digits, containing: "ganze Zeilen"), "it says the last four go too: \(digits.label)")
    }

    func testTheTabBarStaysWholeOnMoreAndStepsAsideOnItsPages() {
        let app = launch("root")
        XCTAssertTrue(element(app, "more-hero-count").waitForExistence(timeout: 15))
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.exists)
        let shown = tabs.buttons.count
        XCTAssertGreaterThanOrEqual(shown, 4)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertEqual(tabs.buttons.count, shown, "the tab bar never shrinks to one button on More")
        XCTAssertTrue(tabs.buttons.element(boundBy: 0).isHittable)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.buttons["more-tile-covered"].tap()
        XCTAssertTrue(element(app, "more-covered-count").waitForExistence(timeout: 5))
        let away = expectation(for: NSPredicate(format: "exists == false OR hittable == false"),
                               evaluatedWith: app.tabBars.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [away], timeout: 5), .completed, "no tab bar under a page of More")
    }

    // MARK: Walks for the videos

    private func recording() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPFLY_RECORD"] != nil, "only while recording")
    }

    private func pause(_ seconds: Double = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func testRecordFirstOpen() throws {
        try recording()
        let app = launch("root")
        XCTAssertTrue(element(app, "more-hero-count").waitForExistence(timeout: 15))
        pause(2.5)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        pause()
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        pause()
    }

    func testRecordTileToPage() throws {
        try recording()
        let app = launch("root")
        XCTAssertTrue(element(app, "more-hero-count").waitForExistence(timeout: 15))
        pause(2)
        for tile in ["more-tile-covered", "more-tile-style", "more-tile-detection"] {
            app.buttons[tile].tap()
            pause(1.6)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(1.4)
        }
    }

    func testRecordPillsPresetsAndTabs() throws {
        try recording()
        let app = launch("covered")
        XCTAssertTrue(element(app, "more-covered-count").waitForExistence(timeout: 15))
        pause(1.5)
        for pill in ["more-pill-usernames", "more-pill-faces", "more-pill-organizations"] {
            app.buttons[pill].tap()
            pause(0.9)
        }
        for preset in ["more-preset-all", "more-preset-none", "more-preset-recommended"] {
            app.buttons[preset].tap()
            pause(1.3)
        }
        for tab in ["tab-money", "tab-documents", "tab-access", "tab-all"] {
            app.buttons[tab].tap()
            pause(1.2)
        }
        app.buttons["more-group-all-people"].tap()
        pause(1.3)
        app.buttons["more-group-all-people"].tap()
        pause(1.3)
    }

    func testRecordStyle() throws {
        try recording()
        let app = launch("style")
        XCTAssertTrue(app.buttons["more-style-ink"].waitForExistence(timeout: 15))
        pause(1.5)
        for style in ["more-style-label", "more-style-blur", "more-style-pixels", "more-style-dots", "more-style-erase",
                      "more-style-ink"] {
            app.buttons[style].tap()
            pause(1.1)
        }
        let digits = app.switches.matching(identifier: "more-toggle-digits").firstMatch
        let strongest = app.switches.matching(identifier: "more-toggle-strongest").firstMatch
        reveal(strongest, in: app)
        flip(digits)
        pause(1.4)
        flip(strongest)
        pause(1.6)
        flip(strongest)
        pause(1.4)
        flip(digits)
        pause(1.2)
    }
}
