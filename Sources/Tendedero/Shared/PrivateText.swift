import CoreGraphics
import Foundation
import ImageIO
import NaturalLanguage
import os
import Vision

/// The kinds of private detail that can be covered, each chosen on its own
/// under Privacy in Settings, on the Mac and on the iPhone.
enum PrivateDetail: String, CaseIterable {
    case names, addresses, emails, phones, bank, health
    case usernames, faces, ids, codes, orders, tracking, amounts, dates, links

    var title: String {
        switch self {
        case .names: L("Names")
        case .addresses: L("Addresses")
        case .emails: L("Emails")
        case .phones: L("Phone numbers")
        case .bank: L("Bank cards and accounts")
        case .health: L("Health details")
        case .usernames: L("Usernames")
        case .faces: L("Faces")
        case .ids: L("ID and tax numbers")
        case .codes: L("Passwords and codes")
        case .orders: L("Order and customer numbers")
        case .tracking: L("Tracking numbers")
        case .amounts: L("Amounts")
        case .dates: L("Dates")
        case .links: L("Links")
        }
    }

    /// How Settings groups the kinds, so fifteen read as three short lists.
    enum Group: CaseIterable {
        case people, sensitive, business

        var title: String {
            switch self {
            case .people: L("People")
            case .sensitive: L("Money, identity and health")
            case .business: L("Orders and documents")
            }
        }

        var kinds: [PrivateDetail] { PrivateDetail.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .names, .addresses, .emails, .phones, .usernames, .faces: .people
        case .bank, .ids, .codes, .health: .sensitive
        case .orders, .tracking, .amounts, .dates, .links: .business
        }
    }

    /// What is private in nearly every screenshot, on until turned off. The
    /// rest, like the amount and the date, is often what a screenshot is
    /// sent for, so it waits to be chosen.
    var isRecommended: Bool {
        switch self {
        case .names, .addresses, .emails, .phones, .bank, .health, .ids, .codes: true
        case .usernames, .faces, .orders, .tracking, .amounts, .dates, .links: false
        }
    }

    static var recommended: Set<PrivateDetail> { Set(allCases.filter(\.isRecommended)) }
}

/// Finds private details in the text of a screenshot, three ways together:
/// patterns that are private wherever they appear, like an email address;
/// labels that announce one, like "Rechnungsadresse" above a name and an
/// address; and names found once and met again elsewhere.
enum Finder {
    struct TextLine {
        let text: VNRecognizedText
        /// Normalized, from the bottom left, as Vision measures.
        let box: CGRect
        var string: String { text.string }
    }

    /// One thing to cover: part of a line, or all of it.
    fileprivate struct Hit {
        let line: Int
        let range: NSRange?
    }

    /// What a label announces: the kind of its first line, the kind of the
    /// lines after it, and how many lines it can take.
    private struct Block {
        let first: PrivateDetail
        let rest: PrivateDetail
        let lines: Int
    }

    private static let person = Block(first: .names, rest: .addresses, lines: 6)
    private static let name = Block(first: .names, rest: .names, lines: 1)
    private static let health = Block(first: .health, rest: .health, lines: 4)
    private static let bank = Block(first: .bank, rest: .bank, lines: 1)
    private static let order = Block(first: .orders, rest: .orders, lines: 1)
    private static let parcel = Block(first: .tracking, rest: .tracking, lines: 1)
    private static let identity = Block(first: .ids, rest: .ids, lines: 1)
    private static let code = Block(first: .codes, rest: .codes, lines: 1)
    private static let user = Block(first: .usernames, rest: .usernames, lines: 1)

    /// Labels, lowercased, in the languages screenshots tend to come in.
    private static let labels: [String: Block] = {
        var labels: [String: Block] = [:]
        for label in ["rechnungsadresse", "lieferadresse", "versandadresse", "anschrift", "adresse",
                      "billing address", "shipping address", "delivery address", "address",
                      "ship to", "bill to", "sold to", "absender", "empfänger", "empfaenger",
                      "sender", "recipient", "from", "to", "von", "an",
                      "المرسل", "المستلم", "العنوان"] {
            labels[label] = person
        }
        for label in ["kunde", "kundin", "customer", "käufer", "buyer", "kontoinhaber", "account holder",
                      "name", "patient", "patientin", "versicherter", "الاسم", "العميل", "المريض"] {
            labels[label] = name
        }
        for label in ["diagnose", "diagnosis", "befund", "medikament", "medikamente", "medikation",
                      "medication", "medications", "medicine", "arzneimittel", "rezept", "prescription",
                      "behandlung", "treatment", "therapie", "therapy", "symptome", "symptoms",
                      "allergien", "allergies", "التشخيص", "الدواء", "الأدوية", "العلاج", "الوصفة"] {
            labels[label] = health
        }
        for label in ["iban", "bic", "swift", "kontonummer", "account number", "kartennummer", "card number",
                      "blz", "bankleitzahl", "sort code", "routing number", "cvv", "cvc"] {
            labels[label] = bank
        }
        for label in ["bestellnummer", "bestell-nr", "bestell-nr.", "bestellnr", "auftragsnummer", "auftrags-nr",
                      "order number", "order no", "order no.", "order #", "order id", "rechnungsnummer",
                      "rechnungs-nr", "rechnungs-nr.", "rechnung nr", "invoice number", "invoice no", "invoice no.",
                      "invoice #", "kundennummer", "kunden-nr", "kunden-nr.", "kundennr", "customer number",
                      "customer no", "customer no.", "customer id", "belegnummer", "beleg-nr", "vorgangsnummer",
                      "transaktionsnummer", "transaktions-id", "transaction id", "transaction number",
                      "رقم الطلب", "رقم الفاتورة", "رقم العميل", "رقم المعاملة"] {
            labels[label] = order
        }
        for label in ["sendungsnummer", "sendungs-nr", "sendungs-nr.", "sendungsverfolgung", "trackingnummer",
                      "tracking", "tracking number", "tracking no", "tracking no.", "tracking id", "paketnummer",
                      "paket-nr", "shipment number", "shipment id", "رقم الشحنة", "رقم التتبع"] {
            labels[label] = parcel
        }
        for label in ["ust-idnr", "ust-idnr.", "ust-id", "ust-id.", "umsatzsteuer-id",
                      "umsatzsteuer-identifikationsnummer", "steuernummer", "steuer-nr", "steuer-nr.", "steuer-id",
                      "steuerliche identifikationsnummer", "identifikationsnummer", "vat", "vat id", "vat number",
                      "vat no", "vat no.", "tax id", "tax number", "tax no", "tax no.", "ein", "personalausweis",
                      "ausweisnummer", "ausweis-nr", "passnummer", "reisepassnummer", "passport", "passport number",
                      "passport no", "passport no.", "id number", "id no", "id no.", "sozialversicherungsnummer",
                      "sv-nummer", "rentenversicherungsnummer", "ssn", "social security number", "kennzeichen",
                      "amtliches kennzeichen", "license plate", "licence plate",
                      "رقم الهوية", "رقم الجواز", "رقم جواز السفر", "الرقم الضريبي"] {
            labels[label] = identity
        }
        for label in ["passwort", "password", "kennwort", "pin", "pin-code", "tan", "code", "sicherheitscode",
                      "security code", "verification code", "verifizierungscode", "bestätigungscode",
                      "bestaetigungscode", "otp", "einmalpasswort", "one-time code", "one-time password",
                      "zugangscode", "access code", "gutscheincode", "gutschein", "coupon", "coupon code",
                      "promo code", "rabattcode", "discount code", "voucher", "voucher code",
                      "كلمة المرور", "كلمة السر", "رمز التحقق", "الرمز", "رمز الخصم"] {
            labels[label] = code
        }
        for label in ["benutzername", "nutzername", "username", "user name", "benutzer", "anmeldename", "login",
                      "login name", "handle", "اسم المستخدم"] {
            labels[label] = user
        }
        return labels
    }()

    /// Where the chosen details and the owner's own rules are, as they are
    /// covered: from 0 to 1 from the bottom left, with a margin around the
    /// text, and the faces when those are chosen.
    static func areas(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all) -> [CGRect] {
        let rules = rules.filter { !$0.isBlank }
        guard !chosen.isEmpty || !rules.isEmpty else { return [] }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var areas = boxes(in: image, chosen, rules: rules).map { box -> CGRect in
            // Vision measures from the bottom left, as Core Graphics draws.
            let text = VNImageRectForNormalizedRect(box, image.width, image.height)
            let rect = text.insetBy(dx: -text.height * 0.25, dy: -text.height * 0.2)
            return CGRect(x: rect.minX / width, y: rect.minY / height,
                          width: rect.width / width, height: rect.height / height)
        }
        if chosen.contains(.faces) { areas += faces(in: image) }
        return areas
    }

    /// The faces in a photo, with room around each so the hair and the chin
    /// go with it. From 0 to 1 from the bottom left, like the text.
    static func faces(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            log.error("Could not look for faces: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return (request.results ?? []).map { face in
            let box = face.boundingBox
            return box.insetBy(dx: -box.width * 0.2, dy: -box.height * 0.3)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    /// The picture with the given areas, from 0 to 1 from the bottom left,
    /// covered in opaque ink with softened corners.
    static func cover(_ image: CGImage, _ areas: [CGRect]) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        for box in areas {
            let rect = VNImageRectForNormalizedRect(box, image.width, image.height)
            let radius = min(rect.height / 4, rect.width / 2, 8)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        return context.makeImage()
    }

    /// Where the chosen details are, in Vision's normalized coordinates.
    static func boxes(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all) -> [CGRect] {
        // Faces are not read as text: with nothing else chosen, no reading.
        guard !chosen.subtracting([.faces]).isEmpty || rules.contains(where: { !$0.isBlank }) else { return [] }
        let lines = read(image)
        return hits(in: lines, chosen, rules: rules).compactMap { hit -> CGRect? in
            let line = lines[hit.line]
            guard let range = hit.range else { return line.box }
            guard let part = Range(range, in: line.string) else { return nil }
            return try? line.text.boundingBox(for: part)?.boundingBox
        }
    }

    /// What a screenshot says, a line per row, with the chosen details and
    /// the words under the parts hidden by hand left out as dots. Copy Text,
    /// translations and descriptions all start from it.
    struct Reading {
        let lines: [String]
        /// How tall each line's letters are, from 0 to 1 of the screenshot.
        let heights: [CGFloat]

        var text: String { lines.joined(separator: "\n") }

        /// The biggest words, most often the page's title, like "Order #1024".
        var headline: String? {
            lines.indices
                .filter { i in lines[i].unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 3 }
                .max { heights[$0] < heights[$1] }
                .map { lines[$0].trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Every line of text in a screenshot, as read, with where it sits,
    /// from 0 to 1 from the bottom left. Search looks through these.
    static func lines(of url: URL) -> [(text: String, box: CGRect)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return read(image).map { ($0.string, $0.box) }
    }

    /// The lines as read, so a part of one can be found and boxed.
    static func textLines(of url: URL) -> [TextLine] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return read(image)
    }

    /// The lines of a picture already open, like a page of a PDF.
    static func textLines(in image: CGImage) -> [TextLine] {
        read(image)
    }

    static func text(of url: URL, hiding chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                     rules: [OwnRule] = OwnRules.all) -> String {
        reading(of: url, hiding: chosen, hand: hand, rules: rules).text
    }

    static func reading(of url: URL, hiding chosen: Set<PrivateDetail>, hand: [CGRect] = [],
                        rules: [OwnRule] = OwnRules.all) -> Reading {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return Reading(lines: [], heights: []) }
        let lines = read(image)
        var hidden = [IndexSet](repeating: IndexSet(), count: lines.count)
        for hit in hits(in: lines, chosen, rules: rules) {
            let length = lines[hit.line].string.utf16.count
            let range = hit.range ?? NSRange(location: 0, length: length)
            let end = min(range.location + range.length, length)
            if range.location < end { hidden[hit.line].insert(integersIn: range.location..<end) }
        }
        for (i, line) in lines.enumerated() where hand.contains(where: { $0.intersects(line.box) }) {
            let string = line.string
            let all = NSRange(location: 0, length: string.utf16.count)
            for word in Self.word.matches(in: string, range: all) {
                guard let part = Range(word.range, in: string),
                      let box = try? line.text.boundingBox(for: part)?.boundingBox,
                      hand.contains(where: { $0.contains(CGPoint(x: box.midX, y: box.midY)) }) else { continue }
                hidden[i].insert(integersIn: word.range.location..<(word.range.location + word.range.length))
            }
        }
        let kept = lines.indices.map { i -> String in
            let line = lines[i].string as NSString
            var kept = ""
            var from = 0
            for run in hidden[i].rangeView {
                kept += line.substring(with: NSRange(location: from, length: run.lowerBound - from)) + "•••"
                from = run.upperBound
            }
            return kept + line.substring(from: from)
        }
        return Reading(lines: kept, heights: lines.map(\.box.height))
    }

    private static let word = try! NSRegularExpression(pattern: "\\S+")

    /// Everything to leave out, all three ways, and the owner's own rules.
    private static func hits(in lines: [TextLine], _ chosen: Set<PrivateDetail>, rules: [OwnRule]) -> [Hit] {
        let rules = rules.filter { !$0.isBlank }
        guard !lines.isEmpty, !chosen.isEmpty || !rules.isEmpty else { return [] }
        let text = Text(lines)
        var learned = Set<String>()
        var hits = patterns(in: text, chosen)
        hits += labelled(in: lines, chosen, learned: &learned)
        if chosen.contains(.names) { hits += names(in: text, learned: learned) }
        if chosen.contains(.health) { hits += medicines(in: lines) }
        hits += own(in: text, rules)
        return hits
    }

    /// The owner's own rules: words and patterns wherever they appear, and
    /// what follows a label, on its line or on the line below.
    private static func own(in text: Text, _ rules: [OwnRule]) -> [Hit] {
        var hits = ruleRanges(in: text.full, rules).flatMap { text.hits($0) }
        for rule in rules where rule.kind == .label && !rule.isBlank {
            let label = rule.text.trimmingCharacters(in: .whitespaces)
            for (i, line) in text.lines.enumerated() {
                let string = line.string
                guard let found = string.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else { continue }
                // The whole label, not the start of a longer word.
                if found.upperBound < string.endIndex, string[found.upperBound].isLetter { continue }
                let rest = string[found.upperBound...].drop { ": -–\t".contains($0) }
                if !rest.isEmpty {
                    hits.append(Hit(line: i, range: NSRange(rest.startIndex..<string.endIndex, in: string)))
                } else if let next = Self.line(below: i, in: text.lines, gap: 2) {
                    hits.append(Hit(line: next, range: nil))
                }
            }
        }
        return hits
    }

    /// The owner's words and patterns in plain text: a word whole, wherever
    /// it appears, in any case; a pattern as it matches. A pattern that
    /// cannot be read covers nothing. Pure text, so it can be checked
    /// without a picture.
    static func ruleRanges(in full: String, _ rules: [OwnRule]) -> [NSRange] {
        let whole = NSRange(full.startIndex..., in: full)
        var found: [NSRange] = []
        for rule in rules where !rule.isBlank {
            let text = rule.text.trimmingCharacters(in: .whitespaces)
            let pattern: String
            switch rule.kind {
            case .word:
                let edge: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber } == true }
                pattern = (edge(text.first) ? #"(?<!\w)"# : "") + NSRegularExpression.escapedPattern(for: text)
                    + (edge(text.last) ? #"(?!\w)"# : "")
            case .pattern:
                pattern = text
            case .label:
                continue
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            found += regex.matches(in: full, range: whole).map(\.range).filter { $0.length > 0 }
        }
        return found
    }

    private static func read(_ image: CGImage) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Numbers and addresses are read as they are, not corrected into words.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            log.error("Could not read a screenshot: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { TextLine(text: $0, box: observation.boundingBox) }
        }
    }

    /// All the text at once, a line per row, so a match that runs over two
    /// lines, like an address, is still found.
    fileprivate struct Text {
        let lines: [TextLine]
        let full: String
        let starts: [Int]

        init(_ lines: [TextLine]) {
            self.lines = lines
            var full = ""
            var starts: [Int] = []
            for line in lines {
                starts.append(full.utf16.count)
                full += line.string + "\n"
            }
            self.full = full
            self.starts = starts
        }

        var whole: NSRange { NSRange(full.startIndex..., in: full) }

        /// A range of the whole text, line by line.
        func hits(_ range: NSRange) -> [Hit] {
            lines.indices.compactMap { i -> Hit? in
                let span = NSRange(location: starts[i], length: lines[i].string.utf16.count)
                let overlap = NSIntersectionRange(range, span)
                guard overlap.length > 0 else { return nil }
                return Hit(line: i, range: NSRange(location: overlap.location - span.location, length: overlap.length))
            }
        }

        func matches(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [NSRange] {
            (try? NSRegularExpression(pattern: pattern, options: options))?
                .matches(in: full, range: whole).map(\.range) ?? []
        }
    }

    private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#

    /// Details that are private wherever they appear.
    private static func patterns(in text: Text, _ chosen: Set<PrivateDetail>) -> [Hit] {
        var hits = patternRanges(in: text.full, chosen).flatMap { text.hits($0) }
        if chosen.contains(.addresses),
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            for match in addresses.matches(in: text.full, range: text.whole) {
                let lines = text.hits(match.range)
                hits += lines
                // The detector often stops at the street. The postcode, the
                // town and the country follow just below.
                guard var last = lines.last?.line else { continue }
                for _ in 0..<3 {
                    guard let next = Self.line(below: last, in: text.lines, gap: 1.1),
                          looksLikeAddress(text.lines[next].string) else { break }
                    hits.append(Hit(line: next, range: nil))
                    last = next
                }
            }
        }
        return hits
    }

    /// The details found by their shape alone, in plain text: an email, an
    /// IBAN, "Order #1024", a code after the word "Code". Pure text, so it
    /// can be checked without a picture.
    static func patternRanges(in full: String, _ chosen: Set<PrivateDetail>) -> [NSRange] {
        let whole = NSRange(full.startIndex..., in: full)
        let text = full as NSString
        /// The whole match, or one group of it: the number after the word.
        func matches(_ pattern: String, _ options: NSRegularExpression.Options = [], group: Int = 0) -> [NSRange] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
            return regex.matches(in: full, range: whole).compactMap { match in
                let range = match.range(at: group)
                return range.location == NSNotFound || range.length == 0 ? nil : range
            }
        }
        func detected(_ type: NSTextCheckingResult.CheckingType) -> [NSTextCheckingResult] {
            (try? NSDataDetector(types: type.rawValue))?.matches(in: full, range: whole) ?? []
        }
        var found: [NSRange] = []
        if chosen.contains(.emails) {
            found += matches(emailPattern, .caseInsensitive)
        }
        if chosen.contains(.bank) {
            // IBANs, in groups of four with or without spaces between them.
            found += matches(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#)
            // Card numbers: 13 to 19 digits, grouped or not, that pass the Luhn check.
            found += matches(#"\b\d(?:[ -]?\d){12,18}\b"#).filter { passesLuhn(text.substring(with: $0)) }
        }
        if chosen.contains(.phones) {
            found += detected(.phoneNumber).map(\.range)
        }
        if chosen.contains(.orders) {
            // "#1024", and the number after "Order No.", "Rechnung" or
            // "Kundennummer", which must hold a digit.
            found += matches(#"(?<![\w#])#\s?(\d{3,}[\w-]*)"#, [], group: 1)
            found += matches(#"\b(?:Bestellung|Bestell-?Nr|Auftrag|Auftrags-?Nr|Order|Rechnung|Rechnungs-?Nr|Invoice|Kundennummer|Kunden-?Nr|Customer|Beleg|Vorgang|Transaktion|Transaction)\.?[ \t]*(?:Nr\.?|No\.?|Number|ID|#)?[ \t]*[:#]?[ \t]*((?=[A-Z0-9/-]*\d)[A-Z0-9][A-Z0-9/-]{2,})\b"#,
                             .caseInsensitive, group: 1)
        }
        if chosen.contains(.tracking) {
            // UPS, DHL Express, and the runs of 12, 14 or 20 digits DHL, DPD,
            // GLS, Hermes and FedEx print.
            found += matches(#"\b1Z[A-Z0-9]{16}\b"#)
            found += matches(#"\bJJD\d{16,20}\b"#)
            found += matches(#"\b(?:\d{12}|\d{14}|\d{20})\b"#)
        }
        if chosen.contains(.ids) {
            // VAT numbers, the German Steuernummer and Sozialversicherungsnummer, the US SSN.
            found += matches(#"\b(?:DE\d{9}|ATU\d{8}|NL\d{9}B\d{2}|FR[A-Z0-9]{2}\d{9}|CHE-?\d{3}\.?\d{3}\.?\d{3})\b"#)
            found += matches(#"\b\d{2,3}/\d{3}/\d{4,5}\b"#)
            found += matches(#"\b\d{3}-\d{2}-\d{4}\b"#)
            found += matches(#"\b\d{2} ?\d{6} ?[A-Z] ?\d{3}\b"#)
        }
        if chosen.contains(.codes) {
            // "Dein Code lautet 482913", "PIN: 1234", "TAN 123 456": the digits after the word.
            found += matches(#"\b(?:code|pin|tan|otp|passwort|password|kennwort)\b[^\n\d]{0,30}?(\d(?:[ -]?\d){3,7})(?!\d)"#,
                             .caseInsensitive, group: 1)
        }
        if chosen.contains(.amounts) {
            let number = #"\d{1,3}(?:[.,\x{00A0} ]\d{3})*(?:[.,]\d{2})?|\d+(?:[.,]\d{2})?"#
            found += matches(#"(?:€|EUR|US\$|\$|USD|£|GBP|CHF|SFr\.?)[ \x{00A0}]?(?:"# + number + #")"#)
            found += matches(#"\b(?:"# + number + #")[ \x{00A0}]?(?:€|EUR|US\$|\$|USD|£|GBP|CHF|SFr\.?|,-|,–)"#)
        }
        if chosen.contains(.dates) {
            found += detected(.date).map(\.range)
            found += matches(#"\b\d{1,2}[./]\d{1,2}[./]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b"#)
            found += matches(#"\b\d{1,2}\.?\s(?:Jan|Feb|Mär|Mar|Apr|Mai|May|Jun|Jul|Aug|Sep|Okt|Oct|Nov|Dez|Dec)[a-zäö]*\.?\s\d{4}\b"#,
                             .caseInsensitive)
        }
        if chosen.contains(.links) {
            // Web addresses; an email address is its own kind.
            found += detected(.link).filter { $0.url?.scheme?.lowercased() != "mailto" }.map(\.range)
        }
        if chosen.contains(.usernames) {
            // "@lena_h", but not the "@" inside an email address.
            found += matches(#"(?<![\w.@])@[A-Za-z0-9_][A-Za-z0-9_.]{1,29}\b"#)
        }
        return found
    }

    /// A postcode with its town, or a town or country on its own.
    private static func looksLikeAddress(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        if line.range(of: #"(^|\s)\d{4,6}(\s|$)"#, options: .regularExpression) != nil { return words.count <= 6 }
        return (1...3).contains(words.count) && line.first?.isUppercase == true
            && line.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" }
    }

    /// Details announced by a label: on the same line, as in "IBAN: DE89…",
    /// or in the lines under it, as a name and an address under
    /// "Rechnungsadresse".
    private static func labelled(in lines: [TextLine], _ chosen: Set<PrivateDetail>,
                                 learned: inout Set<String>) -> [Hit] {
        var hits: [Hit] = []
        for (i, line) in lines.enumerated() {
            let text = line.string.trimmingCharacters(in: .whitespaces)
            var label = normalized(text)
            if let colon = text.firstIndex(of: ":"), let block = labels[normalized(String(text[..<colon]))] {
                let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    let detail = kind(of: value, first: true, in: block)
                    if chosen.contains(detail), let part = line.string.range(of: value) {
                        hits.append(Hit(line: i, range: NSRange(part, in: line.string)))
                        if detail == .names { learn(value, into: &learned) }
                    }
                    continue
                }
                label = normalized(String(text[..<colon]))
            }
            guard let block = labels[label] else { continue }
            var last = i
            for n in 0..<block.lines {
                // A label sits a little further from its first line than the
                // lines from each other.
                guard let next = Self.line(below: last, in: lines, gap: n == 0 ? 2 : 1.1),
                      labels[normalized(lines[next].string)] == nil else { break }
                let detail = kind(of: lines[next].string, first: n == 0, in: block)
                if chosen.contains(detail) {
                    hits.append(Hit(line: next, range: nil))
                    if detail == .names { learn(lines[next].string, into: &learned) }
                }
                last = next
            }
        }
        return hits
    }

    /// The first line under a person's label is their name, when it reads
    /// like one; otherwise, like a street, it is part of the address.
    private static func kind(of line: String, first: Bool, in block: Block) -> PrivateDetail {
        guard first else { return block.rest }
        guard block.first == .names, block.rest != .names else { return block.first }
        return nameWords(line) != nil ? .names : block.rest
    }

    private static func learn(_ name: String, into learned: inout Set<String>) {
        if let words = nameWords(name) { learned.formUnion(words) }
    }

    /// The line right under another, starting in the same column, or nil
    /// when the gap is one a new section would leave.
    private static func line(below index: Int, in lines: [TextLine], gap: CGFloat) -> Int? {
        let above = lines[index].box
        var best: Int?
        for (i, line) in lines.enumerated() where i != index {
            let box = line.box
            guard box.maxY <= above.minY + above.height * 0.3,
                  above.minY - box.maxY < above.height * gap,
                  abs(box.minX - above.minX) < 0.03 else { continue }
            if let current = best, lines[current].box.maxY >= box.maxY { continue }
            best = i
        }
        return best
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":"))).lowercased()
    }

    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static let particles: Set<String> = ["van", "von", "de", "da", "del", "der", "den", "la", "le",
                                                 "bin", "ibn", "al", "el", "di", "du"]

    /// The words of a line that reads like a person's name: two to five
    /// words, at least two of them capitalized, and no digits. German
    /// capitalizes every noun, so the shape alone is never enough.
    private static func nameWords(_ line: String) -> [String]? {
        let words = line.split(separator: " ").map(String.init)
        guard (2...5).contains(words.count), !line.contains(where: \.isNumber) else { return nil }
        var names: [String] = []
        for word in words where !particles.contains(word) {
            guard word.first?.isUppercase == true,
                  word.allSatisfy({ $0.isLetter || "'’.-".contains($0) }) else { return nil }
            names.append(fold(word))
        }
        return names.count >= 2 ? names : nil
    }

    /// Names: a line shaped like one that something vouches for. It was
    /// under a label, the Natural Language framework calls it a person's
    /// name, it is in an email address, or it repeats a name found elsewhere.
    private static func names(in text: Text, learned: Set<String>) -> [Hit] {
        var tagged = Set<Int>()
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text.full
        tagger.enumerateTags(in: text.full.startIndex..<text.full.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            // A whole name, not a lone word: German capitalizes every noun,
            // and the tagger takes some of them for names.
            if tag == .personalName, text.full[range].contains(" ") {
                for hit in text.hits(NSRange(range, in: text.full)) { tagged.insert(hit.line) }
            }
            return true
        }
        let emails = text.matches(emailPattern, .caseInsensitive).map { range -> String in
            let address = (text.full as NSString).substring(with: range)
            return fold(String(address.prefix { $0 != "@" }))
        }

        let candidates = text.lines.indices.compactMap { i in nameWords(text.lines[i].string).map { (i, $0) } }
        var known = learned
        var found = Set<Int>()
        // Twice, so a name vouched for further down covers its earlier
        // mentions too.
        for _ in 0..<2 {
            for (i, words) in candidates where !found.contains(i) {
                let inEmail = words.contains { word in word.count >= 4 && emails.contains { $0.contains(word) } }
                if tagged.contains(i) || inEmail || words.allSatisfy(known.contains) {
                    found.insert(i)
                    known.formUnion(words)
                }
            }
        }
        return found.map { Hit(line: $0, range: nil) }
    }

    /// Lines with a dose or a pharmacy number, where medicines are named.
    private static func medicines(in lines: [TextLine]) -> [Hit] {
        let dose = #"\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ml|ie|iu|tbl|tabletten|tablets?|kapseln|capsules?)\b"#
        let pharmacy = #"\bPZN[:\s-]*\d{7,8}\b"#
        return lines.indices.compactMap { i -> Hit? in
            let line = lines[i].string
            let named = line.range(of: dose, options: [.regularExpression, .caseInsensitive]) != nil
                || line.range(of: pharmacy, options: .regularExpression) != nil
            return named ? Hit(line: i, range: nil) : nil
        }
    }

    private static func passesLuhn(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, digit) in digits.reversed().enumerated() {
            let doubled = digit * 2
            sum += i % 2 == 1 ? (doubled > 9 ? doubled - 9 : doubled) : digit
        }
        return sum % 10 == 0
    }
}
