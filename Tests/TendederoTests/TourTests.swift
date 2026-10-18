import AppKit
import XCTest
@testable import Tendedero

/// The welcome tour: five cards, each with a symbol macOS 14 draws, the
/// screenshot card naming the shortcut chosen, or the menu bar's item
/// without one, and the places in Settings named as Settings names them.
final class TourTests: XCTestCase {
    @MainActor
    func testFiveCardsEachWithASymbolATitleAndWords() {
        let pages = Tour.pages(capture: "⌃⌥S")
        XCTAssertEqual(pages.count, 5)
        for page in pages {
            XCTAssertNotNil(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil), page.symbol)
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.text.isEmpty)
        }
        // The line first, what stays private last.
        XCTAssertEqual(pages.first?.symbol, "menubar.rectangle")
        XCTAssertEqual(pages.last?.symbol, "hand.raised")
    }

    @MainActor
    func testTheScreenshotCardNamesTheShortcutOrTheMenuItem() {
        XCTAssertTrue(Tour.pages(capture: "⌃⌥S")[1].text.contains("⌃⌥S"))
        let without = Tour.pages(capture: nil)[1].text
        XCTAssertTrue(without.contains(L("Take Screenshot")), without)
        XCTAssertFalse(without.contains("%@"))
    }

    @MainActor
    func testThePlacesInSettingsAreNamedAsSettingsNamesThem() {
        let pages = Tour.pages(capture: nil)
        XCTAssertTrue(pages[2].text.contains([L("Settings"), L("Line"), L("Icons under photos")].joined(separator: " › ")),
                      pages[2].text)
        XCTAssertTrue(pages[4].text.contains([L("Settings"), L("Privacy")].joined(separator: " › ")), pages[4].text)
    }
}
