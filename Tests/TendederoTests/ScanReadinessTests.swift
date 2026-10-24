import XCTest
@testable import Tendedero

/// Whether the camera is ready to take a page (`ScanReadiness`), on made-up
/// previews of a page of small print: sharp, still and close enough it is
/// taken by itself; otherwise one hint, the most important first, for each
/// way a preview can fall short. Drawn in shapes, so it is checked on any machine.
final class ScanReadinessTests: XCTestCase {
    /// The page's rows of letters, as Vision gives their lines: from 0 to 1 from the bottom left.
    private var lines: [CGRect] {
        let w = Double(ScanBurstTests.width), h = Double(ScanBurstTests.height)
        return (0..<12).map { row in
            let top = 30 + Double(row) * 26 - 2
            return CGRect(x: 30 / w, y: 1 - (top + 18) / h, width: 420 / w, height: 18 / h)
        }
    }

    private func look(_ take: ScanBurstTests.Take = .init(), photoHeight: Int = 1440, still: Double = 1,
                      smudged: Bool = false, darker: Double = 0) -> ScanReadiness.Look {
        let frame = ScanBurstTests.frame(take)
        var plane = frame.brightness
        if darker > 0 { plane = plane.map { UInt8(Double($0) * (1 - darker)) } }
        return ScanReadiness.Look(plane: plane, width: frame.width, height: frame.height,
                                  page: CGRect(x: 0, y: 0, width: 1, height: 1), lines: lines,
                                  photoHeight: photoHeight, still: still, smudged: smudged)
    }

    func testASharpStillCloseEnoughPageIsTakenByItself() {
        let state = ScanReadiness.state(of: look())
        XCTAssertTrue(state.ready, "\(state)")
        XCTAssertNil(state.hint)
        XCTAssertEqual(state.letters, 18 * 1440 / 360 * 0.5, accuracy: 0.5, "the smallest letters' x-height")
    }

    func testEachShortfallHasItsHintTheMostImportantFirst() {
        var blurred = ScanBurstTests.Take()
        blurred.focus = 2
        XCTAssertEqual(ScanReadiness.state(of: look(blurred)).hint, .steady, "out of focus")
        XCTAssertEqual(ScanReadiness.state(of: look(still: 0.1)).hint, .steady, "not still long enough")
        XCTAssertEqual(ScanReadiness.state(of: look(photoHeight: 480)).hint, .closer, "letters too small")
        var glare = ScanBurstTests.Take()
        glare.reflection = true
        XCTAssertEqual(ScanReadiness.state(of: look(glare)).hint, .glare, "a reflection")
        XCTAssertEqual(ScanReadiness.state(of: look(darker: 0.6)).hint, .light, "too dark")
        XCTAssertEqual(ScanReadiness.state(of: look(smudged: true)).hint, .smudge, "a smudged lens")
        // Moving and far away: holding still comes first.
        XCTAssertEqual(ScanReadiness.state(of: look(photoHeight: 480, still: 0.1)).hint, .steady)
        for hint in ScanReadiness.Hint.allCases { XCTAssertFalse(hint.message.isEmpty) }
    }

    func testACloseUpOfSmallPrintNeedsNoWholePageButLargerLetters() {
        var close = look(photoHeight: 1440)
        close.page = nil
        XCTAssertFalse(ScanReadiness.state(of: close).ready, "a page needs its page in view")
        XCTAssertTrue(ScanReadiness.state(of: close, tuning: .closeUp).ready, "a close-up does not")
        close.photoHeight = 900
        XCTAssertEqual(ScanReadiness.state(of: close, tuning: .closeUp).hint, .closer, "letters 22 px: closer still")
    }

    func testWithoutAPageOrTextNothingIsTakenAndNothingSaid() {
        var nothing = look()
        nothing.lines = []
        let state = ScanReadiness.state(of: nothing)
        XCTAssertFalse(state.ready)
        XCTAssertNil(state.hint)
        XCTAssertEqual(state.letters, 0)
    }
}
