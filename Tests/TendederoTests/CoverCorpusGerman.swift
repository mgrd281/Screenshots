import Foundation
@testable import Tendedero

/// More German papers than the seven kinds every language has: a tax
/// office's notice, a tenancy agreement, a bank statement, a chat as an
/// export writes it, a CV and an order confirmation. Made up like the rest,
/// from the German pools, with a seed of their own, so the other documents
/// stay as they were.
extension CoverCorpus {
    static var germanDocuments: [Document] {
        var random = Seeded(20_261_029)
        let german = languages[0]
        var all: [Document] = []
        for round in 0..<2 {
            all.append(taxNotice(german, &random))
            all.append(tenancy(german, &random))
            all.append(statement(german, &random))
            all.append(chatExport(german, &random, android: round == 1))
            all.append(cv(german, &random))
            all.append(order(german, &random))
        }
        return all
    }

    /// Whether a made-up first name is a woman's, for "Frau" or "Herrn".
    private static func isWoman(_ first: String) -> Bool {
        ["Lena", "Miriam", "Katrin", "Sabine"].contains(first)
    }

    static func taxNotice(_ l: Language, _ random: inout Seeded) -> Document {
        let payer = person(l, &random)
        let number = "\(random.digits(2))/\(random.int(100...999))/\(random.digits(5))"
        let rows: [[Part]] = [
            [.keep("Finanzamt Musterstadt")],
            [.keep("Bescheid für 2025 über Einkommensteuer")],
            ["Steuernummer: ", .secret(Kind.ids, number)],
            ["Identifikationsnummer: ", .secret(Kind.ids, steuerID(&random))],
            [.plain(isWoman(payer.first) ? "Frau" : "Herrn")],
            [.secret(Kind.names, payer.name)],
            [.secret(Kind.addresses, payer.street)],
            [.secret(Kind.addresses, payer.town)],
            ["Festgesetzt werden: ", .keep(l.money(random.int(80_000...900_000)))],
            ["Erstattung: ", .keep(l.money(random.int(5_000...90_000)))],
            ["Der Betrag wird überwiesen auf ", .secret(Kind.bank, l.iban(&random))],
        ]
        return Document(l.code, "tax notice", rows)
    }

    static func tenancy(_ l: Language, _ random: inout Seeded) -> Document {
        let landlord = person(l, &random), tenant = person(l, &random), flat = person(l, &random)
        let owner = isWoman(landlord.first) ? "Vermieterin" : "Vermieter"
        let rent = random.int(50_000...160_000)
        let rows: [[Part]] = [
            [.keep("Mietvertrag für Wohnräume")],
            ["Zwischen"],
            [.secret(Kind.names, landlord.name), ", ", .secret(Kind.addresses, landlord.street), ", ",
             .secret(Kind.addresses, landlord.town)],
            ["– \(owner) –"],
            ["und"],
            [.secret(Kind.names, tenant.name), ", geb. ", .secret(Kind.birthDates, l.birth.value)],
            ["– \(isWoman(tenant.first) ? "Mieterin" : "Mieter") –"],
            ["§ 1 Mietsache: Wohnung im 2. OG, ", .secret(Kind.addresses, flat.street), ", ",
             .secret(Kind.addresses, flat.town)],
            ["§ 3 Miete: ", .keep(l.money(rent)), " monatlich"],
            ["Kaution: ", .keep(l.money(rent * 3))],
            ["Konto der \(owner == "Vermieterin" ? "Vermieterin" : "Vermieters"): ", .secret(Kind.bank, l.iban(&random))],
        ]
        return Document(l.code, "tenancy", rows)
    }

    static func statement(_ l: Language, _ random: inout Seeded) -> Document {
        let holder = person(l, &random), paid = person(l, &random), payer = person(l, &random)
        let rows: [[Part]] = [
            [.keep("Musterbank eG")],
            [.keep("Kontoauszug Nr. 3/2026")],
            ["Kontoinhaber: ", .secret(Kind.names, holder.name)],
            ["IBAN: ", .secret(Kind.bank, l.iban(&random))],
            [.keep("Datum"), " ", .keep("Buchungstext"), " ", .keep("Betrag")],
            ["01.03. Gehalt ", .keep(l.shop), " ", .keep(l.money(random.int(180_000...420_000)))],
            ["03.03. Lastschrift ", .keep("Stadtwerke Musterstadt"), " -", .keep(l.money(random.int(4_000...12_000)))],
            ["05.03. Überweisung an ", .secret(Kind.names, paid.name), " -",
             .keep(l.money(random.int(2_000...30_000)))],
            ["10.03. Gutschrift von ", .secret(Kind.names, payer.name), " ",
             .keep(l.money(random.int(2_000...30_000)))],
            ["Neuer Kontostand: ", .keep(l.money(random.int(100_000...500_000)))],
        ]
        return Document(l.code, "bank statement", rows)
    }

    /// A chat as its export, or a copied message, writes it: the date and
    /// time before each writer, as on an iPhone or, with a dash, on Android.
    static func chatExport(_ l: Language, _ random: inout Seeded, android: Bool) -> Document {
        let one = person(l, &random)
        var two = person(l, &random), three = person(l, &random)
        while two.first == one.first { two = person(l, &random) }
        while three.first == one.first || three.first == two.first { three = person(l, &random) }
        func at(_ minute: Int) -> String {
            android ? "12.03.26, 14:\(minute) - " : "[12.03.26, 14:\(minute):0\(minute % 10)] "
        }
        let phone = "0\(random.pick(["221", "30", "89", "40"])) \(random.digits(7))"
        let rows: [[Part]] = [
            [.plain(at(10)), .secret(Kind.names, one.first), ": Hat jemand die Adresse von Oma?"],
            [.plain(at(12)), .secret(Kind.names, two.first), ": ", .secret(Kind.addresses, two.street), ", ",
             .secret(Kind.addresses, two.town)],
            [.plain(at(13)), .secret(Kind.names, one.first), ": Danke! Und ihre Nummer?"],
            [.plain(at(14)), .secret(Kind.names, two.first), ": ", .secret(Kind.phones, phone)],
            [.plain(at(20)), .secret(Kind.names, three.first), ": ", .secret(Kind.names, one.first),
             ", ich hol dich um 15 Uhr ab"],
            [.plain(at(21)), .secret(Kind.names, one.first), ": Super, danke ", .secret(Kind.names, three.first), "!"],
        ]
        return Document(l.code, "chat export", rows)
    }

    static func cv(_ l: Language, _ random: inout Seeded) -> Document {
        let applicant = person(l, &random)
        let rows: [[Part]] = [
            [.keep("Lebenslauf")],
            [.keep("Persönliche Daten")],
            ["Name: ", .secret(Kind.names, applicant.name)],
            ["Geburtsdatum: ", .secret(Kind.birthDates, l.birth.value)],
            ["Anschrift: ", .secret(Kind.addresses, applicant.street), ", ", .secret(Kind.addresses, applicant.town)],
            ["Telefon: ", .secret(Kind.phones, applicant.phone)],
            ["E-Mail: ", .secret(Kind.emails, applicant.email)],
            [.keep("Berufserfahrung")],
            [.keep("2019–2026"), " ", .keep(isWoman(applicant.first) ? "Sachbearbeiterin" : "Sachbearbeiter"), ", ",
             .keep(l.shop)],
            [.keep("Ausbildung")],
            [.keep("2016–2019"), " ", .keep("Ausbildung zur Kauffrau für Büromanagement")],
        ]
        return Document(l.code, "cv", rows)
    }

    static func order(_ l: Language, _ random: inout Seeded) -> Document {
        let customer = person(l, &random)
        let prices = (0..<2).map { _ in random.int(390...12_990) }
        var rows: [[Part]] = [
            [.keep(l.shop)],
            [.keep("Bestellbestätigung")],
            ["Bestellnummer: NV-\(random.digits(8))"],
            [.keep("Artikel"), " ", .keep("Menge"), " ", .keep("Preis")],
        ]
        for (item, price) in zip(l.items, prices) {
            rows.append([.keep(item), " 1 ", .keep(l.money(price))])
        }
        rows += [
            ["Gesamt: ", .keep(l.money(prices.reduce(0, +)))],
            [.keep("Lieferadresse")],
            [.secret(Kind.names, customer.name)],
            [.secret(Kind.addresses, customer.street)],
            [.secret(Kind.addresses, customer.town)],
            ["Sendungsnummer: JJD\(random.digits(18))"],
        ]
        return Document(l.code, "order", rows)
    }
}
