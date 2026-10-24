import XCTest
@testable import Tendedero

/// The line under the Review title says how the page stands, and never that
/// nothing private was found while a place is still to check, a private
/// detail is left visible or the picture has a fault: every combination of
/// covered, open, visible and hints.
final class ReviewStatusTests: XCTestCase {
    private func status(_ covered: Int, _ open: Int, _ hints: Int, visible: Int = 0) -> ReviewStatus {
        ReviewStatus(covered: covered, open: open, hints: hints, visible: visible)
    }

    func testEachStateReadsAsItIs() {
        XCTAssertEqual(status(3, 4, 0).text, "3 covered · 4 to check")
        XCTAssertEqual(status(3, 4, 1).text, "3 covered · 4 to check", "what is to check comes before a hint")
        XCTAssertEqual(status(0, 2, 0).text, "2 to check")
        XCTAssertEqual(status(3, 0, 0).text, "3 covered, everything checked")
        XCTAssertEqual(status(3, 0, 1).text, "3 covered · 1 quality hint")
        XCTAssertEqual(status(3, 0, 2).text, "3 covered · 2 quality hints")
        XCTAssertEqual(status(0, 0, 1).text, "Nothing private · 1 quality hint")
        XCTAssertEqual(status(0, 0, 0).text, "Nothing private found")
    }

    func testDetailsLeftVisibleAreNeverNothingPrivate() {
        // A letter whose name, address and date of birth the categories leave visible.
        XCTAssertEqual(status(0, 0, 2, visible: 3).text, "Nothing covered · 3 visible")
        XCTAssertEqual(status(4, 0, 0, visible: 2).text, "4 covered · 2 visible")
        XCTAssertEqual(status(4, 1, 0, visible: 2).text, "4 covered · 1 to check", "what is to check comes first")
        XCTAssertEqual(status(0, 0, 0, visible: 1).spoken, "Nothing covered, 1 visible. Open the list.")
    }

    func testNothingFoundOnlyWhenNothingIsOpen() {
        for covered in 0...3 {
            for open in 0...3 {
                for hints in 0...2 {
                    for visible in 0...2 {
                        let line = status(covered, open, hints, visible: visible)
                        let nothing = covered == 0 && open == 0 && hints == 0 && visible == 0
                        XCTAssertEqual(line.text == "Nothing private found", nothing,
                                       "\(covered) \(open) \(hints) \(visible): \(line.text)")
                        XCTAssertEqual(line.state == .nothing, nothing)
                        XCTAssertEqual(line.text.hasPrefix("Nothing private"), covered == 0 && open == 0 && visible == 0,
                                       "never nothing private while a detail is left visible: \(line.text)")
                        if open > 0 { XCTAssertTrue(line.text.contains("\(open) to check"), line.text) }
                        if open == 0, visible > 0 { XCTAssertTrue(line.text.contains("\(visible) visible"), line.text) }
                        if covered > 0 { XCTAssertTrue(line.text.hasPrefix("\(covered) covered"), line.text) }
                    }
                }
            }
        }
    }

    func testVoiceOverSaysWhatATapDoes() {
        XCTAssertEqual(status(4, 2, 0).spoken, "4 covered, 2 to check. Open the list.")
        XCTAssertEqual(status(0, 0, 0).spoken, "Nothing private found")
    }
}
