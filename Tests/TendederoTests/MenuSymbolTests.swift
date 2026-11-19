import AppKit
import XCTest
@testable import Tendedero

/// The menu bar menu's symbols: each one the Mac has, and no two lines alike
/// but the stop that stands for what is running.
final class MenuSymbolTests: XCTestCase {
    func testEverySymbolIsOneTheMacHas() {
        for name in MenuSymbol.all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testNoTwoLinesShareASymbol() {
        XCTAssertEqual(Set(MenuSymbol.all).count, MenuSymbol.all.count)
    }
}
