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
        let parts = [PrivateDetail.names.title, PrivateDetail.barcodes.title, L("Your details and rules"), L("Hidden by hand")]
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

    /// Where the lock shows the copy was covered: as in the picture, cut to
    /// the part kept, and lower when a band of words sits above it.
    func testThePlacesAreWhereTheCopyIsCovered() {
        let name = CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.1)
        XCTAssertEqual(CoverReport.places([name], crop: nil), [name])
        // Cut to its right half: the name's left edge is the cut's.
        let right = CGRect(x: 0.2, y: 0, width: 0.8, height: 1)
        let cut = CoverReport.places([name], crop: right)
        XCTAssertEqual(cut.count, 1)
        XCTAssertEqual(cut[0].minX, 0, accuracy: 1e-9)
        XCTAssertEqual(cut[0].width, 0.25, accuracy: 1e-9)
        XCTAssertEqual(cut[0].minY, 0.4, accuracy: 1e-9)
        // What the cut leaves out is left out.
        XCTAssertEqual(CoverReport.places([name], crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)), [])
        // A band above the picture takes a fifth of the copy.
        let banded = CoverReport.places([name], crop: nil, share: 0.8)
        XCTAssertEqual(banded[0].minY, 0.32, accuracy: 1e-9)
        XCTAssertEqual(banded[0].height, 0.08, accuracy: 1e-9)
        XCTAssertEqual(banded[0].minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(CoverReport([area(.names)], places: banded).places, banded)
    }
}
