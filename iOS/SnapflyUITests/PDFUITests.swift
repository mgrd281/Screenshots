import XCTest

/// PDF projects driven on the simulator as the owner would use them, in
/// German, on a made-up project (`-SnapflyProject`): a three-page invoice
/// with real text, a photo of a narrow receipt and a page photographed
/// sideways. The Scan tab offers to merge files or open a PDF and lists the
/// project; the pages show in their order with where each comes from; pages
/// are chosen, turned, duplicated and deleted, every step undone and done
/// again from the dark note; a page dragged to another place lands there;
/// an empty page is added; the editor opens a page as "Seite 1 von 5" and a
/// swipe goes to the next; Save and Share offers the page size, the quality
/// with the file's size, and covers; a locked PDF asks for its password and
/// asks again after Snapfly was closed, so it was never kept; a signed PDF
/// warns; and the project opens again where it was left after Snapfly was
/// closed by force. With 300 pages, the frames drawn while it scrolls and
/// while a page is dragged are counted (`PDF-NUMBERS` lines). The
/// `testRecord…` walks are slow on purpose, for the videos
/// `scripts/pdf-checks.sh` records, and run only there (`SNAPFLY_RECORD`).
final class PDFUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ state: String, _ app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        var arguments = ["-SnapflyProject", state, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
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

    private func wait(_ element: XCUIElement, _ format: String, _ value: Any, timeout: TimeInterval = 15) -> Bool {
        let settled = expectation(for: NSPredicate(format: format, argumentArray: [value]), evaluatedWith: element)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    /// The made-up project's five pages, in.
    private func overview(_ state: String = "overview") -> XCUIApplication {
        let app = launch(state)
        XCTAssertTrue(element(app, "project-page-5").waitForExistence(timeout: 60), "the five pages show")
        return app
    }

    private func title(_ app: XCUIApplication) -> XCUIElement {
        element(app, "project-title")
    }

    /// Whether the project has a page in this place, as the grid shows it.
    private func page(_ app: XCUIApplication, _ number: Int, shows: Bool) -> Bool {
        wait(element(app, "project-page-\(number)"), "exists == %@", NSNumber(value: shows))
    }

    // MARK: Checks

    func testTheScanTabOffersToMergeOrOpenAPDFAndListsTheProject() {
        let app = launch("tab")
        XCTAssertTrue(element(app, "project-merge").waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "project-open-pdf").exists)
        XCTAssertTrue(element(app, "scan-camera").exists, "the scan card stays")
        let recent = element(app, "scan-recent")
        XCTAssertTrue(recent.waitForExistence(timeout: 60))
        XCTAssertTrue(words(app, "Zuletzt").exists)
        XCTAssertTrue(recent.label.hasPrefix("Rechnung März, 5 Seiten, "), recent.label)
        // Alle anzeigen lists it too.
        element(app, "scan-show-all").tap()
        XCTAssertTrue(element(app, "scan-all-documents").waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        // It opens again where it was left.
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        recent.tap()
        XCTAssertTrue(element(app, "project-page-5").waitForExistence(timeout: 30))
    }

    /// The recent document shows its first page covered: a cover's dark
    /// band, wider than any letter's stroke, is in its picture.
    func testTheRecentDocumentShowsItsFirstPageCovered() throws {
        let app = launch("tab")
        let recent = element(app, "scan-recent")
        XCTAssertTrue(recent.waitForExistence(timeout: 60))
        // Covered and drawn: the first time, Vision's models load first; two minutes at most.
        var picture = recent.screenshot().image
        var band = 0
        for _ in 0..<60 {
            picture = recent.screenshot().image
            band = try XCTUnwrap(Self.widestDarkRun(picture))
            if band >= 24 { break }
            Thread.sleep(forTimeInterval: 2)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "recent-covered"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(band, 24, "a cover's band, in pixels")
    }

    /// The widest run of near-black pixels in any row of the picture's upper part, the page.
    static func widestDarkRun(_ image: UIImage) -> Int? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var widest = 0
        for y in 0..<(h * 6 / 10) {
            var run = 0
            for x in 0..<w {
                let i = (y * w + x) * 4
                let dark = Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) < 3 * 70
                run = dark ? run + 1 : 0
                widest = max(widest, run)
            }
        }
        return widest
    }

    func testMixedSourcesShowInTheirOrderWithWhereEachComesFrom() {
        let app = overview()
        XCTAssertTrue(title(app).label.contains("Rechnung März"), title(app).label)
        XCTAssertTrue(title(app).label.contains("5 Seiten"), title(app).label)
        let expected = ["Rechnung.pdf · S. 1", "Rechnung.pdf · S. 2", "Rechnung.pdf · S. 3", "Foto", "Foto"]
        for (index, label) in expected.enumerated() {
            let page = element(app, "project-page-\(index + 1)")
            XCTAssertTrue(page.label.hasPrefix("Seite \(index + 1) von 5"), page.label)
            XCTAssertTrue(page.label.contains(label), page.label)
        }
        XCTAssertTrue(words(app, "Tippe auf eine Seite, um sie auszuwählen.").exists)
        XCTAssertTrue(element(app, "project-add").exists)
        XCTAssertTrue(element(app, "project-next").exists)
    }

    func testEveryPageOperationIsUndoneAndDoneAgain() {
        let app = overview()
        // A tap chooses a page and starts choosing.
        element(app, "project-page-2").tap()
        XCTAssertTrue(wait(title(app), "label CONTAINS %@", "1 Seite ausgewählt"), title(app).label)
        XCTAssertTrue(element(app, "project-page-2").isSelected)
        // Duplicated, then undone and done again.
        element(app, "project-duplicate").tap()
        // The note stays a few seconds and each look takes a moment here: its button first, then the rest.
        let undo = element(app, "project-toast-undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 30), "the note with Undo")
        XCTAssertEqual(undo.label, "Rückgängig")
        XCTAssertTrue(words(app, "1 Seite dupliziert").exists)
        undo.tap()
        XCTAssertTrue(page(app, 6, shows: false), "the copy is gone")
        XCTAssertTrue(wait(undo, "label == %@", "Wiederholen"))
        undo.tap()
        XCTAssertTrue(page(app, 6, shows: true), "the copy is back")
        // Another page chosen, turned.
        element(app, "project-page-3").tap()
        XCTAssertTrue(wait(title(app), "label CONTAINS %@", "1 Seite ausgewählt"), title(app).label)
        element(app, "project-turn").tap()
        // Deleted without asking, then undone.
        element(app, "project-delete").tap()
        XCTAssertTrue(words(app, "1 Seite gelöscht").waitForExistence(timeout: 30), "the note says a page is gone")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no dialog")
        element(app, "project-toast-undo").tap()
        XCTAssertTrue(page(app, 6, shows: true), "the page is back")
        // Nothing chosen: the bar's actions are dimmed and do nothing.
        element(app, "project-select").tap()
        element(app, "project-select").tap()
        XCTAssertTrue(wait(title(app), "label CONTAINS %@", "0 Seiten ausgewählt"), title(app).label)
        XCTAssertFalse(element(app, "project-delete").isEnabled)
    }

    func testAPageDraggedToAnotherPlaceLandsThere() {
        let app = overview()
        let first = element(app, "project-page-1")
        XCTAssertTrue(first.label.contains("Rechnung.pdf · S. 1"), first.label)
        first.press(forDuration: 0.8, thenDragTo: element(app, "project-page-3"))
        let third = element(app, "project-page-3")
        XCTAssertTrue(wait(third, "label CONTAINS %@", "Rechnung.pdf · S. 1"), third.label)
        XCTAssertTrue(element(app, "project-page-1").label.contains("Rechnung.pdf · S. 2"), element(app, "project-page-1").label)
    }

    func testAnEmptyPageIsAdded() {
        let app = overview()
        element(app, "project-add").tap()
        let blank = app.buttons["Leere Seite"]
        XCTAssertTrue(blank.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Aus Fotos"].exists)
        XCTAssertTrue(app.buttons["Aus Dateien"].exists)
        blank.tap()
        let page = element(app, "project-page-6")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(page.label.contains("Leere Seite"), page.label)
    }

    func testTheEditorOpensAPageAndASwipeGoesToTheNext() {
        let app = overview()
        element(app, "project-next").tap()
        XCTAssertTrue(app.navigationBars["Seite 1 von 5"].waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "project-overview").exists)
        XCTAssertTrue(element(app, "project-thumb-1").isSelected)
        let canvas = element(app, "protect-canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 60))
        canvas.swipeUp()
        XCTAssertTrue(app.navigationBars["Seite 2 von 5"].waitForExistence(timeout: 20))
        let next = element(app, "protect-canvas")
        XCTAssertTrue(next.waitForExistence(timeout: 60))
        next.swipeDown()
        XCTAssertTrue(app.navigationBars["Seite 1 von 5"].waitForExistence(timeout: 20))
        // The strip opens another page.
        element(app, "project-thumb-4").tap()
        XCTAssertTrue(app.navigationBars["Seite 4 von 5"].waitForExistence(timeout: 20))
        element(app, "project-overview").tap()
        XCTAssertTrue(element(app, "project-page-5").waitForExistence(timeout: 10))
    }

    func testSaveAndShareOffersSizeQualityAndCovers() {
        // The sheet opens over the pages once they are in.
        let app = launch("export")
        XCTAssertTrue(words(app, "Sichern und teilen").waitForExistence(timeout: 90))
        XCTAssertTrue(words(app, "PDF, 5 Seiten").exists)
        XCTAssertTrue(element(app, "project-export-name").exists)
        XCTAssertTrue(words(app, "Seitengröße für Bilder").exists)
        XCTAssertTrue(app.buttons["US Letter"].exists)
        XCTAssertTrue(words(app, "Qualität").exists)
        XCTAssertTrue(app.buttons["Hoch"].exists)
        let estimate = element(app, "project-export-estimate")
        XCTAssertTrue(wait(estimate, "label BEGINSWITH %@", "ca. ", timeout: 60), estimate.label)
        XCTAssertTrue(element(app, "project-with-covers").isSelected)
        XCTAssertTrue(words(app, "Empfohlen").exists)
        // The warning is read with the choice itself.
        let without = element(app, "project-without-covers")
        without.tap()
        XCTAssertTrue(wait(without, "isSelected == %@", NSNumber(value: true)))
        XCTAssertTrue((without.value as? String)?.contains("Diese Datei enthält alle privaten Angaben") == true,
                      String(describing: without.value))
        XCTAssertTrue(words(app, "Enthält den ganzen Text").exists)
        for way in ["copy", "save", "share"] {
            XCTAssertTrue(element(app, "project-way-\(way)").exists, way)
        }
        // With covers again, the PDF is made and copied.
        element(app, "project-with-covers").tap()
        element(app, "project-way-copy").tap()
        let note = element(app, "project-export-note")
        XCTAssertTrue(note.waitForExistence(timeout: 240))
        XCTAssertEqual(note.label, "Kopiert")
    }

    func testALockedPDFAsksForItsPasswordEveryTime() {
        let app = launch("locked")
        let alert = app.alerts["Diese PDF ist mit einem Passwort geschützt."]
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        alert.secureTextFields.firstMatch.tap()
        alert.secureTextFields.firstMatch.typeText("falsch")
        alert.buttons["Öffnen"].tap()
        let again = app.alerts["Diese PDF ist mit einem Passwort geschützt."]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertTrue(again.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "nicht das Passwort")).firstMatch.exists)
        again.secureTextFields.firstMatch.tap()
        again.secureTextFields.firstMatch.typeText("Muster-2026")
        again.buttons["Öffnen"].tap()
        XCTAssertTrue(element(app, "project-page-3").waitForExistence(timeout: 30))
        // Opened again after Snapfly was closed, it asks again: the password was not kept.
        sleep(2)
        app.terminate()
        let reopened = launch("reopen")
        XCTAssertTrue(reopened.alerts["Diese PDF ist mit einem Passwort geschützt."].waitForExistence(timeout: 30))
    }

    func testASignedPDFWarnsThatEditingEndsTheSignature() {
        let app = launch("signed")
        let alert = app.alerts["Diese PDF ist digital signiert."]
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                                             "Nach dem Bearbeiten ist die Signatur nicht mehr gültig.")).firstMatch.exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(element(app, "project-page-1").waitForExistence(timeout: 10))
    }

    func testTheProjectOpensAgainAfterSnapflyWasClosedByForce() {
        let app = overview()
        element(app, "project-page-2").tap()
        element(app, "project-delete").tap()
        XCTAssertTrue(page(app, 5, shows: false), "the page is gone")
        // A moment for it to be written, then closed by force.
        sleep(2)
        app.terminate()
        let reopened = launch("reopen")
        let heading = title(reopened)
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        XCTAssertTrue(heading.label.contains("Rechnung März"), heading.label)
        XCTAssertTrue(wait(heading, "label CONTAINS %@", "4 Seiten"), heading.label)
    }

    func testThreeHundredPagesScrollAndReorderWithoutHitches() {
        let app = launch("long")
        let grid = app.collectionViews.firstMatch
        XCTAssertTrue(element(app, "project-page-1").waitForExistence(timeout: 120))
        XCTAssertTrue(wait(title(app), "label CONTAINS %@", "300 Seiten", timeout: 60), title(app).label)
        let meter = element(app, "project-frame-meter")
        for _ in 0..<4 { grid.swipeUp(velocity: .fast) }
        XCTAssertTrue(wait(meter, "label BEGINSWITH %@", "scroll", timeout: 20), meter.label)
        print("PDF-NUMBERS \(meter.label)")
        // A page held and dragged down to the bottom edge, so the grid scrolls under it.
        // A hold on a place in the grid that shows a page, never on a page picked from the list of cells, which may lie off the screen after the swipes. The first hold can also land while the grid still coasts, and then it lifts nothing: once more, in the next row, when it did.
        let bottom = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        var lifted = false
        for row in [0.2, 0.45] where !lifted {
            sleep(2)
            grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: row))
                .press(forDuration: 0.8, thenDragTo: bottom, withVelocity: .slow, thenHoldForDuration: 3)
            lifted = wait(meter, "label BEGINSWITH %@", "reorder", timeout: 20)
        }
        XCTAssertTrue(lifted, meter.label)
        print("PDF-NUMBERS \(meter.label)")
    }

    // MARK: Walks for the videos

    private func walk() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAPFLY_RECORD"] != nil, "only while recording")
    }

    /// Merging and dragging pages: the project's pages come in, one is
    /// chosen and turned, another dragged to a new place, one deleted and
    /// brought back, then the editor and a swipe to the next page, then Save and Share.
    func testRecordMergingAndDragging() throws {
        try walk()
        let app = overview()
        sleep(2)
        element(app, "project-page-4").tap()
        sleep(1)
        element(app, "project-turn").tap()
        sleep(1)
        element(app, "project-select").tap()
        sleep(1)
        element(app, "project-page-1").press(forDuration: 0.8, thenDragTo: element(app, "project-page-3"),
                                             withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(2)
        element(app, "project-page-5").tap()
        element(app, "project-delete").tap()
        sleep(2)
        element(app, "project-toast-undo").tap()
        sleep(2)
        element(app, "project-select").tap()
        sleep(1)
        element(app, "project-next").tap()
        XCTAssertTrue(element(app, "protect-canvas").waitForExistence(timeout: 60))
        sleep(4)
        element(app, "protect-canvas").swipeUp()
        sleep(4)
        element(app, "project-next").tap()
        sleep(6)
    }
}
