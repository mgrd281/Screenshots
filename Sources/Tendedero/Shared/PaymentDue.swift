import Foundation

/// When a document asks to be paid, read from its text on this device, for
/// a reminder the owner adds to their own calendar: the day it names to pay
/// by, or the days it gives from its own date; the amount it names to pay;
/// the company to pay, as its letterhead names it; and its number. Only
/// what the page writes, nothing guessed: without a day to pay by there is
/// nothing, and nothing for a document already paid, paid by direct debit,
/// or a credit note.
enum PaymentDue {
    /// A day of the calendar, as a page writes it.
    struct Day: Equatable, Comparable, Hashable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        static func < (a: Day, b: Day) -> Bool {
            (a.year, a.month, a.day) < (b.year, b.month, b.day)
        }

        /// A day that is one: the 31st of April is none.
        init?(year: Int, month: Int, day: Int) {
            guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            guard let date = Self.calendar.date(from: parts),
                  Self.calendar.component(.day, from: date) == day else { return nil }
            self.year = year
            self.month = month
            self.day = day
        }

        /// That many days later.
        func adding(days: Int) -> Day? {
            guard let date = date(in: Self.calendar),
                  let later = Self.calendar.date(byAdding: .day, value: days, to: date) else { return nil }
            let parts = Self.calendar.dateComponents([.year, .month, .day], from: later)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            return Day(year: year, month: month, day: day)
        }

        /// The day's start in a calendar, as the owner's calendar counts it.
        func date(in calendar: Calendar) -> Date? {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            return calendar.date(from: parts)
        }

        /// The day a date falls on in a calendar.
        init?(_ date: Date, in calendar: Calendar) {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            self.init(year: year, month: month, day: day)
        }

        /// Days counted the same everywhere, so a day is the one written.
        private static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            return calendar
        }()
    }

    /// What a document asks to be paid.
    struct Found: Equatable, Sendable {
        /// The day to pay by.
        var day: Day
        /// The amount to pay, as written: "369,73 €".
        var amount: String?
        /// The company to pay, as the page names it: "Musterfirma GmbH".
        var payee: String?
        /// The document's number, as written: "RE-2026-0417".
        var reference: String?
    }

    /// What the text asks to be paid, or nil. `text` is the document's
    /// text in reading order, a line each, a table's cells apart by tabs,
    /// as `ScanReading` writes it. `own` holds the owner's own words,
    /// folded (`OwnDetails.fold`): a company named with them is the
    /// owner's, never the one to pay.
    static func find(in text: String, own: Set<String> = []) -> Found? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let flat = lines.map { $0.replacingOccurrences(of: "\t", with: "  ") }
        let whole = flat.joined(separator: "\n").lowercased()
        guard !matches(notToPay, in: whole) else { return nil }
        let issued = documentDate(in: flat)
        var days: [(day: Day, line: Int)] = []
        for (index, line) in flat.enumerated() {
            guard let cue = firstMatch(dueCue, in: line) else { continue }
            let next = index + 1 < flat.count ? flat[index + 1] : ""
            guard let day = day(asked: line, cue: cue, next: next, issued: issued) else { continue }
            // A day before the document's own is none to pay by.
            if let issued, day < issued { continue }
            days.append((day, index))
        }
        // The last day given, as a reminder letter names a new one and a
        // discount's day comes before the one without it.
        guard let due = days.max(by: { $0.day < $1.day }) else { return nil }
        return Found(day: due.day, amount: amount(in: flat, due: due.line), payee: payee(in: flat, own: own),
                     reference: reference(in: flat))
    }

    // MARK: Days

    /// Words that ask for a payment by a day or within some days.
    private static let dueCue = try? NSRegularExpression(pattern:
        #"\b(?:zahlbar|fällig(?:keit|keitsdatum)?|faellig|zahlungsziel|zahlungsfrist|zahlungsbedingung(?:en)?|überweisen|ueberweisen|bezahlen|bitte\s+zahlen|zahlen\s+sie|zu\s+zahlen|zahlung\s+bis|zahlungseingang\s+bis|begleichen|due(?!\s+to\b)|pay\s+by|please\s+pay|payable|payment\s+by|payment\s+terms|terms\s*:|remit\s+by)(?!\p{L})"#,
        options: [.caseInsensitive])
    /// Words a sentence asking for a payment runs on after, to the next line.
    private static let runsOn = try? NSRegularExpression(pattern:
        #"\b(?:bis|zum|am|den|spätestens|innerhalb|binnen|von|by|until|before|on|within)\s*$"#, options: [.caseInsensitive])
    /// Words that name the day before it as the one to pay by: "bis
    /// 04.11.", "ist am 15.11.2026 fällig".
    private static let lastDay = try? NSRegularExpression(pattern:
        #"\b(?:bis|spätestens|am|zum|by|until|before|on)\s+(?:zum\s+|zur\s+|am\s+|den\s+|spätestens\s+)?$"#, options: [.caseInsensitive])

    /// The day a line asks to be paid by, round its cue: the first written
    /// after it, on its line or, where the sentence runs on, the next; else
    /// the days it gives from the document's date; else the last day before
    /// the cue named as the one, as "Bitte bis 04.11. überweisen."
    private static func day(asked line: String, cue: Range<String.Index>, next: String, issued: Day?) -> Day? {
        var after = String(line[cue.upperBound...])
        if firstMatch(runsOn, in: after) != nil || after.trimmingCharacters(in: .whitespaces).isEmpty && !next.isEmpty {
            after += " " + next
        }
        if let day = firstDay(in: after, issued: issued) ?? relativeDay(in: after, from: issued) { return day }
        let before = String(line[..<cue.lowerBound])
        return days(in: before, issued: issued).last { found in
            firstMatch(lastDay, in: (before as NSString).substring(to: found.at)) != nil
        }?.day
    }

    /// Words that say nothing is to be paid: paid already, a stamp alone
    /// on its line or with its day; by direct debit; or money coming back,
    /// a credit note named so at the start of a line.
    private static let notToPay = try? NSRegularExpression(pattern:
        #"(?:^|\n)\s*(?:bezahlt|beglichen|paid)\b[\s\d./:-]*(?:\n|$)|\b(?:bereits\s+(?:bezahlt|beglichen|überwiesen)|dankend\s+erhalten|zahlung\s+erhalten|bezahlt\s+(?:am|mit|per|via|durch)|already\s+paid|payment\s+received|paid\s+in\s+full|abgebucht|abbuchen|abbuchung|eingezogen|einziehen|belastet|direct\s+debit|rückerstattung|erstatten\s+wir|wir\s+überweisen\s+ihnen|refund)\b|(?<!rück)lastschrift|(?:^|\n)\s*(?:gutschrift|credit\s+note)\b"#,
        options: [.caseInsensitive])

    private static let months: [String: Int] = [
        "januar": 1, "jänner": 1, "january": 1, "jan": 1, "februar": 2, "february": 2, "feb": 2, "märz": 3,
        "maerz": 3, "march": 3, "mär": 3, "mrz": 3, "mar": 3, "april": 4, "apr": 4, "mai": 5, "may": 5, "juni": 6,
        "june": 6, "jun": 6, "juli": 7, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sept": 9,
        "sep": 9, "oktober": 10, "october": 10, "okt": 10, "oct": 10, "november": 11, "nov": 11, "dezember": 12,
        "december": 12, "dez": 12, "dec": 12,
    ]
    private static let monthPattern = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    /// "28.10.2026", "28.10.26", "04.11." (its year the document's).
    private static let dotted = try? NSRegularExpression(pattern: #"(?<![\d.])(\d{1,2})\.\s?(\d{1,2})\.(?:\s?(\d{4}|\d{2})(?![\d]))?"#)
    /// "2026-10-28".
    private static let iso = try? NSRegularExpression(pattern: #"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#)
    /// "28/10/2026", only where the day is plain from the numbers.
    private static let slashed = try? NSRegularExpression(pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4})(?![\d/])"#)
    /// "28. Oktober 2026", "28 Oct 2026".
    private static let dayMonth = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})\.?\s+("# + monthPattern + #")\.?\s+(\d{4})(?!\d)"#,
                                                           options: [.caseInsensitive])
    /// "October 28, 2026", "Oct. 28th 2026".
    private static let monthDay = try? NSRegularExpression(pattern: #"\b("# + monthPattern + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})(?!\d)"#,
                                                           options: [.caseInsensitive])

    /// The days written in a piece of text, and where each starts. A day
    /// written without its year, "04.11.", is in the year of the document's
    /// own date, or the next where it would come before it; without that
    /// date it is none.
    private static func days(in text: String, issued: Day?) -> [(day: Day, at: Int)] {
        let whole = NSRange(text.startIndex..., in: text)
        func number(_ match: NSTextCheckingResult, _ group: Int) -> Int? {
            Range(match.range(at: group), in: text).flatMap { Int(text[$0]) }
        }
        func month(_ match: NSTextCheckingResult, _ group: Int) -> Int? {
            Range(match.range(at: group), in: text).flatMap { months[text[$0].lowercased()] }
        }
        var found: [(day: Day, at: Int)] = []
        for match in dotted?.matches(in: text, range: whole) ?? [] {
            guard let day = number(match, 1), let month = number(match, 2) else { continue }
            if let written = number(match, 3) {
                guard let one = Day(year: written < 100 ? 2000 + written : written, month: month, day: day) else { continue }
                found.append((one, match.range.location))
            } else if let issued, let one = Day(year: issued.year, month: month, day: day) {
                found.append((one < issued ? Day(year: issued.year + 1, month: month, day: day) ?? one : one, match.range.location))
            }
        }
        for match in iso?.matches(in: text, range: whole) ?? [] {
            guard let year = number(match, 1), let month = number(match, 2), let day = number(match, 3),
                  let one = Day(year: year, month: month, day: day) else { continue }
            found.append((one, match.range.location))
        }
        for match in slashed?.matches(in: text, range: whole) ?? [] {
            guard let first = number(match, 1), let second = number(match, 2), let year = number(match, 3) else { continue }
            // 04/11/2026 is the 4th of November or the 11th of April: not guessed.
            let day: Day?
            if first > 12 { day = Day(year: year, month: second, day: first) }
            else if second > 12 { day = Day(year: year, month: first, day: second) }
            else { day = nil }
            if let day { found.append((day, match.range.location)) }
        }
        for match in dayMonth?.matches(in: text, range: whole) ?? [] {
            guard let day = number(match, 1), let month = month(match, 2), let year = number(match, 3),
                  let one = Day(year: year, month: month, day: day) else { continue }
            found.append((one, match.range.location))
        }
        for match in monthDay?.matches(in: text, range: whole) ?? [] {
            guard let month = month(match, 1), let day = number(match, 2), let year = number(match, 3),
                  let one = Day(year: year, month: month, day: day) else { continue }
            found.append((one, match.range.location))
        }
        return found.sorted { $0.at < $1.at }
    }

    private static func firstDay(in text: String, issued: Day?) -> Day? {
        days(in: text, issued: issued).first?.day
    }

    /// "innerhalb von 14 Tagen", "Zahlungsziel: 30 Tage", "within 14 days",
    /// "net 30": that many days from the document's date. Working days are
    /// not counted, as the calendar alone does not say which they are.
    private static let within = try? NSRegularExpression(pattern:
        #"(?:(?:innerhalb|binnen)\s+(?:von\s+)?(\d{1,3})\s+tag(?:en|e)\b|(?<![\d,.])(\d{1,3})\s+tag(?:en|e)\b(?!\s*(?:vor|früher))|within\s+(\d{1,3})\s+days\b|\bnet\s+(\d{1,3})\b|(?<![\d,.])(\d{1,3})\s+days\b)"#,
        options: [.caseInsensitive])

    private static func relativeDay(in text: String, from issued: Day?) -> Day? {
        guard let issued, let match = within?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for group in 1...5 {
            if let range = Range(match.range(at: group), in: text), let days = Int(text[range]), (0...180).contains(days) {
                return issued.adding(days: days)
            }
        }
        return nil
    }

    /// Labels a document's own date follows.
    private static let dateLabel = try? NSRegularExpression(pattern:
        #"\b(?:rechnungsdatum|belegdatum|ausstellungsdatum|datum|invoice\s+date|issue\s+date|date)\b"#, options: [.caseInsensitive])

    /// The document's own date: after its label first, up to a cue that
    /// asks for a payment, never after one ("Due date"); else the first day
    /// written on a line that asks for none.
    private static func documentDate(in lines: [String]) -> Day? {
        for line in lines {
            guard let label = firstMatch(dateLabel, in: line) else { continue }
            let cue = firstMatch(dueCue, in: line)
            if let cue, cue.lowerBound <= label.lowerBound { continue }
            let end = cue?.lowerBound ?? line.endIndex
            guard label.upperBound <= end, let day = firstDay(in: String(line[label.upperBound..<end]), issued: nil) else { continue }
            return day
        }
        for line in lines where firstMatch(dueCue, in: line) == nil {
            if let day = firstDay(in: line, issued: nil) { return day }
        }
        return nil
    }

    // MARK: The amount

    /// "369,73 €", "€ 1.234,56", "$120.00", "49,90 EUR".
    private static let money = try? NSRegularExpression(pattern:
        #"(?:€|EUR|US\$|\$|USD|£|GBP|CHF)\s?-?\d{1,3}(?:[.,\x{00A0} ]\d{3})*(?:[.,]\d{2})?(?!\d)|(?<![\d.,])-?\d{1,3}(?:[.,\x{00A0} ]\d{3})*[.,]\d{2}(?:\s?(?:€|EUR\b|USD\b|£|GBP\b|CHF\b))?(?![\d.,]*\d)"#)

    /// Labels of the amount to pay, the surest first.
    private static let payLabels = try? NSRegularExpression(pattern:
        #"\b(?:zu\s+zahlen|zahlbetrag|zahlungsbetrag|rechnungsbetrag|gesamtbetrag|endbetrag|offener\s+betrag|offene\s+summe|noch\s+offen|zu\s+überweisen|bruttobetrag|summe\s+brutto|gesamt\s+brutto|amount\s+due|balance\s+due|total\s+due|amount\s+payable|total\s+amount|grand\s+total)\b"#,
        options: [.caseInsensitive])
    private static let totalLabels = try? NSRegularExpression(pattern:
        #"\b(?:gesamt|gesamtsumme|summe|total|brutto)\b"#, options: [.caseInsensitive])
    /// Labels of amounts that are part of the whole, never the whole.
    private static let partLabels = try? NSRegularExpression(pattern:
        #"\b(?:netto|zwischensumme|subtotal|sub-total|mwst|ust|vat|steuer|tax|rabatt|discount|skonto|anzahlung|versand|shipping)\b"#,
        options: [.caseInsensitive])

    /// The amount to pay: the one the sentence asking for it names; else
    /// the last after a label of the amount to pay, the surest kind first.
    private static func amount(in lines: [String], due: Int) -> String? {
        // Not where it names a discount or part of the whole: "2 % Skonto (7,39 €)".
        if firstMatch(partLabels, in: lines[due]) == nil, let named = lastAmount(in: lines[due]) { return named }
        for labels in [payLabels, totalLabels] {
            var last: String?
            for line in lines {
                guard let label = firstMatch(labels, in: line), firstMatch(partLabels, in: line) == nil else { continue }
                if let found = lastAmount(in: String(line[label.upperBound...])) { last = found }
            }
            if let last { return last }
        }
        return nil
    }

    private static func lastAmount(in text: String) -> String? {
        guard let match = money?.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else { return nil }
        return text[range].trimmingCharacters(in: .whitespaces)
    }

    // MARK: Who, and which

    /// The company to pay: the first its letterhead names with its legal
    /// form, "Musterfirma GmbH", near the top, without a letter read from a
    /// logo or a label before it. A practice or a person is not named: the
    /// reminder's title then says only that a payment is due.
    private static func payee(in lines: [String], own: Set<String>) -> String? {
        for line in lines.prefix(12) {
            let words = line.split(whereSeparator: { $0.isWhitespace }).map { OwnDetails.fold(String($0)) }
            guard !words.contains(where: own.contains) else { continue }
            for range in DocumentSense.organizationRanges(in: line) {
                var name = line[range].split(separator: " ", omittingEmptySubsequences: true)
                while let first = name.first, first.count == 1 || first.hasSuffix(":"), name.count > 1 { name.removeFirst() }
                guard let form = name.lastIndex(where: { DocumentSense.isLegalForm(String($0)) }), form > name.startIndex
                else { continue }
                return name[...form].joined(separator: " ")
            }
        }
        return nil
    }

    /// The document's number, after its label: "Rechnungsnr. RE-2026-0417".
    private static let referenceLabel = try? NSRegularExpression(pattern:
        #"\b(?:rechnungs-?(?:nr|nummer|no)|rechnung\s+nr|beleg-?(?:nr|nummer)|invoice\s*(?:no|number|#))\.?\s*:?\s*([A-Za-z0-9][A-Za-z0-9/._-]*\d[A-Za-z0-9/._-]*)"#,
        options: [.caseInsensitive])

    private static func reference(in lines: [String]) -> String? {
        for line in lines {
            guard let match = referenceLabel?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { continue }
            return String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        }
        return nil
    }

    // MARK: Matching

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> Range<String.Index>? {
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return Range(match.range, in: text)
    }

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> Bool {
        firstMatch(regex, in: text) != nil
    }
}
