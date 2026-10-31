import Foundation
@testable import Tendedero

/// German papers whose address block has no label read over it, as a
/// scan of small print reads them: a sick note's insured person, the
/// surname over the given name, with the doctor's stamp repeating the
/// practice's and the doctor's numbers; a company's letter to a customer,
/// with a street that has no word like "Straße" in it and the country's
/// letter before the postcode; and a newsletter whose words with a number
/// look like streets and towns but are none. Made up like the rest, with a
/// seed of their own, so the other documents stay as they were.
extension CoverCorpus {
    static var postalDocuments: [Document] {
        var random = Seeded(20_261_031)
        let german = languages[0]
        var all: [Document] = []
        for _ in 0..<2 {
            all.append(sickNoteCopy(german, &random))
            all.append(customerLetter(german, &random))
            all.append(newsletter())
        }
        return all
    }

    /// Streets without a word like "Straße", as many are named.
    static let plainStreets = ["Birkenhöhe", "Mühlenkamp", "Sonnenhang", "Am Lindenhof", "Eichenhain", "Lerchenfeld"]

    static func sickNoteCopy(_ l: Language, _ random: inout Seeded) -> Document {
        let insured = person(l, &random)
        let street = "\(random.pick(plainStreets)) \(random.int(2...148))"
        // A practice's number that is no doctor's by its check digit, and a
        // doctor's number that is.
        var practice = random.digits(9)
        while Finder.isDoctorNumber(practice[...]) { practice = random.digits(9) }
        let first = (0..<6).map { _ in random.int(0...9) }
        let check = (10 - zip(first, [4, 9, 4, 9, 4, 9]).map(*).reduce(0, +) % 10) % 10
        let doctor = (first + [check]).map(String.init).joined() + random.digits(2)
        let doctorName = person(l, &random).name
        let rows: [[Part]] = [
            [.keep("Muster BKK")],
            // The surname's row with the date of birth's label at its end,
            // the given name's with the date, each read as one line.
            [.secret(Kind.names, insured.last), " geb. am"],
            [.secret(Kind.names, insured.first), " ", .secret(Kind.birthDates, l.birth.value)],
            [.secret(Kind.addresses, street)],
            [.secret(Kind.addresses, "D " + insured.town)],
            [.plain("Betriebsstätten-Nr.   Arzt-Nr.   Datum")],
            [.secret(Kind.ids, practice), .plain("             "), .secret(Kind.ids, doctor), .plain("  "), .keep("05.10.26")],
            [.keep("Arbeitsunfähigkeitsbescheinigung")],
            [.keep("Erstbescheinigung")],
            // The doctor's stamp, repeating both numbers.
            [.secret(Kind.ids, practice)],
            [.plain("Tel. "), .secret(Kind.phones, "040 \(random.digits(7))")],
            [.plain("Dr. med. "), .secret(Kind.names, doctorName)],
            [.keep("Fachärztin für Chirurgie")],
            [.keep("Proktologie")],
            [.secret(Kind.ids, doctor)],
        ]
        return Document(l.code, "sick note copy", rows)
    }

    static func customerLetter(_ l: Language, _ random: inout Seeded) -> Document {
        let customer = person(l, &random)
        let street = "\(random.pick(plainStreets)) \(random.int(2...148))"
        let woman = ["Lena", "Miriam", "Katrin", "Sabine"].contains(customer.first)
        let rows: [[Part]] = [
            [.keep("Stadtwerke Musterstadt GmbH")],
            [.plain(woman ? "Frau" : "Herrn")],
            [.secret(Kind.names, customer.name)],
            [.secret(Kind.addresses, street)],
            [.secret(Kind.addresses, "D-" + customer.town)],
            [.keep("Bestätigung Ihrer Kündigung")],
            [woman ? "Sehr geehrte Frau " : "Sehr geehrter Herr ", .secret(Kind.names, customer.last), ","],
            [.keep("wir bestätigen die Kündigung zum 31.12.2026.")],
            [.keep("Mit freundlichen Grüßen")],
            [.keep("Ihr Kundenservice")],
        ]
        return Document(l.code, "customer letter", rows)
    }

    /// Words with a number that are no street, some over a number and a
    /// word that read as a postcode and its town.
    static func newsletter() -> Document {
        let rows: [[Part]] = [
            [.keep("Vereinszeitung")],
            [.keep("Frohe Ostern")],
            [.keep("Ausgabe 2")],
            [.keep("Offene Kurse")],
            [.keep("Stufe 3")],
            [.keep("2026 Programm")],
            [.keep("Gesundheit im Alltag")],
            [.keep("Diabetes mellitus Typ 2")],
            [.keep("Kapitel 4")],
            [.keep("1000 Euro")],
        ]
        return Document("de", "newsletter", rows)
    }
}
