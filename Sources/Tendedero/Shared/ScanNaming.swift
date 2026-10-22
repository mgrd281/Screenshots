import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a scanned document is, as Scan labels it.
enum PaperKind: String, CaseIterable, Sendable {
    case invoice, letter, form, receipt

    var title: String {
        switch self {
        case .invoice: L("Invoice")
        case .letter: L("Letter")
        case .form: L("Form")
        case .receipt: L("Receipt")
        }
    }
}

/// A scanned document's name and kind, from the words its first page
/// shows with its covers on: never a word under a cover, never the owner's
/// own name. With Apple Intelligence on, it reads those words on this device
/// and names the kind and the sender; the date is the one written on the
/// page, as written. Nothing is guessed or filled in: what cannot be found
/// is left out, and with Apple Intelligence off, or nothing found, the
/// document is named by when it was scanned.
enum ScanNaming {
    /// A word read on a page and where it is, from 0 to 1 from the bottom left.
    struct Word: Equatable, Sendable {
        let text: String
        let box: CGRect
    }

    /// What a page shows with its covers on: its lines, top first, of the
    /// words no cover touches; and the words under the covers, folded, which
    /// a name never holds.
    struct Visible: Equatable, Sendable {
        var lines: [String]
        var hidden: Set<String>
    }

    /// The name and the kind, and whether the name was suggested from the
    /// page or is the one by when it was scanned.
    struct Result: Equatable, Sendable {
        var name: String
        var kind: PaperKind?
        var suggested: Bool
    }

    /// The kind and the sender as Apple Intelligence read them, unchecked.
    struct Reading: Equatable, Sendable {
        var kind: PaperKind?
        var sender: String?
    }

    // MARK: What shows

    /// The lines as they show with these places covered: a word any cover
    /// touches, even at its edge, is hidden.
    static func visible(_ lines: [[Word]], covered places: [CGRect]) -> Visible {
        var shown: [(top: CGFloat, text: String)] = []
        var hidden: Set<String> = []
        for line in lines where !line.isEmpty {
            var kept: [String] = []
            for word in line {
                let touched = places.contains { place in
                    let shared = place.intersection(word.box)
                    return !shared.isNull && shared.width > 0 && shared.height > 0
                }
                if touched {
                    hidden.formUnion(folded(word.text))
                } else {
                    kept.append(word.text)
                }
            }
            let top: CGFloat = line.map(\.box.maxY).max() ?? 0
            if !kept.isEmpty { shown.append((top, kept.joined(separator: " "))) }
        }
        let ordered = shown.sorted { $0.top > $1.top }.map(\.text)
        return Visible(lines: ordered, hidden: hidden)
    }

    /// Each word of a text folded, as the covers' words are compared.
    static func folded(_ text: String) -> Set<String> {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" || $0 == "·" })
        return Set(words.map { OwnDetails.fold(String($0)) }.filter { !$0.isEmpty })
    }

    // MARK: Without Apple Intelligence

    /// The name by when the document was scanned: "Scan 21.10.2026, 14.05".
    static func fallback(at date: Date, in zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "dd.MM.yyyy, HH.mm"
        return String(format: L("Scan %@"), formatter.string(from: date))
    }

    /// Words that say what kind a document is, in the languages its pages
    /// are most often written in.
    private static let kindWords: [(PaperKind, [String])] = [
        (.invoice, ["rechnung", "rechnungsnummer", "rechnungsnr", "rechnungsdatum", "invoice", "facture", "factura",
                    "fattura", "fatura", "請求書", "发票", "청구서", "فاتورة"]),
        (.receipt, ["quittung", "kassenbon", "kassenbeleg", "beleg", "bon-nr", "rückgeld", "receipt", "reçu", "recibo",
                    "ricevuta", "makbuz", "領収書", "收据", "영수증", "إيصال"]),
        (.form, ["formular", "antrag", "bitte ankreuzen", "ausfüllen", "unterschrift des antragstellers", "application form",
                 "form no", "formulaire", "formulario", "modulo", "başvuru formu", "申請書", "申请表", "신청서", "استمارة"]),
        (.letter, ["sehr geehrte", "sehr geehrter", "mit freundlichen grüßen", "freundliche grüße", "dear ", "sincerely",
                   "kind regards", "yours faithfully", "madame, monsieur", "estimado", "gentile", "sayın", "拝啓",
                   "尊敬的", "귀하", "المحترم"]),
    ]

    /// The kind a document's words say most often, from its words alone;
    /// nil where none says.
    static func kind(of lines: [String]) -> PaperKind? {
        let text = " " + lines.joined(separator: " ").lowercased() + " "
        var best: (kind: PaperKind, score: Int)?
        for (kind, words) in kindWords {
            let score = words.filter { text.contains($0) }.count
            if score > 0, score > best?.score ?? 0 { best = (kind, score) }
        }
        return best?.kind
    }

    // MARK: The date

    /// Labels a document's own date follows.
    private static let dateLabels = ["datum", "date", "rechnungsdatum", "belegdatum", "ausgestellt", "fecha", "data",
                                     "tarih", "日付", "日期", "날짜", "التاريخ"]

    /// The document's date as written on it: one after a date label first,
    /// else the first there is, top first. Day, month and year in figures,
    /// "14.10.2026", "14/10/2026" (written "14-10-2026", as a file's name
    /// takes no slash) or "2026-10-14". Nil where there is none.
    static func date(in lines: [String]) -> String? {
        let labelled = lines.filter { line in
            let lower = line.lowercased()
            return dateLabels.contains { lower.contains($0) }
        }
        for line in labelled + lines {
            if let found = firstDate(in: line) { return found }
        }
        return nil
    }

    private static let dayFirst = try? NSRegularExpression(pattern: "(?<![0-9])([0-9]{1,2})[./]([0-9]{1,2})[./]([0-9]{4})(?![0-9])")
    private static let yearFirst = try? NSRegularExpression(pattern: "(?<![0-9])([0-9]{4})-([0-9]{2})-([0-9]{2})(?![0-9])")

    private static func firstDate(in line: String) -> String? {
        let whole = NSRange(line.startIndex..., in: line)
        var found: [(at: Int, text: String)] = []
        if let match = dayFirst?.firstMatch(in: line, range: whole), let text = Range(match.range, in: line),
           let day = number(match, 1, in: line), let month = number(match, 2, in: line), real(day: day, month: month) {
            found.append((match.range.location, line[text].replacingOccurrences(of: "/", with: "-")))
        }
        if let match = yearFirst?.firstMatch(in: line, range: whole), let text = Range(match.range, in: line),
           let month = number(match, 2, in: line), let day = number(match, 3, in: line), real(day: day, month: month) {
            found.append((match.range.location, String(line[text])))
        }
        return found.min { $0.at < $1.at }?.text
    }

    private static func number(_ match: NSTextCheckingResult, _ group: Int, in line: String) -> Int? {
        Range(match.range(at: group), in: line).flatMap { Int(line[$0]) }
    }

    private static func real(day: Int, month: Int) -> Bool {
        (1...31).contains(day) && (1...12).contains(month)
    }

    // MARK: The name

    /// Legal forms left off the end of a sender's name, as people say it.
    private static let legalForms: Set<String> = ["gmbh", "ggmbh", "mbh", "ag", "kg", "kgaa", "ohg", "gbr", "ug", "se",
                                                  "ev", "ek", "inc", "llc", "ltd", "limited", "corp", "plc", "sa",
                                                  "sarl", "sl", "bv", "nv", "spa", "srl", "co"]

    /// The name suggested from what Apple Intelligence read: its kind, its
    /// sender and the date written on the page, each only where the page
    /// shows it and none with a word of a cover or of the owner's own
    /// names. Nil where neither a kind nor a sender is left.
    static func suggestion(_ reading: Reading, visible: Visible, own: Set<String>) -> String? {
        let banned = visible.hidden.union(own)
        let sender = reading.sender.flatMap { checked(sender: $0, visible: visible, banned: banned) }
        guard reading.kind != nil || sender != nil else { return nil }
        var date = Self.date(in: visible.lines)
        if let shown = date, !folded(shown).isDisjoint(with: banned) { date = nil }
        let parts: [String] = [reading.kind?.title, sender, date].compactMap { $0 }
        let name = safe(parts.joined(separator: " "))
        guard !name.isEmpty else { return nil }
        // The kind's word is the app's own; every other word must be one shown.
        let words = folded(name).subtracting(reading.kind.map { folded($0.title) } ?? [])
        return words.isDisjoint(with: banned) ? name : nil
    }

    /// A sender as the page shows it, its legal form left off the end; nil
    /// where the page doesn't show it, a word of it is under a cover or one
    /// of the owner's names, or it reads as a person's name.
    static func checked(sender: String, visible: Visible, banned: Set<String>) -> String? {
        let trimmed = sender.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.,:;")))
        guard trimmed.count >= 2, trimmed.count <= 60, trimmed.contains(where: \.isLetter) else { return nil }
        let shown = visible.lines.contains { line in
            line.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        guard shown, folded(trimmed).isDisjoint(with: banned) else { return nil }
        if DocumentSense.nameWords(trimmed) != nil, !DocumentSense.isOrganization(trimmed) { return nil }
        var words = trimmed.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, legalForms.contains(OwnDetails.fold(last)) {
            words.removeLast()
        }
        let short = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " &,-+"))
        return short.isEmpty ? nil : short
    }

    /// A name a file can take everywhere: no slash, colon or other sign a
    /// folder refuses, one space between words, at most 80 characters.
    static func safe(_ name: String) -> String {
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let spaced = name.unicodeScalars.map { refused.contains($0) ? " " : String($0) }.joined()
        let words = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let short = String(words.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return short
    }

    /// The name and the kind: suggested from what Apple Intelligence read,
    /// where it read anything that holds; otherwise the name by when the
    /// document was scanned, and the kind from its words.
    static func result(_ reading: Reading?, visible: Visible, own: Set<String>, scanned: Date) -> Result {
        let words = kind(of: visible.lines)
        guard let reading else { return Result(name: fallback(at: scanned), kind: words, suggested: false) }
        let kind = reading.kind ?? words
        let checked = Reading(kind: kind, sender: reading.sender)
        if let name = suggestion(checked, visible: visible, own: own) {
            return Result(name: name, kind: kind, suggested: true)
        }
        return Result(name: fallback(at: scanned), kind: kind, suggested: false)
    }

    // MARK: Apple Intelligence

    /// What Apple Intelligence is told: to name the kind and the sender,
    /// copied from the lines, and nothing else.
    static let instructions = """
        You read the visible text of one scanned document. Some parts are covered for privacy and are not in \
        the text: never guess them. Answer with exactly two lines and nothing else:
        type: invoice, letter, form, receipt or other
        sender: the company, office or organisation that sent the document, copied exactly as it is written \
        in the lines, or none
        Never give a private person's name. Never invent, complete or correct anything.
        """

    /// The kind and the sender from Apple Intelligence's answer.
    static func parse(_ answer: String) -> Reading {
        var reading = Reading()
        for line in answer.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = parts[1]
            switch parts[0].lowercased() {
            case "type":
                reading.kind = PaperKind(rawValue: value.lowercased())
            case "sender":
                let none = ["none", "unknown", "n/a", "-", ""].contains(value.lowercased())
                reading.sender = none ? nil : value
            default:
                continue
            }
        }
        return reading
    }

    /// Whether Apple Intelligence may name scans: on in Settings and there
    /// on this device. The AI assistant never does; nothing leaves.
    static var asksIntelligence: Bool {
        Finder.usesIntelligence && Finder.intelligenceAvailable
    }

    /// Asks Apple Intelligence, on this device, for the kind and the
    /// sender in these lines; nil where it is off, not there or gives no
    /// answer.
    static func ask(_ visible: Visible) async -> Reading? {
        guard asksIntelligence, !visible.lines.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return nil }
            let shown = visible.lines.prefix(80).map { String($0.prefix(120)) }.joined(separator: "\n")
            let session = LanguageModelSession(model: model, instructions: instructions)
            do {
                let response = try await session.respond(
                    to: "Lines of text:\n\(shown)", options: GenerationOptions(temperature: 0, maximumResponseTokens: 60))
                return parse(response.content)
            } catch {
                log.error("Apple Intelligence could not name the scan: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
        return nil
    }
}

/// A photo chosen in the Photos tab that looks like a photographed paper
/// document: offered to be straightened and brightened as a scan is, never
/// done unasked; never a screenshot.
enum DocumentPhoto {
    /// Vision's certainty of the page under which it is not offered, as
    /// for corners set by hand in Scan.
    static let sure: Float = 0.65
    /// Words read on it, at the least: a page of text, not a sign.
    static let fewestWords = 12
    /// The page's share of the photo, at the least.
    static let smallestPage: CGFloat = 0.2

    /// Whether to offer it: not a screenshot, a page Vision is sure of,
    /// large enough and in usable corners, and enough words read.
    static func offers(screenshot: Bool, page: ScanQuad?, confidence: Float?, words: Int) -> Bool {
        guard !screenshot, let page, let confidence else { return false }
        return confidence >= sure && page.isUsable && page.area >= smallestPage && words >= fewestWords
    }
}
