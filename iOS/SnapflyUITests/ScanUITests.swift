import XCTest

/// Scan driven on the simulator as the owner would use it, in German, on
/// made-up photos of a made-up invoice (`-SnapflyScan`), made ready as any
/// photo is: the tab offers the camera and Photos with its new lines; a page
/// opens in Review once cleaned, its status chip saying what is covered and
/// open, its tools under Covers and Page; Compare is one adjustable
/// comparison, and a finger moves its divider; a blurred page has a hint in
/// the list, with Look; the colours are three,
/// and Black and White holds for every page; deleting a page asks first;
/// corners are set by hand where Vision is not sure; Save and Share starts
/// with covers every time and warns without them, and a copy without covers
/// says so. A photographed document from Photos is offered cleaning, never
/// a screenshot, and Revert brings the photo back; an AI chat says what goes
/// to it and nothing leaves before a tap, and what leaves is the covered
/// export byte for byte; the name never holds a covered name; photos
/// chosen together keep their order. The `testRecord…` walks are slow on purpose, for the videos
/// `scripts/scan-checks.sh` records, and run only there (`SNAPFLY_RECORD`).
final class ScanUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Long enough for the made-up photos to be made ready on the simulator.
    private static let ready: TimeInterval = 120

    private func launch(_ state: String, ownCamera: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-SnapflyScan", state, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                         "-snapfly.scan.ownCamera", ownCamera ? "YES" : "NO"]
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

    /// The page's status chip once it is clean and its copy checked.
    private func card(_ app: XCUIApplication) -> XCUIElement {
        let status = element(app, "review-status")
        _ = status.waitForExistence(timeout: Self.ready)
        return status
    }

    /// Review's bar switched to the page's own tools.
    private func pageTools(_ app: XCUIApplication) {
        let page = element(app, "review-mode-page")
        if page.waitForExistence(timeout: 10) { page.tap() }
    }

    // MARK: Checks

    func testTheStartOffersOneScanThreeQuickActionsAndThePages() {
        let app = launch("tab")
        let hero = element(app, "scan-camera")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertEqual(hero.label, "Dokument scannen")
        XCTAssertTrue(element(app, "scan-photos").exists)
        XCTAssertEqual(element(app, "scan-photos").label, "Aus Fotos wählen")
        XCTAssertEqual(element(app, "project-merge").label, "Fotos, Scans und PDFs zusammenfügen")
        XCTAssertEqual(element(app, "project-open-pdf").label, "PDF öffnen, Seiten ordnen und verdecken")
        XCTAssertTrue(element(app, "scan-help").exists)
        XCTAssertFalse(words(app, "Neu:").exists, "the tips are behind the ?")
        XCTAssertFalse(words(app, "PDF erstellen und bearbeiten").exists, "the PDF card is gone")
        XCTAssertTrue(element(app, "scan-page-1").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(element(app, "scan-page-2").exists)
        XCTAssertTrue(element(app, "scan-save-share").exists)
    }

    /// The card starts the scanner: Snapfly's own camera here, as the
    /// simulator has no document camera.
    func testTheCardStartsTheScanner() {
        let app = launch("empty", ownCamera: true)
        let hero = element(app, "scan-camera")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        hero.tap()
        let close = element(app, "page-camera-close")
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the camera opens")
        close.tap()
        XCTAssertTrue(gone(close))
    }

    func testTheQuickActionsOpenTheirWays() {
        let app = launch("empty")
        let merge = element(app, "project-merge")
        XCTAssertTrue(merge.waitForExistence(timeout: 20))
        merge.tap()
        XCTAssertTrue(element(app, "project-add").waitForExistence(timeout: 20), "a new PDF project opens")
        // Closed empty, it is gone, so it does not open again over the next launch.
        element(app, "project-close").tap()
        XCTAssertTrue(gone(element(app, "project-add")))
        app.terminate()
        let again = launch("empty")
        let pdf = element(again, "project-open-pdf")
        XCTAssertTrue(pdf.waitForExistence(timeout: 20))
        pdf.tap()
        let names = ["Abbrechen", "Cancel"]
        let cancel = again.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [names])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "Files opens")
        cancel.tap()
        let photos = element(again, "scan-photos")
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        photos.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "the photo picker opens")
    }

    func testTheHelpOpensHowItWorks() {
        let app = launch("empty")
        let help = element(app, "scan-help")
        XCTAssertTrue(help.waitForExistence(timeout: 20))
        help.tap()
        XCTAssertTrue(words(app, "So funktioniert's").waitForExistence(timeout: 10))
        for line in ["Halten", "Aufbereiten", "Verdecken", "Teilen", "Alles geschieht auf diesem iPhone."] {
            XCTAssertTrue(words(app, line).exists, line)
        }
    }

    /// Without documents, how a scan goes, in four short steps.
    func testWithoutDocumentsTheStepsShow() {
        let app = launch("empty")
        XCTAssertTrue(element(app, "scan-steps").waitForExistence(timeout: 20))
        XCTAssertTrue(words(app, "So geht's").exists)
        XCTAssertTrue(words(app, "Über die Seite halten, sie wird von selbst aufgenommen.").exists)
        XCTAssertTrue(words(app, "Prüfen, dann teilen oder als PDF sichern.").exists)
    }

    /// Scrolled past the card, the bar offers Scannen, which starts the scanner.
    func testScrolledTheBarOffersScanning() {
        let app = launch("tab", ownCamera: true)
        XCTAssertTrue(element(app, "scan-page-2").waitForExistence(timeout: Self.ready))
        let pill = element(app, "scan-bar-camera")
        XCTAssertFalse(pill.exists, "not while the card shows")
        for _ in 0..<3 where !pill.exists {
            app.swipeUp()
        }
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        XCTAssertTrue(element(app, "page-camera-close").waitForExistence(timeout: 10), "the camera opens")
    }

    func testAPageOpensInReviewSayingWhatWasDone() {
        let app = launch("editor")
        let status = card(app)
        XCTAssertTrue(status.exists)
        XCTAssertTrue(["verdeckt", "zu prüfen", "Nichts Privates"].contains { status.label.contains($0) }, status.label)
        let title = element(app, "review-title")
        XCTAssertTrue(title.label.contains("Prüfen") && title.label.contains("Seite 1 von 1"), title.label)
        XCTAssertTrue(element(app, "scan-next").exists)
        XCTAssertTrue(element(app, "review-back").exists)
        XCTAssertTrue(element(app, "review-more").exists)
        let thumb = element(app, "scan-thumb-1")
        XCTAssertTrue(thumb.label.hasPrefix("Seite 1 von 1"), thumb.label)
        XCTAssertTrue(thumb.isSelected)
        for tool in ["review-tool-select", "review-tool-box", "review-tool-lasso", "review-tool-marker",
                     "review-tool-eraser", "scan-add"] {
            XCTAssertTrue(element(app, tool).exists, tool)
        }
        XCTAssertTrue(element(app, "review-tool-select").isSelected, "Select in hand")
        pageTools(app)
        for tool in ["scan-compare", "scan-crop", "scan-turn", "scan-color", "scan-delete"] {
            XCTAssertTrue(element(app, tool).waitForExistence(timeout: 5), tool)
        }
    }

    func testTheOwnersNameAndAddressAreCoveredOnALetter() {
        let app = launch("own")
        let status = card(app)
        XCTAssertTrue(wait(status, "label CONTAINS %@", "verdeckt", timeout: Self.ready), status.label)
        XCTAssertFalse(status.label.contains("Nichts Privates"), status.label)
        status.tap()
        XCTAssertTrue(words(app, "Deine Angaben aus Immer verbergen").waitForExistence(timeout: 10),
                      "the list says the owner's details are covered")
    }

    func testCompareIsOneAdjustableComparison() {
        let app = launch("editor")
        XCTAssertTrue(card(app).exists)
        pageTools(app)
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
        let status = element(app, "review-status")
        XCTAssertTrue(status.waitForExistence(timeout: Self.ready * 2))
        XCTAssertTrue(status.label.contains("Qualitätshinweis") || status.label.contains("zu prüfen"), status.label)
        XCTAssertFalse(status.label.contains("Nichts Privates gefunden"), "never while a hint stands")
        let thumb = element(app, "scan-thumb-2")
        XCTAssertTrue(thumb.label.contains("Zu prüfen"), thumb.label)
        XCTAssertTrue(thumb.label.hasPrefix("Seite 2 von 2"), thumb.label)
        XCTAssertTrue(thumb.isSelected)
        status.tap()
        let blurred = words(app, "Unten ist der Text unscharf. Für ein klares Ergebnis neu aufnehmen.")
        let less = words(app, "weniger Text lesbar")
        XCTAssertTrue(blurred.waitForExistence(timeout: 5) || less.exists, "the list says what is wrong")
        let look = app.buttons["Ansehen"].firstMatch
        XCTAssertTrue(look.exists)
        look.tap()
        XCTAssertTrue(element(app, "scan-crop").waitForExistence(timeout: 5), "the page's own tools")
    }

    func testTheColorsAreThreeAndHoldForEveryPage() {
        let app = launch("editor")
        XCTAssertTrue(card(app).exists)
        pageTools(app)
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
        pageTools(app)
        XCTAssertEqual(element(app, "scan-color").value as? String, "Schwarzweiß")
    }

    func testDeletingAPageAsksFirstAndTheNextOneOpens() {
        let app = launch("tab")
        let first = element(app, "scan-page-1")
        XCTAssertTrue(first.waitForExistence(timeout: Self.ready))
        first.tap()
        XCTAssertTrue(card(app).exists)
        XCTAssertTrue(element(app, "scan-thumb-2").exists)
        pageTools(app)
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

    // MARK: Photos, names and AI chats

    /// The editor in the Photos tab on a made-up photo of the made-up
    /// invoice (`-SnapflyDocumentPhoto`), or on the invoice as a screenshot
    /// (`-SnapflyEditorSample`).
    private func launchPhoto(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        var all = arguments + ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if ProcessInfo.processInfo.environment["SNAPFLY_STILL"] != nil { all.append("-SnapflyReduceMotion") }
        app.launchArguments = all
        app.launch()
        return app
    }

    /// The status once the copy is made and checked.
    private func checked(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@ OR label CONTAINS %@",
                                                             "zu prüfen", "verdeckt", "Nichts Privates")).firstMatch
    }

    func testAPhotographedDocumentIsOfferedCleaningAndRevertBringsThePhotoBack() {
        let app = launchPhoto(["-SnapflyDocumentPhoto", "offer"])
        let offer = element(app, "photo-clean-offer")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(words(app, "Sieht aus wie ein fotografiertes Dokument. Gerade rücken und aufhellen?").exists)
        XCTAssertTrue(checked(app).waitForExistence(timeout: Self.ready), "the photo is covered as it is first")
        // Never cleaned without the tap.
        XCTAssertFalse(element(app, "photo-cleaned").exists)
        let clean = element(app, "photo-clean")
        XCTAssertEqual(clean.label, "Aufbereiten")
        clean.tap()
        let cleaned = element(app, "photo-cleaned")
        XCTAssertTrue(cleaned.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(gone(offer))
        // Its covers are found again on the cleaned page, and checked.
        XCTAssertTrue(checked(app).waitForExistence(timeout: Self.ready))
        let revert = element(app, "photo-clean-undo")
        XCTAssertEqual(revert.label, "Rückgängig")
        revert.tap()
        XCTAssertTrue(gone(cleaned))
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the photo as it was, offered again")
        XCTAssertTrue(checked(app).waitForExistence(timeout: 30), "with its covers as they were")
    }

    func testAScreenshotIsNeverOfferedCleaning() {
        let app = launchPhoto(["-SnapflyEditorSample"])
        XCTAssertTrue(checked(app).waitForExistence(timeout: Self.ready))
        // Long enough for the page to have been looked for.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertFalse(element(app, "photo-clean-offer").exists)
    }

    func testAnAIChatSaysWhatGoesAndNothingLeavesBeforeATap() {
        let app = launch("assistant")
        let what = element(app, "scan-ask-what")
        XCTAssertTrue(what.waitForExistence(timeout: Self.ready))
        XCTAssertEqual(what.label, "Die verdeckte Kopie wird an Claude übergeben.")
        for ask in ["Dokument erklären", "Zusammenfassen", "Fristen und Beträge auflisten", "Nur übergeben"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", ask)).firstMatch.exists, ask)
        }
        XCTAssertEqual(element(app, "audit-handed").label, "none", "nothing is handed over before a tap")
        app.navigationBars.buttons["Abbrechen"].tap()
        XCTAssertTrue(gone(what))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(element(app, "audit-handed").label, "none", "nor after Cancel")
    }

    func testThePagesHandedToAnAIChatAreTheCoveredExportByteForByte() {
        let app = launch("tab")
        let save = element(app, "scan-save-share")
        XCTAssertTrue(element(app, "scan-page-2").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(gone(element(app, "scan-improving"), timeout: Self.ready * 2))
        // The covered pictures as Save and Share makes them.
        save.tap()
        element(app, "scan-format-picture").tap()
        let copy = element(app, "scan-way-copy")
        XCTAssertTrue(wait(copy, "isEnabled == %@", NSNumber(value: true), timeout: Self.ready))
        copy.tap()
        let exported = element(app, "audit-exported")
        XCTAssertTrue(wait(exported, "label != %@", "none", timeout: Self.ready))
        app.navigationBars.buttons["Fertig"].tap()
        XCTAssertTrue(gone(copy))
        // Then handed to Claude, after its sheet.
        XCTAssertEqual(element(app, "audit-handed").label, "none")
        element(app, "send-claude").tap()
        let only = element(app, "scan-ask-none")
        XCTAssertTrue(only.waitForExistence(timeout: 10))
        only.tap()
        // Two pages go through the share sheet; it is closed again to read what went.
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [["Schließen", "Close"]])).firstMatch
        if close.waitForExistence(timeout: Self.ready) { close.tap() } else { app.swipeDown(velocity: .fast) }
        let handed = element(app, "audit-handed")
        XCTAssertTrue(wait(handed, "label != %@", "none", timeout: 30))
        XCTAssertEqual(handed.label, exported.label, "the same bytes, page by page")
        XCTAssertEqual(handed.label.split(separator: " ").count, 2, "both pages")
    }

    func testTheNameNeverHoldsACoveredNameAndIsTheScanTimeWithoutAppleIntelligence() {
        let app = launch("sheet")
        let name = app.textFields["scan-name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.ready))
        // Long enough for a suggestion, where Apple Intelligence is there.
        XCTAssertTrue(wait(element(app, "scan-way-copy"), "isEnabled == %@", NSNumber(value: true), timeout: Self.ready))
        Thread.sleep(forTimeInterval: 5)
        let value = name.value as? String ?? ""
        XCTAssertFalse(value.localizedCaseInsensitiveContains("Mustermann"), value)
        XCTAssertFalse(value.localizedCaseInsensitiveContains("Erika"), value)
        if !element(app, "scan-name-suggested").exists {
            let scanned = value.range(of: #"^Scan \d{2}\.\d{2}\.\d{4}, \d{2}\.\d{2}$"#, options: .regularExpression)
            XCTAssertNotNil(scanned, value)
        }
    }

    /// Two photos chosen from Photos (`simctl addmedia` put them there, the
    /// blurred one first, so the sharp one is newest, first in the picker),
    /// the blurred one chosen first: the document keeps the order they were
    /// chosen in, not the picker's.
    func testPhotosChosenTogetherKeepTheOrderTheyWereChosenIn() throws {
        let app = launch("empty")
        let photos = element(app, "scan-photos")
        XCTAssertTrue(photos.waitForExistence(timeout: 20))
        photos.tap()
        let cells = app.descendants(matching: .any).matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20))
        let squares: [CGRect] = cells.allElementsBoundByIndex.map { $0.frame }
            .filter { (frame: CGRect) -> Bool in !frame.isEmpty && abs(frame.width - frame.height) < 4 }
            .sorted { (a: CGRect, b: CGRect) -> Bool in a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX }
        try XCTSkipIf(squares.count < 2, "two photos are put in Photos by scripts/scan-checks.sh")
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        // The older, blurred one first, then the newer, sharp one.
        for frame in [squares[1], squares[0]] {
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        let names = ["Hinzufügen", "Add", "Fertig", "Done"]
        let add = app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [names])).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        // On the simulator Vision finds no page: each photo's corners are set, the first's, then the second's.
        let done = element(app, "scan-corners-done")
        for _ in 0..<2 where done.waitForExistence(timeout: Self.ready) {
            dragCorners(app)
            XCTAssertTrue(gone(done, timeout: 20))
            pause(2)
        }
        let first = element(app, "scan-thumb-1"), second = element(app, "scan-thumb-2")
        XCTAssertTrue(second.waitForExistence(timeout: Self.ready))
        XCTAssertTrue(gone(element(app, "scan-improving"), timeout: Self.ready * 2))
        // The list's hint for the blurred photo opens its page: the first, as it was chosen first.
        let status = card(app)
        XCTAssertTrue(status.exists)
        status.tap()
        let blurred = words(app, "Unten ist der Text unscharf")
        XCTAssertTrue(blurred.waitForExistence(timeout: 20), "the blurred photo's hint")
        let looks = app.buttons.matching(NSPredicate(format: "label == %@", "Ansehen")).allElementsBoundByIndex
        let look = try XCTUnwrap(looks.min { abs($0.frame.midY - blurred.frame.midY) < abs($1.frame.midY - blurred.frame.midY) })
        look.tap()
        XCTAssertTrue(wait(first, "isSelected == %@", NSNumber(value: true), timeout: 10), first.label)
        pause(2)
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
    /// picker (`simctl addmedia` put it in Photos), its corners set by hand
    /// where Vision is not sure of them, made ready, compared, in other
    /// colours, then Save and Share without covers and back.
    func testRecordFromPhotosToSharing() throws {
        try recording()
        let app = launch("empty")
        let photos = element(app, "scan-photos")
        XCTAssertTrue(photos.waitForExistence(timeout: 20))
        pause(1.5)
        photos.tap()
        pause(2.5)
        pickNewest(app)
        setCornersIfAsked(app)
        XCTAssertTrue(card(app).exists)
        pause(2)
        walkThrough(app)
    }

    /// The start as it comes in, three made-up documents arriving one after
    /// another, a press on the card that opens the camera, the bar's pill as
    /// the card scrolls away, and "So funktioniert's".
    func testRecordTheStart() throws {
        try recording()
        let app = launch("recent", ownCamera: true)
        let hero = element(app, "scan-camera")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        // The documents arrive, a few seconds apart.
        let recent = element(app, "scan-recent")
        XCTAssertTrue(recent.waitForExistence(timeout: 60))
        pause(16)
        hero.tap()
        let close = element(app, "page-camera-close")
        if close.waitForExistence(timeout: 10) {
            pause(1.5)
            close.tap()
        }
        pause(1.5)
        app.swipeUp(velocity: .slow)
        pause(2)
        app.swipeDown(velocity: .slow)
        pause(1.5)
        element(app, "scan-help").tap()
        pause(3)
        app.swipeDown(velocity: .slow)
        pause(2)
    }

    /// Where the corners wait for the owner, as on the simulator, where
    /// Vision finds no page: the whole picture first, then each corner
    /// dragged slowly onto the page's corner in the made-up photo
    /// (`ScanSample`), then Done. Otherwise nothing.
    private func setCornersIfAsked(_ app: XCUIApplication) {
        let done = element(app, "scan-corners-done")
        let status = element(app, "review-status")
        let either = expectation(for: NSPredicate { _, _ in done.exists || status.exists }, evaluatedWith: nil)
        _ = XCTWaiter.wait(for: [either], timeout: Self.ready)
        guard done.exists else { return }
        dragCorners(app)
    }

    /// In the corner editor: the whole picture first, then each corner
    /// dragged slowly onto the page's corner in the made-up photo, then Done.
    private func dragCorners(_ app: XCUIApplication) {
        let done = element(app, "scan-corners-done")
        pause(1.5)
        element(app, "scan-corners-whole").tap()
        pause(1)
        // With the whole picture, the first and third corners are the picture's own.
        let first: CGRect = element(app, "scan-corner-0").frame
        let third: CGRect = element(app, "scan-corner-2").frame
        let picture = CGRect(x: first.midX, y: first.midY, width: third.midX - first.midX, height: third.midY - first.midY)
        // The page's corners in the photo, from its top left: top left, top right, bottom right, bottom left.
        let page: [CGPoint] = [CGPoint(x: 0.172, y: 0.105), CGPoint(x: 0.847, y: 0.122),
                               CGPoint(x: 0.923, y: 0.883), CGPoint(x: 0.083, y: 0.851)]
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        for (corner, point) in page.enumerated() {
            let handle: CGRect = element(app, "scan-corner-\(corner)").frame
            let x: CGFloat = picture.minX + point.x * picture.width
            let y: CGFloat = picture.minY + point.y * picture.height
            let from = origin.withOffset(CGVector(dx: handle.midX, dy: handle.midY))
            from.press(forDuration: 0.3, thenDragTo: origin.withOffset(CGVector(dx: x, dy: y)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(0.6)
        }
        pause(1)
        done.tap()
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
        XCTAssertTrue(element(app, "review-status").waitForExistence(timeout: Self.ready * 2))
        pause(2.5)
        element(app, "scan-thumb-1").tap()
        XCTAssertTrue(card(app).exists)
        pause(2)
        element(app, "scan-thumb-2").tap()
        XCTAssertTrue(card(app).exists)
        pause(2.5)
    }

    /// A photographed document from Photos: the offer, cleaning, its covers
    /// found again, then Revert.
    func testRecordCleaningAPhotographedDocument() throws {
        try recording()
        let app = launchPhoto(["-SnapflyDocumentPhoto", "offer"])
        XCTAssertTrue(element(app, "photo-clean-offer").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(checked(app).waitForExistence(timeout: Self.ready))
        pause(3)
        element(app, "photo-clean").tap()
        XCTAssertTrue(element(app, "photo-cleaned").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(checked(app).waitForExistence(timeout: Self.ready))
        pause(3)
        element(app, "photo-clean-undo").tap()
        pause(3)
    }

    /// The scanned pages' name in Save and Share, then Claude: what goes to
    /// it, a question chosen, and the share sheet it opens.
    func testRecordNameAndHandOver() throws {
        try recording()
        let app = launch("tab")
        XCTAssertTrue(element(app, "scan-page-2").waitForExistence(timeout: Self.ready))
        XCTAssertTrue(gone(element(app, "scan-improving"), timeout: Self.ready * 2))
        pause(1.5)
        element(app, "scan-save-share").tap()
        XCTAssertTrue(app.textFields["scan-name"].waitForExistence(timeout: 10))
        pause(4)
        app.navigationBars.buttons["Fertig"].tap()
        pause(1.5)
        element(app, "send-claude").tap()
        XCTAssertTrue(element(app, "scan-ask-what").waitForExistence(timeout: 10))
        pause(3)
        element(app, "scan-ask-summarize").tap()
        pause(5)
    }

    /// Compare, the divider dragged, the colours, then Save and Share
    /// without covers and with them again.
    private func walkThrough(_ app: XCUIApplication) {
        pageTools(app)
        pause(0.8)
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
