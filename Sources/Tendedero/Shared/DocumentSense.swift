import Foundation

/// Who a name in a document belongs to, read from what stands around it: a
/// label like "Patient:", a title like "Dr. med.", the closing above a
/// signature, the date of birth after it.
enum PersonRole: String, CaseIterable, Codable, Sendable {
    case patient, doctor, customer, employee, beneficiary, sender, recipient, other

    /// The people besides patients, covered with Other people.
    static let others: [PersonRole] = [.doctor, .customer, .employee, .beneficiary, .sender, .recipient, .other]
}

/// More of a role, where the words say it: the doctor treating, referring
/// or signing, the account's holder, the business's owner.
enum RoleDetail: String, Sendable {
    case treating, referring, signing, accountHolder, owner
}

/// A name's role, how sure the reading is, and what it was read from, for
/// the tests and for deciding when to ask the owner to check.
struct NameRole: Equatable, Sendable {
    var role: PersonRole
    /// From 0 to 1.
    var confidence: Double
    /// What gave it away, in a word or two, like "label" or "title".
    var reason: String
    var detail: RoleDetail? = nil

    /// Sure enough to cover or leave a name by its role alone.
    var isSure: Bool { confidence >= 0.6 }

    /// The role, where it is sure enough to say whose something is.
    var sureRole: PersonRole? { isSure ? role : nil }

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
                                       "entlassung", "beurteilung", "arbeitsunfähig", "arbeitsunfähigkeit",
                                       "kostenträger", "versicherten", "المريض", "التشخيص", "пациент", "диагноз", "врач"]
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
        "praxis", "gemeinschaftspraxis", "arztpraxis", "practice", "klinik", "klinikum", "uniklinik", "universitätsklinikum",
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

    // MARK: Medical terms

    /// What a findings' text names that is no one's name and no one's
    /// number: the spine's segments, "LWK 5/SWK 1"; a disease named after
    /// a person, "Morbus Scheuermann"; and, in a medical document, the short
    /// segments and roots, "L5/S1", "S1-Wurzel", and diagnosis codes, "M51.2".
    static func medicalRanges(in line: String, medical: Bool) -> [Range<String.Index>] {
        (medical ? medicalTerms + medicalCodes : medicalTerms).flatMap { regex in
            regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { Range($0.range, in: line) }
        }
    }

    /// Terms that are medical wherever they stand.
    private static let medicalTerms: [NSRegularExpression] = [
        // The spine's segments by their German names, alone or as a pair.
        #"\b(?:HWK|BWK|LWK|SWK|HWS|BWS|LWS)\s?\d{0,2}(?:\s?[/-]\s?(?:HWK|BWK|LWK|SWK|C|Th|T|L|S)?\s?\d{1,2})?\b"#,
        // A disease named after a person.
        #"\b(?:Morbus|Mb\.)\s+\p{Lu}[\p{L}\-]+(?:\s+\p{Lu}[\p{L}\-]+)?"#,
        #"\b\p{Lu}[\p{L}]+-(?:Syndrom|Krankheit|Erkrankung|Zeichen|Test|Reflex|Fraktur|Zyste)\b"#,
        #"\b\p{Lu}[\p{L}]+sche[nrsm]?\s+(?:Knötchen|Krankheit|Erkrankung|Syndrom|Zeichen|Operation|Fraktur|Zyste|Ödem)\b"#,
        #"\b\p{Lu}[\p{L}]+['’]s\s+(?:disease|syndrome|sign|palsy|fracture)\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Short codes that are medical in a medical document only.
    private static let medicalCodes: [NSRegularExpression] = [
        // "L5/S1", "C5-C6", "Th12": a segment, alone or as a pair.
        #"\b(?:C|Th|T|L|S)\s?\d{1,2}\s?[/-]\s?(?:C|Th|T|L|S)\s?\d{1,2}\b"#,
        #"\bTh\s?\d{1,2}\b"#,
        // A nerve root, "S1-Wurzel".
        #"\b(?:C|Th|T|L|S)\d{1,2}-Wurzel\b"#,
        // A diagnosis's ICD-10 code, "M51.2", "S82.1 G".
        #"\b[A-TV-Z]\d{2}\.\d{1,2}(?:\s?[GVZA]\b)?"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

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
                                                "the", "dear", "hello", "thanks", "your", "our", "please",
                                                // Small words between names, written in capitals in a
                                                // heading, like "IN HAMBURG": no one is named so.
                                                "in", "im", "am", "auf", "aus", "für", "nach", "vom", "zum", "zur",
                                                "of", "and", "for", "at", "with"]
    /// Words a document is written in, never part of a person's name, like
    /// "Rechnung" or "Arzt": those that tell its kind, and those that say
    /// whose a name is.
    private static let documentWords: Set<String> = {
        let all = medicalWords + invoiceWords + bankingWords + cues.filter { !$0.labelOnly }.map(\.text)
        return Set(all.filter { !$0.contains(" ") && !$0.contains(".") && !$0.contains("/") })
    }()
    /// Endings of German nouns that are no one's name: "-bescheinigung",
    /// "-keit", "-schaft", and a finding's, "-extrusion", "-algie".
    private static let nounEndings = ["ung", "ungen", "heit", "keit", "schaft", "tion", "ität", "sion", "itis", "algie",
                                      "ektomie", "graphie", "skopie", "pathie", "therapie"]
    private static let particles: Set<String> = ["van", "von", "de", "da", "del", "der", "den", "la", "le", "bin",
                                                 "ibn", "al", "el", "di", "du", "zu", "ten", "ter", "dos", "das"]

    /// Whether a word can be part of a person's name as written: a capital
    /// first, then letters, apostrophes, dots or hyphens; or a script
    /// without capitals, like Arabic.
    static func isNameWord(_ word: String, caseless: Bool = true) -> Bool {
        let core = word.hasSuffix(",") ? String(word.dropLast()) : word
        // A word's possessive is no more a name than the word: "Doctor's".
        let bare = ["'s", "’s"].first { core.lowercased().hasSuffix($0) }.map { String(core.lowercased().dropLast($0.count)) }
        guard let first = core.first, core.count >= 2, !notNames.contains(core.lowercased()),
              !documentWords.contains(core.lowercased()), !isOrganizationWord(core),
              bare.map({ !notNames.contains($0) && !documentWords.contains($0) }) ?? true else { return false }
        guard core.allSatisfy({ $0.isLetter || "'’.-".contains($0) }) else { return false }
        // A long German noun of a kind no one is named, like "Erstbescheinigung".
        let lower = core.lowercased()
        if lower.count >= 9, nounEndings.contains(where: { lower.hasSuffix($0) }) { return false }
        if first.isUppercase { return true }
        // Scripts without capitals, like Arabic, only where something else
        // vouches for the name, like a title or a label.
        return caseless && !first.isLowercase && first.isLetter
    }

    /// Whether a word is a small part of a name, like "van" or "al".
    static func isParticle(_ word: String) -> Bool {
        particles.contains(word)
    }

    /// Whether a word is a title or part of one, which a name follows and
    /// is never part of: "Herr", "Frau", "Dr.", "med.".
    static func isTitle(_ word: String) -> Bool {
        let lower = word.lowercased()
        return titles.contains(lower) || titleParts.contains(lower)
    }

    /// Whether a line names a doctor by a doctor's title before the name,
    /// as a practice's letterhead lists them: "Dr. med. Anna Schmidt".
    static func namesADoctor(_ line: String) -> Bool {
        titledNames(in: line).contains { found in
            found.title.lowercased().split(separator: " ").contains { medicalTitles.contains(String($0)) }
        }
    }

    /// A name's whole run around part of it, as the words beside it go on:
    /// "Erika" in "Frau Erika Musterfrau kam" gives "Erika Musterfrau", and
    /// "Musterfrau" in "Musterfrau, Erika" the two. It stops at a title, a
    /// word that is no name, a digit, or after five words.
    static func nameSpan(around part: Range<String.Index>, in line: String) -> Range<String.Index> {
        let all = tokens(in: line, within: line.startIndex..<line.endIndex)
        guard let first = all.firstIndex(where: { $0.overlaps(part) }),
              let last = all.lastIndex(where: { $0.overlaps(part) }) else { return part }
        func isName(_ i: Int) -> Bool {
            let word = String(line[all[i]])
            let bare = word.hasSuffix(",") ? String(word.dropLast()) : word
            // A label, like "Patient:", is not part of the name it announces.
            if all[i].upperBound < line.endIndex, line[all[i].upperBound] == ":" { return false }
            return !titles.contains(bare.lowercased()) && !titleParts.contains(bare.lowercased())
                && isNameWord(bare, caseless: false)
        }
        // Only a name's own words carry it on.
        guard (first...last).allSatisfy(isName) else { return part }
        // Only "Surname, Given name" holds a comma, after its first word.
        func comma(_ i: Int) -> Bool { line[all[i]].hasSuffix(",") }
        func commaIn(_ from: Int, _ to: Int) -> Bool { from <= to && (from...to).contains(where: comma) }
        var start = first, end = last
        while start > 0, end - start < 4, isName(start - 1) {
            if comma(start - 1) {
                // A surname before its given name, the first of the name.
                if !commaIn(start, end - 1) { start -= 1 }
                break
            }
            start -= 1
        }
        while end + 1 < all.count, end - start < 4, isName(end + 1), !comma(end) || !commaIn(start, end - 1) && end == start {
            end += 1
        }
        let upper = comma(end) ? line.index(before: all[end].upperBound) : all[end].upperBound
        return min(all[start].lowerBound, part.lowerBound)..<max(upper, part.upperBound)
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

    /// A word or words that say whose the name after them is.
    private struct Cue {
        let text: String
        let role: PersonRole
        var detail: RoleDetail? = nil
        /// Short, common words, like "An" or "von", count only as a label with
        /// its colon, "An:", never in a sentence.
        var labelOnly = false
    }

    private static let cues: [Cue] = {
        var cues: [Cue] = []
        func add(_ role: PersonRole, detail: RoleDetail? = nil, labelOnly: Bool = false, _ texts: [String]) {
            cues += texts.map { Cue(text: $0, role: role, detail: detail, labelOnly: labelOnly) }
        }
        add(.patient, ["name des patienten", "name der patientin", "name des versicherten", "patientenname",
                       "patientennamen", "patient name", "patient's name", "name of patient", "patientendaten",
                       "patientin", "patienten", "patient/in", "patient", "pat.", "versicherte", "versicherter",
                       "versicherten", "patiente", "paciente", "المريضة", "المريض", "пациентка", "пациент"])
        add(.doctor, detail: .treating, ["behandelnder arzt", "behandelnde ärztin", "behandelnde ärzte", "treating physician",
                                 "attending physician", "verantwortlicher arzt", "hausarzt", "hausärztin"])
        add(.doctor, detail: .referring, ["überweisender arzt", "überweisende ärztin", "überweisung von", "überwiesen von",
                                  "zuweisender arzt", "zuweiser", "einweiser", "überweiser", "referring physician"])
        add(.doctor, detail: .signing, ["befundender arzt", "befundet von", "befund erstellt von", "erstellt von",
                                "diktiert von", "dictated by", "ärztliche unterschrift", "unterschrift des arztes"])
        add(.doctor, ["physician", "facharzt", "fachärztin", "oberarzt", "oberärztin", "chefarzt", "chefärztin",
                      "assistenzarzt", "assistenzärztin", "stationsarzt", "arzt", "ärztin", "doctor", "الطبيب", "врач"])
        add(.customer, detail: .accountHolder, ["kontoinhaberin", "kontoinhaber", "karteninhaberin", "karteninhaber",
                                        "account holder", "cardholder", "card holder", "صاحب الحساب"])
        add(.customer, ["kundenname", "customer name", "kundin", "kunde", "customer", "käuferin", "käufer", "buyer",
                        "rechnungsempfänger", "rechnungsadresse", "lieferadresse", "lieferanschrift", "bill to",
                        "billed to", "ship to", "sold to", "invoice to", "client", "cliente", "العميل", "клиент",
                        "покупатель"])
        add(.employee, detail: .owner, ["geschäftsführerin", "geschäftsführer", "geschäftsführung", "inhaberin", "inhaber",
                                "ceo", "director", "owner"])
        add(.employee, ["sachbearbeiterin", "sachbearbeiter", "bearbeiterin", "bearbeiter", "ansprechpartnerin",
                        "ansprechpartner", "kundenberaterin", "kundenberater", "beraterin", "berater",
                        "verkäuferin", "verkäufer", "kassiererin", "kassierer", "mitarbeiterin", "mitarbeiter",
                        "bedient von", "served by", "employee", "agent", "advisor", "clerk", "cashier",
                        "contact person", "الموظف", "сотрудник", "менеджер"])
        add(.beneficiary, ["zahlungsempfängerin", "zahlungsempfänger", "begünstigte", "begünstigter",
                           "empfängername", "beneficiary", "payee", "المستفيد", "получатель"])
        add(.sender, ["absenderin", "absender", "auftraggeberin", "auftraggeber", "sender", "المرسل"])
        add(.sender, labelOnly: true, ["von", "from"])
        add(.recipient, ["empfängerin", "empfänger", "adressat", "recipient", "المستلم"])
        add(.recipient, labelOnly: true, ["an", "to"])
        return cues
    }()
    private static let birthCues = ["geb.", "geb ", "geboren", "geburtsdatum", "geb.-dat", "geb.dat", "dob",
                                    "d.o.b.", "date of birth", "born", "née", "تاريخ الميلاد", "дата рождения"]
    private static let closings = ["mit freundlichen grüßen", "mit freundlichen kollegialen grüßen",
                                   "mit kollegialen grüßen", "freundliche grüße", "viele grüße", "beste grüße",
                                   "sincerely", "kind regards", "best regards", "yours faithfully", "unterschrift",
                                   "ärztliche unterschrift", "gez.", "i.a.", "i.v.", "مع التحية", "с уважением"]

    /// The cue nearest the end of a piece of text, and what follows it there.
    private static func cue(in text: String) -> (cue: Cue, rest: String)? {
        let lower = text.lowercased()
        var best: (cue: Cue, at: String.Index, start: String.Index)?
        for cue in cues {
            var searched = lower.startIndex..<lower.endIndex
            // The last one that is a whole word, not the start of a longer one.
            while let found = lower.range(of: cue.text, options: .backwards, range: searched) {
                if isWordStart(found.lowerBound, in: lower), isWordEnd(found.upperBound, in: lower) {
                    let rest = lower[found.upperBound...].drop { $0 == " " }
                    // A short word is a label only with its colon.
                    let fits = !cue.labelOnly || rest.first == ":"
                    // The longest cue that ends last wins: "behandelnder Arzt" over "Arzt".
                    if fits, best == nil || found.upperBound > best!.at
                        || found.upperBound == best!.at && found.lowerBound < best!.start {
                        best = (cue, found.upperBound, found.lowerBound)
                    }
                    if fits { break }
                }
                searched = lower.startIndex..<found.lowerBound
            }
        }
        guard let best else { return nil }
        return (best.cue, String(lower[best.at...]))
    }

    /// The role a label gives the name it announces, like "Patient:" or
    /// "Behandelnder Arzt", or nil for one that says nothing of it, like "Name".
    static func role(ofLabel label: String) -> PersonRole? {
        cue(in: label + ":")?.cue.role
    }

    /// The role and its detail a label gives, as `role(ofLabel:)`.
    static func nameRole(ofLabel label: String) -> NameRole? {
        cue(in: label + ":").map { NameRole(role: $0.cue.role, confidence: 0.9, reason: "label", detail: $0.cue.detail) }
    }

    /// A cue just before a name, with no more than a word or a title between,
    /// as in "Patientin Frau Lena Weber", not one further back in a sentence.
    private static func cue(justBefore text: String) -> Cue? {
        guard let found = cue(in: text) else { return nil }
        let between = words(of: found.rest.trimmingCharacters(in: CharacterSet(charactersIn: ":-–()")))
            .filter { !titles.contains($0) && !titleParts.contains($0) && $0 != ":" }
        return between.count <= 1 ? found.cue : nil
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
        let label = cue(justBefore: before)

        // A label just before the name on its line, "Patient: Dr. Max Meier",
        // says more than the name's title; a sender's or a recipient's says less.
        if let label, label.role != .sender, label.role != .recipient {
            return NameRole(role: label.role, confidence: 0.9, reason: "label", detail: label.detail)
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
        if let label {
            return NameRole(role: label.role, confidence: 0.85, reason: "label", detail: label.detail)
        }
        // The subject of a medical letter: "Betreff: Mustermann, Max".
        if medical, ["betreff", "betr.", "re:", "subject"].contains(where: { before.lowercased().contains($0) }) {
            return NameRole(role: .patient, confidence: 0.8, reason: "subject")
        }
        // "Max Mustermann, geb. 01.01.1960", or a doctor's title after the name.
        let rest = after.lowercased()
        if rest.contains(", md") || rest.contains(" md ") || rest.hasSuffix(" md") || rest.contains("facharzt")
            || rest.contains("fachärztin") {
            return NameRole(role: .doctor, confidence: 0.8, reason: "after")
        }
        if birthCues.contains(where: { rest.contains($0) }) || rest.contains("*") {
            return NameRole(role: subject(in: kind), confidence: medical ? 0.8 : 0.6, reason: "birth")
        }
        if medical, startsWithDate(rest) {
            return NameRole(role: .patient, confidence: 0.6, reason: "birth")
        }
        // The lines just above: a label alone on its line, or a closing.
        for distance in 1...4 where index - distance >= 0 {
            let above = lines[index - distance].trimmingCharacters(in: .whitespaces)
            let lower = above.lowercased()
            if closings.contains(where: { lower.hasPrefix($0) }) {
                let role: PersonRole = medical ? .doctor : kind == .invoice ? .employee : .other
                return NameRole(role: role, confidence: medical ? 0.75 : 0.6, reason: "signature",
                                detail: medical ? .signing : nil)
            }
            // A letter's address under "Herrn" or "Frau": in a doctor's
            // letter, most often the patient's, but not for sure.
            if distance == 1, let heading = isTitleLine(above) {
                if heading.doctor { return NameRole(role: .doctor, confidence: 0.85, reason: "title above") }
                if medical { return NameRole(role: .patient, confidence: 0.55, reason: "address") }
            }
            // Only a label that ends its line: "Facharzt für Innere Medizin"
            // under a doctor's name announces no one.
            if distance <= 2, isLabelLine(above), let found = cue(in: above + ":"),
               found.rest.allSatisfy({ $0 == ":" || $0 == " " }) {
                return NameRole(role: found.cue.role, confidence: distance == 1 ? 0.85 : 0.7, reason: "label above",
                                detail: found.cue.detail)
            }
        }
        // A doctor's title on the line under a signature, or a date of birth.
        if index + 1 < lines.count {
            let below = lines[index + 1].lowercased()
            if ["facharzt", "fachärztin", "chefarzt", "chefärztin", "oberarzt", "oberärztin", "arzt für",
                "ärztin für"].contains(where: { below.hasPrefix($0) }) {
                return NameRole(role: .doctor, confidence: 0.8, reason: "under", detail: .signing)
            }
            if birthCues.contains(where: { below.hasPrefix($0) }) || below.hasPrefix("*") {
                return NameRole(role: subject(in: kind), confidence: medical ? 0.75 : 0.55, reason: "birth")
            }
        }
        return .unknown
    }

    /// Whose a document mostly is: the patient's in a medical one.
    static func subject(in kind: DocumentKind) -> PersonRole {
        switch kind {
        case .medical: .patient
        case .invoice, .banking: .customer
        case .general: .other
        }
    }

    /// Whether a line starts with a date of birth, as the line beside or
    /// under a name does: "geb. 01.02.1960", "* 01.02.1960".
    static func startsWithBirth(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasPrefix("*") || birthCues.contains { lower.hasPrefix($0) }
    }

    /// Whether text starts with a date, as a date of birth after a name does.
    private static func startsWithDate(_ text: String) -> Bool {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;(*"))
            .range(of: #"^\d{1,2}[./]\d{1,2}[./]\d{2,4}"#, options: .regularExpression) != nil
    }

    // MARK: Names found by what stands round them

    /// Names right after a word that says whose they are, anywhere in a
    /// line: "Wir berichten über Ihren Patienten Max Mustermann", "Pat.
    /// Mustermann, Max", "Betreff: Mustermann, Max" in a medical letter. Two
    /// words at least, or a surname with a comma and a given name, so a
    /// noun after "Patient" is never taken for one.
    static func cuedNames(in line: String, kind: DocumentKind) -> [Range<String.Index>] {
        let all = tokens(in: line, within: line.startIndex..<line.endIndex)
        var found: [Range<String.Index>] = []
        var texts = cues.filter { !$0.labelOnly && $0.role != .doctor }.map(\.text)
        if kind == .medical { texts += ["betreff", "betr."] }
        for (i, token) in all.enumerated() {
            let word = line[token].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            let upTo = line[..<token.upperBound].lowercased()
            // A cue of one word, or the last word of a longer one.
            guard texts.contains(where: { $0 == word || $0.hasSuffix(" " + word) && upTo.hasSuffix($0) }) else { continue }
            var j = i + 1
            while j < all.count, titles.contains(line[all[j]].lowercased()) || titleParts.contains(line[all[j]].lowercased()) {
                j += 1
            }
            guard j < all.count, let range = nameRun(in: line, tokens: all, from: j, minWords: 1) else { continue }
            let words = line[range].split(separator: " ")
            let commaForm = line[range].contains(",")
            guard words.count >= 2 || commaForm, !found.contains(where: { $0.overlaps(range) }),
                  !isOrganization(String(line[range])) else { continue }
            found.append(range)
        }
        return found
    }

    /// Names just before a date of birth: "Max Mustermann, geb. 01.02.1960",
    /// "Mustermann, Max *01.02.1960", and in a medical document a name before
    /// a date alone, as a table's row has it. Two name words at least.
    static func bornNames(in line: String, kind: DocumentKind) -> [Range<String.Index>] {
        let all = tokens(in: line, within: line.startIndex..<line.endIndex)
        var found: [Range<String.Index>] = []
        for (k, token) in all.enumerated() where k >= 2 {
            let word = line[token].lowercased()
            let isDate = word.range(of: #"^\*?\(?\d{1,2}[./]\d{1,2}[./]\d{2,4}\)?[,;]?$"#, options: .regularExpression) != nil
            let cue = word.hasPrefix("*") || word.hasPrefix("(geb") || birthCues.contains { $0.trimmingCharacters(in: .whitespaces) == word }
                || word.hasPrefix("geb.") || word == "geboren"
            guard cue || isDate && kind == .medical else { continue }
            // Back from the cue over the name's words, up to a title before it.
            var start = k
            while start > 0, start > k - 5 {
                let previous = String(line[all[start - 1]])
                let bare = previous.hasSuffix(",") ? String(previous.dropLast()) : previous
                guard !bare.hasSuffix(":"), !isTitle(bare),
                      isNameWord(bare, caseless: false) || particles.contains(bare) else { break }
                start -= 1
            }
            guard k - start >= 2, let range = nameRun(in: line, tokens: all, from: start, minWords: 2),
                  !found.contains(where: { $0.overlaps(range) }), !isOrganization(String(line[range])) else { continue }
            found.append(range)
        }
        return found
    }

    /// Whether a line holds nothing but a title, as the line over a name in
    /// a letter's address does: "Herrn", "Frau", "Herrn Dr. med.".
    static func isTitleLine(_ line: String) -> (title: String, doctor: Bool)? {
        let words = line.split(separator: " ").map { String($0).lowercased() }
        guard !words.isEmpty, words.count <= 4, titles.contains(words[0]),
              words.allSatisfy({ titles.contains($0) || titleParts.contains($0) }) else { return nil }
        return (line.trimmingCharacters(in: .whitespaces), words.contains { medicalTitles.contains($0) })
    }

    /// The name at the start of a line, of one to five words, as in the
    /// line under a title or a table's header.
    static func nameAtStart(of line: String) -> Range<String.Index>? {
        let all = tokens(in: line, within: line.startIndex..<line.endIndex)
        var j = 0
        while j < all.count, titles.contains(line[all[j]].lowercased()) || titleParts.contains(line[all[j]].lowercased()) {
            j += 1
        }
        guard let range = nameRun(in: line, tokens: all, from: j, minWords: 1),
              !isOrganization(String(line[range])) else { return nil }
        return range
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

/// Whose names are covered (`Finder.resolved`): everyone's, with Names,
/// Patient names and Other people all on; else each one's own people, the
/// patients', everyone else's whose role the words round the name tell,
/// and, with Names, the names whose role is not clear. Without Names, such
/// a name is covered anyway and marked for the owner to check.
struct NameScope: Equatable, Sendable {
    /// Nil: everyone.
    var roles: Set<PersonRole>?
    /// Whether Names is on, so a name whose role is not clear is covered as one.
    var unclear = false

    static let everyone = NameScope(roles: nil)

    enum Decision: Equatable { case cover, coverAndCheck, leave }

    func decide(_ role: NameRole) -> Decision {
        guard let roles else { return .cover }
        guard role.isSure else { return unclear ? .cover : .coverAndCheck }
        return roles.contains(role.role) ? .cover : .leave
    }
}
