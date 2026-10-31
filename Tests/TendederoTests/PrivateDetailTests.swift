import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
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
        XCTAssertTrue(PrivateDetail.recommended.contains(.keys))
        XCTAssertEqual(PrivateDetail.barcodes.group, .documents)
        XCTAssertEqual(PrivateDetail.keys.group, .access)
        XCTAssertEqual(PrivateDetail.ipAddresses.group, .access)
        XCTAssertEqual(PrivateDetail.health.group, .health)
        XCTAssertEqual(PrivateDetail.organizations.group, .organizations)
        // Patients' names are health data: on, even for whoever leaves other names.
        XCTAssertTrue(PrivateDetail.recommended.contains(.patientNames))
        // A date of birth tells who someone is, as a name does.
        XCTAssertTrue(PrivateDetail.recommended.contains(.birthDates))
        XCTAssertEqual(PrivateDetail.birthDates.group, .people)
        XCTAssertEqual(FormFields.Entity.dateOfBirth.detail, .birthDates)
        XCTAssertEqual(FormFields.Entity.date.detail, .dates)
        // Everyone's names: Names and its two parts, each covering its own people.
        XCTAssertTrue(PrivateDetail.recommended.isSuperset(of: PrivateDetail.allNames))
        XCTAssertEqual(PrivateDetail.patientNames.group, .people)
        XCTAssertEqual(PrivateDetail.otherPeople.group, .people)
        // What a screenshot is usually sent for stays visible until chosen,
        // and so does the shop or the practice it comes from.
        for kind in [PrivateDetail.amounts, .dates, .links, .orders, .faces, .ipAddresses, .organizations] {
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

    func testLicenceKeysAndPasswordsInSettings() {
        let text = "Lizenz: ABCD1-EFGH2-IJKL3-MNOP4-QRST5\npassword=hunter22\nUUID 123E4567-E89B-12D3-A456-426614174000"
        XCTAssertEqual(pieces(text, [.codes]), ["ABCD1-EFGH2-IJKL3-MNOP4-QRST5", "hunter22"])
    }

    func testAPIKeysAndTokens() {
        let text = """
            OPENAI_API_KEY=sk-proj-4fGh7Kp2Qx9Lm3Vb8Nc1Zr6Td
            ghp_16C7e42F292c6912E7710c838347Ae178B4a
            AKIAIOSFODNN7EXAMPLE
            Authorization: Bearer abcDEF123456ghiJKL789
            max_tokens: 4096
            commit 3f09f680585c6ab69e45d7b7623a6aabbccdd11
            testTheSampleShowsEveryKindButFaces42
            """
        XCTAssertEqual(pieces(text, [.keys]), ["sk-proj-4fGh7Kp2Qx9Lm3Vb8Nc1Zr6Td", "ghp_16C7e42F292c6912E7710c838347Ae178B4a",
                                               "AKIAIOSFODNN7EXAMPLE", "abcDEF123456ghiJKL789"])
        // A key reads as chance made it; words run together, or a commit, do not.
        XCTAssertTrue(Finder.looksRandom("dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"))
        XCTAssertFalse(Finder.looksRandom("MozillaFirefoxDeveloperEdition2026Beta"))
        XCTAssertFalse(Finder.looksRandom("3f09f680585c6ab69e45d7b7623a6aabbccdd11"))
    }

    func testIPAddresses() {
        let text = """
            Server 203.0.113.42 is up
            Router 192.168.0.1/24.
            Version 1.2.3.4.5
            Time 12:30:45
            2001:db8::8a2e:370:7334
            MAC a4:83:e7:12:34:56
            """
        XCTAssertEqual(pieces(text, [.ipAddresses]), ["203.0.113.42", "192.168.0.1/24", "2001:db8::8a2e:370:7334"])
        XCTAssertTrue(Finder.isIPv6("fe80::1%en0"))
        XCTAssertFalse(Finder.isIPv6("12:30:45"))
    }

    func testWalletsAndCoordinates() {
        XCTAssertEqual(pieces("Send to 0x52908400098527886E0F7030069857D2E4169EE7 now", [.bank]),
                       ["0x52908400098527886E0F7030069857D2E4169EE7"])
        XCTAssertEqual(pieces("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", [.bank]),
                       ["bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"])
        let places = "Pin at 52.520008, 13.404954\n52°31'12.0\"N 13°24'17.8\"E\nTotal 12.50, 13.00"
        XCTAssertEqual(pieces(places, [.addresses]), ["52.520008, 13.404954", "52°31'12.0\"N 13°24'17.8\"E"])
        XCTAssertEqual(pieces("NI number AB 12 34 56 C", [.ids]), ["AB 12 34 56 C"])
    }

    func testAmounts() {
        let text = "Gesamt 74,00 €\nTotal $1,250.00\nEUR 12.50\nArtikel 3"
        XCTAssertEqual(pieces(text, [.amounts]), ["74,00 €", "$1,250.00", "EUR 12.50"])
    }

    func testDatesOfBirthByTheWordBeforeThem() {
        let text = """
            geb. 12.03.1985
            Geburtsdatum: 03.07.1990
            Mustermann, Erika * 01.02.1960
            DOB 1985-03-12
            geboren am 3. März 1975
            Termin am 05.06.2026
            Gebiet 12.03.2026
            """
        XCTAssertEqual(pieces(text, [.birthDates]), ["12.03.1985", "03.07.1990", "01.02.1960", "1985-03-12", "3. März 1975"])
    }

    func testAnIBANReadWithASpaceAfterItsCountryAndTheBanksCode() {
        let text = "DE 89 3704 0044 0532 0130 00\nDAAEDEDDXXX\nRADIOLOGIE\nMR 12 2024 0101"
        XCTAssertEqual(pieces(text, [.bank]), ["DE 89 3704 0044 0532 0130 00", "DAAEDEDDXXX"])
        // A BIC counts only beside an IBAN or its own word.
        XCTAssertEqual(pieces("COBADEFFXXX", [.bank]), [])
        XCTAssertEqual(pieces("BIC: COBADEFFXXX", [.bank]), ["COBADEFFXXX"])
        XCTAssertTrue(Finder.isIBANShaped("DE89370400440532013000"))
        XCTAssertFalse(Finder.isIBANShaped("MR 12 2024 0101"))
    }

    func testAStreetAndTownOnOneLine() {
        let text = "Mustermann, Erika, Lindenberg 12,23456 Musterstadt\nLWK 5/SWK 1, 12 mm\nHamburg, den 05.06.2026"
        XCTAssertEqual(pieces(text, [.addresses]), ["Lindenberg 12,23456 Musterstadt"])
        XCTAssertTrue(Finder.isStreetLine("Am Markt 3a"))
        XCTAssertTrue(Finder.isStreetLine("Hauptstr. 5-7, 12345 Musterstadt"))
        XCTAssertTrue(Finder.isStreetLine("221B Baker Street"))
        XCTAssertFalse(Finder.isStreetLine("Telefon 040 1234567"))
        XCTAssertFalse(Finder.isStreetLine("LWK 5/SWK 1"))
        XCTAssertTrue(Finder.isTownLine("23456 Musterstadt"))
        XCTAssertTrue(Finder.isTownLine("D-23456 Musterstadt"))
        XCTAssertFalse(Finder.isTownLine("2 Tabletten täglich"))
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

    // MARK: Phone numbers

    func testWhatMakesAPhoneNumber() {
        /// Whether `number` in `line` is a phone number on this kind of document.
        func phone(_ number: String, in line: String? = nil, above: String? = nil, on document: DocumentKind) -> Bool {
            let line = line ?? number
            let range = line.range(of: number)!
            return Finder.isPhone(range, in: line, above: above, document: document)
        }
        // Written as one is dialled, or after a word that says so, in any of the app's languages.
        XCTAssertTrue(phone("040-1234567", in: "Tel.: 040-1234567", on: .medical))
        XCTAssertTrue(phone("+491761234567", on: .invoice))
        XCTAssertTrue(phone("0401234568", in: "Fax 0401234568", on: .medical))
        XCTAssertTrue(phone("0301234567", above: "Telefon", on: .invoice))
        for line in ["Teléfono 912345678", "Cep Tel: 05321234567", "GSM 05321234567", "هاتف: 0501234567",
                     "मोबाइल: 9876543210", "电话：13812345678", "ＴＥＬ 0312345678", "전화 0212345678", "Tlf. 912345678",
                     "Portable : 0612345678", "Me liga no 0612345678"] {
            let number = String(line.split(whereSeparator: { !$0.isNumber }).last!)
            XCTAssertTrue(phone(number, in: line, on: .invoice), line)
        }
        // "Tel." as small print reads it, and a call back.
        XCTAssertTrue(phone("0401234567", in: "Te!.: 0401234567", on: .medical))
        XCTAssertTrue(phone("0401234567", in: "Rückruf unter 0401234567", on: .medical))
        // A chat types its numbers bare.
        XCTAssertTrue(phone("017612345678", in: "Jonas: 017612345678", on: .general))
        XCTAssertTrue(phone("612345678", in: "mi número es 612345678", on: .general))
        // A document's bare run, or one after a word for another kind of number, is none.
        XCTAssertFalse(phone("021234560", on: .medical))
        XCTAssertFalse(phone("345678812", above: "Proktologie", on: .medical))
        for (number, line) in [("4711081500", "Kundennummer 4711081500"), ("4711081500", "Tel. 0301234567 Kd-Nr. 4711081500"),
                               ("912345679", "Factura 912345679"), ("0501234568", "رقم الفاتورة 0501234568"),
                               ("123456789", "Invoice Number 123456789"), ("0301234567", "Telekom Rechnung 0301234567"),
                               ("01310100", "CEP 01310100")] {
            XCTAssertFalse(phone(number, in: line, on: .invoice), line)
        }
    }

    func testTheDoctorsNumberCheckAndAHomeNumbersShape() {
        XCTAssertTrue(Finder.isDoctorNumber("345678812"))
        for number in ["021234560", "34567881", "3456788120", "34567881a"] {
            XCTAssertFalse(Finder.isDoctorNumber(number[...]), number)
        }
        XCTAssertTrue(Finder.isNationalNumber("017612345678"))
        XCTAssertTrue(Finder.isNationalNumber("0401234567"))
        XCTAssertFalse(Finder.isNationalNumber("021234560"))
        XCTAssertFalse(Finder.isNationalNumber("4711081500"))
    }

    // MARK: QR codes and barcodes

    func testWhatACodeHoldsIsReadByItsFormatAndItsText() {
        let giro = "BCD\n002\n1\nSCT\nBFSWDE33BER\nLena Hoffmann\nDE89370400440532013000\nEUR12.30\n\n\nRechnung 1024"
        XCTAssertTrue(Finder.kinds(ofCode: giro).isSuperset(of: [.bank, .names]))
        // A shop's own code names only the shop: it is no person's name.
        let shop = "BCD\r\n002\r\n1\r\nSCT\r\n\r\nMuster Versand GmbH\r\nDE89370400440532013000\r\nEUR49.90"
        XCTAssertTrue(Finder.kinds(ofCode: shop).isSuperset(of: [.bank, .organizations]))
        XCTAssertFalse(Finder.kinds(ofCode: shop).contains(.names))
        XCTAssertNil(Finder.kind(ofCode: shop, [.names]), "covering names leaves the shop's code")
        let bill = ["SPC", "0200", "1", "CH4431999123000889012", "S", "Robert Schneider AG", "Rue du Lac", "1268",
                    "2501", "Biel", "CH", "", "", "", "", "", "", "", "1949.75", "CHF", "S", "Pia-Maria Rutschmann-Schnyder",
                    "Grosse Marktgasse", "28", "9400", "Rorschach", "CH"].joined(separator: "\n")
        XCTAssertTrue(Finder.kinds(ofCode: bill).isSuperset(of: [.bank, .names, .organizations]), "the payer is a person")
        XCTAssertTrue(Finder.kinds(ofCode: "otpauth://totp/Shop:lena?secret=JBSWY3DPEHPK3PXP&issuer=Shop").contains(.codes))
        XCTAssertTrue(Finder.kinds(ofCode: "WIFI:T:WPA;S:Laden;P:geheim123;;").contains(.codes))
        let card = "BEGIN:VCARD\nVERSION:3.0\nFN:Lena Hoffmann\nTEL:+49 30 1234 5678\nEND:VCARD"
        XCTAssertTrue(Finder.kinds(ofCode: card).isSuperset(of: [.names, .phones]))
        XCTAssertTrue(Finder.kinds(ofCode: "https://shop.example.com/t/1024").contains(.links))
        XCTAssertTrue(Finder.kinds(ofCode: "M1HOFFMANN/LENA       E1A2B3C FRAJFKLH 0400").isSuperset(of: [.names, .ids]))
        XCTAssertTrue(Finder.kinds(ofCode: "00340434161094015902").contains(.tracking))
        XCTAssertTrue(Finder.kinds(ofCode: "geo:52.520008,13.404954").contains(.addresses))
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
        // A name or a company in a code never covers it alone: the account beside it does.
        XCTAssertNil(Finder.kind(ofCode: giro, [.names, .patientNames, .otherPeople, .organizations]))
        XCTAssertEqual(Finder.kind(ofCode: giro, [.names, .bank]), .bank)
        XCTAssertFalse(Finder.coversCode(giro, [.names]))
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
        XCTAssertEqual(PrivateDetail.added(to: [.names], known: nil),
                       [.barcodes, .keys, .patientNames, .otherPeople, .birthDates])
        XCTAssertEqual(PrivateDetail.added(to: [], known: nil), [])
        XCTAssertEqual(PrivateDetail.added(to: [.names], known: PrivateDetail.allCases.map(\.rawValue)), [])
        XCTAssertEqual(PrivateDetail.added(to: [.names, .barcodes, .keys, .patientNames, .otherPeople, .birthDates],
                                           known: nil), [])
        // Keys came after the sixteen; IP addresses came too, but wait to be chosen.
        let sixteen = PrivateDetail.allCases.filter { $0 != .keys && $0 != .ipAddresses }.map(\.rawValue)
        XCTAssertEqual(PrivateDetail.added(to: [.names], known: sixteen), [.keys])

        let suite = "PrivateDetailTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["names"], forKey: "hiddenDetails")
        PrivateDetail.bringUpToDate(["hiddenDetails", "notSaved"], in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenDetails"),
                       ["barcodes", "birthDates", "keys", "names", "otherPeople", "patientNames"])
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

    /// Read from a picture, as Copy Text does: with Keep the last four
    /// digits on, an IBAN's last four stay, in the text as in a copy.
    func testTheLastFourDigitsStayInTheTextToo() throws {
        let key = "keepLastDigits"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        let url = try saved(drawn(["IBAN: DE89 3704 0044 0532 0130 00"]))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        Finder.keepsLastDigits = true
        let kept = Finder.text(of: url, hiding: [.bank], rules: [])
        XCTAssertTrue(kept.hasSuffix("30 00"), kept)
        XCTAssertFalse(kept.contains("3704"), kept)
        Finder.keepsLastDigits = false
        XCTAssertFalse(Finder.text(of: url, hiding: [.bank], rules: []).contains("30 00"))
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
        XCTAssertEqual(OwnRules.load(from: defaults), [rules[1]], "an empty rule is never kept")
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

    /// A picture as a PNG in a folder of its own.
    private func saved(_ image: CGImage) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("page.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
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
