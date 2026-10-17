import AppKit
import XCTest
@testable import Tendedero

/// Test on a Sample: the made-up order shows every kind but faces, and the
/// test covers only what is checked.
final class SelfTestTests: XCTestCase {
    private let everything = Set(PrivateDetail.allCases)

    func testTheSampleShowsEveryKindButFaces() throws {
        let result = try XCTUnwrap(SelfTest.run(everything))
        XCTAssertEqual(SelfTest.missing(everything, in: result.report), [.faces],
                       "Covered: \(result.report.summary)")
        XCTAssertNotNil(NSImage(data: result.png))
    }

    func testOnlyWhatIsCheckedIsCovered() throws {
        let result = try XCTUnwrap(SelfTest.run([.emails, .amounts]))
        XCTAssertEqual(Set(PrivateDetail.allCases.filter { result.report.kinds[$0, default: 0] > 0 }), [.emails, .amounts])
    }

    func testWhatTheTestSays() {
        let report = CoverReport([Finder.Area(rect: .zero, kind: .emails)])
        let words = SelfTest.sentences([.emails, .faces], report)
        XCTAssertEqual(words.covered, String(format: L("Covered on this sample: %@"), PrivateDetail.emails.title))
        XCTAssertEqual(words.missing, String(format: L("Checked, but not on this sample: %@"), PrivateDetail.faces.title))
        XCTAssertNil(SelfTest.sentences([.emails], report).missing)
        XCTAssertEqual(SelfTest.sentences([.faces], CoverReport()).covered, L("Nothing checked was found on this sample."))
    }
}
