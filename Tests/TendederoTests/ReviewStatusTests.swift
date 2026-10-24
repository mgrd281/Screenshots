import XCTest
@testable import Tendedero

/// The line under the Review title says how the page stands, and never that
/// nothing private was found while a place is still to check or the picture
/// has a fault: every combination of covered, open and hints.
final class ReviewStatusTests: XCTestCase {
    private func status(_ covered: Int, _ open: Int, _ hints: Int) -> ReviewStatus {
        ReviewStatus(covered: covered, open: open, hints: hints)
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

    func testNothingFoundOnlyWhenNothingIsOpen() {
        for covered in 0...3 {
            for open in 0...3 {
                for hints in 0...2 {
                    let line = status(covered, open, hints)
                    let nothing = covered == 0 && open == 0 && hints == 0
                    XCTAssertEqual(line.text == "Nothing private found", nothing, "\(covered) \(open) \(hints): \(line.text)")
                    XCTAssertEqual(line.state == .nothing, nothing)
                    if open > 0 { XCTAssertTrue(line.text.contains("\(open) to check"), line.text) }
                    if covered > 0 { XCTAssertTrue(line.text.hasPrefix("\(covered) covered"), line.text) }
                }
            }
        }
    }

    func testVoiceOverSaysWhatATapDoes() {
        XCTAssertEqual(status(4, 2, 0).spoken, "4 covered, 2 to check. Open the list.")
        XCTAssertEqual(status(0, 0, 0).spoken, "Nothing private found")
    }
}
