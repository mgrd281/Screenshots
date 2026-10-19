import Foundation

/// Who a name in a document belongs to, read from what stands around it: a
/// label like "Patient:", a title like "Dr. med.", the closing above a
/// signature, the date of birth after it.
enum PersonRole: String, CaseIterable, Codable, Sendable {
    case patient, doctor, customer, employee, other

    var title: String {
        switch self {
        case .patient: L("Patients")
        case .doctor: L("Doctors and medical staff")
        case .customer: L("Customers and account holders")
        case .employee: L("Employees and contacts")
        case .other: L("Everyone else")
        }
    }
}

/// A name's role, how sure the reading is, and what it was read from, for
/// the tests and for deciding when to ask the owner to check.
struct NameRole: Equatable, Sendable {
    var role: PersonRole
    /// From 0 to 1.
    var confidence: Double
    /// What gave it away, in a word or two, like "label" or "title".
    var reason: String

    /// Sure enough to cover or leave a name by its role alone.
    var isSure: Bool { confidence >= 0.6 }

    static let unknown = NameRole(role: .other, confidence: 0.3, reason: "none")
}

/// What a screenshot shows, guessed from its words, so a name is read in
/// that light: a medical letter, an invoice, a bank's page, or anything else.
enum DocumentKind: String, Sendable {
    case medical, invoice, banking, general
}

/// Reading a document's text the way a person would: which capitalized
/// words are a person and which a company, whose name a name is, and where
/// a label's value stops being a name. Pure text, so all of it is checked
/// without a picture; `Finder` brings the lines and where they are.
enum DocumentSense {
    // MARK: What kind of document

    private static let medicalWords = ["patient", "patientin", "diagnose", "diagnosis", "befund", "arzt", "ärztin",
                                       "klinik", "klinikum", "praxis", "radiologie", "labor", "therapie", "medikation",
                                       "anamnese", "untersuchung", "krankenhaus", "dr. med", "icd", "rezept",
                                       "überweisung", "facharzt", "fachärztin", "krankenkasse", "physician",
                                       "hospital", "clinic", "mrt", "sonographie", "röntgen", "blutbild", "arztbrief",
                                       "entlassung", "beurteilung", "المريض", "التشخيص", "пациент", "диагноз", "врач"]
    private static let invoiceWords = ["rechnung", "invoice", "rechnungsnummer", "bestellung", "order", "ust", "mwst",
                                       "netto", "brutto", "summe", "total", "betrag", "kunde", "kundennummer",
                                       "lieferung", "artikel", "menge", "preis", "zahlbar", "fällig", "subtotal",
                                       "فاتورة", "счет", "счёт"]
    private static let bankingWords = ["iban", "bic", "kontoauszug", "saldo", "buchung", "gutschrift", "lastschrift",
                                       "verwendungszweck", "kontoinhaber", "sparkasse", "transaction", "balance",
                                       "beneficiary", "payee", "überweisungsbetrag", "zahlungsempfänger",
                                       "حساب", "банк", "получатель"]

    /// The kind whose words a document has most of, at least two of them.
    static func kind(of lines: [String]) -> DocumentKind {
        let text = " " + lines.joined(separator: " ").lowercased() + " "
        func score(_ words: [String]) -> Int { words.filter { text.contains($0) }.count }
        let scores: [(DocumentKind, Int)] = [(.medical, score(medicalWords)), (.banking, score(bankingWords)),
                                             (.invoice, score(invoiceWords))]
        guard let best = scores.max(by: { $0.1 < $1.1 }), best.1 >= 2 else { return .general }
        return best.0
    }

    // MARK: Companies and organizations

    /// Legal forms, as they are written; short ones only in capitals.
    private static let legalForms: Set<String> = ["GmbH", "gGmbH", "mbH", "AG", "KG", "KGaA", "OHG", "GbR", "UG", "SE",
                                                  "e.V.", "eV", "e.K.", "Inc", "Inc.", "LLC", "Ltd", "Ltd.", "Limited",
                                                  "Corp", "Corp.", "Corporation", "PLC", "plc", "S.A.", "SA", "SARL",
                                                  "S.L.", "B.V.", "BV", "N.V.", "NV", "S.p.A.", "SpA", "Srl", "S.r.l.",
                                                  "Oy", "A/S", "AB", "LLP", "ООО", "ОАО", "ЗАО", "ПАО", "АО"]
    /// Words that name an organization wherever they stand, small letters.
    private static let organizationWords: Set<String> = [
        "praxis", "gemeinschaftspraxis", "arztpraxis", "klinik", "klinikum", "uniklinik", "universitätsklinikum",
        "krankenhaus", "hospital", "spital", "clinic", "mvz", "zentrum", "center", "centre", "labor", "laboratorium",
        "laboratory", "lab", "apotheke", "pharmacy", "bank", "sparkasse", "volksbank", "raiffeisenbank",
        "versicherung", "krankenkasse", "insurance", "aok", "bkk", "ikk", "dak", "barmer", "universität",
        "university", "hochschule", "institut", "institute", "stiftung", "foundation", "verein", "verband",
        "behörde", "ministerium", "ministry", "stadtverwaltung", "gemeinde", "landratsamt", "finanzamt", "jobcenter",
        "agentur", "abteilung", "department", "station", "radiologie", "kardiologie", "neurologie", "orthopädie",
        "gynäkologie", "dermatologie", "urologie", "onkologie", "pädiatrie", "chirurgie", "notaufnahme",
        "gruppe", "group", "holding", "company", "firma", "verlag", "restaurant", "hotel", "supermarkt",
        "مستشفى", "عيادة", "بنك", "شركة", "مختبر", "صيدلية", "больница", "клиника", "банк", "компания",
        "лаборатория", "аптека",
    ]
    /// Endings that make a German compound an organization, like
    /// "Radiologiepraxis" or "Volksbank".
    private static let organizationEndings = ["praxis", "klinik", "klinikum", "krankenhaus", "zentrum", "apotheke",
                                              "sparkasse", "versicherung", "krankenkasse", "bank", "amt", "labor",
                                              "institut", "verband", "verein", "stiftung", "gesellschaft"]
    /// Words with those endings that are no organization.
    private static let notOrganizations: Set<String> = ["datenbank", "sitzbank", "werkbank", "parkbank", "schulbank",
                                                        "gartenbank", "sandbank", "nebelbank", "insgesamt", "gesamt",
                                                        "samt", "amt", "laborwerte", "laborwert"]

    /// Whether a word, as it is written, makes its line an organization.
    static func isOrganizationWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ",;:()[]\"'"))
        if legalForms.contains(trimmed) { return true }
        let lower = trimmed.lowercased()
        guard !lower.isEmpty, !notOrganizations.contains(lower) else { return false }
        if organizationWords.contains(lower) { return true }
        // A compound, from its ending, written as a noun.
        guard trimmed.first?.isUppercase == true, lower.count >= 7 else { return false }
        return organizationEndings.contains { lower.hasSuffix($0) && lower.count > $0.count + 2 }
    }

    /// Whether a name-shaped piece of text is a company or an organization,
    /// like "Radiologie Zentrum Nord" or "Muster GmbH", rather than a person.
    static func isOrganization(_ text: String) -> Bool {
        words(of: text).contains(where: isOrganizationWord)
    }

    /// Small words inside an organization's name: "Zentrum für Radiologie".
    private static let connectors: Set<String> = ["für", "der", "des", "die", "und", "&", "am", "an", "im", "of",
                                                  "the", "and", "for", "de", "du", "la", "-"]

    /// The organizations named in a line: the run of capitalized words round
    /// a word that names one, like "Radiologie Zentrum Nord GmbH", never a
    /// lone "Praxis" in a sentence.
    static func organizationRanges(in line: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for segment in segments(of: line) {
            let all = tokens(in: line, within: segment)
            func word(_ i: Int) -> String { String(line[all[i]]) }
            func inName(_ i: Int) -> Bool {
                let w = word(i)
                // A label, like "Empfänger:", is not part of the name it announces.
                if all[i].upperBound < line.endIndex, line[all[i].upperBound] == ":" { return false }
                return w.first?.isUppercase == true || legalForms.contains(w) || w.first?.isNumber == true && i > 0
            }
            var i = 0
            while i < all.count {
                guard isOrganizationWord(word(i)) else { i += 1; continue }
                var first = i, last = i
                while first > 0, inName(first - 1) || connectors.contains(word(first - 1).lowercased())
                    && first - 2 >= 0 && inName(first - 2) { first -= 1 }
                while last + 1 < all.count, inName(last + 1) || connectors.contains(word(last + 1).lowercased())
                    && last + 2 < all.count && inName(last + 2) { last += 1 }
                let named = last > first || legalForms.contains(word(i))
                if named, first <= last { found.append(all[first].lowerBound..<all[last].upperBound) }
                i = last + 1
            }
        }
        return found
    }

    // MARK: Names

    /// Titles a name follows, small letters: "Herr", "Dr. med.", "Mrs.".
    private static let titles: Set<String> = ["herr", "herrn", "frau", "hr.", "fr.", "mr", "mr.", "mrs", "mrs.", "ms",
                                              "ms.", "miss", "mx", "mx.", "dr", "dr.", "prof", "prof.", "dipl.-med.",
                                              "dipl.-ing.", "dipl.-psych.", "monsieur", "madame", "mme", "mme.",
                                              "señor", "señora", "sr.", "sra.", "signor", "signora", "sig.", "sig.ra",
                                              "السيد", "السيدة", "الدكتور", "الدكتورة", "د.", "г-н", "г-жа",
                                              "господин", "госпожа"]
    /// Words that carry on a title before the name: "Dr. med. dent.", "Prof. Dr.".
    private static let titleParts: Set<String> = ["med.", "dent.", "vet.", "rer.", "nat.", "phil.", "jur.", "habil.",
                                                  "univ.", "h.c.", "dr.", "dr", "prof.", "pd", "priv.-doz.", "dipl.",
                                                  "mult.", "sc.", "oec.", "pol."]
    /// Titles that make whoever bears them a doctor.
    private static let medicalTitles: Set<String> = ["dr.", "dr", "prof.", "prof", "dipl.-med.", "الدكتور",
                                                     "الدكتورة", "د."]
    /// Words that are no name, though they are written with a capital: what
    /// follows a title, like "Sehr geehrte Frau Kollegin", and the words a
    /// German sentence starts with, like "Kein Nachweis".
    private static let notNames: Set<String> = ["kollegin", "kollege", "kollegen", "doktor", "doktorin", "professor",
                                                "professorin", "präsident", "präsidentin", "direktor", "direktorin",
                                                "vorsitzende", "vorsitzender", "damen", "herren", "patient",
                                                "patientin", "kunde", "kundin", "colleague", "doctor", "sir", "madam",
                                                "president", "sehr", "geehrte", "geehrter", "liebe", "lieber", "und",
                                                "mit", "freundlichen", "grüßen", "gruß", "datum", "seite", "befund",
                                                "diagnose", "bericht", "betreff", "anlage", "anlagen",
                                                // A disease named after a person names no one here.
                                                "morbus", "syndrom", "syndrome", "krankheit", "erkrankung", "disease",
                                                "zeichen", "sign",
                                                "kein", "keine", "keinen", "keinem", "keiner", "ihr", "ihre", "ihren",
                                                "ihrem", "ihrer", "unser", "unsere", "unseren", "wir", "sie", "ich",
                                                "du", "dein", "deine", "mein", "meine", "die", "dem", "ein", "eine",
                                                "einen", "einem", "einer", "bitte", "hallo", "guten", "vielen",
                                                "dank", "danke", "neue", "neuer", "neues", "alle", "heute", "nr", "nr.",
                                                "the", "dear", "hello", "thanks", "your", "our", "please"]
    /// Words a document is written in, never part of a person's name, like
    /// "Rechnung" or "Arzt": those that tell its kind, and those that say
    /// whose a name is.
    private static let documentWords: Set<String> = {
        let all = medicalWords + invoiceWords + bankingWords + patientCues + doctorCues + customerCues + employeeCues
        return Set(all.filter { !$0.contains(" ") && !$0.contains(".") })
    }()
    private static let particles: Set<String> = ["van", "von", "de", "da", "del", "der", "den", "la", "le", "bin",
                                                 "ibn", "al", "el", "di", "du", "zu", "ten", "ter", "dos", "das"]

    /// Whether a word can be part of a person's name as written: a capital
    /// first, then letters, apostrophes, dots or hyphens; or a script
    /// without capitals, like Arabic.
    static func isNameWord(_ word: String, caseless: Bool = true) -> Bool {
        let core = word.hasSuffix(",") ? String(word.dropLast()) : word
        guard let first = core.first, core.count >= 2, !notNames.contains(core.lowercased()),
              !documentWords.contains(core.lowercased()), !isOrganizationWord(core) else { return false }
        guard core.allSatisfy({ $0.isLetter || "'’.-".contains($0) }) else { return false }
        if first.isUppercase { return true }
        // Scripts without capitals, like Arabic, only where something else
        // vouches for the name, like a title or a label.
        return caseless && !first.isLowercase && first.isLetter
    }

    /// The words of a line that reads like a person's name: two to five
    /// words, at least two of them names, no digits, and no word of a
    /// company. German capitalizes every noun, so the shape alone is never
    /// enough to cover it. "Mustermann, Max" reads as a name too.
    static func nameWords(_ line: String) -> [String]? {
        let words = line.split(separator: " ").map(String.init)
        guard (2...5).contains(words.count), !line.contains(where: \.isNumber) else { return nil }
        var names: [String] = []
        for (i, word) in words.enumerated() where !particles.contains(word) {
            // Only the surname before a given name ends in a comma.
            if word.hasSuffix(","), i != 0 { return nil }
            guard isNameWord(word, caseless: false) else { return nil }
            names.append(fold(word.hasSuffix(",") ? String(word.dropLast()) : word))
        }
        return names.count >= 2 ? names : nil
    }

    /// A name after a title anywhere in a line, as in "wir berichten über
    /// Frau Lena Weber" or "Dr. med. Anna Schmidt": the name's words, without
    /// the title, and the title. One word after a title is enough.
    static func titledNames(in line: String) -> [(range: Range<String.Index>, title: String)] {
        let all = tokens(in: line, within: line.startIndex..<line.endIndex)
        var found: [(range: Range<String.Index>, title: String)] = []
        var i = 0
        while i < all.count {
            let word = line[all[i]].lowercased()
            guard titles.contains(word) else { i += 1; continue }
            var title = String(line[all[i]])
            var j = i + 1
            // "Dr. med. dent.", "Herr Prof. Dr."
            while j < all.count, titleParts.contains(line[all[j]].lowercased()) || titles.contains(line[all[j]].lowercased()) {
                title += " " + line[all[j]]
                j += 1
            }
            if let range = nameRun(in: line, tokens: all, from: j, minWords: 1) {
                found.append((range, title))
                i = all.firstIndex { $0.lowerBound >= range.upperBound } ?? all.count
            } else {
                i = j
            }
        }
        return found
    }

    /// A name without the titles before it: "Frau Dr. Lena Weber" gives
    /// "Lena Weber". Nil when nothing but titles is left.
    static func trimmingTitles(_ range: Range<String.Index>, in line: String) -> Range<String.Index>? {
        let all = tokens(in: line, within: range)
        let first = all.firstIndex { token in
            let word = line[token].lowercased()
            return !titles.contains(word) && !titleParts.contains(word)
        }
        return first.map { all[$0].lowerBound..<range.upperBound }
    }

    /// Where the name at the start of a label's value ends: "Mustermann,
    /// Max, geb. 01.01.1970" gives "Mustermann, Max", without the date that
    /// follows. A title before it is left out. Nil when the value does not
    /// start with a name.
    static func leadingName(in line: String, from start: String.Index) -> Range<String.Index>? {
        // A company's name is no person's: "Kunde: Muster GmbH".
        let value = line[start...].prefix { !",(;".contains($0) }
        guard !isOrganization(String(value)) else { return nil }
        let all = tokens(in: line, within: start..<line.endIndex)
        var j = 0
        while j < all.count, titles.contains(line[all[j]].lowercased()) || titleParts.contains(line[all[j]].lowercased()) {
            j += 1
        }
        return nameRun(in: line, tokens: all, from: j, minWords: 1)
    }

    /// One to five name words from a token on, with particles inside and a
    /// comma after the surname, ending before what is no name.
    private static func nameRun(in line: String, tokens: [Range<String.Index>], from start: Int,
                                minWords: Int) -> Range<String.Index>? {
        var names = 0, end: String.Index?, k = start
        while k < tokens.count, names < 5 {
            let word = String(line[tokens[k]])
            // An aside in brackets is not part of the name: "Lena Weber (Kundennr. 4711)".
            if tokens[k].lowerBound > line.startIndex, "([".contains(line[line.index(before: tokens[k].lowerBound)]) {
                break
            }
            if particles.contains(word), names > 0, k + 1 < tokens.count, isNameWord(String(line[tokens[k + 1]])) {
                k += 1
                continue
            }
            guard isNameWord(word) else { break }
            names += 1
            // A comma ends the name, unless it is "Surname, Given name".
            if word.hasSuffix(",") {
                if names == 1, k + 1 < tokens.count, isNameWord(String(line[tokens[k + 1]])) {
                    k += 1
                    continue
                }
                end = line.index(before: tokens[k].upperBound)
                break
            }
            end = tokens[k].upperBound
            k += 1
        }
        guard names >= minWords, let end, start < tokens.count else { return nil }
        // A word that ends a sentence keeps its dot outside the name.
        var stop = end
        if stop > tokens[start].lowerBound, line[line.index(before: stop)] == ".",
           !line[tokens[start].lowerBound..<stop].dropLast().contains(".") { stop = line.index(before: stop) }
        return tokens[start].lowerBound..<stop
    }

    // MARK: Whose name

    private static let patientCues = ["name des patienten", "name der patientin", "patientenname", "patient name",
                                      "patient's name", "name of patient", "patientin", "patienten", "patient",
                                      "pat.", "versicherte", "versicherter", "versicherten", "patiente", "paciente",
                                      "المريضة", "المريض", "пациентка", "пациент"]
    private static let doctorCues = ["behandelnder arzt", "behandelnde ärztin", "überweisender arzt",
                                     "überweisende ärztin", "überweisung von", "überwiesen von", "zuweiser",
                                     "einweiser", "hausarzt", "hausärztin", "befundender arzt", "befundet von",
                                     "diktiert von", "dictated by", "verantwortlicher arzt", "referring physician",
                                     "treating physician", "attending physician", "physician", "facharzt",
                                     "fachärztin", "oberarzt", "oberärztin", "chefarzt", "chefärztin", "assistenzarzt",
                                     "assistenzärztin", "stationsarzt", "arzt", "ärztin", "doctor", "الطبيب", "врач"]
    private static let customerCues = ["kontoinhaberin", "kontoinhaber", "karteninhaber", "account holder",
                                       "cardholder", "card holder", "kundenname", "customer name", "kundin", "kunde",
                                       "customer", "käuferin", "käufer", "buyer", "rechnungsempfänger",
                                       "rechnungsadresse", "lieferadresse", "lieferanschrift", "bill to", "billed to",
                                       "ship to", "sold to", "invoice to", "client", "cliente", "العميل",
                                       "صاحب الحساب", "клиент", "покупатель"]
    private static let employeeCues = ["sachbearbeiterin", "sachbearbeiter", "bearbeiterin", "bearbeiter",
                                       "ansprechpartnerin", "ansprechpartner", "kundenberaterin", "kundenberater",
                                       "beraterin", "berater", "verkäuferin", "verkäufer", "kassiererin", "kassierer",
                                       "mitarbeiterin", "mitarbeiter", "bedient von", "served by", "employee",
                                       "agent", "advisor", "clerk", "cashier", "contact person", "geschäftsführerin",
                                       "geschäftsführer", "geschäftsführung", "inhaberin", "inhaber", "ceo",
                                       "director", "الموظف", "сотрудник", "менеджер"]
    private static let birthCues = ["geb.", "geb ", "geboren", "geburtsdatum", "dob", "d.o.b.", "date of birth",
                                    "born", "née", "تاريخ الميلاد", "дата рождения"]
    private static let closings = ["mit freundlichen grüßen", "mit freundlichen kollegialen grüßen",
                                   "mit kollegialen grüßen", "freundliche grüße", "viele grüße", "beste grüße",
                                   "sincerely", "kind regards", "best regards", "yours faithfully", "unterschrift",
                                   "gez.", "i.a.", "i.v.", "مع التحية", "с уважением"]

    /// The cue nearest the end of a piece of text, the role it gives, and
    /// what follows it there.
    private static func cue(in text: String) -> (role: PersonRole, rest: String)? {
        let lower = text.lowercased()
        var best: (role: PersonRole, at: String.Index)?
        for (cues, role) in [(patientCues, PersonRole.patient), (doctorCues, .doctor), (customerCues, .customer),
                             (employeeCues, .employee)] {
            for cue in cues {
                var searched = lower.startIndex..<lower.endIndex
                // The last one that is a whole word, not the start of a longer one.
                while let found = lower.range(of: cue, options: .backwards, range: searched) {
                    if isWordStart(found.lowerBound, in: lower), isWordEnd(found.upperBound, in: lower) {
                        if best == nil || found.upperBound > best!.at { best = (role, found.upperBound) }
                        break
                    }
                    searched = lower.startIndex..<found.lowerBound
                }
            }
        }
        guard let best else { return nil }
        return (best.role, String(lower[best.at...]))
    }

    /// The role a label gives the name it announces, like "Patient:" or
    /// "Behandelnder Arzt", or nil for one that says nothing of it, like "Name".
    static func role(ofLabel label: String) -> PersonRole? {
        cue(in: label)?.role
    }

    /// A cue just before a name, with no more than a word or a title between,
    /// as in "Patientin Frau Lena Weber", not one further back in a sentence.
    private static func cue(justBefore text: String) -> PersonRole? {
        guard let found = cue(in: text) else { return nil }
        let between = words(of: found.rest.trimmingCharacters(in: CharacterSet(charactersIn: ":-–()")))
            .filter { !titles.contains($0) && !titleParts.contains($0) && $0 != ":" }
        return between.count <= 1 ? found.role : nil
    }

    /// Whose name is in line `index`, at `name` in it or the whole line: from
    /// the words before it on its line, its title, the label on the lines
    /// just above, the closing above a signature, the words just under it,
    /// and a date of birth beside it, each weighed by the kind of document.
    static func role(ofNameIn index: Int, at name: Range<String.Index>?, title: String? = nil, lines: [String],
                     kind: DocumentKind) -> NameRole {
        let line = lines[index]
        let before = name.map { String(line[..<$0.lowerBound]) } ?? ""
        let after = name.map { String(line[$0.upperBound...]) } ?? ""
        let medical = kind == .medical

        // A label just before the name on its line: "Patient: Dr. Max Meier".
        if let role = cue(justBefore: before) {
            return NameRole(role: role, confidence: 0.9, reason: "label")
        }
        // A title that belongs to the name itself.
        if let title = title?.lowercased() {
            if title.contains("dr.") && (title.contains("med") || title.contains("dent")) || title.contains("prof") {
                return NameRole(role: .doctor, confidence: medical ? 0.9 : 0.75, reason: "title")
            }
            if medicalTitles.contains(where: { title.split(separator: " ").map(String.init).contains($0) }) {
                return NameRole(role: .doctor, confidence: medical ? 0.75 : 0.5, reason: "title")
            }
        }
        // "Max Mustermann, geb. 01.01.1960", or a doctor's title after the name.
        let rest = after.lowercased()
        if rest.contains(", md") || rest.contains(" md ") || rest.hasSuffix(" md") || rest.contains("facharzt")
            || rest.contains("fachärztin") {
            return NameRole(role: .doctor, confidence: 0.8, reason: "after")
        }
        if birthCues.contains(where: { rest.contains($0) }) || rest.contains("*") {
            return NameRole(role: subject(in: kind), confidence: medical ? 0.75 : 0.6, reason: "birth")
        }
        // The lines just above: a label alone on its line, or a closing.
        for distance in 1...4 where index - distance >= 0 {
            let above = lines[index - distance].trimmingCharacters(in: .whitespaces)
            let lower = above.lowercased()
            if closings.contains(where: { lower.hasPrefix($0) }) {
                let role: PersonRole = medical ? .doctor : kind == .invoice ? .employee : .other
                return NameRole(role: role, confidence: medical ? 0.75 : 0.6, reason: "signature")
            }
            if distance <= 2, isLabelLine(above), let role = cue(in: above)?.role {
                return NameRole(role: role, confidence: distance == 1 ? 0.85 : 0.7, reason: "label above")
            }
        }
        // A doctor's title on the line under a signature.
        if index + 1 < lines.count {
            let below = lines[index + 1].lowercased()
            if ["facharzt", "fachärztin", "chefarzt", "chefärztin", "oberarzt", "oberärztin", "arzt für",
                "ärztin für"].contains(where: { below.hasPrefix($0) }) {
                return NameRole(role: .doctor, confidence: 0.8, reason: "under")
            }
            if birthCues.contains(where: { below.hasPrefix($0) }) {
                return NameRole(role: subject(in: kind), confidence: medical ? 0.7 : 0.55, reason: "birth")
            }
        }
        return .unknown
    }

    /// Whose a document mostly is: the patient's in a medical one.
    private static func subject(in kind: DocumentKind) -> PersonRole {
        switch kind {
        case .medical: .patient
        case .invoice, .banking: .customer
        case .general: .other
        }
    }

    /// A short line that only announces what follows, like "Patient:".
    private static func isLabelLine(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        return !words.isEmpty && words.count <= 4 && !line.contains(where: \.isNumber)
    }

    // MARK: Text

    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The words of part of a line, as ranges, without the space between.
    private static func tokens(in line: String, within part: Range<String.Index>) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start: String.Index?
        var i = part.lowerBound
        while i < part.upperBound {
            if line[i].isWhitespace {
                if let s = start { found.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
            i = line.index(after: i)
        }
        if let s = start { found.append(s..<part.upperBound) }
        // Brackets and quotes round a word are not part of it.
        return found.compactMap { range in
            var lower = range.lowerBound, upper = range.upperBound
            while lower < upper, "([\"'„“«".contains(line[lower]) { lower = line.index(after: lower) }
            while upper > lower, ")]\"'“”»:;".contains(line[line.index(before: upper)]) { upper = line.index(before: upper) }
            return lower < upper ? lower..<upper : nil
        }
    }

    /// A line split at its commas, semicolons and bullets, as parts.
    private static func segments(of line: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start = line.startIndex, i = line.startIndex
        while i < line.endIndex {
            if ",;|•·".contains(line[i]) {
                if start < i { found.append(start..<i) }
                start = line.index(after: i)
            }
            i = line.index(after: i)
        }
        if start < line.endIndex { found.append(start..<line.endIndex) }
        return found
    }

    private static func isWordStart(_ index: String.Index, in text: String) -> Bool {
        index == text.startIndex || !text[text.index(before: index)].isLetter
    }

    private static func isWordEnd(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || !text[index].isLetter
    }
}

/// Whose names are covered when Names is on: everyone's, as before, or
/// only some people's, like the patient's and not the doctor's. A name whose
/// role is not clear is covered anyway and marked for the owner to check.
struct NameScope: Equatable, Sendable {
    /// Nil: everyone.
    var roles: Set<PersonRole>?

    static let everyone = NameScope(roles: nil)
    static let key = "nameRoles"

    enum Decision: Equatable { case cover, coverAndCheck, leave }

    func decide(_ role: NameRole) -> Decision {
        guard let roles else { return .cover }
        guard role.isSure else { return .coverAndCheck }
        return roles.contains(role.role) ? .cover : .leave
    }

    static func load(from defaults: UserDefaults = .standard) -> NameScope {
        guard let raw = defaults.stringArray(forKey: key) else { return .everyone }
        return NameScope(roles: Set(raw.compactMap(PersonRole.init(rawValue:))))
    }

    func save(to defaults: UserDefaults = .standard) {
        if let roles {
            defaults.set(roles.map(\.rawValue).sorted(), forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    static var current: NameScope {
        get { load() }
        set { newValue.save() }
    }
}
