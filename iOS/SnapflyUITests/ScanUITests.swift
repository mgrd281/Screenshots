import XCTest

/// Scan driven on the simulator as the owner would use it, in German, on
/// made-up photos of a made-up invoice (`-SnapflyScan`), made ready as any
/// photo is: the tab offers the camera and Photos with its new lines; a page
/// opens in Review once cleaned, its card saying what was done and covered;
/// Compare is one adjustable comparison, and a finger moves its divider; a
/// blurred page says so and offers to take it again; the colours are three,
/// and Black and White holds for every page; deleting a page asks first;
/// corners are set by hand where Vision is not sure; Save and Share starts
/// with covers every time and warns without them, and a copy without covers
/// says so. The `testRecord…` walks are slow on purpose, for the videos
/// `scripts/scan-checks.sh` records, and run only there (`SNAPFLY_RECORD`).
final class ScanUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Long enough for the made-up photos to be made ready on the simulator.
    private static let ready: TimeInterval = 120

    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-SnapflyScan", state, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if ProcessInfo.processInfo.environment["SNAPFLY_STILL"] != nil { arguments.append("-SnapflyReduceMotion") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Anything on the screen whose words hold these.
    private func words(_ app: XCUIApplication, _ words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    private func wait(_ element: XCUIElement, _ format: String, _ value: Any, timeout: TimeInterval = 10) -> Bool {
        let settled = expectation(for: NSPredicate(format: format, argumentArray: [value]), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    private func gone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let away = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [away], timeout: timeout) == .completed
    }

    /// The page's card once it is clean and its copy checked, or its warning.
    private func card(_ app: XCUIApplication) -> XCUIElement {
        let good = element(app, "scan-status-good"), warning = element(app, "scan-status-warning")
        let either = expectation(for: NSPredicate { _, _ in good.exists || warning.exists }, evaluatedWith: nil)
        _ = XCTWaiter.wait(for: [either], timeout: Self.ready)
        return good.exists ? good : warning
    }

    // MARK: Checks

    func testTheTabOffersTheCameraAndPhotosWithItsNewLines() {
        let app = launch("tab")
        XCTAssertTrue(element(app, "scan-photos").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "scan-camera").exists)
        XCTAssertTrue(words(app, "Aus Fotos wählen").exists)
        XCTAssertTrue(words(app, "Gerade gerückt, aufgehellt und mit abgedeckten privaten Angaben").exists)
        XCTAssertTrue(words(app, "Neu:").exists)
        XCTAssertTrue(words(app, "Halte dein iPhone über die Seite. Sie wird").exists)
        XCTAssertTrue(words(app, "als PDF oder Bild").exists)
        XCTAssertFalse(words(app, "bevor irgendetwas").exists, "the old promise is gone")
        XCTAssertTrue(element(app, "scan-page-1").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(element(app, "scan-page-2").exists)
        XCTAssertTrue(element(app, "scan-save-share").exists)
    }

    func testAPageOpensInReviewSayingWhatWasDone() {
        let app = launch("editor")
        let card = element(app, "scan-status-good")
        XCTAssertTrue(card.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(card.label.contains("Gerade gerückt und aufgehellt"), card.label)
        XCTAssertTrue(card.label.contains("abgedeckt") || card.label.contains("Keine privaten Angaben"), card.label)
        XCTAssertTrue(app.navigationBars["Prüfen"].exists)
        XCTAssertTrue(element(app, "scan-next").exists)
        let thumb = element(app, "scan-thumb-1")
        XCTAssertTrue(thumb.label.hasPrefix("Seite 1 von 1"), thumb.label)
        XCTAssertTrue(thumb.isSelected)
        for tool in ["scan-compare", "scan-crop", "scan-turn", "scan-color", "scan-delete", "scan-add"] {
            XCTAssertTrue(element(app, tool).exists, tool)
        }
    }

    func testCompareIsOneAdjustableComparison() {
        let app = launch("editor")
        XCTAssertTrue(card(app).exists)
        element(app, "scan-compare").tap()
        let canvas = element(app, "protect-canvas")
        XCTAssertTrue(wait(canvas, "label == %@", "Vergleich Vorher und Nachher"), canvas.label)
        XCTAssertTrue((canvas.value as? String)?.contains("50") == true, String(describing: canvas.value))
        // A finger moves the divider.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)))
        XCTAssertTrue(wait(canvas, "NOT (value CONTAINS %@)", "50"), String(describing: canvas.value))
        element(app, "scan-compare").tap()
        XCTAssertTrue(wait(canvas, "label != %@", "Vergleich Vorher und Nachher"), canvas.label)
    }

    func testABlurredPageSaysSoAndOffersToTakeItAgain() {
        let app = launch("warning")
        let warning = element(app, "scan-status-warning")
        XCTAssertTrue(warning.waitForExistence(timeout: Self.ready * 2))
        let blurred = words(app, "Unten ist der Text unscharf. Für ein klares Ergebnis neu aufnehmen.")
        let less = words(app, "weniger Text lesbar")
        XCTAssertTrue(blurred.exists || less.exists, "the card says what is wrong")
        let action = element(app, "scan-status-action")
        XCTAssertTrue(action.exists)
        XCTAssertTrue(["Neu", "Vergleichen"].contains(action.label), action.label)
        let thumb = element(app, "scan-thumb-2")
        XCTAssertTrue(thumb.label.contains("schwer lesbar"), thumb.label)
        XCTAssertTrue(thumb.label.hasPrefix("Seite 2 von 2"), thumb.label)
        XCTAssertTrue(thumb.isSelected)
    }

    func testTheColorsAreThreeAndHoldForEveryPage() {
        let app = launch("editor")
        XCTAssertTrue(card(app).exists)
        let color = element(app, "scan-color")
        XCTAssertEqual(color.value as? String, "Farbe")
        color.tap()
        for name in ["Farbe", "Graustufen", "Schwarzweiß"] {
            let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 5), name)
        }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Graustufen")).firstMatch.tap()
        XCTAssertTrue(wait(color, "value == %@", "Graustufen"))
        XCTAssertTrue(card(app).exists, "the page is made again and checked")
    }

    func testBlackAndWhiteIsChosenForTheWholeDocument() {
        let app = launch("bw")
        XCTAssertTrue(card(app).exists)
        XCTAssertEqual(element(app, "scan-color").value as? String, "Schwarzweiß")
    }

    func testDeletingAPageAsksFirstAndTheNextOneOpens() {
        let app = launch("tab")
        let first = element(app, "scan-page-1")
        XCTAssertTrue(first.waitForExistence(timeout: Self.ready))
        first.tap()
        XCTAssertTrue(card(app).exists)
        XCTAssertTrue(element(app, "scan-thumb-2").exists)
        element(app, "scan-delete").tap()
        // The dialog's button, not the tool of the same name.
        let delete = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Seite löschen", "scan-delete"))
            .firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(words(app, "Seite 1 löschen?").exists)
        delete.tap()
        XCTAssertTrue(gone(element(app, "scan-thumb-2")))
        XCTAssertTrue(element(app, "scan-thumb-1").label.hasPrefix("Seite 1 von 1"))
    }

    func testTheCornersAreSetByHandWhereVisionIsNotSure() {
        let app = launch("corners")
        let done = element(app, "scan-corners-done")
        XCTAssertTrue(done.waitForExistence(timeout: 60))
        XCTAssertTrue(element(app, "scan-corner-0").label == "Ecke oben links")
        element(app, "scan-corners-whole").tap()
        done.tap()
        XCTAssertTrue(gone(done))
        XCTAssertTrue(element(app, "scan-page-1").waitForExistence(timeout: Self.ready))
    }

    func testSaveAndShareStartsWithCoversEveryTimeAndWarnsWithout() {
        let app = launch("sheet")
        let with = element(app, "scan-with-covers"), without = element(app, "scan-without-covers")
        XCTAssertTrue(with.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(with.isSelected)
        XCTAssertTrue(with.label.contains("Empfohlen"), with.label)
        XCTAssertTrue(element(app, "scan-format-pdf").label.contains("A4, 2 Seiten"))
        XCTAssertTrue(element(app, "scan-format-picture").label.contains("PNG, 2 Dateien"))
        XCTAssertTrue(app.switches["scan-searchable"].exists)
        XCTAssertTrue(words(app, "Nur gerade gerückt und aufgehellt.").exists)
        without.tap()
        XCTAssertTrue(wait(without, "isSelected == %@", NSNumber(value: true)))
        // The warning is read with Without Covers.
        XCTAssertTrue((without.value as? String)?.contains("Diese Datei enthält alle privaten Angaben") == true,
                      String(describing: without.value))
        element(app, "scan-format-picture").tap()
        XCTAssertTrue(gone(app.switches["scan-searchable"]), "searchable text is for a PDF only")
        // Opened again, it starts with covers.
        app.navigationBars.buttons["Fertig"].tap()
        XCTAssertTrue(gone(with))
        element(app, "scan-next").tap()
        XCTAssertTrue(with.waitForExistence(timeout: 10))
        XCTAssertTrue(with.isSelected)
    }

    func testACopyWithoutCoversSaysSo() {
        let app = launch("uncovered")
        let copy = element(app, "scan-way-copy")
        XCTAssertTrue(copy.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(element(app, "scan-without-covers").isSelected)
        XCTAssertTrue(wait(copy, "isEnabled == %@", NSNumber(value: true), timeout: Self.ready))
        copy.tap()
        let note = element(app, "scan-note")
        XCTAssertTrue(note.waitForExistence(timeout: 60))
        // Never called protected: the words say it left without covers.
        XCTAssertTrue(note.label.contains("ohne Abdeckung"), note.label)
    }

    // MARK: Walks for the videos

    private func recording() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPFLY_RECORD"] != nil, "only while recording")
    }

    private func pause(_ seconds: Double = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Drags the divider slowly from one place on the page to another.
    private func slide(_ canvas: XCUIElement, from: CGFloat, to: CGFloat) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.45))
            .press(forDuration: 0.2, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    /// From Photos to sharing: the made-up photo chosen in the system's
    /// picker (`simctl addmedia` put it in Photos), made ready, compared,
    /// in other colours, then Save and Share without covers and back.
    func testRecordFromPhotosToSharing() throws {
        try recording()
        let app = launch("empty")
        let photos = element(app, "scan-photos")
        XCTAssertTrue(photos.waitForExistence(timeout: 20))
        pause(1.5)
        photos.tap()
        pause(2.5)
        pickNewest(app)
        XCTAssertTrue(card(app).exists)
        pause(2)
        walkThrough(app)
    }

    /// The newest photo in the system's picker, then its button that adds
    /// it. The picker runs on its own and takes a tap at a point, not on
    /// its cell: the middle of the top left cell, where the newest is, or
    /// where it lies on this iPhone if its cells cannot be found; then the
    /// button by its name, or where it lies.
    private func pickNewest(_ app: XCUIApplication) {
        let cells = app.descendants(matching: .any).matching(identifier: "PXGGridLayout-Info")
        let found = cells.firstMatch.waitForExistence(timeout: 20)
        let frames: [CGRect] = found ? cells.allElementsBoundByIndex.map { $0.frame } : []
        // A photo's cell is square; anything else of that name is not a photo.
        let squares: [CGRect] = frames.filter { (frame: CGRect) -> Bool in
            !frame.isEmpty && abs(frame.width - frame.height) < 4
        }
        let newest: CGRect? = squares.min { (a: CGRect, b: CGRect) -> Bool in
            a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX
        }
        if let newest {
            let middle = CGVector(dx: newest.midX, dy: newest.midY)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(middle).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.44)).tap()
        }
        pause(1)
        let names = ["Hinzufügen", "Add", "Fertig", "Done"]
        let add = app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [names])).firstMatch
        if add.waitForExistence(timeout: 5), add.isHittable {
            add.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.155)).tap()
        }
    }

    /// The wipe, then comparing, the colours and Save and Share.
    func testRecordWipeAndCompare() throws {
        try recording()
        let app = launch("editor")
        XCTAssertTrue(card(app).exists)
        pause(2.5)
        walkThrough(app)
    }

    /// The document's pages: the strip, a page opened from it, the warning.
    func testRecordPagesAndWarning() throws {
        try recording()
        let app = launch("warning")
        XCTAssertTrue(element(app, "scan-status-warning").waitForExistence(timeout: Self.ready * 2))
        pause(2.5)
        element(app, "scan-thumb-1").tap()
        XCTAssertTrue(card(app).exists)
        pause(2)
        element(app, "scan-thumb-2").tap()
        XCTAssertTrue(card(app).exists)
        pause(2.5)
    }

    /// Compare, the divider dragged, the colours, then Save and Share
    /// without covers and with them again.
    private func walkThrough(_ app: XCUIApplication) {
        element(app, "scan-compare").tap()
        pause(1.2)
        let canvas = element(app, "protect-canvas")
        slide(canvas, from: 0.5, to: 0.15)
        pause(0.6)
        slide(canvas, from: 0.15, to: 0.85)
        pause(0.6)
        slide(canvas, from: 0.85, to: 0.5)
        pause(1)
        element(app, "scan-compare").tap()
        pause(1.2)
        for name in ["Graustufen", "Schwarzweiß", "Farbe"] {
            element(app, "scan-color").tap()
            pause(0.8)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()
            _ = card(app)
            pause(2)
        }
        element(app, "scan-next").tap()
        let without = element(app, "scan-without-covers")
        XCTAssertTrue(without.waitForExistence(timeout: 10))
        pause(1.5)
        without.tap()
        pause(2)
        element(app, "scan-format-picture").tap()
        pause(1.5)
        element(app, "scan-format-pdf").tap()
        pause(1)
        element(app, "scan-with-covers").tap()
        pause(1.5)
        element(app, "scan-way-share").tap()
        pause(3)
    }
}
