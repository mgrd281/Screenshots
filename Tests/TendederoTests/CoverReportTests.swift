import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// What the lock says was covered: kind by kind, in the order Settings lists
/// them, then the owner's own rules and the parts hidden by hand.
final class CoverReportTests: XCTestCase {
    private let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)

    private func area(_ kind: PrivateDetail?) -> Finder.Area {
        Finder.Area(rect: box, kind: kind)
    }

    func testKindsAreCountedAndToldInTheOrderSettingsLists() {
        let report = CoverReport([area(.barcodes), area(.names), area(.names), area(nil)], hand: 1)
        XCTAssertEqual(report.kinds[.names], 2)
        XCTAssertEqual(report.kinds[.barcodes], 1)
        XCTAssertEqual(report.rules, 1)
        XCTAssertEqual(report.hand, 1)
        XCTAssertEqual(report.total, 5)
        XCTAssertFalse(report.isEmpty)
        let parts = [PrivateDetail.names.title, PrivateDetail.barcodes.title, L("Your own rules"), L("Hidden by hand")]
        XCTAssertEqual(report.summary, parts.joined(separator: " · "))
        XCTAssertEqual(report.sentence, String(format: L("Covered: %@"), report.summary))
    }

    func testNothingCoveredSaysNothing() {
        XCTAssertTrue(CoverReport().isEmpty)
        XCTAssertNil(CoverReport().sentence)
        XCTAssertEqual(CoverReport([], hand: 0).summary, "")
        XCTAssertEqual(CoverReport([], hand: 2).sentence, String(format: L("Covered: %@"), L("Hidden by hand")))
    }

    func testThePagesOfAPDFAddUp() {
        var report = CoverReport([area(.emails)])
        report.add(CoverReport([area(.emails), area(.bank)], hand: 2))
        XCTAssertEqual(report.kinds[.emails], 2)
        XCTAssertEqual(report.kinds[.bank], 1)
        XCTAssertEqual(report.hand, 2)
        XCTAssertEqual(report.total, 5)
    }
}
