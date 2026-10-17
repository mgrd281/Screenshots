import Foundation
import XCTest
@testable import Tendedero

/// The messages sent lately, offered again in the message bar.
final class CaptionTests: XCTestCase {
    func testTheNewestComesFirstOnceAndOnlyFiveAreKept() {
        var list: [String] = []
        for message in ["One", "Two", "Three", "Four", "Five", "Six"] {
            list = RecentCaptions.adding(message, to: list)
        }
        XCTAssertEqual(list, ["Six", "Five", "Four", "Three", "Two"])
        // Sent again, a message moves to the top instead of showing twice.
        XCTAssertEqual(RecentCaptions.adding("Four", to: list), ["Four", "Six", "Five", "Three", "Two"])
        // Spaces around it go; an empty message is not kept.
        XCTAssertEqual(RecentCaptions.adding("  Seven \n", to: []), ["Seven"])
        XCTAssertEqual(RecentCaptions.adding("   ", to: ["One"]), ["One"])
    }
}
