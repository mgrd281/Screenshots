import CoreGraphics
import CoreImage
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
        XCTAssertTrue(PrivateDetail.recommended.contains(.barcodes))
        XCTAssertEqual(PrivateDetail.barcodes.group, .sensitive)
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

    func testTheOrderNumberIsTheFirstFoundTopToBottom() {
        XCTAssertEqual(Finder.orderNumber(in: ["Danke für deine Bestellung", "Bestellung #1024", "Kundennummer: K-88210"]), "1024")
        XCTAssertEqual(Finder.orderNumber(in: ["Kundennummer: K-88210", "Order No. 55512"]), "K-88210")
        XCTAssertNil(Finder.orderNumber(in: ["Vielen Dank", "In order to help you"]))
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

    // MARK: QR codes and barcodes

    func testWhatACodeHoldsIsReadByItsFormatAndItsText() {
        let giro = "BCD\n002\n1\nSCT\nBFSWDE33BER\nLena Hoffmann\nDE89370400440532013000\nEUR12.30\n\n\nRechnung 1024"
        XCTAssertTrue(Finder.kinds(ofCode: giro).isSuperset(of: [.bank, .names]))
        XCTAssertTrue(Finder.kinds(ofCode: "otpauth://totp/Shop:lena?secret=JBSWY3DPEHPK3PXP&issuer=Shop").contains(.codes))
        XCTAssertTrue(Finder.kinds(ofCode: "WIFI:T:WPA;S:Laden;P:geheim123;;").contains(.codes))
        let card = "BEGIN:VCARD\nVERSION:3.0\nFN:Lena Hoffmann\nTEL:+49 30 1234 5678\nEND:VCARD"
        XCTAssertTrue(Finder.kinds(ofCode: card).isSuperset(of: [.names, .phones]))
        XCTAssertTrue(Finder.kinds(ofCode: "https://shop.example.com/t/1024").contains(.links))
        XCTAssertTrue(Finder.kinds(ofCode: "M1HOFFMANN/LENA       E1A2B3C FRAJFKLH 0400").isSuperset(of: [.names, .ids]))
        XCTAssertTrue(Finder.kinds(ofCode: "00340434161094015902").contains(.tracking))
        XCTAssertEqual(Finder.kinds(ofCode: "Hello"), [])
    }

    func testEveryCodeIsCoveredWhenCodesAreChosenOtherwiseByWhatItHolds() {
        let giro = "BCD\n002\n1\nSCT\nBFSWDE33BER\nLena Hoffmann\nDE89370400440532013000\nEUR12.30"
        XCTAssertTrue(Finder.coversCode(nil, [.barcodes]), "a code that is not text is covered too")
        XCTAssertTrue(Finder.coversCode("Hello", [.barcodes]))
        XCTAssertFalse(Finder.coversCode(nil, [.bank]))
        XCTAssertTrue(Finder.coversCode(giro, [.bank]))
        XCTAssertFalse(Finder.coversCode("https://shop.example.com/t/1024", [.bank]))
        XCTAssertTrue(Finder.coversCode("https://shop.example.com/t/1024", [.links]))
        XCTAssertFalse(Finder.coversCode(giro, []))
        // Covered as a code when codes are chosen, otherwise as what it holds.
        XCTAssertEqual(Finder.kind(ofCode: nil, [.barcodes, .links]), .barcodes)
        XCTAssertEqual(Finder.kind(ofCode: "https://shop.example.com/t/1024", [.links, .emails]), .links)
        XCTAssertNil(Finder.kind(ofCode: "Hello", [.links]))
    }

    func testTheNumberPrintedUnderABarcodeGoesWithIt() throws {
        let pattern = try XCTUnwrap(Finder.printedPattern(ofCode: "00340434161094015902"))
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        func found(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        XCTAssertTrue(found("Sendung 0034 0434 1610 9401 5902 ist unterwegs"))
        XCTAssertTrue(found("00340434161094015902"))
        XCTAssertFalse(found("X00340434161094015902"))
        XCTAssertFalse(found("0034043416109401590"))
        // Links and cards are found by their own kinds; short codes by nothing.
        XCTAssertNil(Finder.printedPattern(ofCode: "https://shop.example.com"))
        XCTAssertNil(Finder.printedPattern(ofCode: "12345"))
        XCTAssertNil(Finder.printedPattern(ofCode: String(repeating: "7", count: 41)))
    }

    func testANewRecommendedKindStartsOnOnceForWhoeverCoversAnything() throws {
        XCTAssertEqual(PrivateDetail.added(to: [.names], known: nil), [.barcodes])
        XCTAssertEqual(PrivateDetail.added(to: [], known: nil), [])
        XCTAssertEqual(PrivateDetail.added(to: [.names], known: PrivateDetail.allCases.map(\.rawValue)), [])
        XCTAssertEqual(PrivateDetail.added(to: [.names, .barcodes], known: nil), [])

        let suite = "PrivateDetailTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["names"], forKey: "hiddenDetails")
        PrivateDetail.bringUpToDate(["hiddenDetails", "notSaved"], in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenDetails"), ["barcodes", "names"])
        XCTAssertNil(defaults.stringArray(forKey: "notSaved"))
        // Turned off afterwards, it stays off.
        defaults.set(["names"], forKey: "hiddenDetails")
        PrivateDetail.bringUpToDate(["hiddenDetails"], in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenDetails"), ["names"])
    }

    /// Read from a picture, as the app does: a QR code is covered when codes
    /// are chosen, or when it holds a chosen kind, and left when it does not.
    func testACodeIsFoundInAPicture() throws {
        let image = try qrCode("https://shop.example.com/t/1024", at: CGPoint(x: 200, y: 200))
        let middle = CGPoint(x: 350 / 800.0, y: 350 / 800.0)
        let codes = Finder.areas(in: image, [.barcodes], rules: [])
        XCTAssertEqual(codes.count, 1)
        XCTAssertTrue(codes.contains { $0.contains(middle) }, "\(codes)")
        XCTAssertTrue(Finder.areas(in: image, [.links], rules: []).contains { $0.contains(middle) })
        XCTAssertFalse(Finder.areas(in: image, [.emails], rules: []).contains { $0.contains(middle) })
        // And the lock says why it was covered.
        XCTAssertEqual(Finder.coveredAreas(in: image, [.barcodes], rules: []).first?.kind, .barcodes)
        XCTAssertEqual(Finder.coveredAreas(in: image, [.links], rules: []).first { $0.rect.contains(middle) }?.kind, .links)
    }

    /// Each place covered is known by the kind that found it, and a rule's
    /// place as the owner's own, so the lock can say what was covered.
    func testEachPlaceIsKnownByTheKindThatFoundIt() throws {
        let image = try drawn(["lena.hoffmann@example.com", "Bestellung #1024", "Kundennummer: 88210"])
        let rules = [OwnRule(text: "Kundennummer", kind: .label)]
        let areas = Finder.coveredAreas(in: image, [.emails, .orders], rules: rules)
        let kinds = Set(areas.map(\.kind))
        XCTAssertTrue(kinds.contains(.emails), "\(areas)")
        XCTAssertTrue(kinds.contains(.orders), "\(areas)")
        XCTAssertTrue(kinds.contains(nil), "\(areas)")
        XCTAssertFalse(kinds.contains(.names), "only what is chosen")
        XCTAssertEqual(Finder.areas(in: image, [.emails, .orders], rules: rules).count, areas.count)
    }

    // MARK: Small print

    /// A whole screen at Retina size, as a screenshot is: text at the size
    /// of a page's body is read, and so is the small print of a footer.
    func testSmallPrintOnAWholeScreenIsRead() throws {
        let image = try screen([("Lena Hoffmann, lena.hoffmann@example.com", 26, 1500),
                                ("IBAN DE89 3704 0044 0532 0130 00", 26, 1400),
                                ("Fragen? kontakt@shop-example.de", 18, 200),
                                ("Kleingedrucktes: info@shop-example.de", 14, 120)])
        let lines = Finder.textLines(in: image).map(\.string)
        let found = Finder.areas(in: image, [.emails], rules: [])
        XCTAssertGreaterThanOrEqual(found.count, 1, "body text: \(lines)")
        XCTAssertTrue(found.contains { $0.midY > 0.7 }, "the body's email: \(lines)")
        XCTAssertTrue(found.contains { $0.midY < 0.13 && $0.midY > 0.08 }, "the 18 px footer: \(lines)")
        XCTAssertTrue(found.contains { $0.midY < 0.08 }, "the 14 px small print: \(lines)")
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

    /// A QR code of 300 points or so, sharp, on a white square of 800.
    private func qrCode(_ message: String, at origin: CGPoint) throws -> CGImage {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let code = try XCTUnwrap(filter.outputImage)
        let scale = 300 / code.extent.width
        let large = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let drawn = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(large, from: large.extent))
        let size = 800
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .none
        context.draw(drawn, in: CGRect(origin: origin, size: CGSize(width: drawn.width, height: drawn.height)))
        return try XCTUnwrap(context.makeImage())
    }

    /// A Retina screen, 2880 by 1800, with lines of text of the given size
    /// at the given height from the bottom.
    private func screen(_ lines: [(text: String, size: CGFloat, y: CGFloat)]) throws -> CGImage {
        let width = 2880, height = 1800
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for line in lines {
            let font = CTFontCreateWithName("Helvetica" as CFString, line.size, nil)
            let text = NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: CGColor(gray: 0.1, alpha: 1)])
            context.textPosition = CGPoint(x: 120, y: line.y)
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        return try XCTUnwrap(context.makeImage())
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
