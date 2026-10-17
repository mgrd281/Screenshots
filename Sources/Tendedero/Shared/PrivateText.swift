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
    case usernames, faces, ipAddresses, ids, codes, keys, barcodes, orders, tracking, amounts, dates, links

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
        case .ipAddresses: L("IP addresses")
        case .ids: L("ID and tax numbers")
        case .codes: L("Passwords and codes")
        case .keys: L("API keys and tokens")
        case .barcodes: L("QR codes and barcodes")
        case .orders: L("Order and customer numbers")
        case .tracking: L("Tracking numbers")
        case .amounts: L("Amounts")
        case .dates: L("Dates")
        case .links: L("Links")
        }
    }

    /// How Settings groups the kinds, so eighteen read as three short lists.
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
        case .names, .addresses, .emails, .phones, .usernames, .faces, .ipAddresses: .people
        case .bank, .ids, .codes, .keys, .barcodes, .health: .sensitive
        case .orders, .tracking, .amounts, .dates, .links: .business
        }
    }

    /// What is private in nearly every screenshot, on until turned off. The
    /// rest, like the amount and the date, is often what a screenshot is
    /// sent for, so it waits to be chosen. A code is private more often than
    /// not: a payment, a sign-in, a ticket or a parcel, unreadable to the eye.
    /// A key opens an account to whoever reads it. An IP address is often
    /// what a screenshot of a network is sent for.
    var isRecommended: Bool {
        switch self {
        case .names, .addresses, .emails, .phones, .bank, .health, .ids, .codes, .keys, .barcodes: true
        case .usernames, .faces, .ipAddresses, .orders, .tracking, .amounts, .dates, .links: false
        }
    }

    static var recommended: Set<PrivateDetail> { Set(allCases.filter(\.isRecommended)) }

    // MARK: Kinds added later

    /// The kinds there were when a choice was last brought up to date.
    static let knownKey = "knownDetails"

    /// The kinds there were before Snapfly noted which it knew.
    private static let firstKnown: Set<String> = ["names", "addresses", "emails", "phones", "bank", "health",
                                                  "usernames", "faces", "ids", "codes", "orders", "tracking",
                                                  "amounts", "dates", "links"]

    /// The recommended kinds added since a choice was made, which start on
    /// for whoever covers anything. A kind turned off after that stays off.
    static func added(to chosen: Set<PrivateDetail>, known: [String]?) -> Set<PrivateDetail> {
        guard !chosen.isEmpty else { return [] }
        let before = known.map { Set($0) } ?? firstKnown
        return Set(allCases.filter { $0.isRecommended && !before.contains($0.rawValue) && !chosen.contains($0) })
    }

    /// Brings the choices saved under these names up to date, then notes
    /// every kind as known, so each new kind is added once.
    static func bringUpToDate(_ keys: [String], in defaults: UserDefaults = .standard) {
        let known = defaults.stringArray(forKey: knownKey)
        for key in keys {
            guard let raw = defaults.stringArray(forKey: key) else { continue }
            let new = added(to: Set(raw.compactMap(PrivateDetail.init(rawValue:))), known: known)
            if !new.isEmpty { defaults.set((raw + new.map(\.rawValue)).sorted(), forKey: key) }
        }
        defaults.set(allCases.map(\.rawValue), forKey: knownKey)
    }
}

/// Finds private details in the text of a screenshot, three ways together:
/// patterns that are private wherever they appear, like an email address;
/// labels that announce one, like "Rechnungsadresse" above a name and an
/// address; and names found once and met again elsewhere. Where it is on,
/// Apple Intelligence reads along and names what those miss. Each copy is
/// then read again, as anyone could read it, and covered further if need be.
enum Finder {
    struct TextLine {
        let text: VNRecognizedText
        /// Normalized, from the bottom left, as Vision measures.
        let box: CGRect
        /// The part of the picture the text was read in: all of it, or the
        /// strip a line of small print was read again from, larger.
        var frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        var string: String { text.string }

        /// Where part of the line is in the picture, normalized like `box`.
        func box(for range: Range<String.Index>) -> CGRect? {
            guard let part = try? text.boundingBox(for: range)?.boundingBox else { return nil }
            return CGRect(x: frame.minX + part.minX * frame.width, y: frame.minY + part.minY * frame.height,
                          width: part.width * frame.width, height: part.height * frame.height)
        }
    }

    /// One thing to cover: part of a line, or all of it, and the kind it
    /// is covered as; nil for a rule of the owner's own.
    fileprivate struct Hit {
        let line: Int
        let range: NSRange?
        let kind: PrivateDetail?
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
    private static let key = Block(first: .keys, rest: .keys, lines: 1)
    private static let network = Block(first: .ipAddresses, rest: .ipAddresses, lines: 1)
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
                      "vertragsnummer", "vertrags-nr", "vertrags-nr.", "contract number", "policennummer",
                      "policy number", "mitgliedsnummer", "mitglieds-nr", "member number", "membership number",
                      "member id", "buchungsnummer", "booking number", "reservierungsnummer", "reservation number",
                      "ticketnummer", "ticket number", "referenznummer", "reference number", "aktenzeichen",
                      "case number", "zählernummer", "meter number",
                      "رقم الطلب", "رقم الفاتورة", "رقم العميل", "رقم المعاملة", "رقم العقد", "رقم الحجز"] {
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
                      "amtliches kennzeichen", "license plate", "licence plate", "fahrgestellnummer",
                      "fahrzeug-identifizierungsnummer", "vehicle identification number",
                      "führerscheinnummer", "führerschein-nr", "driver's license number", "driving licence number",
                      "license number", "licence number", "versichertennummer", "krankenversichertennummer",
                      "versicherungsnummer", "insurance number", "national insurance number", "ni number",
                      "personalnummer", "employee id", "employee number", "matrikelnummer", "student id",
                      "رقم الهوية", "رقم الجواز", "رقم جواز السفر", "الرقم الضريبي", "رقم الرخصة", "رقم التأمين"] {
            labels[label] = identity
        }
        for label in ["passwort", "password", "kennwort", "pin", "pin-code", "tan", "code", "sicherheitscode",
                      "security code", "verification code", "verifizierungscode", "bestätigungscode",
                      "bestaetigungscode", "otp", "einmalpasswort", "one-time code", "one-time password",
                      "zugangscode", "access code", "gutscheincode", "gutschein", "coupon", "coupon code",
                      "promo code", "rabattcode", "discount code", "voucher", "voucher code",
                      "wlan-passwort", "wlan passwort", "wlan-schlüssel", "wlan-schluessel", "wlan-kennwort",
                      "wi-fi password", "wifi password", "wi-fi-passwort", "netzwerkschlüssel", "network key",
                      "network password", "wpa key", "wpa2 key", "license key", "licence key", "lizenzschlüssel",
                      "product key", "produktschlüssel", "activation key", "aktivierungsschlüssel",
                      "aktivierungscode", "activation code", "seriennummer", "serial number", "buchungscode",
                      "booking code", "booking reference", "confirmation code", "recovery code",
                      "wiederherstellungscode", "backup code", "sicherungscode",
                      "كلمة المرور", "كلمة السر", "رمز التحقق", "الرمز", "رمز الخصم", "كلمة مرور الشبكة",
                      "مفتاح الترخيص", "رمز الحجز"] {
            labels[label] = code
        }
        for label in ["api key", "api-key", "apikey", "api_key", "api-schlüssel", "api-schluessel", "api token",
                      "secret", "secret key", "client secret", "access key", "access key id", "secret access key",
                      "access token", "auth token", "authentication token", "bearer token", "refresh token",
                      "token", "private key", "privater schlüssel", "geheimer schlüssel", "webhook secret",
                      "signing secret", "zugriffsschlüssel", "zugriffstoken",
                      "مفتاح api", "المفتاح السري", "رمز الوصول"] {
            labels[label] = key
        }
        for label in ["ip", "ip address", "ip-adresse", "ipv4", "ipv6", "ipv4 address", "ipv6 address",
                      "ipv4-adresse", "ipv6-adresse", "public ip", "öffentliche ip", "عنوان ip"] {
            labels[label] = network
        }
        for label in ["benutzername", "nutzername", "username", "user name", "benutzer", "anmeldename", "login",
                      "login name", "handle", "اسم المستخدم"] {
            labels[label] = user
        }
        return labels
    }()

    /// One place to cover, and the kind it is covered as; nil for a rule of
    /// the owner's own.
    struct Area: Equatable {
        let rect: CGRect
        let kind: PrivateDetail?
        /// What it hides, while a copy is made, so the copy can be checked
        /// for any of it still showing; nil for a face, a code or a part
        /// hidden by hand.
        var text: String? = nil
    }

    /// Where the chosen details and the owner's own rules are, as they are
    /// covered: from 0 to 1 from the bottom left, with a margin around the
    /// text, the faces when those are chosen, and the codes.
    static func areas(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all) -> [CGRect] {
        coveredAreas(in: image, chosen, rules: rules).map(\.rect)
    }

    /// The same places, each with the kind it is covered as, so the line can
    /// tell what was covered.
    /// - Parameter intelligence: whether Apple Intelligence may read along,
    ///   where it is on; not for the sample, which must read the same each time.
    static func coveredAreas(in image: CGImage, _ chosen: Set<PrivateDetail>,
                             rules: [OwnRule] = OwnRules.all, intelligence: Bool = true) -> [Area] {
        let rules = rules.filter { !$0.isBlank }
        guard !chosen.isEmpty || !rules.isEmpty else { return [] }
        let codes = Self.codes(in: image, chosen)
        var areas = boxes(in: image, chosen, rules: rules, printed: codes.compactMap(\.payload),
                          intelligence: intelligence).map { box in
            Area(rect: withMargin(box.rect, in: image), kind: box.kind, text: box.text)
        }
        if chosen.contains(.faces) { areas += faces(in: image).map { Area(rect: $0, kind: .faces) } }
        areas += codes.map { Area(rect: $0.box, kind: $0.kind) }
        return areas
    }

    /// Text's box with room around it, as it is covered, from 0 to 1 from
    /// the bottom left; more room with the strongest protection, so no
    /// letter's tail or accent shows.
    private static func withMargin(_ box: CGRect, in image: CGImage) -> CGRect {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        // Vision measures from the bottom left, as Core Graphics draws.
        let text = VNImageRectForNormalizedRect(box, image.width, image.height)
        let room: (across: CGFloat, up: CGFloat) = strongest ? (0.45, 0.35) : (0.25, 0.2)
        let rect = text.insetBy(dx: -text.height * room.across, dy: -text.height * room.up)
        return CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height)
    }

    // MARK: Covered, and checked

    /// The picture with the chosen details, the owner's rules and the parts
    /// hidden by hand covered in the chosen look, then read again as anyone
    /// could read it: whatever private still shows, and any piece of what
    /// was hidden left beside its cover, is covered too, in two more rounds
    /// at most. The places come with it, for the lock to say what was
    /// covered; nil only when the picture cannot be drawn.
    static func covered(_ image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                        hand: [CGRect] = [], intelligence: Bool = true,
                        style: CoverStyle = .current) -> (image: CGImage, areas: [Area])? {
        let rules = rules.filter { !$0.isBlank }
        var areas = coveredAreas(in: image, chosen, rules: rules, intelligence: intelligence)
        let hidden = hand.map { Area(rect: $0, kind: nil) }
        guard !areas.isEmpty || !hidden.isEmpty else { return (image, []) }
        guard var covered = cover(image, areas: areas + hidden, style: style) else { return nil }
        // Only what is read can be read again.
        guard !chosen.subtracting([.faces, .barcodes]).isEmpty || !rules.isEmpty else { return (covered, areas) }
        for _ in 0..<2 {
            let more = stillReadable(in: covered, hidden: areas + hidden, chosen, rules: rules)
            guard !more.isEmpty, let again = cover(image, areas: areas + more + hidden, style: style) else { break }
            areas += more
            covered = again
        }
        return (covered, areas)
    }

    /// What still shows in a covered copy, read as anyone could read it: a
    /// detail the kinds or the owner's rules find where nothing covers it,
    /// and a piece of three letters or more of what was hidden, left on the
    /// row beside its cover. What is drawn on a cover is never read as text.
    static func stillReadable(in covered: CGImage, hidden: [Area], _ chosen: Set<PrivateDetail>,
                              rules: [OwnRule] = OwnRules.all) -> [Area] {
        let rules = rules.filter { !$0.isBlank }
        let lines = read(covered)
        guard !lines.isEmpty else { return [] }
        let covers = hidden.map(\.rect)
        func underCover(_ box: CGRect) -> Bool {
            covers.contains { $0.contains(CGPoint(x: box.midX, y: box.midY)) }
        }
        var found: [Area] = []
        for hit in keepingLastDigits(hits(in: lines, chosen, rules: rules), in: lines) {
            guard let place = Self.area(of: hit, in: lines), !underCover(place.rect) else { continue }
            found.append(Area(rect: withMargin(place.rect, in: covered), kind: place.kind, text: place.text))
        }
        // A number keeping its last four digits shows them on purpose.
        let pieces = hidden.filter { area in
            guard let text = area.text, !text.isEmpty else { return false }
            return !(keepsLastDigits && !strongest && area.kind.map(lastDigitKinds.contains) == true)
        }
        guard !pieces.isEmpty else { return found }
        let size = CGSize(width: covered.width, height: covered.height)
        for line in lines {
            let string = line.string
            for word in Self.word.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                guard let range = Range(word.range, in: string), let box = line.box(for: range),
                      !underCover(box) else { continue }
                let piece = letters(String(string[range]))
                guard piece.count >= 3,
                      let source = pieces.first(where: { beside(box, $0.rect, in: size) && letters($0.text ?? "").contains(piece) })
                else { continue }
                found.append(Area(rect: withMargin(box, in: covered), kind: source.kind, text: String(string[range])))
            }
        }
        return found
    }

    /// Letters and digits alone, in small letters, so a piece of hidden text
    /// is known however it was read.
    private static func letters(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber })
    }

    /// Whether a word sits on a cover's row, just before or after it.
    private static func beside(_ box: CGRect, _ cover: CGRect, in size: CGSize) -> Bool {
        let a = CGRect(x: box.minX * size.width, y: box.minY * size.height,
                       width: box.width * size.width, height: box.height * size.height)
        let b = CGRect(x: cover.minX * size.width, y: cover.minY * size.height,
                       width: cover.width * size.width, height: cover.height * size.height)
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap >= min(a.height, b.height) * 0.5 else { return false }
        let gap = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
        return gap <= a.height * 1.5
    }

    /// A QR code or a barcode, with what it says when that is text, and the
    /// kind it is covered as.
    struct Code {
        /// From 0 to 1 from the bottom left, with a quiet margin around it.
        let box: CGRect
        let payload: String?
        let kind: PrivateDetail
    }

    /// The codes to cover: every one when codes are chosen, otherwise those
    /// whose contents hold a chosen detail, like the IBAN in a GiroCode.
    static func codes(in image: CGImage, _ chosen: Set<PrivateDetail>) -> [Code] {
        guard !chosen.subtracting([.faces]).isEmpty else { return [] }
        let request = VNDetectBarcodesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // Where the newest reader of codes fails, the one before it is tried.
            log.error("Could not look for codes: \(error.localizedDescription, privacy: .public)")
            request.revision = VNDetectBarcodesRequestRevision3
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        }
        return (request.results ?? []).compactMap { code in
            guard let kind = Self.kind(ofCode: code.payloadStringValue, chosen) else { return nil }
            let box = code.boundingBox
            return Code(box: box.insetBy(dx: -box.width * 0.1, dy: -box.height * 0.1)
                            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1)),
                        payload: code.payloadStringValue, kind: kind)
        }
    }

    /// Whether a code is covered: every one when codes are chosen, otherwise
    /// when its contents hold a chosen detail. Pure text, so it can be
    /// checked without a picture.
    static func coversCode(_ payload: String?, _ chosen: Set<PrivateDetail>) -> Bool {
        kind(ofCode: payload, chosen) != nil
    }

    /// The kind a code is covered as: a code, when codes are chosen,
    /// otherwise the first chosen kind it holds; nil when it is not covered.
    static func kind(ofCode payload: String?, _ chosen: Set<PrivateDetail>) -> PrivateDetail? {
        if chosen.contains(.barcodes) { return .barcodes }
        guard let payload, !payload.isEmpty else { return nil }
        let held = kinds(ofCode: payload)
        return PrivateDetail.allCases.first { held.contains($0) && chosen.contains($0) }
    }

    /// The kinds of detail a code's contents hold: by the formats codes use,
    /// like a transfer, a contact card or a network's password, and read like
    /// the text on a screen.
    static func kinds(ofCode payload: String) -> Set<PrivateDetail> {
        var kinds = Set<PrivateDetail>()
        let lower = payload.lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { lower.hasPrefix($0) } }
        // A transfer: the GiroCode of European banks, the Swiss QR bill.
        if starts("bcd\n", "bcd\r\n", "spc\n", "spc\r\n", "bank:") { kinds.formUnion([.bank, .names]) }
        // A sign-in, or the password of a network.
        if starts("otpauth:", "otpauth-migration:", "wifi:") { kinds.insert(.codes) }
        if starts("begin:vcard", "mecard:") { kinds.formUnion([.names, .addresses, .emails, .phones]) }
        if starts("mailto:", "matmsg:") { kinds.insert(.emails) }
        if starts("tel:", "sms:", "smsto:") { kinds.insert(.phones) }
        // A place on a map.
        if starts("geo:") { kinds.insert(.addresses) }
        // A boarding pass starts with the passenger's name.
        if payload.range(of: #"^M[1-4][A-Z]+/[A-Z ]+"#, options: .regularExpression) != nil {
            kinds.formUnion([.names, .ids])
        }
        for kind in PrivateDetail.allCases where !patternRanges(in: payload, [kind]).isEmpty {
            kinds.insert(kind)
        }
        return kinds
    }

    /// A pattern that finds a covered code's contents where they are also
    /// printed, like the number under a barcode, with or without the spaces
    /// print puts between its groups. Only short, plain contents: a link or
    /// a contact card is found by its own kinds.
    static func printedPattern(ofCode payload: String) -> String? {
        guard (6...40).contains(payload.count),
              payload.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let characters = payload.map { NSRegularExpression.escapedPattern(for: String($0)) }
        return #"(?<![A-Za-z0-9])"# + characters.joined(separator: " ?") + #"(?![A-Za-z0-9])"#
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

    /// Where the chosen details are, in Vision's normalized coordinates,
    /// each with the kind it is covered as and what it says.
    /// - Parameter printed: what the covered codes say, covered too where it
    ///   is printed beside them.
    static func boxes(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                      printed: [String] = [], intelligence: Bool = true) -> [Area] {
        // Faces and codes are not read as text: with nothing else chosen, no reading.
        let patterns = printed.compactMap(printedPattern(ofCode:))
        guard !chosen.subtracting([.faces, .barcodes]).isEmpty || rules.contains(where: { !$0.isBlank })
            || !patterns.isEmpty else { return [] }
        let lines = read(image)
        let printedHits = patterns.isEmpty ? [] : Text(lines).hits(forPatterns: patterns)
        var found = hits(in: lines, chosen, rules: rules)
        if intelligence { found += intelligentHits(in: lines, chosen) }
        return (keepingLastDigits(found, in: lines) + printedHits).compactMap { Self.area(of: $0, in: lines) }
    }

    /// Where a detail found in a line is, and what it says: just its words,
    /// or with the strongest protection, the whole line, so nothing of it
    /// shows, not even how long it is.
    private static func area(of hit: Hit, in lines: [TextLine]) -> Area? {
        let line = lines[hit.line]
        guard let range = hit.range, !strongest else { return Area(rect: line.box, kind: hit.kind, text: line.string) }
        guard let part = Range(range, in: line.string), let box = line.box(for: part) else { return nil }
        return Area(rect: box, kind: hit.kind, text: String(line.string[part]))
    }

    /// What Apple Intelligence names in the lines, of the kinds chosen, where
    /// it is on: never on a guess, only words that are in their line.
    /// - Parameter waits: whether to wait for an answer not yet given; else
    ///   only one given before counts.
    private static func intelligentHits(in lines: [TextLine], _ chosen: Set<PrivateDetail>,
                                        waits: Bool = true) -> [Hit] {
        guard usesIntelligence, !chosen.isDisjoint(with: intelligentKinds.values), intelligenceAvailable,
              let pieces = intelligentPieces(for: lines.map(\.string), waits: waits) else { return [] }
        return pieces.compactMap { piece -> Hit? in
            guard chosen.contains(piece.kind), piece.line < lines.count else { return nil }
            let line = lines[piece.line].string
            guard let found = line.range(of: piece.words, options: sameWords) else { return nil }
            return Hit(line: piece.line, range: NSRange(found, in: line), kind: piece.kind)
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
        // What Apple Intelligence found when the photo was read, never waited for here.
        let found = hits(in: lines, chosen, rules: rules) + intelligentHits(in: lines, chosen, waits: false)
        for hit in keepingLastDigits(found, in: lines) {
            let length = lines[hit.line].string.utf16.count
            // The strongest protection leaves out whole lines, as it covers them.
            let range = (strongest ? nil : hit.range) ?? NSRange(location: 0, length: length)
            let end = min(range.location + range.length, length)
            if range.location < end { hidden[hit.line].insert(integersIn: range.location..<end) }
        }
        for (i, line) in lines.enumerated() where hand.contains(where: { $0.intersects(line.box) }) {
            let string = line.string
            let all = NSRange(location: 0, length: string.utf16.count)
            for word in Self.word.matches(in: string, range: all) {
                guard let part = Range(word.range, in: string),
                      let box = line.box(for: part),
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

    /// Every detail the kinds find in a picture's lines, with its text and
    /// the line it is on, top to bottom: what the order card lists. The
    /// owner's own rules are left out.
    static func details(in lines: [TextLine]) -> [(kind: PrivateDetail, text: String, line: Int)] {
        var seen = Set<String>()
        return hits(in: lines, Set(PrivateDetail.allCases), rules: [])
            .sorted { ($0.line, $0.range?.location ?? 0) < ($1.line, $1.range?.location ?? 0) }
            .compactMap { hit -> (kind: PrivateDetail, text: String, line: Int)? in
                guard let kind = hit.kind else { return nil }
                let line = lines[hit.line].string
                let text = (hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line)
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, seen.insert("\(kind.rawValue)|\(text)").inserted else { return nil }
                return (kind: kind, text: text, line: hit.line)
            }
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

    /// With Keep the last four digits on, a long number's last four stay
    /// readable, in a copy and in its text alike, as on a bank statement.
    private static func keepingLastDigits(_ hits: [Hit], in lines: [TextLine]) -> [Hit] {
        guard keepsLastDigits else { return hits }
        return hits.map { hit in
            guard let kind = hit.kind, lastDigitKinds.contains(kind) else { return hit }
            return Hit(line: hit.line, range: keepingLastDigits(hit.range, in: lines[hit.line].string), kind: kind)
        }
    }

    /// The owner's own rules: words and patterns wherever they appear, and
    /// what follows a label, on its line or on the line below.
    private static func own(in text: Text, _ rules: [OwnRule]) -> [Hit] {
        var hits = ruleRanges(in: text.full, rules).flatMap { text.hits($0, nil) }
        for rule in rules where rule.kind == .label && !rule.isBlank {
            let label = rule.text.trimmingCharacters(in: .whitespaces)
            for (i, line) in text.lines.enumerated() {
                let string = line.string
                guard let found = string.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else { continue }
                // The whole label, not the start of a longer word.
                if found.upperBound < string.endIndex, string[found.upperBound].isLetter { continue }
                let rest = string[found.upperBound...].drop { ": -–\t".contains($0) }
                if !rest.isEmpty {
                    hits.append(Hit(line: i, range: NSRange(rest.startIndex..<string.endIndex, in: string), kind: nil))
                } else if let next = Self.line(below: i, in: text.lines, gap: 2) {
                    hits.append(Hit(line: next, range: nil, kind: nil))
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

    /// Letters under this many pixels high are often misread, like
    /// "examole" for "example", so a line that size is read a second time,
    /// larger, when it holds what could be a detail.
    private static let smallPrint: CGFloat = 20
    /// How many lines are read again at most, so a page of small print
    /// keeps no copy waiting long.
    private static let secondReadings = 12

    private static func read(_ image: CGImage) -> [TextLine] {
        var lines = recognize(image)
        var left = secondReadings
        for i in lines.indices where left > 0 {
            let line = lines[i]
            guard line.box.height * CGFloat(image.height) < smallPrint, mayHoldDetail(line.string) else { continue }
            left -= 1
            if let again = readAgain(line, in: image) { lines[i] = again }
        }
        return lines
    }

    /// A digit, an @ or a label's colon: what most details hold.
    private static func mayHoldDetail(_ text: String) -> Bool {
        text.contains { $0.isNumber || $0 == "@" || $0 == ":" }
    }

    /// The line read again from its own strip of the picture, made large
    /// enough for its letters to be about 36 pixels high. Nil when the strip
    /// cannot be made larger, or nothing is read where the line was.
    private static func readAgain(_ line: TextLine, in image: CGImage) -> TextLine? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(4, 36 / max(1, line.box.height * height))
        let room = line.box.height * 0.6
        let strip = line.box.insetBy(dx: -room * 2, dy: -room).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // Cut from the top left, as pictures are.
        let pixels = CGRect(x: strip.minX * width, y: (1 - strip.maxY) * height,
                            width: strip.width * width, height: strip.height * height).integral
        guard scale > 1.2, let piece = image.cropping(to: pixels), let large = enlarged(piece, by: scale) else { return nil }
        let frame = CGRect(x: pixels.minX / width, y: 1 - pixels.maxY / height,
                           width: pixels.width / width, height: pixels.height / height)
        // The line read where it was in the strip, not a neighbour caught at its edge.
        let middle = (line.box.midY - frame.minY) / frame.height
        guard let found = recognize(large).min(by: { abs($0.box.midY - middle) < abs($1.box.midY - middle) }),
              abs(found.box.midY - middle) < 0.25 else { return nil }
        return TextLine(text: found.text, box: line.box, frame: frame)
    }

    /// A picture drawn larger, on white, smoothly.
    private static func enlarged(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) * scale).rounded()), height = Int((CGFloat(image.height) * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Every line of text Vision reads in a picture.
    private static func recognize(_ image: CGImage) -> [TextLine] {
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

        /// A range of the whole text, line by line, covered as this kind.
        func hits(_ range: NSRange, _ kind: PrivateDetail?) -> [Hit] {
            lines.indices.compactMap { i -> Hit? in
                let span = NSRange(location: starts[i], length: lines[i].string.utf16.count)
                let overlap = NSIntersectionRange(range, span)
                guard overlap.length > 0 else { return nil }
                return Hit(line: i, range: NSRange(location: overlap.location - span.location, length: overlap.length),
                           kind: kind)
            }
        }

        func matches(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [NSRange] {
            (try? NSRegularExpression(pattern: pattern, options: options))?
                .matches(in: full, range: whole).map(\.range) ?? []
        }

        /// Every match of these patterns, in any case, line by line: what a
        /// covered code says, where it is printed.
        func hits(forPatterns patterns: [String]) -> [Hit] {
            patterns.flatMap { matches($0, .caseInsensitive) }.flatMap { hits($0, .barcodes) }
        }
    }

    private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#

    /// Details that are private wherever they appear.
    private static func patterns(in text: Text, _ chosen: Set<PrivateDetail>) -> [Hit] {
        // Kind by kind, so each place is known by the kind that found it.
        var hits = chosen.flatMap { kind in patternRanges(in: text.full, [kind]).flatMap { text.hits($0, kind) } }
        if chosen.contains(.addresses),
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            for match in addresses.matches(in: text.full, range: text.whole) {
                let lines = text.hits(match.range, .addresses)
                hits += lines
                // The detector often stops at the street. The postcode, the
                // town and the country follow just below.
                guard var last = lines.last?.line else { continue }
                for _ in 0..<3 {
                    guard let next = Self.line(below: last, in: text.lines, gap: 1.1),
                          looksLikeAddress(text.lines[next].string) else { break }
                    hits.append(Hit(line: next, range: nil, kind: .addresses))
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
            // Crypto wallets: an Ethereum address, and Bitcoin's two kinds.
            found += matches(#"\b0x[0-9a-fA-F]{40}\b"#)
            found += matches(#"\b(?:bc1|tb1)[02-9ac-hj-np-z]{25,62}\b"#)
            found += matches(#"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#).filter { hasBothCases(text.substring(with: $0)) }
        }
        if chosen.contains(.addresses) {
            // Coordinates, as maps give them: "52.520008, 13.404954",
            // 52.52° N, 13.40° E or 52°31'12.0"N 13°24'17.8"E. A plain pair
            // needs five decimals, so two numbers in a table are left. The
            // street is found with the rest below.
            found += matches(#"(?<![\d.])-?\d{1,2}\.\d{5,},\s?-?\d{1,3}\.\d{5,}(?![\d.])"#)
                .filter { isCoordinate(text.substring(with: $0)) }
            found += matches(#"(?<![\d.])\d{1,2}(?:\.\d+)?°\s?[NS],?\s+\d{1,3}(?:\.\d+)?°\s?[EOW]\b"#)
            found += matches(#"\b\d{1,2}°\s?\d{1,2}['′’]\s?\d{1,2}(?:[.,]\d+)?["″”]?\s?[NS][\s,]+\d{1,3}°\s?\d{1,2}['′’]\s?\d{1,2}(?:[.,]\d+)?["″”]?\s?[EOW]\b"#)
        }
        if chosen.contains(.phones) {
            found += detected(.phoneNumber).map(\.range)
        }
        if chosen.contains(.ipAddresses) {
            // IPv4, with a network's size or not, but not a version with more parts.
            let octet = #"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"#
            found += matches(#"(?<![\d.])"# + octet + #"(?:\."# + octet + #"){3}(?:/\d{1,2})?(?!\.?\d)"#)
            // IPv6, as the system reads it, so a time like 12:30:45 is left.
            found += matches(#"(?<![\w:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:%[\w.]+)?(?![\w:])"#)
                .filter { isIPv6(text.substring(with: $0)) }
        }
        if chosen.contains(.orders) {
            // "#1024", and the number after "Order No.", "Rechnung" or
            // "Kundennummer", which must hold a digit.
            found += matches(#"(?<![\w#])#\s?(\d{3,}[\w-]*)"#, [], group: 1)
            found += matches(#"\b(?:Bestellung|Bestell-?Nr|Auftrag|Auftrags-?Nr|Order|Rechnung|Rechnungs-?Nr|Invoice|Kundennummer|Kunden-?Nr|Customer|Beleg|Vorgang|Transaktion|Transaction|Vertrag|Vertrags-?Nr|Contract|Policy|Mitglied|Mitglieds-?Nr|Member|Buchung|Buchungs-?Nr|Booking|Reservierung|Reservation|Ticket|Referenz|Reference|Aktenzeichen)\.?[ \t]*(?:Nr\.?|No\.?|Number|ID|#)?[ \t]*[:#]?[ \t]*((?=[A-Z0-9/-]*\d)[A-Z0-9][A-Z0-9/-]{2,})\b"#,
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
            // The British National Insurance number.
            found += matches(#"\b[A-CEGHJ-PR-TW-Z][A-CEGHJ-NPR-TW-Z] ?\d{2} ?\d{2} ?\d{2} ?[A-D]\b"#)
        }
        if chosen.contains(.codes) {
            // "Dein Code lautet 482913", "PIN: 1234", "TAN 123 456": the digits after the word.
            found += matches(#"\b(?:code|pin|tan|otp|passwort|password|kennwort)\b[^\n\d]{0,30}?(\d(?:[ -]?\d){3,7})(?!\d)"#,
                             .caseInsensitive, group: 1)
            // A password given in a setting or in the middle of a line: "password=…".
            found += matches(#"\b(?:password|passwort|passwd|kennwort)["']?\s*[:=]\s*["']?([^\s"',;]{4,})"#,
                             .caseInsensitive, group: 1)
            // A licence key or a gift card's code, in four groups or more.
            found += matches(#"\b[A-Z0-9]{4,6}(?:-[A-Z0-9]{4,6}){3,7}\b"#)
                .filter { hasLettersAndDigits(text.substring(with: $0)) }
        }
        if chosen.contains(.keys) {
            // Keys and tokens services hand out, known by how they start:
            // OpenAI, Anthropic, Stripe, GitHub, GitLab, Slack, Hugging Face,
            // npm, Amazon and Google.
            found += matches(#"(?<![\w-])(?:sk|rk)-(?:proj-|svcacct-|admin-|ant-(?:api|admin)\d{2}-)?[A-Za-z0-9_-]{20,}"#)
            found += matches(#"(?<!\w)(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#)
            found += matches(#"(?<!\w)(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|xox[abposr]-[A-Za-z0-9-]{10,}|whsec_[A-Za-z0-9]{20,}|hf_[A-Za-z0-9]{30,}|npm_[A-Za-z0-9]{30,})"#)
            found += matches(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#)
            found += matches(#"\bAIza[0-9A-Za-z_-]{35}"#)
            // A signed token in three parts, the first two JSON.
            found += matches(#"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#)
            // What follows "Bearer", and a key or a secret given in a setting or in code.
            found += matches(#"\bBearer\s+([A-Za-z0-9._~+/-]{16,}=*)"#, [], group: 1)
            found += matches(#"\b[A-Za-z_]*(?:api[_-]?key|secret|token|access[_-]?key|private[_-]?key)[A-Za-z_]*["']?\s*[:=]\s*["']?([^\s"',;]{8,})"#,
                             .caseInsensitive, group: 1)
            // A private key, from its first line to its last.
            found += matches(#"-----BEGIN [A-Z ]*PRIVATE KEY-----(?:\n[A-Za-z0-9+/= ]{16,})*(?:\n-----END [A-Z ]*PRIVATE KEY-----)?"#)
            // Any other long run of letters and digits that reads as chance made it.
            found += matches(#"(?<![\w-])[A-Za-z0-9_-]{32,}(?![\w-])"#).filter { looksRandom(text.substring(with: $0)) }
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

    /// The order, invoice or customer number a screenshot is about: the
    /// first one found, top to bottom, like "1024" in "Order #1024". Pure
    /// text, so it can be checked without a picture.
    static func orderNumber(in lines: [String]) -> String? {
        let full = lines.joined(separator: "\n")
        let first = patternRanges(in: full, [.orders]).min { $0.location < $1.location }
        return first.map { (full as NSString).substring(with: $0) }
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
                        hits.append(Hit(line: i, range: NSRange(part, in: line.string), kind: detail))
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
                    hits.append(Hit(line: next, range: nil, kind: detail))
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
                for hit in text.hits(NSRange(range, in: text.full), .names) { tagged.insert(hit.line) }
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
        return found.map { Hit(line: $0, range: nil, kind: .names) }
    }

    /// Lines with a dose or a pharmacy number, where medicines are named.
    private static func medicines(in lines: [TextLine]) -> [Hit] {
        let dose = #"\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ml|ie|iu|tbl|tabletten|tablets?|kapseln|capsules?)\b"#
        let pharmacy = #"\bPZN[:\s-]*\d{7,8}\b"#
        return lines.indices.compactMap { i -> Hit? in
            let line = lines[i].string
            let named = line.range(of: dose, options: [.regularExpression, .caseInsensitive]) != nil
                || line.range(of: pharmacy, options: .regularExpression) != nil
            return named ? Hit(line: i, range: nil, kind: .health) : nil
        }
    }

    /// Whether a long run of letters and digits reads as chance made it, as
    /// a key does, rather than as words run together, as names in code are:
    /// both cases and a digit, and few runs of four small letters or more.
    /// A long hex number, like a commit's, is one case only and stays.
    static func looksRandom(_ run: String) -> Bool {
        let characters = Array(run)
        guard characters.count >= 32, !run.hasPrefix("0x"),
              characters.filter(\.isUppercase).count >= 2, characters.filter(\.isLowercase).count >= 2,
              characters.contains(where: \.isNumber) else { return false }
        var wordy = 0, streak = 0
        for character in characters + ["!"] {
            if character.isLowercase {
                streak += 1
            } else {
                if streak >= 4 { wordy += streak }
                streak = 0
            }
        }
        var counts: [Character: Int] = [:]
        for character in characters { counts[character, default: 0] += 1 }
        let n = Double(characters.count)
        let entropy = counts.values.reduce(0.0) { $0 - Double($1) / n * log2(Double($1) / n) }
        return Double(wordy) / n < 0.3 && entropy >= 3.5
    }

    /// Whether text is an IPv6 address as the system reads one, with two
    /// colons at least, so a time like 12:30:45 is not.
    static func isIPv6(_ candidate: String) -> Bool {
        let address = candidate.split(separator: "%", maxSplits: 1).first.map(String.init) ?? candidate
        var parsed = in6_addr()
        return address.filter { $0 == ":" }.count >= 2 && inet_pton(AF_INET6, address, &parsed) == 1
    }

    /// Whether two numbers can be a place on Earth: a latitude, then a
    /// longitude.
    private static func isCoordinate(_ pair: String) -> Bool {
        let parts = pair.split(separator: ",", maxSplits: 1).map { part in
            Double(part.filter { "0123456789.-".contains($0) })
        }
        guard parts.count == 2, let latitude = parts[0], let longitude = parts[1] else { return false }
        return abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static func hasLettersAndDigits(_ text: String) -> Bool {
        text.contains(where: \.isLetter) && text.contains(where: \.isNumber)
    }

    private static func hasBothCases(_ text: String) -> Bool {
        text.contains(where: \.isUppercase) && text.contains(where: \.isLowercase)
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
