import AppKit
import XCTest
@testable import Tendedero

final class OpenPanelPlanTests: XCTestCase {
    func testOnePhotoIsGoneToByItsPathAndOpened() {
        XCTAssertEqual(OpenPanelPlan.steps(for: ["/tmp/a/Foto.png"], in: "/tmp/a"),
                       [.goTo, .wait(0.4), .type("/tmp/a/Foto.png"), .wait(0.2), .confirm, .wait(0.6), .confirm])
    }

    func testSeveralAreGoneToByTheirFolderAndAllChosen() {
        let steps = OpenPanelPlan.steps(for: ["/tmp/a/1.png", "/tmp/a/2.png"], in: "/tmp/a")
        XCTAssertEqual(steps.first, .goTo)
        XCTAssertTrue(steps.contains(.type("/tmp/a")))
        XCTAssertFalse(steps.contains(.type("/tmp/a/1.png")))
        XCTAssertEqual(Array(steps.suffix(3)), [.selectAll, .wait(0.2), .confirm])
        XCTAssertEqual(OpenPanelPlan.steps(for: [], in: "/tmp/a"), [])
    }

    func testEachCopyKeepsAName() {
        XCTAssertEqual(OpenPanelPlan.names(["Bildschirmfoto.png", "Bildschirmfoto.png", "bildschirmfoto.PNG", "Brief"]),
                       ["Bildschirmfoto.png", "Bildschirmfoto 2.png", "bildschirmfoto 3.PNG", "Brief"])
    }

    func testTypedTextIsNeverSplitInsideACharacter() {
        let text = "/Users/m/Downloads/Foto 😀 März.png"
        let chunks = OpenPanelPlan.chunks(of: text, size: 16)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 16 })
        XCTAssertEqual(String(decoding: chunks.flatMap { $0 }, as: UTF16.self), text)
        XCTAssertTrue(chunks.allSatisfy { String(decoding: $0, as: UTF16.self).unicodeScalars.allSatisfy { $0 != "\u{FFFD}" } })
    }

    /// What an Open window says it is to Accessibility, which is how the
    /// line finds one in another app.
    @MainActor
    func testAnOpenWindowSaysWhatItIs() {
        _ = NSApplication.shared
        let panel = NSOpenPanel()
        print("OPEN PANEL accessibility \(panel.accessibilityIdentifier()) identifier \(panel.identifier?.rawValue ?? "none")")
        XCTAssertTrue([panel.accessibilityIdentifier(), panel.identifier?.rawValue].contains("open-panel"))
    }
}
