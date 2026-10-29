import Carbon
import XCTest
@testable import Tendedero

final class ShortcutTapTests: XCTestCase {
    func testAShortcutUnderAMenuIsItsKeyWithExactlyItsModifiers() {
        let capture = Shortcut(keyCode: kVK_ANSI_S, modifiers: [.control, .option], key: "s")
        let s = Int64(kVK_ANSI_S)
        XCTAssertTrue(ShortcutTap.matches(capture, key: s, flags: [.maskControl, .maskAlternate]))
        // Caps Lock and the like don't count.
        XCTAssertTrue(ShortcutTap.matches(capture, key: s, flags: [.maskControl, .maskAlternate, .maskAlphaShift]))
        XCTAssertFalse(ShortcutTap.matches(capture, key: s, flags: [.maskControl, .maskAlternate, .maskShift]))
        XCTAssertFalse(ShortcutTap.matches(capture, key: s, flags: [.maskControl]))
        XCTAssertFalse(ShortcutTap.matches(capture, key: s, flags: []))
        XCTAssertFalse(ShortcutTap.matches(capture, key: Int64(kVK_ANSI_R), flags: [.maskControl, .maskAlternate]))
        let withCommand = Shortcut(keyCode: kVK_ANSI_5, modifiers: [.command, .shift], key: "5")
        XCTAssertTrue(ShortcutTap.matches(withCommand, key: Int64(kVK_ANSI_5), flags: [.maskCommand, .maskShift]))
    }

    func testOnlyTheShortcutsThatTakeTheScreenAreHeardUnderMenus() {
        XCTAssertEqual(Set(ShortcutTap.roles), [.capture, .record])
    }
}
