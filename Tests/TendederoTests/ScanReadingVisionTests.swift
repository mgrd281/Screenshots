import XCTest
@testable import Tendedero

/// Made-up pages as Vision read them on a Mac in CI (October 2026), line by
/// line as it gave them, each word with its box (`ScanReadingFixtureTests`
/// prints them): put in reading order here, so the order is checked against
/// what Vision really gives, on any machine. A receipt whose prices Vision
/// reads apart from their items, an invoice with an address beside its
/// details, a letter with a letterhead of small print down its side, and a
/// page turned on its side.
final class ScanReadingVisionTests: XCTestCase {
    /// A page from what the log says: "RAW name aspect", then each line
    /// Vision read, its confidence, then each word and its box ("word@x,y,w,h").
    static func page(_ dump: String) -> ScanReading.Page {
        var lines = dump.split(separator: "\n")
        let aspect = lines.isEmpty ? 1 : CGFloat(Double(lines.removeFirst().split(separator: " ").last ?? "") ?? 1)
        let segments = lines.map { line -> ScanReading.Segment in
            var parts = line.split(separator: " ")
            let confidence = Float(parts.removeFirst()) ?? 0
            return ScanReading.Segment(words: parts.compactMap { part -> ScanReading.Word? in
                guard let at = part.lastIndex(of: "@") else { return nil }
                let box = part[part.index(after: at)...].split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
                guard box.count == 4 else { return nil }
                return ScanReading.Word(text: String(part[..<at]), box: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]),
                                        unsure: confidence < ScanContent.sure)
            })
        }
        return ScanReading.page(segments, aspect: aspect)
    }

    private func order(_ text: String, _ parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: from..<text.endIndex) else {
                return XCTFail("\"\(part)\" not after what came before it, in:\n\(text)", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    func testAReceiptsItemsAndTheirPricesReadApartAreATable() {
        let text = ScanReading.text(Self.page(Self.receipt))
        XCTAssertTrue(text.contains("2 x Brötchen\t1,20 €\n1 x Kaffee\t2,80 €\n1 x Croissant\t1,90 €\nSumme\t5,90 €"), text)
        XCTAssertTrue(text.hasPrefix("Bäckerei Muster\n\nHauptstraße 1 • 10115 Berlin\n21.10.2026 08:14\n\n"), "the address and the time each a line: \(text)")
        XCTAssertTrue(text.hasSuffix("Kartenzahlung\nVielen Dank!"), text)
    }

    func testAnInvoicesAddressIsReadWholeThenItsDetailsItemsAndTotals() {
        let text = ScanReading.text(Self.page(Self.invoice))
        XCTAssertTrue(text.contains("Erika Mustermann\nMusterstraße 12\n20095 Hamburg\n\nRechnungsnr.\tRE-2026-0417\nDatum\t14.10.2026\nKundennr.\t48213"),
                      "the address, then the details beside it: \(text)")
        XCTAssertTrue(text.contains("Beratung (Stunden)\t3\t85,00 €\t255,00 €\n2 Druckpatronen Schwarz\t2\t24,90 €\t49,80 €"), text)
        XCTAssertTrue(text.contains("Netto\t310,70 €\nMwSt. 19%\t59,03 €\nGesamt\t369,73 €"), text)
        XCTAssertTrue(text.contains("bis zum 28.10.2026.\nIBAN: DE89 3704 0044 0532 0130 00 • BIC: COBADEFFXXX\nTelefon: 030 1234567"),
                      "a line that names what follows stands on its own: \(text)")
        order(text, ["Musterfirma GmbH", "Erika Mustermann", "Rechnungsnr.", "Rechnung", "Pos Beschreibung", "Netto", "Bitte überweisen", "BEZAHLT",
                     "Max Muster, Buchhaltung", "Amtsgericht Berlin"])
    }

    func testLinesThatNameWhatFollowsDoNotRunOn() {
        XCTAssertEqual(ScanReading.text(Self.page(Self.sideways)),
                       "Protokoll der Sitzung vom 14.10.2026\nAnwesend: Max Muster, Erika Mustermann\nNächster Termin: 28.10.2026")
    }

    func testALetterheadDownTheSideIsReadAfterTheLetterAndTheTextRunsOn() {
        let page = Self.page(Self.smallPrint)
        let text = ScanReading.text(page)
        XCTAssertTrue(text.contains("Sehr geehrte Frau Kollegin,\n\ndie Untersuchung ergab einen unauffälligen Befund. Größere Veränderungen sind "
                                    + "nicht erkennbar; die übrigen Strukturen erscheinen regelrecht. Ärztliche Rückfragen gern über unser Büro.\n\n"
                                    + "Mit freundlichen Grüßen"), text)
        order(text, ["Erika Musterfrau", "Befund vom 05.06.2026", "die Untersuchung", "Mit freundlichen Grüßen", "RADIOLOGIE AM MUSTERWALL",
                     "Dr. med. Jörg Müller", "BIC MUSTDEHHXXX", "Radiologie Süderstraße"])
        let headings = page.blocks.compactMap { block -> String? in
            guard case .paragraph(let paragraph) = block, paragraph.heading else { return nil }
            return paragraph.lines.map { ScanReading.line(of: $0) }.joined(separator: " ")
        }
        XCTAssertFalse(headings.contains("Mit freundlichen Grüßen"), "the closing is no heading, set larger than the letterhead though it is: \(headings)")
    }

    func testALetterIsReadFromItsSenderLineToItsClosing() {
        let text = ScanReading.text(Self.page(Self.letter))
        order(text, ["Praxis am Musterpark • Musterpark 3 • 20095 Hamburg", "Lena Brandtner\nLindenallee 14\n22301 Hamburg", "PRAXIS AM MUSTERPARK",
                     "MRT der Lendenwirbelsäule vom 05.06.2026", "Sehr geehrte Kolleginnen und Kollegen,", "Segmente sind unauffällig.",
                     "Mit freundlichen Grüßen\nDr. med. Paul Beispiel"])
    }

    // MARK: What Vision read

    static let receipt = """
        RAW receipt 0.2909090909090909
        1.00 Bäckerei@0.0750,0.9273,0.2891,0.0182 Muster@0.3719,0.9273,0.2406,0.0182
        1.00 Hauptstraße@0.0750,0.8895,0.2109,0.0111 1@0.2906,0.8895,0.0234,0.0109 •@0.3187,0.8895,0.0188,0.0109 10115@0.3422,0.8895,0.1078,0.0109 Berlin@0.4547,0.8895,0.0995,0.0111
        1.00 21.10.2026@0.0708,0.8655,0.1964,0.0109 08:14@0.2719,0.8655,0.0948,0.0109
        1.00 2@0.0708,0.8412,0.0350,0.0121 x@0.1109,0.8414,0.0305,0.0118 Brötchen@0.1465,0.8412,0.1785,0.0121
        1.00 1@0.0708,0.8132,0.0306,0.0121 x@0.1063,0.8136,0.0306,0.0118 Kaffee@0.1419,0.8133,0.1332,0.0122
        1.00 1@0.0708,0.7855,0.0323,0.0109 x@0.1078,0.7855,0.0328,0.0109 Croissant@0.1453,0.7855,0.1922,0.0109
        1.00 Summe@0.0705,0.7560,0.1881,0.0129
        1.00 Kartenzahlung@0.0791,0.7259,0.2376,0.0112
        1.00 Vielen@0.0667,0.7018,0.1365,0.0109 Dank!@0.2078,0.7018,0.1214,0.0109
        1.00 1,20@0.3917,0.8386,0.0943,0.0147 €@0.4922,0.8386,0.0370,0.0147
        1.00 2,80@0.3667,0.8109,0.0962,0.0159 €@0.4697,0.8109,0.0386,0.0159
        1.00 1,90@0.3871,0.7817,0.0938,0.0162 €@0.4867,0.7815,0.0387,0.0159
        1.00 5,90@0.4292,0.7527,0.1099,0.0182 €@0.5469,0.7527,0.0448,0.0182
        """

    static let invoice = """
        RAW invoice 0.7071398033347585
        1.00 M@0.0821,0.9157,0.0472,0.0305
        1.00 Musterfirma@0.1561,0.9273,0.1888,0.0218 GmbH@0.3487,0.9273,0.1010,0.0218
        1.00 Beispielweg@0.1561,0.9068,0.0867,0.0120 5@0.2449,0.9068,0.0127,0.0120 •@0.2597,0.9068,0.0063,0.0120 10115@0.2681,0.9068,0.0487,0.0120 Berlin@0.3189,0.9068,0.0425,0.0120
        1.00 Erika@0.0719,0.8358,0.0489,0.0147 Mustermann@0.1233,0.8358,0.1149,0.0147
        1.00 Musterstraße@0.0719,0.8154,0.1242,0.0132 12@0.1985,0.8154,0.0233,0.0132
        1.00 20095@0.0719,0.7936,0.0588,0.0160 Hamburg@0.1335,0.7936,0.0862,0.0160
        1.00 Rechnungsnr.@0.6057,0.8358,0.1129,0.0160
        1.00 Datum@0.6037,0.8169,0.0616,0.0160
        1.00 Kundennr.@0.6057,0.7965,0.0862,0.0160
        1.00 RE-2026-0417@0.7474,0.8372,0.1170,0.0131
        1.00 14.10.2026@0.7453,0.8167,0.0925,0.0134
        1.00 48213@0.7454,0.7965,0.0534,0.0131
        1.00 Rechnung@0.0737,0.7113,0.1771,0.0279
        1.00 Pos@0.0801,0.6714,0.0513,0.0132 Beschreibung@0.1337,0.6714,0.1189,0.0132
        1.00 Beratung@0.1335,0.6395,0.0750,0.0131 (Stunden)@0.2107,0.6395,0.0788,0.0131
        1.00 2@0.0801,0.6134,0.0185,0.0102
        1.00 Druckpatronen@0.1335,0.6119,0.1205,0.0116 Schwarz@0.2560,0.6119,0.0684,0.0116
        1.00 3@0.0801,0.5858,0.0123,0.0102
        1.00 Versandpauschale@0.1355,0.5843,0.1458,0.0116
        1.00 Menge@0.5112,0.6698,0.0619,0.0179
        1.00 3@0.5216,0.6381,0.0226,0.0160
        1.00 2@0.5216,0.6090,0.0226,0.0174
        1.00 1@0.5236,0.5828,0.0185,0.0145
        1.00 Einzelpreis@0.6242,0.6699,0.0987,0.0178
        1.00 85,00@0.6404,0.6376,0.0504,0.0195 €@0.6936,0.6384,0.0150,0.0190
        1.00 24,90@0.6385,0.6089,0.0516,0.0177 €@0.6929,0.6088,0.0156,0.0175
        1.00 5,90@0.6386,0.5814,0.0394,0.0175 €@0.6809,0.5813,0.0173,0.0175
        1.00 Netto@0.6260,0.5344,0.0520,0.0184
        1.00 MwSt.@0.6259,0.5116,0.0575,0.0213 19%@0.6863,0.5107,0.0492,0.0212
        1.00 Gesamt@0.6263,0.4898,0.0780,0.0160
        1.00 Betrag@0.7988,0.6701,0.0595,0.0160
        1.00 255,00@0.8090,0.6366,0.0605,0.0205 €@0.8729,0.6365,0.0142,0.0204
        1.00 49,80@0.8090,0.6089,0.0500,0.0191 €@0.8622,0.6092,0.0147,0.0189
        1.00 5,90@0.8090,0.5799,0.0402,0.0175 €@0.8523,0.5799,0.0142,0.0175
        1.00 310,70@0.8089,0.5331,0.0635,0.0194 €@0.8754,0.5337,0.0180,0.0189
        1.00 59,03@0.8090,0.5116,0.0545,0.0175 €@0.8664,0.5117,0.0165,0.0174
        1.00 369,73@0.8090,0.4869,0.0632,0.0190 €@0.8755,0.4870,0.0177,0.0189
        1.00 Bitte@0.0739,0.4273,0.0326,0.0133 überweisen@0.1089,0.4274,0.0937,0.0132 Sie@0.2050,0.4274,0.0281,0.0132 den@0.2354,0.4274,0.0328,0.0132 Betrag@0.2706,0.4274,0.0515,0.0132 bis@0.3244,0.4274,0.0258,0.0132 zum@0.3526,0.4274,0.0375,0.0132 28.10.2026.@0.3924,0.4273,0.0963,0.0133
        1.00 IBAN:@0.0698,0.4041,0.0485,0.0147 DE89@0.1209,0.4043,0.0463,0.0145 3704@0.1697,0.4043,0.0411,0.0145 0044@0.2134,0.4043,0.0411,0.0145 0532@0.2571,0.4043,0.0411,0.0145 0130@0.3008,0.4043,0.0437,0.0145 00@0.3470,0.4043,0.0206,0.0145 •@0.3702,0.4043,0.0077,0.0145 BIC:@0.3804,0.4043,0.0360,0.0145 COBADEFFXXX@0.4190,0.4041,0.1334,0.0147
        1.00 Telefon:@0.0718,0.3792,0.0627,0.0159 030@0.1371,0.3797,0.0301,0.0155 1234567@0.1697,0.3799,0.0709,0.0157 •@0.2432,0.3803,0.0056,0.0154 E-Mail:@0.2513,0.3803,0.0573,0.0157 buchhaltung@musterfirma.de@0.3112,0.3803,0.2351,0.0167
        1.00 BEZAHLT@0.5752,0.2823,0.2166,0.0485
        1.00 16.10.2026@0.5807,0.2531,0.1304,0.0321
        1.00 Max@0.0698,0.2166,0.0337,0.0131 Muster,@0.1058,0.2167,0.0544,0.0128 Buchhaltung@0.1625,0.2166,0.0880,0.0131
        1.00 Musterfirma@0.0719,0.0436,0.0654,0.0103 GmbH@0.1391,0.0436,0.0363,0.0103 •@0.1771,0.0436,0.0036,0.0103 Amtsgericht@0.1826,0.0436,0.0653,0.0103 Berlin@0.2497,0.0436,0.0326,0.0103 HRB@0.2842,0.0436,0.0272,0.0103 123456@0.3132,0.0436,0.0417,0.0103 •@0.3567,0.0436,0.0036,0.0103 USt-IdNr.@0.3622,0.0436,0.0526,0.0103 DE123456789@0.4166,0.0436,0.0804,0.0103
        """

    static let sideways = """
        RAW sideways 1.4144271570014144
        1.00 Protokoll@0.0610,0.8479,0.1134,0.0391 der@0.1779,0.8479,0.0447,0.0389 Sitzung@0.2260,0.8479,0.0962,0.0389 vom@0.3257,0.8479,0.0584,0.0389 14.10.2026@0.3876,0.8479,0.1342,0.0391
        1.00 Anwesend:@0.0596,0.7822,0.1304,0.0412 Max@0.1936,0.7822,0.0544,0.0410 Muster,@0.2516,0.7822,0.0870,0.0410 Erika@0.3422,0.7822,0.0616,0.0410 Mustermann@0.4075,0.7822,0.1492,0.0412
        1.00 Nächster@0.0583,0.7235,0.1089,0.0412 Termin:@0.1709,0.7235,0.0870,0.0410 28.10.2026@0.2615,0.7235,0.1343,0.0412
        """

    static let smallPrint = """
        RAW small-print 0.7074422583404619
        1.00 Erika@0.1088,0.8125,0.0431,0.0131 Musterfrau@0.1542,0.8125,0.0902,0.0131
        1.00 Lindenallee@0.1088,0.7934,0.0951,0.0147 14@0.2065,0.7934,0.0235,0.0147
        1.00 22301@0.1068,0.7733,0.0542,0.0146 Hamburg@0.1635,0.7733,0.0788,0.0146
        1.00 Befund@0.1088,0.7267,0.0656,0.0133 vom@0.1768,0.7267,0.0398,0.0133 05.06.2026@0.2189,0.7267,0.0952,0.0133
        1.00 Sehr@0.1068,0.7064,0.0413,0.0147 geehrte@0.1507,0.7066,0.0668,0.0145 Frau@0.2201,0.7066,0.0411,0.0145 Kollegin,@0.2638,0.7064,0.0730,0.0147
        1.00 die@0.1068,0.6873,0.0285,0.0147 Untersuchung@0.1378,0.6873,0.1156,0.0145 ergab@0.2560,0.6873,0.0514,0.0145 einen@0.3100,0.6873,0.0463,0.0145 unauffälligen@0.3588,0.6873,0.1079,0.0145 Befund.@0.4693,0.6873,0.0666,0.0147
        1.00 Größere@0.1088,0.6685,0.0694,0.0146 Veränderungen@0.1808,0.6685,0.1285,0.0145 sind@0.3118,0.6685,0.0360,0.0145 nicht@0.3504,0.6685,0.0437,0.0145 erkennbar;@0.3966,0.6685,0.0899,0.0145 die@0.4891,0.6685,0.0257,0.0145 übrigen@0.5174,0.6685,0.0658,0.0146
        1.00 Strukturen@0.1068,0.6497,0.0869,0.0160 erscheinen@0.1965,0.6497,0.0923,0.0158 regelrecht.@0.2916,0.6497,0.0923,0.0158 Ärztliche@0.3866,0.6497,0.0727,0.0158 Rückfragen@0.4621,0.6497,0.0964,0.0160
        1.00 gern@0.1088,0.6322,0.0375,0.0133 über@0.1487,0.6322,0.0398,0.0133 unser@0.1908,0.6322,0.0492,0.0133 Büro.@0.2424,0.6322,0.0472,0.0133
        1.00 Mit@0.1088,0.6146,0.0254,0.0120 freundlichen@0.1363,0.6146,0.1058,0.0120 Grüßen@0.2443,0.6146,0.0638,0.0120
        1.00 RADIOLOGIE@0.7187,0.9055,0.0824,0.0073 AM@0.8024,0.9055,0.0206,0.0073 MUSTERWALL@0.8242,0.9055,0.0916,0.0073
        1.00 MAMMA-DIAGNOSTIK@0.7187,0.8852,0.1355,0.0087
        1.00 Ärzte@0.7184,0.8716,0.0290,0.0094 für@0.7487,0.8716,0.0169,0.0089 Radiologie@0.7668,0.8702,0.0589,0.0099
        1.00 Dr.@0.7187,0.8576,0.0168,0.0087 med.@0.7370,0.8576,0.0287,0.0086 Jörg@0.7672,0.8576,0.0257,0.0086 Müller@0.7944,0.8576,0.0331,0.0087
        1.00 Dr.@0.7187,0.8459,0.0168,0.0087 med.@0.7370,0.8460,0.0287,0.0086 René@0.7672,0.8460,0.0287,0.0086 Brückner@0.7975,0.8459,0.0506,0.0087
        1.00 Dr.@0.7187,0.8343,0.0169,0.0074 med.@0.7369,0.8345,0.0283,0.0073 Sören@0.7664,0.8345,0.0334,0.0073 Weiß@0.8011,0.8343,0.0285,0.0074
        1.00 Évelyne@0.7187,0.8212,0.0437,0.0103 Größer,@0.7642,0.8212,0.0381,0.0103 MBA@0.8041,0.8212,0.0275,0.0103
        1.00 Musterwall@0.7187,0.8080,0.0589,0.0090 7a@0.7792,0.8080,0.0143,0.0090 •@0.7950,0.8080,0.0048,0.0090 20354@0.8014,0.8080,0.0333,0.0090 Hamburg@0.8363,0.8080,0.0528,0.0090
        1.00 Telefon@0.7173,0.7966,0.0403,0.0073 040@0.7589,0.7966,0.0221,0.0073 1234567-0@0.7823,0.7966,0.0575,0.0073
        1.00 Telefax@0.7187,0.7834,0.0395,0.0087 040@0.7597,0.7836,0.0212,0.0086 1234567-66@0.7823,0.7834,0.0637,0.0087
        1.00 praxis@radiologie-musterwall.de@0.7187,0.7703,0.1725,0.0087
        1.00 www.radiologie-musterwall.de@0.7187,0.7587,0.1602,0.0087
        1.00 MRT-DIAGNOSTIK@0.7187,0.7398,0.1129,0.0087
        1.00 Öffnungszeiten@0.7187,0.7253,0.0800,0.0104 Mo-Fr@0.8005,0.7254,0.0345,0.0103 8-18@0.8368,0.7254,0.0272,0.0103 Uhr@0.8658,0.7253,0.0213,0.0104
        1.00 Übrige@0.7187,0.7121,0.0383,0.0103 Zeiten@0.7588,0.7121,0.0326,0.0103 nach@0.7932,0.7121,0.0290,0.0103 Absprache@0.8241,0.7121,0.0589,0.0103
        1.00 Musterbank@0.7166,0.7006,0.0663,0.0087 Hamburg@0.7845,0.7006,0.0513,0.0087
        1.00 DE12@0.7187,0.6890,0.0304,0.0087 3456@0.7506,0.6891,0.0287,0.0086 7890@0.7808,0.6891,0.0272,0.0086 1234@0.8096,0.6891,0.0287,0.0086 5678@0.8398,0.6891,0.0272,0.0086 90@0.8685,0.6890,0.0145,0.0087
        1.00 BIC@0.7187,0.6773,0.0220,0.0074 MUSTDEHHXXX@0.7420,0.6773,0.0896,0.0074
        1.00 WEITERER@0.7187,0.6570,0.0682,0.0087 STANDORT@0.7884,0.6570,0.0720,0.0087
        1.00 Radiologie@0.7187,0.6424,0.0576,0.0087 Süderstraße@0.7778,0.6424,0.0661,0.0087
        """

    static let letter = """
        RAW letter 0.7071398033347585
        1.00 Praxis@0.0842,0.8632,0.0316,0.0090 am@0.1174,0.8632,0.0159,0.0090 Musterpark@0.1348,0.8632,0.0571,0.0090 •@0.1935,0.8632,0.0032,0.0090 Musterpark@0.1983,0.8632,0.0571,0.0090 3@0.2570,0.8632,0.0063,0.0090 •@0.2650,0.8632,0.0048,0.0090 20095@0.2713,0.8632,0.0317,0.0090 Hamburg@0.3046,0.8632,0.0465,0.0090
        1.00 Lena@0.0821,0.8358,0.0476,0.0160 Brandtner@0.1326,0.8358,0.0872,0.0160
        1.00 Lindenallee@0.0842,0.8167,0.1001,0.0147 14@0.1868,0.8167,0.0247,0.0147
        1.00 22301@0.0821,0.7949,0.0575,0.0162 Hamburg@0.1425,0.7949,0.0813,0.0162
        1.00 PRAXIS@0.7105,0.9259,0.0725,0.0174 AM@0.7860,0.9261,0.0272,0.0171 MUSTERPARK@0.8162,0.9259,0.1304,0.0174
        1.00 Radiologie@0.7084,0.9011,0.0760,0.0161
        1.00 Musterpark@0.7084,0.8850,0.0772,0.0149 3@0.7880,0.8853,0.0108,0.0146
        1.00 20095@0.7064,0.8675,0.0486,0.0162 Hamburg@0.7579,0.8675,0.0614,0.0162
        1.00 Telefon@0.7084,0.8517,0.0516,0.0146 040@0.7625,0.8517,0.0257,0.0145 1234567@0.7908,0.8517,0.0572,0.0146
        1.00 Dr.@0.7084,0.8167,0.0259,0.0147 med.@0.7369,0.8167,0.0334,0.0145 Paul@0.7728,0.8167,0.0308,0.0145 Beispiel@0.8062,0.8167,0.0521,0.0147
        1.00 Dr.@0.7105,0.7994,0.0241,0.0174 med.@0.7376,0.7996,0.0333,0.0171 Jana@0.7739,0.7996,0.0302,0.0171 Probe@0.8071,0.7994,0.0430,0.0174
        1.00 Dr.@0.7084,0.7833,0.0250,0.0175 med.@0.7365,0.7833,0.0341,0.0175 Tom@0.7737,0.7833,0.0248,0.0175 Muster@0.8015,0.7833,0.0506,0.0175
        1.00 Unser@0.0842,0.7093,0.0376,0.0087 Zeichen:@0.1233,0.7094,0.0529,0.0085 4711023@0.1778,0.7093,0.0522,0.0087
        1.00 Brandtner,@0.0924,0.6786,0.0920,0.0162 Lena@0.1873,0.6786,0.0386,0.0162
        1.00 Lindenallee@0.0924,0.6598,0.0920,0.0162 14,22301@0.1873,0.6598,0.0718,0.0162 Hamburg@0.2619,0.6598,0.0707,0.0162
        1.00 Hamburg,@0.4559,0.7209,0.0797,0.0145 den@0.5381,0.7209,0.0283,0.0145 05.06.2026@0.5689,0.7209,0.0882,0.0145
        1.00 geb.@0.4908,0.6802,0.0387,0.0146 05.03.1992@0.5320,0.6802,0.0860,0.0146
        1.00 MRT@0.0862,0.6162,0.0390,0.0117 der@0.1273,0.6162,0.0326,0.0115 Lendenwirbelsäule@0.1620,0.6162,0.1653,0.0115 vom@0.3293,0.6162,0.0408,0.0115 05.06.2026@0.3721,0.6162,0.0919,0.0117
        1.00 Sehr@0.0842,0.5756,0.0407,0.0131 geehrte@0.1271,0.5756,0.0635,0.0128 Kolleginnen@0.1929,0.5756,0.0975,0.0128 und@0.2926,0.5756,0.0340,0.0128 Kollegen,@0.3289,0.5756,0.0777,0.0131
        1.00 wir@0.0821,0.5538,0.0258,0.0146 berichten@0.1105,0.5538,0.0771,0.0145 über@0.1901,0.5538,0.0385,0.0145 LENA@0.2313,0.5538,0.0488,0.0145 BRANDTNER@0.2826,0.5538,0.1156,0.0145 nach@0.4008,0.5538,0.0411,0.0145 der@0.4445,0.5538,0.0308,0.0145 Untersuchung@0.4779,0.5538,0.1134,0.0146
        1.00 in@0.0821,0.5349,0.0185,0.0117 unserer@0.1026,0.5350,0.0653,0.0115 Praxis.@0.1700,0.5350,0.0571,0.0115 Die@0.2291,0.5350,0.0286,0.0115 Akte@0.2597,0.5350,0.0388,0.0115 lautet@0.3006,0.5350,0.0490,0.0115 auf@0.3516,0.5350,0.0286,0.0115 Lena@0.3822,0.5349,0.0408,0.0117
        1.00 Brandtner.@0.0862,0.5115,0.0822,0.0132 Rückfragen@0.1708,0.5115,0.0961,0.0132 von@0.2692,0.5115,0.0328,0.0132 Lena@0.3043,0.5115,0.0422,0.0132 Brandtnar@0.3489,0.5115,0.0820,0.0132 bitte@0.4332,0.5115,0.0375,0.0132 an@0.4730,0.5115,0.0234,0.0132 die@0.4988,0.5115,0.0248,0.0132
        1.00 Praxis.@0.0862,0.4897,0.0541,0.0132 Die@0.1427,0.4897,0.0305,0.0132 übrigen@0.1755,0.4897,0.0633,0.0132 Segmente@0.2411,0.4897,0.0843,0.0132 sind@0.3278,0.4897,0.0375,0.0132 unauffällig.@0.3676,0.4897,0.0903,0.0132
        1.00 Mit@0.0862,0.4504,0.0238,0.0103 freundlichen@0.1119,0.4504,0.1034,0.0103 Grüßen@0.2170,0.4504,0.0622,0.0103
        1.00 Dr.@0.0862,0.4273,0.0227,0.0116 med.@0.1109,0.4274,0.0449,0.0115 Paul@0.1579,0.4274,0.0388,0.0115 Beispiel@0.1987,0.4273,0.0662,0.0116
        """
}
