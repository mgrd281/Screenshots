import CoreGraphics
import Foundation

/// Made-up scans for pictures made in CI (`scripts/scan-checks.sh`), as
/// `-SnapflyScan` asks: the editor on a photo of a made-up invoice
/// (editor), comparing Before and After (compare), a second page blurred at
/// its bottom (warning), Save and Share open (sheet) or without covers
/// (uncovered), the pages in black and white (bw), corners to set by hand
/// (corners), the Scan tab with its pages (tab), with what to ask Claude
/// over it (assistant), or with none yet, for photos chosen from Photos
/// (empty); `-SnapflyReduceMotion`
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
    static var opensEditor: Bool { state != "tab" && state != "corners" && state != "assistant" }
    /// The sheet a tap on Claude opens, over the tab.
    static var asksAssistant: Bool { state == "assistant" }
    /// Which page the editor opens on: the blurred one for the warning.
    static var page: Int { state == "warning" ? 1 : 0 }
    static var compares: Bool { state == "compare" }
    static var opensSheet: Bool { state == "sheet" || state == "uncovered" }
    static var uncovered: Bool { state == "uncovered" }
    /// Played as Reduce Motion would, for the videos (`-SnapflyReduceMotion`).
    static let still = arguments.contains("-SnapflyReduceMotion")

    /// The photos: one, or two where the strip or the warning shows; for
    /// corners, without where the page is, to set it by hand. Each as a PNG,
    /// as Photos gives its photos, so it is decoded as theirs are.
    static func photos() -> [ScanPhoto] {
        guard state != "empty", let page = ScanSample.page() else { return [] }
        let flaws: [ScanSample.Flaw]
        switch state {
        case "editor", "corners": flaws = [.none]
        case "warning": flaws = [.none, .blurredBottom]
        default: flaws = [.none, .none]
        }
        return flaws.compactMap { flaw in
            guard let photo = ScanSample.photographed(page, flaw: flaw), let png = Covering.png(photo.image),
                  var scan = ScanPhoto(data: png) else { return nil }
            scan.quad = unsure ? nil : photo.quad
            return scan
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
    static let uncovered = false
    static let still = false
    static func photos() -> [ScanPhoto] { [] }
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
