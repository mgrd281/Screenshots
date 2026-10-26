import CoreGraphics
import Foundation

/// Made-up scans for pictures made in CI (`scripts/scan-checks.sh`), as
/// `-SnapflyScan` asks: the editor on a photo of a made-up invoice
/// (editor), comparing Before and After (compare), a second page blurred at
/// its bottom (warning), Save and Share open (sheet), on the invoice still
/// to pay, offering its reminder (due), without covers
/// (uncovered) or on the pages' text, open to read (text), on its Page view
/// (textpage) or correcting (textfix), the pages in
/// black and white (bw), corners to set by hand
/// (corners), the Scan tab with its pages (tab), with what to ask Claude
/// over it (assistant), or with none yet, for photos chosen from Photos
/// (empty), or a letter naming the owner, whose made-up name and address
/// are then kept in Always Hide (own), or Review's list of what is to check
/// over two pages, the second blurred (list); the Scan tab's start with
/// "So funktioniert's" open (help), scrolled past its card (scrolled), or
/// with three made-up documents arriving one after another (recent);
/// `-SnapflyReduceMotion`
/// plays it as Reduce Motion would. The photos are drawn here
/// (`ScanSample`) and made ready as any photo is, where the page is in them
/// already known. Nothing of it is in a release build.
enum ScanDemo {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    static let state: String? = {
        guard let index = arguments.firstIndex(of: "-SnapflyScan"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var requested: Bool { state != nil }
    static var mode: ScanColor? { state == "bw" ? .blackAndWhite : nil }
    static var unsure: Bool { state == "corners" }
    static var opensEditor: Bool {
        !["tab", "corners", "assistant", "help", "scrolled", "recent", "empty"].contains(state ?? "")
    }
    /// "So funktioniert's", open over the start.
    static var opensHelp: Bool { state == "help" }
    /// The start scrolled past its card, the pill in the bar.
    static var scrolls: Bool { state == "scrolled" }
    /// Made-up documents among the recent ones.
    static var makesRecent: Bool { state == "recent" }
    /// The start begins without documents, whatever an earlier run left.
    static var clearsDocuments: Bool { ["empty", "help", "scrolled", "recent"].contains(state ?? "") }
    /// The sheet a tap on Claude opens, over the tab.
    static var asksAssistant: Bool { state == "assistant" }
    /// Which page the editor opens on: the blurred one for the warning.
    static var page: Int { state == "warning" ? 1 : 0 }
    static var compares: Bool { state == "compare" }
    static var opensSheet: Bool { ["sheet", "due", "uncovered", "text", "textpage", "textfix"].contains(state ?? "") }
    /// The invoice without its stamp, still to pay.
    static var remindsToPay: Bool { state == "due" }
    /// The day it is, for what is still to come: the invoice's own date in
    /// the made-up scans, so its day to pay by is always ahead.
    static var today: Date {
        guard requested, let day = PaymentDue.Day(year: 2026, month: 10, day: 14) else { return .now }
        return day.date(in: .current) ?? .now
    }
    static var uncovered: Bool { state == "uncovered" }
    /// Save and Share on the Text format, its text open to read.
    static var opensText: Bool { ["text", "textpage", "textfix"].contains(state ?? "") }
    /// The text open on its Page view, or correcting.
    static var readsPage: Bool { state == "textpage" }
    static var corrects: Bool { state == "textfix" }
    /// The letter to the owner, with their details kept as Always Hide keeps them.
    static var ownLetter: Bool { state == "own" }
    /// Review's list, open over the first page.
    static var opensList: Bool { state == "list" }
    /// Played as Reduce Motion would, for the videos (`-SnapflyReduceMotion`).
    static let still = arguments.contains("-SnapflyReduceMotion")

    /// The photos: one, or two where the strip or the warning shows; for
    /// corners, without where the page is, to set it by hand. Each as a PNG,
    /// as Photos gives its photos, so it is decoded as theirs are.
    static func photos() -> [ScanPhoto] {
        guard !["empty", "help", "recent"].contains(state ?? ""),
              let page = ownLetter ? ScanSample.letter() : ScanSample.page(paid: !remindsToPay) else { return [] }
        let flaws: [ScanSample.Flaw]
        switch state {
        case "editor", "corners", "own", "due": flaws = [.none]
        case "warning", "list": flaws = [.none, .blurredBottom]
        default: flaws = [.none, .none]
        }
        return flaws.compactMap { flaw in
            guard let photo = ScanSample.photographed(page, flaw: flaw), let png = Covering.png(photo.image),
                  var scan = ScanPhoto(data: png) else { return nil }
            scan.quad = unsure ? nil : photo.quad
            return scan
        }
    }

    /// Keeps the owner's made-up details for the letter, as Always Hide does.
    static func keepOwnDetails() {
        guard ownLetter else { return }
        OwnDetailStore.details = [ScanSample.ownName, ScanSample.ownAddress]
    }

    /// Three made-up documents, one after another, as they would arrive:
    /// a contract, a letter of two photographed pages and an invoice, each
    /// put together as a PDF project and closed, so it waits among the
    /// recent ones. A few seconds apart, so each is seen arriving.
    @MainActor static func makeRecent(_ store: ProjectStore) async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Made-up files", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func file(_ data: Data, _ name: String) -> URL {
            let url = folder.appendingPathComponent(name)
            try? data.write(to: url)
            return url
        }
        let letter = [PDFFixtures.sideways(), PDFFixtures.receipt()].compactMap { $0 }
        let documents: [(name: String, items: ProjectImport)] = [
            ("Mietvertrag", .files([file(PDFFixtures.signed(), "Mietvertrag.pdf")])),
            ("Brief 22.10.2026", .pictures(letter, origin: .photo)),
            ("Rechnung Musterfirma", .files([file(PDFFixtures.invoice(), "Rechnung.pdf")])),
        ]
        try? await Task.sleep(for: .seconds(4))
        for document in documents {
            store.start()
            await store.add(document.items)
            // The made-up contract is signed; its warning is not what the pictures show.
            store.notice = nil
            store.rename(document.name)
            store.close()
            try? await Task.sleep(for: .seconds(5))
        }
    }
    #else
    static let requested = false
    static let mode: ScanColor? = nil
    static let unsure = false
    static let opensEditor = false
    static let asksAssistant = false
    static let page = 0
    static let compares = false
    static let opensSheet = false
    static let remindsToPay = false
    static var today: Date { .now }
    static let uncovered = false
    static let opensText = false
    static let readsPage = false
    static let corrects = false
    static let ownLetter = false
    static let opensList = false
    static let still = false
    static func photos() -> [ScanPhoto] { [] }
    static func keepOwnDetails() {}
    static let opensHelp = false
    static let scrolls = false
    static let makesRecent = false
    static let clearsDocuments = false
    @MainActor static func makeRecent(_ store: ProjectStore) async {}
    #endif
}

/// A made-up photo of the made-up invoice opened from the Photos tab, for
/// pictures made in CI, as `-SnapflyDocumentPhoto` asks: offered to be
/// straightened and brightened (offer), or cleaned at once (cleaned). Where
/// its page is, is known, as Vision finds no page on the simulator.
/// Nothing of it is in a release build.
enum DocumentPhotoDemo {
    #if DEBUG
    private static let state: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SnapflyDocumentPhoto"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var requested: Bool { state != nil }
    static var cleansAtOnce: Bool { state == "cleaned" }

    @MainActor static func photo() -> (image: CGImage, info: Imported.Info)? {
        guard let page = ScanSample.page(), let photo = ScanSample.photographed(page) else { return nil }
        return (photo.image, Imported.Info(screenshot: false, page: photo.quad))
    }
    #else
    static let requested = false
    static let cleansAtOnce = false
    @MainActor static func photo() -> (image: CGImage, info: Imported.Info)? { nil }
    #endif
}
