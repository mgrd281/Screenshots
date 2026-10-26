import XCTest
@testable import Tendedero

/// Finding words in every document, page by page: every word searched for
/// on one page, whatever its case or accents, and only where it stands,
/// never the words around it. Made-up pages.
final class DocumentSearchTests: XCTestCase {
    private let invoice = ["Musterfirma GmbH\nRechnung RE-2026-0417\nDruckpatronen Schwarz 2 24,90 €",
                           "",
                           "Versandpauschale\nDRUCKPATRONEN Farbe\nBitte überweisen Sie den Betrag."]

    func testEveryWordOnOnePageFindsIt() {
        XCTAssertEqual(DocumentSearch.find("druckpatronen", in: invoice), .init(pages: [1, 3], count: 2))
        XCTAssertEqual(DocumentSearch.find("Druckpatronen Schwarz", in: invoice), .init(pages: [1], count: 1))
        XCTAssertNil(DocumentSearch.find("Schwarz Versandpauschale", in: invoice), "never two pages' words together")
        XCTAssertNil(DocumentSearch.find("Mahnung", in: invoice))
    }

    func testCaseAccentsAndWidthsDoNotMatter() {
        XCTAssertEqual(DocumentSearch.find("UBERWEISEN", in: invoice)?.pages, [3])
        XCTAssertEqual(DocumentSearch.find("ｒｅ-2026", in: invoice)?.pages, [1], "full-width letters")
    }

    func testASearchOfSpacesFindsNothing() {
        XCTAssertNil(DocumentSearch.find("   ", in: invoice))
        XCTAssertEqual(DocumentSearch.words("  Rechnung   2026 "), ["rechnung", "2026"])
    }

    func testTheRarestWordCountsHowOftenTheyStandTogether() {
        let pages = ["Muster Muster Muster GmbH", "Muster GmbH GmbH"]
        XCTAssertEqual(DocumentSearch.find("muster gmbh", in: pages), .init(pages: [1, 2], count: 2))
        XCTAssertEqual(DocumentSearch.find("muster", in: pages)?.count, 4)
    }

    func testTheLabelSaysWhereAndHowOftenOnly() {
        XCTAssertEqual(DocumentSearch.label(.init(pages: [2], count: 1)), "Page 2 · 1 match")
        XCTAssertEqual(DocumentSearch.label(.init(pages: [2, 5], count: 4)), "Pages 2, 5 · 4 matches")
        XCTAssertEqual(DocumentSearch.label(.init(pages: [1, 2, 3, 4, 6], count: 9)), "Pages 1, 2, 3 +2 more · 9 matches")
    }
}
