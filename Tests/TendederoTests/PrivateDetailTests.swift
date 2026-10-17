import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Tendedero

/// The kinds of private detail, what each one finds in plain text, and the
/// owner's own rules. Most of it is checked without a picture; one test
/// reads a drawn one, as the app does.
final class PrivateDetailTests: XCTestCase {
    func testEveryKindHasAGroupAndTheRecommendedOnesAreTheSensitiveOnes() {
        for group in PrivateDetail.Group.allCases {
            XCTAssertFalse(group.kinds.isEmpty, "\(group) is empty")
        }
        XCTAssertEqual(PrivateDetail.Group.allCases.flatMap(\.kinds).count, PrivateDetail.allCases.count)
        XCTAssertTrue(PrivateDetail.recommended.isSuperset(of: [.names, .addresses, .emails, .phones, .bank, .health]))
        XCTAssertTrue(PrivateDetail.recommended.contains(.ids))
        XCTAssertTrue(PrivateDetail.recommended.contains(.codes))
        // What a screenshot is usually sent for stays visible until chosen.
        for kind in [PrivateDetail.amounts, .dates, .links, .orders, .faces] {
            XCTAssertFalse(PrivateDetail.recommended.contains(kind), "\(kind) should wait to be chosen")
        }
        // The stored names of the first six stay what they were.
        XCTAssertEqual(PrivateDetail(rawValue: "bank"), .bank)
        XCTAssertEqual(PrivateDetail(rawValue: "health"), .health)
    }

    func testOrderAndCustomerNumbers() {
        let text = "Bestellung #1024\nOrder No. 55512\nKundennummer: K-88210\nIn order to help you\nVielen Dank"
        let found = pieces(text, [.orders])
        XCTAssertEqual(found, ["1024", "55512", "K-88210"])
        XCTAssertEqual(pieces(text, [.names]), [])
    }

    func testTrackingNumbers() {
        let text = "UPS 1Z999AA10123456784\nDHL 00340434161094015902\nTel 030 1234567"
        XCTAssertEqual(pieces(text, [.tracking]), ["1Z999AA10123456784", "00340434161094015902"])
    }

    func testIDAndTaxNumbers() {
        let text = "USt-IdNr. DE123456789\nSteuernummer 12/345/67890\nSSN 123-45-6789\nOrder 1024"
        XCTAssertEqual(pieces(text, [.ids]), ["DE123456789", "12/345/67890", "123-45-6789"])
    }

    func testPasswordsAndCodes() {
        let text = "Dein Code lautet 482913\nPIN: 1234\nTAN 123 456\nCode of conduct"
        XCTAssertEqual(pieces(text, [.codes]), ["482913", "1234", "123 456"])
    }

    func testAmounts() {
        let text = "Gesamt 74,00 €\nTotal $1,250.00\nEUR 12.50\nArtikel 3"
        XCTAssertEqual(pieces(text, [.amounts]), ["74,00 €", "$1,250.00", "EUR 12.50"])
    }

    func testDates() {
        let text = "Datum: 17.10.2026\n2026-10-17\n23. Oktober 2026\nArtikel 3"
        let found = pieces(text, [.dates])
        XCTAssertTrue(found.contains("17.10.2026"), "\(found)")
        XCTAssertTrue(found.contains("2026-10-17"), "\(found)")
        XCTAssertTrue(found.contains("23. Oktober 2026"), "\(found)")
        XCTAssertFalse(found.contains("Artikel 3"))
    }

    func testLinksButNotEmails() {
        let text = "Mehr unter https://shop.example.com/orders/1024\nlena@example.com"
        let found = pieces(text, [.links])
        XCTAssertEqual(found, ["https://shop.example.com/orders/1024"])
        XCTAssertEqual(pieces(text, [.emails]), ["lena@example.com"])
    }

    func testUsernamesButNotEmails() {
        let text = "Von @lena_h für @jonas.w\nlena@example.com"
        XCTAssertEqual(pieces(text, [.usernames]), ["@lena_h", "@jonas.w"])
    }

    func testTheFirstSixStillFindWhatTheyDid() {
        let text = "IBAN DE89 3704 0044 0532 0130 00\nlena.hoffmann@example.com\n+49 30 1234 5678"
        XCTAssertEqual(pieces(text, [.bank]), ["DE89 3704 0044 0532 0130 00"])
        XCTAssertEqual(pieces(text, [.emails]), ["lena.hoffmann@example.com"])
        XCTAssertEqual(pieces(text, [.phones]), ["+49 30 1234 5678"])
    }

    // MARK: The owner's own rules

    func testAWordIsCoveredWholeWhereverItAppears() {
        let text = "Officehauss GmbH liefert\nofficehauss.de\nMax und Maximal"
        let rules = [OwnRule(text: "officehauss", kind: .word), OwnRule(text: "Max", kind: .word)]
        XCTAssertEqual(pieces(text, rules: rules), ["Officehauss", "officehauss", "Max"])
    }

    func testAPatternIsCoveredAndABrokenOneCoversNothing() {
        let text = "SKU-12345 and SKU-9\nABC"
        XCTAssertEqual(pieces(text, rules: [OwnRule(text: "SKU-[0-9]+", kind: .pattern)]), ["SKU-12345", "SKU-9"])
        let broken = OwnRule(text: "(", kind: .pattern)
        XCTAssertFalse(broken.isReadable)
        XCTAssertEqual(pieces(text, rules: [broken]), [])
        XCTAssertTrue(OwnRule(text: "SKU-[0-9]+", kind: .pattern).isReadable)
        XCTAssertTrue(OwnRule(text: "(", kind: .word).isReadable, "only a pattern can be unreadable")
    }

    func testBlankRulesCoverNothingAndAreLeftOutOfTheFingerprint() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PrivateDetailTests-\(UUID().uuidString)"))
        let rules = [OwnRule(text: "", kind: .word), OwnRule(text: "Kundennummer", kind: .label)]
        OwnRules.save(rules, to: defaults)
        XCTAssertEqual(OwnRules.load(from: defaults), rules)
        XCTAssertEqual(pieces("Kundennummer 5", rules: [OwnRule(text: "   ", kind: .word)]), [])
    }

    /// Read from a picture, as the app does: a label of the owner's own with
    /// its value on the same line and on the line below, and an order
    /// number. No faces in a page of text.
    func testRulesAndKindsAreFoundInAPicture() throws {
        let image = try drawn(["Kundennummer: 88210", "Bestellung #1024", "Lieferung", "", "Kundennummer", "77301"])
        let label = [OwnRule(text: "Kundennummer", kind: .label)]
        XCTAssertGreaterThanOrEqual(Finder.areas(in: image, [], rules: label).count, 2)
        XCTAssertGreaterThanOrEqual(Finder.areas(in: image, [.orders], rules: []).count, 1)
        XCTAssertEqual(Finder.areas(in: image, [.faces], rules: []).count, 0)
        XCTAssertEqual(Finder.areas(in: image, [], rules: []).count, 0)
    }

    // MARK: Helpers

    /// What the kinds cover in the text, in order.
    private func pieces(_ text: String, _ chosen: Set<PrivateDetail> = [], rules: [OwnRule] = []) -> [String] {
        // Two kinds can find one piece; it counts once.
        let ranges = Finder.patternRanges(in: text, chosen) + Finder.ruleRanges(in: text, rules)
        var seen = Set<String>()
        return ranges.sorted { $0.location < $1.location }
            .filter { seen.insert("\($0.location):\($0.length)").inserted }
            .map { (text as NSString).substring(with: $0) }
    }

    /// Lines of large black text on white, one under another.
    private func drawn(_ lines: [String]) throws -> CGImage {
        let width = 1400, height = 120 * lines.count + 80
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 100 - 120 * i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        return try XCTUnwrap(context.makeImage())
    }
}
