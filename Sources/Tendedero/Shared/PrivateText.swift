import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import NaturalLanguage
import os
import Vision

/// The kinds of private detail that can be covered, each chosen on its own
/// under Privacy in Settings, on the Mac and on the iPhone.
enum PrivateDetail: String, CaseIterable {
    case names, patientNames, otherPeople, addresses, birthDates, emails, phones, bank, health
    case usernames, faces, ipAddresses, ids, codes, keys, barcodes, orders, tracking, amounts, dates, links
    case organizations

    var title: String {
        switch self {
        case .names: L("Names")
        case .patientNames: L("Patient names")
        case .otherPeople: L("Other people")
        case .addresses: L("Addresses")
        case .birthDates: L("Dates of birth")
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
        case .organizations: L("Companies and organizations")
        }
    }

    /// What a kind takes in, where its title alone does not say.
    var subtitle: String? {
        switch self {
        case .names: L("Without a clear role, as in chats and lists")
        case .patientNames: L("In medical letters, reports and forms")
        case .otherPeople: L("Doctors, customers, staff, payees, senders and recipients")
        default: nil
        }
    }

    /// How Settings groups the kinds, so twenty-two read as short lists, the
    /// same on the Mac and the iPhone.
    enum Group: CaseIterable {
        case people, organizations, money, health, documents, access

        var title: String {
            switch self {
            case .people: L("People")
            case .organizations: L("Companies and organizations")
            case .money: L("Money")
            case .health: L("Health")
            case .documents: L("Documents")
            case .access: L("Passwords and access")
            }
        }

        var kinds: [PrivateDetail] { PrivateDetail.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .names, .patientNames, .otherPeople, .addresses, .birthDates, .emails, .phones, .usernames, .faces: .people
        case .organizations: .organizations
        case .bank, .amounts: .money
        case .health: .health
        case .ids, .barcodes, .orders, .tracking, .dates, .links: .documents
        case .codes, .keys, .ipAddresses: .access
        }
    }

    /// What is private in nearly every screenshot, on until turned off. The
    /// rest, like the amount and the date, is often what a screenshot is
    /// sent for, so it waits to be chosen. A code is private more often than
    /// not: a payment, a sign-in, a ticket or a parcel, unreadable to the eye.
    /// A key opens an account to whoever reads it. An IP address is often
    /// what a screenshot of a network is sent for. Everyone's name is
    /// covered, with Names and its two parts on; a patient's name is health
    /// data, and a date of birth tells who someone is, as the name beside it
    /// does.
    var isRecommended: Bool {
        switch self {
        case .names, .patientNames, .otherPeople, .addresses, .birthDates, .emails, .phones, .bank, .health, .ids,
             .codes, .keys, .barcodes: true
        case .usernames, .faces, .ipAddresses, .orders, .tracking, .amounts, .dates, .links, .organizations: false
        }
    }

    /// Kinds that choose some people's names by their role: the patients',
    /// and everyone else's whose role the words round the name tell. Their
    /// places are covered as names.
    static let people: Set<PrivateDetail> = [.patientNames, .otherPeople]

    /// Names, Patient names and Other people: everyone's names, as covering
    /// "the names" means wherever no one chose whose.
    static let allNames: Set<PrivateDetail> = [.names, .patientNames, .otherPeople]

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
        let roles = defaults.stringArray(forKey: rolesKey).map { Set($0.compactMap(PersonRole.init(rawValue:))) }
        let parted = defaults.bool(forKey: partedKey)
        for key in keys {
            guard let raw = defaults.stringArray(forKey: key) else { continue }
            var chosen = Set(raw.compactMap(PrivateDetail.init(rawValue:)))
            let moved = roles.map { movingRoles($0, in: &chosen) } ?? false
            var new = added(to: chosen, known: known)
            // Whoever chose some people's names alone keeps that choice.
            if moved { new.subtract(people) }
            if !parted { new.formUnion(parting(chosen).subtracting(chosen)) }
            if moved || !new.isEmpty { defaults.set(chosen.union(new).map(\.rawValue).sorted(), forKey: key) }
        }
        defaults.removeObject(forKey: rolesKey)
        defaults.set(allCases.map(\.rawValue), forKey: knownKey)
        defaults.set(true, forKey: partedKey)
    }

    /// Whether the choices were brought up to Names, Patient names and
    /// Other people each covering their own people.
    static let partedKey = "namesParted"

    /// A choice made while Names covered everyone's names, whatever its two
    /// parts said, as it covers the same names now that each covers its own:
    /// Names with Patient names, as recommended then, takes Other people
    /// too. Names alone stays as it is: it was chosen with both parts off.
    static func parting(_ chosen: Set<PrivateDetail>) -> Set<PrivateDetail> {
        chosen.isSuperset(of: [.names, .patientNames]) ? chosen.union([.otherPeople]) : chosen
    }

    /// The same for a list of kinds kept without its switches shown apart,
    /// as Cover Files kept what it covered last: with Names, which was
    /// everyone's names, both parts too.
    static func partingAll(_ chosen: Set<PrivateDetail>) -> Set<PrivateDetail> {
        chosen.contains(.names) ? chosen.union(allNames) : chosen
    }

    /// Where whose names were kept, before patients and other people were
    /// kinds of their own.
    static let rolesKey = "nameRoles"

    /// Names covered for some people only, as kinds: the parts for those
    /// people, without Names. True when the choice changed.
    static func movingRoles(_ roles: Set<PersonRole>, in chosen: inout Set<PrivateDetail>) -> Bool {
        guard !roles.isEmpty, chosen.contains(.names) else { return false }
        chosen.remove(.names)
        if roles.contains(.patient) { chosen.insert(.patientNames) }
        if !roles.isDisjoint(with: PersonRole.others) { chosen.insert(.otherPeople) }
        return true
    }
}

extension FormFields.Entity {
    /// The kind a form field's value is covered as; nil for a code the
    /// form prints that is no one's.
    var detail: PrivateDetail? {
        switch self {
        case .personName: .names
        case .address: .addresses
        case .dateOfBirth: .birthDates
        case .date: .dates
        case .healthInsuranceNumber, .identificationNumber, .institutionNumber: .ids
        case .institution: .organizations
        case .medicalDiagnosis, .medicalDate: .health
        case .formCode: nil
        }
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
        let string: String
        /// Normalized, from the bottom left, as Vision measures.
        let box: CGRect
        /// The part of the picture the text was read in: all of it, or the
        /// strip a line of small print was read again from, larger.
        var frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        /// How the line knows where its parts are: from Vision's reading, or
        /// from its words' places, kept from an earlier reading.
        private let parts: Parts

        private enum Parts {
            case read(VNRecognizedText)
            case kept([Word])
        }

        /// A word of a line and where it is in the picture, as the photos
        /// prepared ahead of time keep it.
        struct Word: Equatable {
            /// Where in the line, in UTF-16 units.
            let range: NSRange
            /// Normalized, from the bottom left, in the whole picture.
            let box: CGRect
        }

        init(text: VNRecognizedText, box: CGRect, frame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
            string = text.string
            self.box = box
            self.frame = frame
            parts = .read(text)
        }

        /// A line kept from an earlier reading, with its words' places.
        init(string: String, box: CGRect, words: [Word]) {
            self.string = string
            self.box = box
            parts = .kept(words)
        }

        /// How sure the reading is of the line, from 0 to 1; a line kept
        /// from an earlier reading counts as sure.
        var confidence: Float {
            switch parts {
            case .read(let text): text.confidence
            case .kept: 1
            }
        }

        /// The same reading, where it was found in the picture.
        func placed(box: CGRect, frame: CGRect) -> TextLine {
            switch parts {
            case .read(let text): TextLine(text: text, box: box, frame: frame)
            case .kept: self
            }
        }

        /// Where part of the line is in the picture, normalized like `box`.
        /// A kept line has only its words' places: part of a word is told
        /// by its share of the word's letters.
        func box(for range: Range<String.Index>) -> CGRect? {
            switch parts {
            case .read(let text):
                guard let part = try? text.boundingBox(for: range)?.boundingBox else { return nil }
                return CGRect(x: frame.minX + part.minX * frame.width, y: frame.minY + part.minY * frame.height,
                              width: part.width * frame.width, height: part.height * frame.height)
            case .kept(let words):
                let wanted = NSRange(range, in: string)
                var found: CGRect?
                for word in words where word.range.length > 0 {
                    let overlap = NSIntersectionRange(word.range, wanted)
                    guard overlap.length > 0 else { continue }
                    let length = CGFloat(word.range.length)
                    let start = CGFloat(overlap.location - word.range.location) / length
                    let end = CGFloat(overlap.location + overlap.length - word.range.location) / length
                    let part = CGRect(x: word.box.minX + start * word.box.width, y: word.box.minY,
                                      width: (end - start) * word.box.width, height: word.box.height)
                    found = found?.union(part) ?? part
                }
                return found
            }
        }

        /// Each word with where it is, as the spaces part them, to keep.
        var words: [Word] {
            if case .kept(let words) = parts { return words }
            var found: [Word] = []
            var start: String.Index?
            for index in string.indices + [string.endIndex] {
                if index == string.endIndex || string[index].isWhitespace {
                    if let begun = start, let place = box(for: begun..<index) {
                        found.append(Word(range: NSRange(begun..<index, in: string), box: place))
                    }
                    start = nil
                } else if start == nil {
                    start = index
                }
            }
            return found
        }
    }

    /// One thing to cover: part of a line, or all of it, and the kind it
    /// is covered as; nil for a rule of the owner's own.
    struct Hit {
        let line: Int
        var range: NSRange?
        var kind: PrivateDetail?
        /// Whose name it is, when it is a name and that is known.
        var role: NameRole? = nil
        /// The title before a name, like "Dr. med.", which tells whose it is.
        var title: String? = nil
        /// Covered, though it is not clear it should be: shown for the owner to check.
        var check = false
        /// The name a detail belongs to, like the address under it in a
        /// letter: its line and where it is there; nil for most details.
        var owner: NameLink? = nil
    }

    /// Where a name is: its line, and its place in the line, or all of it.
    struct NameLink: Equatable {
        let line: Int
        let range: NSRange?
    }

    /// What was found in a picture's lines: what is covered, and what may
    /// be private but is not covered unless the owner says so, like a line
    /// shaped like a name that nothing vouches for.
    struct Findings {
        var hits: [Hit] = []
        var possible: [Hit] = []
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
    private static let place = Block(first: .addresses, rest: .addresses, lines: 1)
    private static let health = Block(first: .health, rest: .health, lines: 4)
    private static let bank = Block(first: .bank, rest: .bank, lines: 1)
    private static let order = Block(first: .orders, rest: .orders, lines: 1)
    private static let parcel = Block(first: .tracking, rest: .tracking, lines: 1)
    private static let identity = Block(first: .ids, rest: .ids, lines: 1)
    private static let code = Block(first: .codes, rest: .codes, lines: 1)
    private static let key = Block(first: .keys, rest: .keys, lines: 1)
    private static let network = Block(first: .ipAddresses, rest: .ipAddresses, lines: 1)
    private static let user = Block(first: .usernames, rest: .usernames, lines: 1)
    private static let company = Block(first: .organizations, rest: .organizations, lines: 1)

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
                      "name", "patient", "patientin", "versicherter", "الاسم", "العميل", "المريض",
                      "vorname", "nachname", "familienname", "vor- und nachname", "vollständiger name",
                      "first name", "last name", "surname", "given name", "family name", "full name",
                      "nom", "prénom", "nombre", "apellido", "apellidos", "nome", "sobrenome", "cognome",
                      "الاسم الأول", "اسم العائلة", "الاسم الكامل",
                      // Whose name it is, said by the label: the patient, the
                      // doctor, the customer, someone of the company's.
                      "name des patienten", "name der patientin", "patientenname", "patient name", "patient's name",
                      "behandelnder arzt", "behandelnde ärztin", "überweisender arzt", "überweisende ärztin",
                      "hausarzt", "hausärztin", "arzt", "ärztin", "facharzt", "fachärztin", "doctor", "physician",
                      "referring physician", "treating physician", "attending physician", "kundenname",
                      "customer name", "karteninhaber", "cardholder", "card holder", "ansprechpartner",
                      "ansprechpartnerin", "ihr ansprechpartner", "sachbearbeiter", "sachbearbeiterin",
                      "bearbeiter", "bearbeiterin", "berater", "beraterin", "mitarbeiter", "mitarbeiterin",
                      "contact person", "begünstigter", "begünstigte", "zahlungsempfänger", "beneficiary", "payee",
                      "الطبيب", "фио", "имя", "фамилия", "пациент", "врач", "клиент",
                      // A patient's name, as reports and forms write it.
                      "pat", "patient/in", "patientin/patient", "patientenname/vorname", "name, vorname",
                      "nachname, vorname", "name/vorname", "vorname/name", "vorname, name", "name des versicherten",
                      "versicherte/r", "versicherte", "name, vorname, geb.-datum", "patientennamen",
                      // The doctors: referring, treating and signing.
                      "zuweiser", "einweiser", "überweiser", "zuweisender arzt", "befund erstellt von", "befundet von",
                      "befundender arzt", "erstellt von", "diktiert von", "ärztliche unterschrift",
                      "verantwortlicher arzt", "auftraggeber", "zahlungsempfängerin", "empfängername",
                      "begünstigte/r"] {
            labels[label] = name
        }
        for label in ["firma", "firmenname", "unternehmen", "company", "company name", "arbeitgeber", "employer",
                      "bank", "bankname", "bank name", "kreditinstitut", "geldinstitut", "krankenkasse",
                      "versicherung", "insurance", "praxis", "klinik", "krankenhaus", "hospital", "clinic",
                      "الشركة", "البنك", "компания", "банк"] {
            labels[label] = company
        }
        for label in ["straße", "strasse", "str", "straße und hausnummer", "hausnummer", "adresszusatz",
                      "street", "street address", "address line 1", "address line 2", "plz", "postleitzahl",
                      "zip", "zip code", "postal code", "postcode", "ort", "stadt", "wohnort", "city", "town",
                      "plz / ort", "plz/ort", "الشارع", "المدينة", "الرمز البريدي"] {
            labels[label] = place
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
                      "paket-nr", "shipment number", "shipment id", "versendet mit", "versand mit",
                      "shipped with", "رقم الشحنة", "رقم التتبع"] {
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
        // The same labels in French, Spanish, Portuguese, Turkish and
        // more Arabic, as letters, transfers, payslips and forms print them.
        for label in ["expéditeur", "expéditrice", "destinataire", "adresse de livraison", "adresse de facturation",
                      "remitente", "destinatario", "destinataria", "dirección", "dirección de envío",
                      "dirección de facturación", "destinatário", "destinatária", "endereço", "endereço de entrega",
                      "endereço de cobrança", "adres", "teslimat adresi", "fatura adresi",
                      // An email's sender and recipients.
                      "de", "à", "para", "kimden", "kime", "من", "إلى"] where labels[label] == nil {
            labels[label] = person
        }
        for label in ["client", "cliente", "nom et prénom", "nom complet", "patiente", "salarié", "salariée",
                      "employé", "employée", "donneur d'ordre", "bénéficiaire", "titulaire", "titulaire du compte",
                      "médecin", "médecin traitant", "paciente", "nombre completo", "nombre y apellidos",
                      "trabajador", "trabajadora", "empleado", "empleada", "ordenante", "beneficiario",
                      "beneficiaria", "titular", "titular de la cuenta", "médico", "médica", "nome completo",
                      "funcionário", "funcionária", "empregado", "empregada", "colaborador", "colaboradora",
                      "remetente", "favorecido", "favorecida", "beneficiário", "beneficiária", "titular da conta",
                      "müşteri", "hasta", "ad soyad", "adı soyadı", "ad", "soyad", "soyadı", "isim", "personel",
                      "çalışan", "gönderen", "alıcı", "hesap sahibi", "doktor", "hekim",
                      "المحول", "المحوِّل", "المستفيد", "صاحب الحساب", "الموظف", "اسم العميل", "اسم المريض",
                      "اسم الموظف"] where labels[label] == nil {
            labels[label] = name
        }
        for label in ["rue", "code postal", "ville", "calle", "código postal", "ciudad", "rua", "cep", "cidade",
                      "cadde", "sokak", "posta kodu", "il", "ilçe", "şehir"] where labels[label] == nil {
            labels[label] = place
        }
        for label in ["diagnostic", "diagnóstico", "tanı", "teşhis", "traitement", "tratamiento", "tratamento",
                      "tedavi", "médicament", "medicamento", "ilaç"] where labels[label] == nil {
            labels[label] = health
        }
        for label in ["dni", "nie", "nif", "n.i.f", "número de identidad", "número de la seguridad social", "nss",
                      "naf", "cpf", "rg", "pis", "t.c. kimlik no", "tc kimlik no", "t.c. kimlik numarası",
                      "kimlik no", "kimlik numarası", "vergi no", "vergi numarası", "sgk no",
                      "n° de sécurité sociale", "numéro de sécurité sociale", "numéro fiscal", "codice fiscale",
                      "رقم الهوية الوطنية", "رقم الإقامة", "رقم السجل المدني"] where labels[label] == nil {
            labels[label] = identity
        }
        for label in ["mot de passe", "code de vérification", "contraseña", "código", "código de verificación",
                      "senha", "código de verificação", "şifre", "doğrulama kodu", "kod"] where labels[label] == nil {
            labels[label] = code
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
        /// How far up and down its margin may reach, from 0 to 1 from the
        /// bottom: not into a line above or below that stays to be read.
        var room: ClosedRange<CGFloat>? = nil
        /// Covered, though it is not clear it should be, like a name whose
        /// role is unclear when only some people's are covered.
        var check = false
        /// Drawn by hand, covered in solid ink as drawn; nil, the box itself.
        var shape: HandShape? = nil
        /// Whose it is, where that is known: a patient's name, the address
        /// under it, a doctor's name.
        var role: PersonRole? = nil
    }

    /// Where the details are in a picture: the places covered, the places
    /// that may be private, left for the owner to check, and, when asked
    /// for, the places of the sensitive kinds that are left visible as
    /// Settings says, like a doctor's name where only patients' are
    /// covered, for the owner to cover one by one.
    struct Analysis {
        var areas: [Area] = []
        var possible: [Area] = []
        var spared: [Area] = []
        /// Vision could not read the picture's text, as iOS may keep it from
        /// doing in the background: nothing found is then not nothing there.
        var unread = false
        /// The paper the picture's text was read as, like a sick note,
        /// whatever kinds are chosen; nil for any other page.
        var paper: DocumentPaper? = nil
    }

    /// The kinds a picture's places are found for, beyond those chosen, so
    /// they can be shown and covered with a tap: who someone is, where they
    /// live, how to reach them, their money and their health.
    static let sparedKinds: Set<PrivateDetail> = [.names, .addresses, .birthDates, .emails, .phones, .bank, .health, .ids]

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
        analysis(in: image, chosen, rules: rules, intelligence: intelligence).areas
    }

    /// The places to cover, as `coveredAreas`, and the places that may be
    /// private but are left for the owner to check, each with its margin.
    /// - Parameter spare: whether to find the places left visible too
    ///   (`Analysis.spared`), as the iPhone's editor lists them.
    static func analysis(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                         intelligence: Bool = true, spare: Bool = false) -> Analysis {
        let rules = rules.filter(\.isActive)
        let (chosen, scope) = resolved(chosen)
        guard !chosen.isEmpty || !rules.isEmpty || spare else { return Analysis() }
        let codes = Timing.measure("codes") { Self.codes(in: image, chosen) }
        let found = places(in: image, chosen, rules: rules,
                           printed: codes.compactMap { code in code.payload.map { ($0, code.kind) } },
                           intelligence: intelligence, scope: scope, spare: spare)
        var areas = found.areas.map { box in
            Area(rect: withMargin(box.rect, in: image, room: box.room), kind: box.kind, text: box.text, check: box.check,
                 role: box.role)
        }
        if chosen.contains(.faces) { areas += Timing.measure("faces") { faces(in: image) }.map { Area(rect: $0, kind: .faces) } }
        areas += codes.map { Area(rect: $0.box, kind: $0.kind) }
        let possible = found.possible.map { box in
            Area(rect: withMargin(box.rect, in: image, room: box.room), kind: box.kind, text: box.text, check: true,
                 role: box.role)
        }
        let spared = found.spared.map { box in
            Area(rect: withMargin(box.rect, in: image, room: box.room), kind: box.kind, text: box.text, role: box.role)
        }
        // The last word is Settings', whatever found a place.
        return Analysis(areas: areas.filter { allowed($0.kind, chosen) },
                        possible: possible.filter { allowed($0.kind, chosen) }, spared: spared, unread: found.unread,
                        paper: found.paper)
    }

    /// Whether a place may be covered, or offered to be: its kind is on, or
    /// it is one of the owner's own rules. Applied after every way of
    /// finding, Apple Intelligence's too, so nothing else decides what is
    /// covered. `chosen` is as `resolved` gives it: Names, Patient names and
    /// Other people come to names, their people told apart by `decided`.
    static func allowed(_ kind: PrivateDetail?, _ chosen: Set<PrivateDetail>) -> Bool {
        kind.map(chosen.contains) ?? true
    }

    /// What the kinds chosen come to. Names, Patient names and Other people
    /// each cover their own people, as their switches say: the names whose
    /// role is not clear, the patients', and everyone else's whose role the
    /// words round the name tell. All three cover everyone's names. Every
    /// entry point resolves once; what it calls takes the result as it is.
    static func resolved(_ chosen: Set<PrivateDetail>) -> (chosen: Set<PrivateDetail>, scope: NameScope) {
        let kinds = chosen.subtracting(PrivateDetail.people)
        guard !chosen.isDisjoint(with: PrivateDetail.allNames),
              !chosen.isSuperset(of: PrivateDetail.allNames) else { return (kinds, .everyone) }
        var roles: Set<PersonRole> = []
        if chosen.contains(.patientNames) { roles.insert(.patient) }
        if chosen.contains(.otherPeople) { roles.formUnion(PersonRole.others) }
        return (kinds.union([.names]), NameScope(roles: roles, unclear: chosen.contains(.names)))
    }

    /// Text's box with room around it, as it is covered, from 0 to 1 from
    /// the bottom left; more room with the strongest protection, so no
    /// letter's tail or accent shows. Up and down it stops at `room`, so it
    /// never hides part of a line that is meant to show, like the street
    /// under a name.
    private static func withMargin(_ box: CGRect, in image: CGImage, room: ClosedRange<CGFloat>? = nil) -> CGRect {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        // Vision measures from the bottom left, as Core Graphics draws.
        let text = VNImageRectForNormalizedRect(box, image.width, image.height)
        let extra: (across: CGFloat, up: CGFloat) = strongest ? (0.45, 0.35) : (0.25, 0.2)
        let rect = text.insetBy(dx: -text.height * extra.across, dy: -text.height * extra.up)
        var bottom = rect.minY / height, top = rect.maxY / height
        if let room {
            bottom = max(bottom, min(room.lowerBound, box.minY))
            top = min(top, max(room.upperBound, box.maxY))
        }
        return CGRect(x: rect.minX / width, y: bottom, width: rect.width / width, height: top - bottom)
    }

    /// How far up and down a cover over `box`, read in line `index`, may
    /// reach, from 0 to 1 from the bottom: as far as the nearest line above
    /// and below it, in its column, that is not covered too. A line that is
    /// covered as well may be covered into.
    static func room(around box: CGRect, line index: Int, in boxes: [CGRect], covered: Set<Int>) -> ClosedRange<CGFloat> {
        var bottom: CGFloat = 0, top: CGFloat = 1
        // The margin reaches a little to the sides too.
        let side = box.height * 0.5
        for (i, other) in boxes.enumerated() where i != index && !covered.contains(i) {
            guard other.maxX > box.minX - side, other.minX < box.maxX + side else { continue }
            if other.midY > box.maxY {
                top = min(top, max(other.minY, box.maxY))
            } else if other.midY < box.minY {
                bottom = max(bottom, min(other.maxY, box.minY))
            }
        }
        // Lines beyond the page, as a cropped PDF's text can lie, leave no room, never less than none.
        return bottom...max(bottom, top)
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
        protect(image, chosen, rules: rules, hand: hand, intelligence: intelligence, style: style)
            .map { ($0.image, $0.areas) }
    }

    /// A covered copy, as `covered` makes it, with what the owner may want
    /// to check: the places covered though it is not clear they should be
    /// (`Area.check`), and those that may be private but are not covered.
    struct Protected {
        let image: CGImage
        let areas: [Area]
        let possible: [Area]
    }

    static func protect(_ image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                        hand: [CGRect] = [], intelligence: Bool = true, style: CoverStyle = .current) -> Protected? {
        let started = Timing.start()
        defer { Timing.report(since: started) }
        let rules = rules.filter(\.isActive)
        let found = analysis(in: image, chosen, rules: rules, intelligence: intelligence)
        let hidden = hand.map { Area(rect: $0, kind: nil) }
        guard !found.areas.isEmpty || !hidden.isEmpty else { return Protected(image: image, areas: [], possible: found.possible) }
        guard let done = finish(image, covering: found.areas + hidden, chosen, rules: rules, style: style)
        else { return nil }
        let areas = found.areas + done.added
        let possible = found.possible.filter { place in !areas.contains { $0.rect.intersects(place.rect) } }
        return Protected(image: done.image, areas: areas, possible: possible)
    }

    /// The picture with these places covered, then read again as anyone
    /// could read it: whatever private still shows is covered too, in two
    /// more rounds at most, except where the owner chose to leave it
    /// (`left`). The places the check added come back with the picture.
    static func finish(_ image: CGImage, covering areas: [Area], leaving left: [CGRect] = [],
                       _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                       style: CoverStyle = .current) -> (image: CGImage, added: [Area])? {
        let rules = rules.filter(\.isActive)
        guard var covered = Timing.measure("cover", { cover(image, areas: areas, style: style) }) else { return nil }
        // Only what is read can be read again.
        guard !chosen.subtracting([.faces, .barcodes]).isEmpty || !rules.isEmpty else { return (covered, []) }
        var added: [Area] = []
        for _ in 0..<2 {
            let more = Timing.measure("check") {
                stillReadable(in: covered, hidden: areas + added, chosen, rules: rules)
            }.filter { place in !left.contains { $0.contains(CGPoint(x: place.rect.midX, y: place.rect.midY)) } }
            guard !more.isEmpty, let again = cover(image, areas: areas + added + more, style: style) else { break }
            added += more
            covered = again
        }
        return (covered, added)
    }

    /// What still shows in a covered copy, read as anyone could read it: a
    /// detail the kinds or the owner's rules find where nothing covers it,
    /// and a piece of three letters or more of what was hidden, left on the
    /// row beside its cover. What is drawn on a cover is never read as text.
    static func stillReadable(in covered: CGImage, hidden: [Area], _ chosen: Set<PrivateDetail>,
                              rules: [OwnRule] = OwnRules.all) -> [Area] {
        let rules = rules.filter(\.isActive)
        let (chosen, scope) = resolved(chosen)
        // A covered copy is read once; it is not kept with the pictures read.
        let lines = read(covered, remember: false)
        guard !lines.isEmpty else { return [] }
        let covers = hidden.map(\.rect)
        func underCover(_ box: CGRect) -> Bool {
            covers.contains { $0.contains(CGPoint(x: box.midX, y: box.midY)) }
        }
        var found: [Area] = []
        let missed = keepingLastDigits(hits(in: lines, chosen, rules: rules, scope: scope), in: lines)
            .filter { allowed($0.kind, chosen) }
        let boxes = lines.map(\.box), coveredLines = Set(missed.map(\.line))
        for hit in missed {
            guard let place = Self.area(of: hit, in: lines), !underCover(place.rect) else { continue }
            let reach = Self.room(around: place.rect, line: hit.line, in: boxes, covered: coveredLines)
            found.append(Area(rect: withMargin(place.rect, in: covered, room: reach), kind: place.kind, text: place.text))
        }
        // A number keeping its last four digits shows them on purpose.
        let pieces = hidden.filter { area in
            guard let text = area.text, !text.isEmpty else { return false }
            return !(keepsLastDigits && !strongest && area.kind.map(lastDigitKinds.contains) == true)
        }
        guard !pieces.isEmpty else { return found }
        let size = CGSize(width: covered.width, height: covered.height)
        for (index, line) in lines.enumerated() {
            let string = line.string
            for word in Self.word.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                guard let range = Range(word.range, in: string), let box = line.box(for: range),
                      !underCover(box) else { continue }
                let piece = letters(String(string[range]))
                guard piece.count >= 3,
                      let source = pieces.first(where: { beside(box, $0.rect, in: size) && holds($0.text ?? "", piece) })
                else { continue }
                let reach = Self.room(around: box, line: index, in: boxes, covered: coveredLines.union([index]))
                found.append(Area(rect: withMargin(box, in: covered, room: reach), kind: source.kind,
                                  text: String(string[range])))
            }
        }
        return found
    }

    /// Whether hidden text holds a piece read beside its cover: as a whole
    /// word of it, or, four letters or more, as part of one, as a word split
    /// differently when read again. A short word that only happens to be in
    /// a longer one, like "der" in "Alexander", is not a piece of it.
    static func holds(_ hidden: String, _ piece: String) -> Bool {
        let words = hidden.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { letters(String($0)) }
        return words.contains(piece) || piece.count >= 4 && letters(hidden).contains(piece)
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
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else {
                failed()
                return []
            }
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
    /// A name or a company in a code never covers it by itself: only codes,
    /// or another kind it holds, like the IBAN in a payment's code.
    static func kind(ofCode payload: String?, _ chosen: Set<PrivateDetail>) -> PrivateDetail? {
        if chosen.contains(.barcodes) { return .barcodes }
        guard let payload, !payload.isEmpty else { return nil }
        let held = kinds(ofCode: payload).subtracting([.names, .organizations])
        return PrivateDetail.allCases.first { held.contains($0) && chosen.contains($0) }
    }

    /// The kinds of detail a code's contents hold: by the formats codes use,
    /// like a transfer, a contact card or a network's password, and read like
    /// the text on a screen.
    static func kinds(ofCode payload: String) -> Set<PrivateDetail> {
        var kinds = Set<PrivateDetail>()
        let lower = payload.lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { lower.hasPrefix($0) } }
        // A transfer: the GiroCode of European banks, the Swiss QR bill. It
        // names a person, or only a company, like the shop being paid.
        if starts("bcd\n", "bcd\r\n", "spc\n", "spc\r\n", "bank:") {
            kinds.insert(.bank)
            let parties = parties(ofTransfer: payload)
            // With no name to tell by, it may be a person's.
            if parties.isEmpty || parties.contains(where: { !DocumentSense.isOrganization($0) }) { kinds.insert(.names) }
            if parties.contains(where: DocumentSense.isOrganization) { kinds.insert(.organizations) }
        }
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

    /// Who a transfer's code names: a GiroCode's payee, and a Swiss QR
    /// bill's payee and payer, each where its format puts it.
    private static func parties(ofTransfer payload: String) -> [String] {
        let fields = payload.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let places: [Int]
        switch fields.first?.lowercased() {
        case "bcd": places = [5]
        case "spc": places = [5, 21]
        default: places = []
        }
        return places.filter(fields.indices.contains).map { fields[$0].trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
            failed()
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
        let (chosen, scope) = resolved(chosen)
        return places(in: image, chosen, rules: rules, printed: printed.map { ($0, .barcodes) },
                      intelligence: intelligence, scope: scope).areas
    }

    /// The places, without their margins, and those that may be private,
    /// for what is chosen as `resolved` gives it.
    /// - Parameter printed: what each covered code says, with the kind the
    ///   code is covered as, which its printed contents are covered as too.
    private static func places(in image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule],
                               printed: [(payload: String, kind: PrivateDetail)],
                               intelligence: Bool, scope: NameScope, spare: Bool = false) -> Analysis {
        // Faces and codes are not read as text: with nothing else chosen, no reading.
        let patterns = printed.compactMap { code in printedPattern(ofCode: code.payload).map { ($0, code.kind) } }
        guard !chosen.subtracting([.faces, .barcodes]).isEmpty || rules.contains(where: \.isActive)
            || !patterns.isEmpty || spare else { return Analysis() }
        let reading = Timing.measure("read") { linesRead(in: image, remember: true) }
        let lines = reading ?? []
        let printedHits = patterns.isEmpty ? [] : Text(lines).hits(forPatterns: patterns)
        var found = Timing.measure("find") { findings(in: lines, chosen, rules: rules, scope: scope) }
        if intelligence {
            let strings = lines.map(\.string), boxes = lines.map(\.box), form = form(of: lines)
            let document = DocumentSense.kind(of: strings)
            let more = Timing.measure("intelligence") { intelligentHits(in: lines, chosen) }
            let read = decided(isolated(more.hits, by: form, in: strings), in: strings, chosen, scope: scope,
                               own: ownWords(in: rules), doctors: doctorsColumn(strings, boxes: boxes, kind: document),
                               kind: document)
            // One kind for each number, what the rules found and what the model named alike.
            found.hits = oneKind(found.hits + read,
                                 named: namedNumbers(strings, boxes: boxes, form: form, document: document),
                                 in: strings, boxes: boxes, chosen, document: document)
            // What it named that only may be what it says is offered, not covered.
            let taken = Set(found.hits.map(\.line))
            found.possible += isolated(more.possible, by: form, in: strings).filter { !taken.contains($0.line) }
        }
        let all = keepingLastDigits(found.hits, in: lines) + printedHits
        let covered = Set(all.map(\.line)), boxes = lines.map(\.box)
        func place(_ hit: Hit) -> Area? {
            guard var area = Self.area(of: hit, in: lines) else { return nil }
            area.room = Self.room(around: area.rect, line: hit.line, in: boxes, covered: covered)
            area.check = hit.check
            return area
        }
        // What may be private, where nothing covers it already.
        let possible = found.possible.filter { !covered.contains($0.line) }.compactMap(place)
        // The sensitive kinds left visible, found as if everything were
        // chosen; none where they are all covered already.
        var spared: [Hit] = []
        if spare, !(chosen.isSuperset(of: sparedKinds) && scope == .everyone) {
            let wide = Timing.measure("spare") {
                findings(in: lines, chosen.union(sparedKinds), rules: [], scope: .everyone).hits
            }
            let taken = all + found.possible
            spared = wide.filter { hit in
                hit.kind != nil && !taken.contains { $0.line == hit.line && overlap($0.range, hit.range) }
            }
        }
        return Analysis(areas: all.compactMap(place), possible: possible, spared: spared.compactMap(place),
                        unread: reading == nil, paper: reading == nil ? nil : DocumentSense.paper(of: lines.map(\.string)))
    }

    /// Where a detail found in a line is, and what it says: just its words,
    /// or with the strongest protection, the whole line, so nothing of it
    /// shows, not even how long it is.
    private static func area(of hit: Hit, in lines: [TextLine]) -> Area? {
        let line = lines[hit.line]
        guard let range = hit.range, !strongest else {
            return Area(rect: line.box, kind: hit.kind, text: line.string, role: hit.role?.sureRole)
        }
        guard let part = Range(range, in: line.string), let box = line.box(for: part) else { return nil }
        return Area(rect: box, kind: hit.kind, text: String(line.string[part]), role: hit.role?.sureRole)
    }

    /// What Apple Intelligence names in the lines, of the kinds chosen, where
    /// it is on, as `vetted` keeps it: never on a guess, only words that are
    /// in their line and are what it says they are.
    /// - Parameter waits: whether to wait for an answer not yet given; else
    ///   only one given before counts.
    private static func intelligentHits(in lines: [TextLine], _ chosen: Set<PrivateDetail>,
                                        waits: Bool = true) -> Findings {
        guard !chosen.isDisjoint(with: intelligentKinds.values), asksAssistant || usesIntelligence && intelligenceAvailable,
              let pieces = intelligentPieces(for: lines.map(\.string), kinds: chosen, waits: waits) else { return Findings() }
        return vetted(pieces, in: lines.map(\.string), chosen)
    }

    /// Apple Intelligence's answer, or the assistant's, read again by the
    /// rules, so a model never decides alone what is covered: each piece is
    /// kept only as a kind that is on, and only where its words fit that
    /// kind (`fit`), widened to the whole of it (`wholeEntity`). A street,
    /// a date or a segment of the spine it calls a name is no name. What
    /// only may fit is offered, for the owner to check. Pure text, so it
    /// can be checked without a picture or a model.
    static func vetted(_ pieces: [IntelligentPiece], in strings: [String], _ chosen: Set<PrivateDetail>) -> Findings {
        let document = DocumentSense.kind(of: strings), medical = document == .medical
        var found = Findings()
        for piece in pieces where piece.line < strings.count {
            // A company it took for a person is a company, covered only as one.
            let kind = piece.kind == .names && DocumentSense.isOrganization(piece.words) ? .organizations : piece.kind
            let line = strings[piece.line]
            guard chosen.contains(kind), let words = line.range(of: piece.words, options: sameWords) else { continue }
            let range = wholeEntity(words, kind: kind, in: line, widely: true)
            let hit = Hit(line: piece.line, range: NSRange(range, in: line), kind: kind)
            let above = piece.line > 0 ? strings[piece.line - 1] : ""
            switch fit(kind, range, in: line, after: above, medical: medical, document: document) {
            case .sure: found.hits.append(hit)
            case .unsure:
                var offered = hit
                offered.check = true
                found.possible.append(offered)
            case .no: continue
            }
        }
        return found
    }

    /// How well words fit the kind they are said to be.
    enum Fit: Equatable { case sure, unsure, no }

    /// Whether the words at `range` in a line are what their kind says, by
    /// their shape and what stands round them: a name has a name's words and
    /// no digits, and is no street, town or medical term; a date of birth
    /// is a date; a phone number, a number. Deterministic, so what a model
    /// says is checked the same way every time.
    /// - Parameter above: the line before, where a term this line ends may
    ///   start, as "Morbus" before "Scheuermann".
    /// - Parameter document: the kind of document the line is in, where a
    ///   bare run of digits is a phone number only off a document.
    static func fit(_ kind: PrivateDetail, _ range: Range<String.Index>, in line: String, after above: String = "",
                    medical: Bool, document: DocumentKind = .general) -> Fit {
        let text = String(line[range]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .no }
        let digits = text.filter(\.isNumber).count
        let isDate = text.range(of: #"\d{1,2}\s?[./-]\s?\d{1,2}\s?[./-]\s?\d{2,4}|\d{4}-\d{2}-\d{2}"#,
                                options: .regularExpression) != nil
        // A segment of the spine or a disease is no one's name or number,
        // the line before included: "… eines Morbus" / "Scheuermann in …".
        let lastAbove = above.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let joined = lastAbove + " " + line
        let shift = joined.index(joined.startIndex, offsetBy: lastAbove.count + 1)
        let inJoined = joined.index(shift, offsetBy: line.distance(from: line.startIndex, to: range.lowerBound))
            ..< joined.index(shift, offsetBy: line.distance(from: line.startIndex, to: range.upperBound))
        let inMedical = DocumentSense.medicalRanges(in: joined, medical: medical).contains { $0.overlaps(inJoined) }
        if inMedical, kind != .health { return .no }
        switch kind {
        case .names, .patientNames, .otherPeople:
            return nameFit(range, in: line)
        case .addresses:
            let whole = line.trimmingCharacters(in: .whitespaces)
            if isStreetLine(whole) || isTownLine(whole) { return .sure }
            return digits > 0 && text.contains(where: \.isLetter) && !isDate ? .sure : .no
        case .birthDates, .dates:
            return isDate || text.range(of: #"\d{1,2}\.?\s\p{L}{3,}\.?\s\d{4}"#, options: .regularExpression) != nil
                ? .sure : .no
        case .emails:
            return text.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil ? .sure : .no
        case .phones:
            guard digits >= 6, text.allSatisfy({ $0.isNumber || " +()/.-–".contains($0) }), !isDate else { return .no }
            // Written as one is dialled, or said to be one, on any page; a bare run on a document only maybe.
            if isPhone(range, in: line, above: above.isEmpty ? nil : above, document: document) { return .sure }
            return isNationalNumber(Substring(text)) ? .unsure : .no
        case .bank:
            let compact = text.replacingOccurrences(of: " ", with: "")
            let iban = compact.range(of: #"^[A-Z]{2}\d{2}[A-Z0-9]{8,30}$"#, options: .regularExpression) != nil
            let bic = compact.range(of: #"^[A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?$"#, options: .regularExpression) != nil
            return iban || bic || digits >= 8 && !isDate ? .sure : .no
        case .ids, .codes, .orders, .tracking:
            let shaped = text.count >= 4 && !text.contains(" ") || text.filter({ $0 != " " }).count >= 6
            return digits > 0 && shaped && !isDate ? .sure : .no
        case .keys:
            return text.count >= 16 && !text.contains(" ") ? .sure : .no
        case .usernames:
            return (2...40).contains(text.count) && !text.contains(" ") ? .sure : .no
        case .health:
            return digits == text.filter({ !$0.isWhitespace && !$0.isPunctuation }).count || isDate ? .no : .sure
        case .ipAddresses, .amounts, .links:
            return digits > 0 || kind == .links && text.contains(".") ? .sure : .no
        case .organizations:
            return DocumentSense.isOrganization(text) ? .sure : .unsure
        case .faces, .barcodes:
            return .no
        }
    }

    /// How well a piece fits a person's name: its words are a name's, with
    /// no digits and no company; not a letter's street or town; not the
    /// place before a letter's date, "Hamburg, den 12.03.2026"; not a place
    /// after "in", "aus" or "nach". One word alone, or words in capitals,
    /// may be a heading as well as a name: offered, not covered.
    private static func nameFit(_ range: Range<String.Index>, in line: String) -> Fit {
        let text = String(line[range])
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (1...5).contains(words.count), !text.contains(where: \.isNumber), !DocumentSense.isOrganization(text),
              words.allSatisfy({ word in
                  let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
                  return DocumentSense.isNameWord(bare) || DocumentSense.isParticle(bare)
              }) else { return .no }
        let whole = line.trimmingCharacters(in: .whitespaces)
        if isStreetLine(whole) || isTownLine(whole) { return .no }
        // "Hamburg, den 12.03.2026": the place a letter is dated in.
        if line.range(of: #"^\s*\p{Lu}[\p{L}\- ]*,\s*(?:den\s+)?\d{1,2}\."#, options: .regularExpression)
            .map({ $0.overlaps(range) }) == true { return .no }
        // "in Hamburg", "aus Berlin": a place, not a person.
        let before = line[..<range.lowerBound].split(whereSeparator: { $0.isWhitespace }).last.map { $0.lowercased() }
        if let before, ["in", "aus", "nach"].contains(before) { return .no }
        let capitals = text.contains(where: \.isLetter) && text == text.uppercased()
        return words.count >= 2 && !capitals ? .sure : .unsure
    }

    /// The whole of an entity part of which was found: whole words and
    /// numbers, never part of one; for an address, the street with its
    /// number and the postcode with its town on that line. `widely`, for
    /// what a model named: a name's whole run of names, and a number's or an
    /// email's whole match of its kind's pattern.
    static func wholeEntity(_ range: Range<String.Index>, kind: PrivateDetail?, in line: String,
                            widely: Bool = false) -> Range<String.Index> {
        var lower = range.lowerBound, upper = range.upperBound
        func joins(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        while lower > line.startIndex, joins(line[line.index(before: lower)]), lower < upper, joins(line[lower]) {
            lower = line.index(before: lower)
        }
        while upper < line.endIndex, upper > lower, joins(line[line.index(before: upper)]), joins(line[upper]) {
            upper = line.index(after: upper)
        }
        var whole = lower..<upper
        func widen(by pattern: String, _ options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let found = Range(match.range, in: line), found.overlaps(whole) else { continue }
                whole = min(found.lowerBound, whole.lowerBound)..<max(found.upperBound, whole.upperBound)
            }
        }
        if kind == .addresses {
            widen(by: #"\p{Lu}[\p{L}'’.\-]*(?:\s[\p{L}'’.\-]+){0,4}\s\d{1,4}\s?[a-zA-Z]?(?:\s?[-/]\s?\d{1,4}\s?[a-zA-Z]?)?\b"#)
            widen(by: #"(?:\b[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\b\d{4,5}\s\p{Lu}[\p{L}'’.\-]+(?:\s(?:am|an der|im|in der|bei|ob der|vor der)\s\p{Lu}[\p{L}'’.\-]+)?"#)
        }
        guard widely, let kind else { return whole }
        if kind == .names {
            whole = DocumentSense.nameSpan(around: whole, in: line)
        } else if [.bank, .ids, .orders, .tracking, .phones, .emails, .codes, .keys].contains(kind) {
            for pattern in patternRanges(in: line, [kind]) {
                guard let found = Range(pattern, in: line), found.overlaps(whole) else { continue }
                whole = min(found.lowerBound, whole.lowerBound)..<max(found.upperBound, whole.upperBound)
            }
        }
        return whole
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
        let (chosen, scope) = resolved(chosen)
        // What Apple Intelligence found when the photo was read, never waited for here.
        let strings = lines.map(\.string), boxes = lines.map(\.box), form = form(of: lines)
        let document = DocumentSense.kind(of: strings)
        let read = decided(isolated(intelligentHits(in: lines, chosen, waits: false).hits, by: form, in: strings),
                           in: strings, chosen, scope: scope, own: ownWords(in: rules),
                           doctors: doctorsColumn(strings, boxes: boxes, kind: document), kind: document)
        // One kind for each number, what the rules found and what the model named alike.
        let found = oneKind(hits(in: lines, chosen, rules: rules, scope: scope) + read,
                            named: namedNumbers(strings, boxes: boxes, form: form, document: document),
                            in: strings, boxes: boxes, chosen, document: document)
        for hit in keepingLastDigits(found, in: lines) where allowed(hit.kind, chosen) {
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
        return hits(in: lines, Set(PrivateDetail.allCases), rules: [], scope: .everyone)
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

    /// Everything to leave out, all three ways, and the owner's own rules,
    /// as the owner chose (`findings`), for what is chosen as `resolved` gives it.
    private static func hits(in lines: [TextLine], _ chosen: Set<PrivateDetail>, rules: [OwnRule],
                             scope: NameScope) -> [Hit] {
        findings(in: lines, chosen, rules: rules, scope: scope).hits
    }

    /// Everything private in the lines, in three steps kept apart: each
    /// place is found, then read for what it is, like a patient's name or a
    /// company's, then kept only as the owner chose (`decided`). What only
    /// may be private comes apart, for the owner to check.
    private static func findings(in lines: [TextLine], _ chosen: Set<PrivateDetail>, rules: [OwnRule],
                                 scope: NameScope) -> Findings {
        collect(lines.map(\.string), boxes: lines.map(\.box), part: { lines[$0].box(for: $1) }, chosen, rules: rules,
                scope: scope)
    }

    /// The same, from the lines' words and where they are; `part` says
    /// where part of a line is. So it can be checked without a picture.
    static func findings(_ strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?,
                         _ chosen: Set<PrivateDetail>, rules: [OwnRule] = []) -> Findings {
        let (chosen, scope) = resolved(chosen)
        return collect(strings, boxes: boxes, part: part, chosen, rules: rules, scope: scope)
    }

    private static func collect(_ strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?,
                                _ chosen: Set<PrivateDetail>, rules: [OwnRule], scope: NameScope) -> Findings {
        let rules = rules.filter(\.isActive)
        guard !strings.isEmpty, !chosen.isEmpty || !rules.isEmpty else { return Findings() }
        let text = Text(strings, boxes: boxes)
        let document = DocumentSense.kind(of: strings)
        let mine = ownWords(in: rules)
        var learned = Set<String>()
        var found = patterns(in: text, chosen)
        found += labelled(strings, boxes: boxes, part: part, chosen, learned: &learned)
        found += speakers(strings, chosen, learned: &learned)
        let form = FormFields.read(strings, boxes: boxes, part: part)
        let blocks = postalBlocks(strings, boxes: boxes)
        let named = namedNumbers(strings, boxes: boxes, form: form, document: document)
        var possible: [Hit] = []
        for value in form.values {
            // A name a form's label announces is looked for elsewhere too.
            if value.entity == .personName { learn(String(strings[value.line][value.range]), into: &learned) }
            guard let kind = value.entity.detail, chosen.contains(kind) else { continue }
            let hit = Hit(line: value.line, range: NSRange(value.range, in: strings[value.line]), kind: kind,
                          role: value.role.map { NameRole(role: $0, confidence: 0.9, reason: "form") },
                          check: value.confidence == .medium)
            if value.confidence == .low { possible.append(hit) } else { found.append(hit) }
        }
        if chosen.contains(.names) {
            let people = names(in: text, learned: learned, own: mine, blocks: blocks, kind: document)
            found += people.hits
            possible += people.possible
        }
        // The people named, whether their names are covered or not: what
        // goes with a name, like the address under it, is theirs.
        var people = found.filter { $0.kind == .names }
        if !chosen.contains(.names), !chosen.isDisjoint(with: [.addresses, .birthDates]) {
            people += names(in: text, learned: learned, own: mine, blocks: blocks, kind: document).hits
            people += form.values.filter { $0.entity == .personName }.map { value in
                Hit(line: value.line, range: NSRange(value.range, in: strings[value.line]), kind: .names,
                    role: value.role.map { NameRole(role: $0, confidence: 0.9, reason: "form") })
            }
        }
        // A letter's address: under a person's name, or after it on its line.
        if chosen.contains(.addresses) {
            found += addresses(after: people, in: text)
            found += postalAddresses(blocks, people: people)
        }
        if chosen.contains(.birthDates) { found += postalBirthDates(blocks, in: text) }
        // In a medical letter, a reference number is the patient's case.
        if chosen.contains(.ids), document == .medical {
            found += references(in: text).map { hit in
                var hit = hit
                hit.role = NameRole(role: .patient, confidence: 0.7, reason: "reference")
                return hit
            }
        }
        if chosen.contains(.organizations) { found += organizations(in: text) }
        if chosen.contains(.health) { found += medicines(in: strings) }
        found += own(in: text, rules)
        // A date of birth is that, not a date as well; a medical letter's
        // reference is the patient's, not an order's.
        let born = found.filter { $0.kind == .birthDates }
        let cases = found.filter { $0.kind == .ids && $0.role?.reason == "reference" }
        found.removeAll { hit in
            hit.kind == .dates && born.contains { $0.line == hit.line && overlap($0.range, hit.range) }
                || hit.kind == .orders && cases.contains { $0.line == hit.line && overlap($0.range, hit.range) }
        }
        // Each place whole: never part of a word or a number, nor a street without its number.
        found = found.map { hit in
            let line = strings[hit.line]
            guard hit.kind != nil, let range = hit.range.flatMap({ Range($0, in: line) }) else { return hit }
            var whole = hit
            whole.range = NSRange(wholeEntity(range, kind: hit.kind, in: line), in: line)
            return whole
        }
        let column = doctorsColumn(strings, boxes: boxes, kind: document)
        // One kind for each number, then only what the owner chose.
        let kinds = oneKind(isolated(found, by: form, in: strings), named: named, in: strings, boxes: boxes, chosen,
                            document: document)
        let kept = merged(decided(kinds, in: strings, chosen, scope: scope, own: mine, doctors: column, kind: document))
        // Each person's role, read as when everyone's names are covered.
        let whose = decided(people, in: strings, [.names], scope: .everyone, own: mine, doctors: column, kind: document)
        return sure(of: Findings(hits: owned(kept, by: whose, kind: document),
                                 possible: isolated(possible, by: form, in: strings)))
    }

    /// What the owner's own rules and details cover is covered for sure:
    /// never to check, however else it was found, and no longer a place
    /// that only may be private.
    private static func sure(of findings: Findings) -> Findings {
        let own = findings.hits.filter { $0.kind == nil }
        guard !own.isEmpty else { return findings }
        func isOwn(_ hit: Hit) -> Bool { own.contains { $0.line == hit.line && overlap($0.range, hit.range) } }
        var sure = findings
        sure.hits = findings.hits.map { hit in
            guard hit.check, hit.kind != nil, isOwn(hit) else { return hit }
            var hit = hit
            hit.check = false
            return hit
        }
        sure.possible = findings.possible.filter { !isOwn($0) }
        return sure
    }

    /// Whose the details are that go with a person: the address under a
    /// name is that person's, and a date of birth that of the name on its
    /// line, or of a medical letter's patient.
    private static func owned(_ hits: [Hit], by people: [Hit], kind: DocumentKind) -> [Hit] {
        hits.map { hit in
            guard hit.role == nil else { return hit }
            var hit = hit
            if let owner = hit.owner {
                hit.role = people.first { $0.line == owner.line && overlap($0.range, owner.range) }?.role
            } else if hit.kind == .birthDates {
                hit.role = people.first { $0.line == hit.line }?.role
                    ?? (kind == .medical ? NameRole(role: .patient, confidence: 0.6, reason: "birth") : nil)
            }
            return hit
        }
    }

    /// A letter's address: the lines under a person's name, in its column,
    /// that read as a street, a postcode with its town, or the country
    /// after them; and the street and town after a name on its line, as a
    /// letter's subject writes them: "Mustermann, Erika, Lindenberg 12,
    /// 23456 Musterstadt". The data detector misses many a street without
    /// a word like "Straße" in it.
    private static func addresses(after names: [Hit], in text: Text) -> [Hit] {
        var hits: [Hit] = []
        var seen = Set<Int>()
        for name in names where seen.insert(name.line).inserted {
            let string = text.strings[name.line]
            let owner = NameLink(line: name.line, range: name.range)
            if let range = name.range.flatMap({ Range($0, in: string) }),
               let start = string[range.upperBound...].firstIndex(where: { $0.isLetter || $0.isNumber }),
               let found = string.range(of: addressStart, options: .regularExpression, range: start..<string.endIndex),
               found.lowerBound == start, isAddress(String(string[found])) {
                hits.append(Hit(line: name.line, range: NSRange(found, in: string), kind: .addresses, owner: owner))
            }
            var last = name.line
            var town = false
            for _ in 0..<3 {
                // A letter leaves more room between the name and its street
                // than between the address's own lines.
                guard let next = line(below: last, in: text.boxes, gap: last == name.line ? 3 : 1.6) else { break }
                let candidate = text.strings[next].trimmingCharacters(in: .whitespaces)
                let isTown = isTownLine(candidate)
                guard isStreetLine(candidate) || isTown || town && isCountryLine(candidate) else { break }
                hits.append(Hit(line: next, range: nil, kind: .addresses, owner: owner))
                town = town || isTown || candidate.range(of: #",\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s"#,
                                                          options: .regularExpression) != nil
                last = next
            }
        }
        return hits
    }

    /// A letter's or a form's postal block, by where its lines stand, with
    /// no label read: a street right over its postcode and town in one
    /// column, or both on one line, and the name's line right over the
    /// street, as an envelope's window prints them; or two, as a form
    /// prints the surname over the given names, beside the date of birth:
    /// "Beispielyan", "Nare", "Sonnenhang 9", "D 12345 Musterstadt". A
    /// line is a name's only in the size the street is printed in: a form
    /// prints its labels smaller, and a letter its headings larger.
    struct PostalBlock: Equatable {
        /// The name's lines, top first; none where no name is over the street.
        var names: [Int]
        /// The street, the town under it and the country after them.
        var address: [Int]
        /// Whether a date of birth's label is read on the name's rows, or
        /// right after the name, as a form prints it.
        var born = false
    }

    static func postalBlocks(_ strings: [String], boxes: [CGRect]) -> [PostalBlock] {
        guard boxes.count == strings.count else { return [] }
        // The line right over each, in its column.
        var above = [Int?](repeating: nil, count: strings.count)
        for i in strings.indices {
            guard let under = line(below: i, in: boxes, gap: 2) else { continue }
            if let over = above[under], boxes[over].minY <= boxes[i].minY { continue }
            above[under] = i
        }
        func onRow(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxY, b.maxY) - max(a.minY, b.minY) > a.height * 0.5 }
        // A date, its year in four digits or in two, as a health insurance form prints it: "14.03.87".
        func startsWithDate(_ text: Substring) -> Bool { DocumentSense.startsWithDate(String(text)) }
        var blocks: [PostalBlock] = []
        for street in strings.indices {
            let text = bare(strings[street])
            guard isStreetLine(text), !isTownLine(text) else { continue }
            var address = [street]
            if text.range(of: #",\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}"#, options: .regularExpression) == nil {
                guard let town = line(below: street, in: boxes, gap: 1.6), isTownLine(bare(strings[town])) else { continue }
                address.append(town)
            }
            if let country = line(below: address[address.count - 1], in: boxes, gap: 1.6),
               isCountryLine(bare(strings[country])) {
                address.append(country)
            }
            // A thing an invoice charges for, beside its price, is no street.
            if address.contains(where: { isItem($0, strings: strings, boxes: boxes) }) { continue }
            var names: [Int] = []
            var top = street
            while names.count < 2, let over = above[top], !isLabel(strings[over]), !DocumentSense.isClosing(strings[over]),
                  (0.7...1.5).contains(boxes[over].height / max(boxes[street].height, 0.0001)),
                  DocumentSense.namePart(of: strings[over]) != nil {
                names.insert(over, at: 0)
                top = over
            }
            let rests = names.compactMap { i in
                DocumentSense.namePart(of: strings[i]).map { strings[i][$0.upperBound...].drop { $0 == " " } }
            }
            let born = rests.contains { DocumentSense.startsWithBirth(String($0)) || startsWithDate($0) }
                || names.first.map { first in
                    let top = boxes[first], bottom = boxes[names[names.count - 1]]
                    return strings.indices.contains { i in
                        boxes[i].midY < top.maxY && boxes[i].midY > bottom.minY - bottom.height * 0.5
                            && boxes[i].minX > top.maxX && DocumentSense.startsWithBirth(strings[i])
                    }
                } ?? false
            let dated = names.contains { name in
                strings.indices.contains { i in
                    onRow(boxes[name], boxes[i]) && boxes[i].minX > boxes[name].maxX && startsWithDate(strings[i][...])
                }
            }
            // In a letter, the line over a name is a heading, like "Lebenslauf".
            if names.count == 2, !born, !dated { names.removeFirst() }
            // A word alone under a company's name is its department's: "Kundenservice".
            if names.count == 1, let over = above[names[0]], DocumentSense.isOrganization(strings[over]),
               DocumentSense.namePart(of: strings[names[0]]).map({ strings[names[0]][$0].split(separator: " ").count }) == 1 {
                names = []
            }
            blocks.append(PostalBlock(names: names, address: address, born: born))
        }
        return blocks
    }

    /// A line without the lines of a form's box read at its ends, as "|"
    /// or "ł", on their own or stuck to a word as `FormFields.unframed`
    /// reads them, or a stroke of a signature drawn across it, as "/" or "~":
    /// "Sonnenhang 9 |" and "Sonnenhang 9|" are read as "Sonnenhang 9".
    static func bare(_ line: String) -> String {
        var words = line.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, strayMarks.contains(last) { words.removeLast() }
        while words.count > 1, let first = words.first, strayMarks.contains(first) { words.removeFirst() }
        let joined = words.joined(separator: " ")
        let inner = FormFields.unframed(joined.startIndex..<joined.endIndex, in: joined)
        return inner.isEmpty ? joined : String(joined[inner])
    }

    private static let strayMarks = DocumentSense.boxLines.union(["/", "\\", "~", "_", "-", "–", "—", "(", ")", ",", ".",
                                                                  ";", ":", "'", "\"", "*"])

    /// A postal block's street and town are an address wherever they stand,
    /// with no name or label read over them; the name over them, where one
    /// is, is whose they are.
    private static func postalAddresses(_ blocks: [PostalBlock], people: [Hit]) -> [Hit] {
        blocks.flatMap { block -> [Hit] in
            let name = block.names.reversed().lazy.compactMap { line in people.first { $0.line == line } }.first
            let owner = name.map { NameLink(line: $0.line, range: $0.range) }
            return block.address.map { Hit(line: $0, range: nil, kind: .addresses, owner: owner) }
        }
    }

    /// A date right after a postal block's name, where a date of birth's
    /// label is read on its rows, is the date of birth: "Nare 14.03.1987"
    /// under "Beispielyan geb. am", as a form's row is read whole, or
    /// "Nare 14.03.87", as a health insurance form prints the year.
    private static func postalBirthDates(_ blocks: [PostalBlock], in text: Text) -> [Hit] {
        blocks.filter(\.born).flatMap(\.names).compactMap { i in
            let line = text.strings[i]
            guard let name = DocumentSense.namePart(of: line),
                  let date = line.range(of: #"\d{1,2}[./]\d{1,2}[./](?:\d{4}|\d{2})(?!\d)"#, options: .regularExpression,
                                        range: name.upperBound..<line.endIndex),
                  line[name.upperBound..<date.lowerBound].allSatisfy({ $0 == " " }) else { return nil }
            return Hit(line: i, range: NSRange(date, in: line), kind: .birthDates)
        }
    }

    /// The start of an address after a name: a street with its number and,
    /// maybe, its postcode and town, or a postcode and town alone.
    private static let addressStart = #"^(?:\p{Lu}[\p{L}'’.\-]*(?:\s[\p{L}'’.\-]+){0,4}\s\d{1,4}\s?[a-zA-Z]?(?:\s?[-/]\s?\d{1,4}\s?[a-zA-Z]?)?(?:\s?,\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}[\p{L}'’.\-]+(?:\s(?:am|an der|im|in der|bei|ob der|vor der)\s\p{Lu}[\p{L}'’.\-]+)?)?|(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}[\p{L}'’.\-]+)"#

    /// Words that start a line of a number that is no street: a telephone,
    /// a page, a room, a vertebra.
    private static let notStreets: Set<String> = [
        "telefon", "tel", "fax", "telefax", "mobil", "mobile", "handy", "phone", "zimmer", "raum", "room", "seite",
        "page", "station", "lwk", "bwk", "hwk", "swk", "segment", "kapitel", "artikel", "haus", "etage", "stock",
        "bett", "gruppe", "klasse", "version", "jahr", "woche", "tag", "termin", "konto", "kunde", "order",
        "bestellung", "rechnung", "nr", "no", "iban", "bic", "ust", "steuer", "geb", "dr", "prof", "zeichen", "ref",
        "befund", "datum", "date", "uhr", "pos", "position", "menge", "anzahl",
        "status", "bereich", "stufe", "teil", "abschnitt", "punkt", "schritt", "zeile", "spalte", "typ", "type",
        "grad", "stadium", "phase", "level", "anlage", "anlagen", "monat", "quartal", "kw", "frage", "aufgabe",
        "lektion", "runde", "folge", "tabelle", "abbildung", "abb", "section", "chapter", "step", "part",
        "ausgabe", "heft", "nummer",
    ]

    /// Words a number follows that is no house number, wherever they stand
    /// in the line, as no street's name ends in one: "Diabetes mellitus Typ
    /// 2", "Ergebnis Stufe 3", "Bescheid Seite 2".
    private static let notHouseNumbers: Set<String> = [
        "seite", "page", "kapitel", "chapter", "abschnitt", "section", "teil", "part", "schritt", "step", "anlage",
        "anlagen", "status", "typ", "type", "stufe", "grad", "grade", "stadium", "stage", "phase", "level", "version",
        "klasse", "kw", "woche", "monat", "quartal", "jahr", "frage", "aufgabe", "lektion", "tabelle", "abbildung",
        "abb", "termin", "position", "pos", "menge", "anzahl", "bereich", "gruppe", "ausgabe", "heft", "nummer",
    ]

    /// Words that read as a town after a number but count something:
    /// "1000 Euro", "2000 Stück".
    private static let notTowns: Set<String> = [
        "stück", "stk", "euro", "eur", "blatt", "seiten", "punkte", "mal", "jahre", "monate", "tage", "stunden",
        "minuten", "kcal", "kalorien", "meter", "km", "liter", "gramm", "kg", "mitglieder", "besucher", "exemplare",
        "einheiten", "teilnehmer", "pieces", "pages", "points", "years", "days", "units", "members",
    ]

    /// Whether a line is a street and its house number, maybe with its
    /// postcode and town after a comma: "Lindenberg 12", "Am Markt 3a",
    /// "Hauptstr. 5-7, 12345 Musterstadt", or "221B Baker Street".
    static func isStreetLine(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard (2...7).contains(words.count),
              let first = words.first.map({ String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) }),
              !notStreets.contains(first) else { return false }
        if let number = words.firstIndex(where: { $0.first?.isNumber == true }), number > 0,
           notHouseNumbers.contains(String(words[number - 1]).lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            return false
        }
        return line.range(of: #"^\p{Lu}[\p{L}'’.\-]*(?:\s[\p{L}'’.\-]+){0,4}\s(?:(?:No|Nº|N°|nº|n°)[.:]?\s?)?\d{1,4}\s?[a-zA-Z]?(?:\s?[-/]\s?\d{1,4}\s?[a-zA-Z]?)?(?:\s?,\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}[\p{L}'’.\-/]+(?:\s[\p{L}'’.\-()/]+){0,3})?$"#,
                          options: .regularExpression) != nil
            // A street in a script without capitals, like Arabic: "شارع التحلية 44",
            // maybe with its town and postcode after a comma: ", جدة 21577".
            || line.range(of: #"^\p{Lo}[\p{Lo}\p{M}]*(?:\s\p{Lo}[\p{Lo}\p{M}]*){1,4}\s\d{1,4}(?:\s?[,،]\s?\p{Lo}[\p{Lo}\p{M}]*(?:\s\p{Lo}[\p{Lo}\p{M}]*){0,2}\s\d{5})?$"#,
                             options: .regularExpression) != nil
            || line.range(of: #"^\d{1,5}[a-zA-Z]?\s\p{Lu}[\p{L}'’.\-]+(?:\s[\p{L}'’.\-]+){0,4}$"#,
                          options: .regularExpression) != nil
    }

    /// Whether a line is a postcode with its town: "23456 Musterstadt",
    /// "D-23456 Musterstadt", "1010 Wien", "Springfield, IL 62704".
    static func isTownLine(_ line: String) -> Bool {
        if countsSomething(line) { return false }
        return line.range(of: #"^(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s+\p{Lu}[\p{L}'’.\-/]+(?:\s[\p{L}'’.\-()/]+){0,3}$"#,
                   options: .regularExpression) != nil
            // A town before its postcode, in a script without capitals: "الرياض 12271";
            // never a number's label, like "رقم الطلب 12345".
            || line.range(of: #"^(?!رقم|هاتف|جوال|فاكس)\p{Lo}[\p{Lo}\p{M}]*(?:\s\p{Lo}[\p{Lo}\p{M}]*){0,2}\s\d{5}$"#,
                          options: .regularExpression) != nil
            || line.range(of: #"^\p{Lu}[\p{L}'’.\- ]+,?\s(?:[A-Z]{2}\s\d{5}(?:-\d{4})?|[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})$"#,
                          options: .regularExpression) != nil
    }

    /// Whether a number in a line counts something, by the word after it:
    /// "1000 Euro", "2000 Stück", never a postcode and its town.
    private static func countsSomething(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard let number = words.firstIndex(where: { $0.allSatisfy(\.isNumber) }), number + 1 < words.count else {
            return false
        }
        return notTowns.contains(words[number + 1].lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    /// Whether a line is only a word and the number it counts, or a number
    /// and what it counts, as no address has a line: "Stufe 3", "Kapitel 4",
    /// "1000 Euro".
    private static func countsOnly(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard words.count == 2 else { return false }
        let word = words[0].lowercased().trimmingCharacters(in: .punctuationCharacters)
        return words[1].allSatisfy(\.isNumber) && notHouseNumbers.contains(word) || countsSomething(line)
    }

    /// Whether a line is a country alone, as under a town: a word or two,
    /// "Schweden", "Vereinigtes Königreich", or up to three in capitals, as
    /// an envelope prints them; never what a page prints on a line of its
    /// own, like a form's label, "Kostenträgerkennung", or a letter's
    /// subject, "Bestätigung Ihrer Kündigung".
    private static func isCountryLine(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard (1...3).contains(words.count), line.count <= 24, line.first?.isUppercase == true,
              line.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" }),
              words.count <= 2 || line == line.uppercased() && line.count >= 4 else { return false }
        return !DocumentSense.isPrintedText(line) && !words.contains { FormFields.isLabelWord($0) }
    }

    /// Whether what follows a name is an address, not a date or a word.
    private static func isAddress(_ text: String) -> Bool {
        isStreetLine(text) || isTownLine(text)
            || text.range(of: #",\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}"#, options: .regularExpression) != nil
    }

    /// Reference numbers by their label, as a practice's letter writes them:
    /// "Unser Zeichen: 1364691", "Referenznummer: POW370055", "Pat.-Nr. 88213".
    private static func references(in text: Text) -> [Hit] {
        guard let regex = try? NSRegularExpression(pattern: referencePattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text.full, range: text.whole).flatMap { text.hits($0.range(at: 1), .ids) }
    }

    private static let referencePattern = #"\b(?:unser(?:e)?\s+zeichen|ihr(?:e)?\s+zeichen|referenz(?:-?nummer|-?nr\.?)?|ref\.?-?nr\.?|patienten(?:-?nummer|-?nr\.?|-?id)|pat\.?-?(?:nr|id)\.?|fall(?:-?nummer|-?nr\.?)|aufnahme(?:-?nummer|-?nr\.?)|untersuchungs(?:-?nummer|-?nr\.?)|befund(?:-?nummer|-?nr\.?)|auftrags(?:-?nummer|-?nr\.?)|accession(?:\s?(?:no\.?|number))?)\s*[:#.]?\s*((?=[A-Z0-9/.\-]*\d)[A-Z0-9][A-Z0-9/.\-]{2,}[A-Z0-9])"#

    /// A form's labels say what a place is, over what it looks like: a
    /// label itself is never covered, and a field's value only as what its
    /// label says it is, or as a date where it is one. So a disease named
    /// after a person under "Diagnose" is no name, and the number under
    /// "Versicherten-Nr." no phone number. An address or an insurer's name
    /// may hold other details, like a phone number or a doctor's name, so
    /// those stay as found. The owner's own rules always count.
    private static func isolated(_ hits: [Hit], by form: FormFields.Reading, in strings: [String]) -> [Hit] {
        guard !form.labels.isEmpty else { return hits }
        return hits.filter { hit in
            guard let kind = hit.kind else { return true }
            let line = strings[hit.line]
            let range = hit.range.flatMap { Range($0, in: line) }
            if form.isLabel(range, in: hit.line, of: line) { return false }
            guard let value = form.value(at: range, in: hit.line, of: line) else { return true }
            switch value.entity {
            case .address, .institution: return true
            default: return value.entity.detail == kind || kind == .dates
            }
        }
    }

    /// What a page's form fields hold, from its lines as read.
    private static func form(of lines: [TextLine]) -> FormFields.Reading {
        FormFields.read(lines.map(\.string), boxes: lines.map(\.box), part: { lines[$0].box(for: $1) })
    }

    /// With Keep the last four digits on, a long number's last four stay
    /// readable, in a copy and in its text alike, as on a bank statement.
    private static func keepingLastDigits(_ hits: [Hit], in lines: [TextLine]) -> [Hit] {
        guard keepsLastDigits else { return hits }
        return hits.map { hit in
            guard let kind = hit.kind, lastDigitKinds.contains(kind) else { return hit }
            return Hit(line: hit.line, range: keepingLastDigits(hit.range, in: lines[hit.line].string), kind: kind,
                       role: hit.role, title: hit.title, check: hit.check, owner: hit.owner)
        }
    }

    /// The places found more than once as one: a kind's places on one line
    /// that overlap, so a name found by its label and again by its title is
    /// one place, counted once. A sure finding wins over one to check.
    static func merged(_ hits: [Hit]) -> [Hit] {
        var kept: [Hit] = []
        for hit in hits {
            if let i = kept.firstIndex(where: { $0.line == hit.line && $0.kind == hit.kind && overlap($0.range, hit.range) }) {
                var merged = kept[i]
                merged = Hit(line: hit.line, range: union(merged.range, hit.range), kind: hit.kind,
                             role: merged.role?.isSure == true ? merged.role : hit.role ?? merged.role,
                             title: merged.title ?? hit.title, check: merged.check && hit.check,
                             owner: merged.owner ?? hit.owner)
                kept[i] = merged
            } else {
                kept.append(hit)
            }
        }
        return kept
    }

    private static func overlap(_ a: NSRange?, _ b: NSRange?) -> Bool {
        guard let a, let b else { return true }
        return NSIntersectionRange(a, b).length > 0 || a.location == b.location
    }

    private static func union(_ a: NSRange?, _ b: NSRange?) -> NSRange? {
        guard let a, let b else { return nil }
        return NSUnionRange(a, b)
    }

    /// The owner's own name: their name among their details, or one of
    /// their word rules that holds a person's name: two to five words of a
    /// name, no digits, no company, in any case, as "Nachname, Vorname" too.
    /// Each name as its words, folded. It helps tell that name as a person's
    /// wherever it is written, and stays on this device; the name detail is
    /// covered by itself too (`OwnDetails`).
    static func ownNames(in rules: [OwnRule]) -> [[String]] {
        rules.filter { ($0.kind == .word || $0.kind == .name) && $0.isActive }.compactMap { rule in
            let text = rule.kind == .name ? OwnDetails.displayName(rule.text) : rule.text.trimmingCharacters(in: .whitespaces)
            guard rule.kind == .name || !DocumentSense.isOrganization(text) else { return nil }
            return DocumentSense.nameWords(text.capitalized)
        }
    }

    /// The words of the owner's own names, folded.
    static func ownWords(in rules: [OwnRule]) -> Set<String> {
        Set(ownNames(in: rules).joined())
    }

    /// The owner's own rules: words and patterns wherever they appear, and
    /// what follows a label, on its line or on the line below, as its reach
    /// says (`labelPlaces`).
    private static func own(in text: Text, _ rules: [OwnRule]) -> [Hit] {
        var hits = ruleRanges(in: text.full, rules).flatMap { text.hits($0, nil) }
        // A name or a number run on into the next line of its column, where
        // the reading puts a line of another column between the two, as a
        // practice's letterhead down the side of a letter.
        let details = rules.filter { $0.kind.isDetail && $0.isActive }
        if !details.isEmpty, text.boxes.count == text.strings.count {
            for i in text.strings.indices {
                guard let j = Self.line(below: i, in: text.boxes, gap: 1.6), j != i + 1 else { continue }
                let first = text.strings[i]
                let split = first.utf16.count + 1
                for range in OwnDetails.ranges(in: first + "\n" + text.strings[j], details)
                where range.location < split - 1 && NSMaxRange(range) > split {
                    hits.append(Hit(line: i, range: NSRange(location: range.location, length: split - 1 - range.location),
                                    kind: nil))
                    hits.append(Hit(line: j, range: NSRange(location: 0, length: NSMaxRange(range) - split), kind: nil))
                }
            }
        }
        for place in labelPlaces(text.strings, rules, below: { Self.line(below: $0, in: text.boxes, gap: 2) }) {
            hits.append(Hit(line: place.line, range: place.range.map { NSRange($0, in: text.strings[place.line]) }, kind: nil))
        }
        return hits
    }

    /// Where a label rule covers: a line, and a part of it, or all of it.
    typealias LabelPlace = (line: Int, range: Range<String.Index>?)

    /// What the owner's label rules cover in these lines: where a line
    /// begins with a label, the rest of that line, or the line `below` it,
    /// whole, as the rule's reach says. Automatically, the rest of the line,
    /// or the line below where nothing follows the label on its line.
    static func labelPlaces(_ strings: [String], _ rules: [OwnRule], below: (Int) -> Int?) -> [LabelPlace] {
        var places: [LabelPlace] = []
        for rule in rules where rule.kind == .label && rule.isActive {
            let label = rule.text.trimmingCharacters(in: .whitespaces)
            for (i, string) in strings.enumerated() {
                guard let found = string.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else { continue }
                // The whole label, not the start of a longer word.
                if found.upperBound < string.endIndex, string[found.upperBound].isLetter { continue }
                let rest = string[found.upperBound...].drop { ": -–\t".contains($0) }
                let restOfLine: LabelPlace? = rest.isEmpty ? nil : (i, rest.startIndex..<string.endIndex)
                let next: LabelPlace? = below(i).map { ($0, nil) }
                let place: LabelPlace?
                switch rule.reach {
                case .automatic: place = restOfLine ?? next
                case .restOfLine: place = restOfLine
                case .nextLine: place = next
                }
                if let place { places.append(place) }
            }
        }
        return places
    }

    /// The owner's words, patterns and details in plain text: a word whole,
    /// wherever it appears, in any case; a pattern as it matches; a detail
    /// however it is written (`OwnDetails`). A pattern that cannot be read
    /// covers nothing. Pure text, so it can be checked without a picture.
    static func ruleRanges(in full: String, _ rules: [OwnRule]) -> [NSRange] {
        let whole = NSRange(full.startIndex..., in: full)
        var found: [NSRange] = []
        for rule in rules where rule.isActive {
            let text = rule.text.trimmingCharacters(in: .whitespaces)
            let pattern: String
            switch rule.kind {
            case .word:
                let edge: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber } == true }
                pattern = (edge(text.first) ? #"(?<!\w)"# : "") + NSRegularExpression.escapedPattern(for: text)
                    + (edge(text.last) ? #"(?!\w)"# : "")
            case .pattern:
                pattern = text
            case .label, .name, .address, .card, .account:
                continue
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            found += regex.matches(in: full, range: whole).map(\.range).filter { $0.length > 0 }
        }
        return found + OwnDetails.ranges(in: full, rules)
    }

    /// The lines with the owner's own rules and details in them hidden, as
    /// their words go to the AI assistant: a word or a pattern wherever it
    /// is, what follows a label, the next line taken for the line below,
    /// and each detail, in a few more ways than the covering takes. They are
    /// covered anyway, so they never leave this device.
    static func masking(_ lines: [String], _ rules: [OwnRule]) -> [String] {
        let rules = rules.filter(\.isActive)
        guard !rules.isEmpty, !lines.isEmpty else { return lines }
        let text = Text(lines, boxes: [])
        var hits = ruleRanges(in: text.full, rules.filter { !$0.kind.isDetail }).flatMap { text.hits($0, nil) }
        hits += OwnDetails.ranges(in: text.full, rules, masking: true).flatMap { text.hits($0, nil) }
        for place in labelPlaces(lines, rules, below: { $0 + 1 < lines.count ? $0 + 1 : nil }) {
            hits.append(Hit(line: place.line, range: place.range.map { NSRange($0, in: lines[place.line]) }, kind: nil))
        }
        return lines.enumerated().map { i, line in
            let places = hits.filter { $0.line == i }
            if places.contains(where: { $0.range == nil }) { return "•••" }
            // Places that overlap as one, then each from the end, so the rest stay where they were.
            var merged: [NSRange] = []
            for range in places.compactMap(\.range).sorted(by: { $0.location < $1.location }) {
                if let last = merged.last, range.location <= NSMaxRange(last) {
                    merged[merged.count - 1] = NSUnionRange(last, range)
                } else {
                    merged.append(range)
                }
            }
            var masked = line as NSString
            for range in merged.reversed() {
                masked = masked.replacingCharacters(in: range, with: "•••") as NSString
            }
            return masked as String
        }
    }

    /// Letters under this many pixels high are often misread, like
    /// "examole" for "example", so a line that size is read a second time,
    /// larger, when it holds what could be a detail.
    private static let smallPrint: CGFloat = 20
    /// How many lines are read again at most, so a page of small print
    /// keeps no copy waiting long.
    private static let secondReadings = 12

    /// The pictures read lately, so covering one again, after a choice
    /// changes in Settings, needs no second reading.
    private static let readings = Readings()

    /// Forgets the pictures read lately, as when the app goes to the
    /// background, so nothing read stays in memory longer than it is needed.
    static func forgetReadings() {
        readings.forget()
        forgetAnswers()
    }

    /// How many times Vision could not read a whole picture, or look in it
    /// for faces or codes, as iOS may keep it from doing in the background,
    /// on the thread asking. What was found then is not all there is: a
    /// covered copy made while it happened is not trusted (`CoveredCopy`).
    /// Counted for each thread, as a picture is read and covered on one, so
    /// a failure with another picture read at the same time is never taken
    /// for this one's.
    static var failures: Int {
        (Thread.current.threadDictionary[failuresKey] as? Int) ?? 0
    }

    /// The same, on every thread together, since the app started.
    static var allFailures: Int {
        failureCount.withLock { $0 }
    }

    private static let failuresKey = "SnapflyVisionFailures"
    private static let failureCount = OSAllocatedUnfairLock(initialState: 0)

    private static func failed() {
        failureCount.withLock { $0 += 1 }
        let here = Thread.current.threadDictionary
        here[failuresKey] = ((here[failuresKey] as? Int) ?? 0) + 1
    }

    /// Every line in a picture, as `read` gives it, for a photo prepared
    /// ahead of time; not kept with the pictures read lately. Nil when
    /// Vision could not read it, so it is never kept as a picture without
    /// words.
    static func lines(in image: CGImage) -> [TextLine]? {
        linesRead(in: image, remember: false)
    }

    /// Every line in a picture, read now and kept as its reading, so covering
    /// it next reads nothing again, as a scanned page's check reads it; nil
    /// when Vision could not read it.
    static func reading(of image: CGImage) -> [TextLine]? {
        linesRead(in: image, remember: true)
    }

    /// Every word in a picture and where it is, from the reading kept of it,
    /// so a word can be hidden with a tap. In memory only, while it is open.
    static func words(in image: CGImage) -> [(text: String, box: CGRect)] {
        read(image).flatMap { line in
            line.words.compactMap { word in
                Range(word.range, in: line.string).map { (String(line.string[$0]), word.box) }
            }
        }
    }

    /// Lines read before, kept with a photo prepared ahead of time, so the
    /// picture is not read again when it is covered.
    static func remember(_ lines: [TextLine], for image: CGImage) {
        guard let print = Readings.fingerprint(of: image) else { return }
        readings.keep(lines, for: print)
    }

    /// Every line in a picture, as `linesRead` gives it; none when Vision
    /// could not read it.
    /// - Parameter remember: false for a covered copy, read once to check it.
    private static func read(_ image: CGImage, remember: Bool = true) -> [TextLine] {
        linesRead(in: image, remember: remember) ?? []
    }

    /// Every line in a picture, the small print read twice. Kept a while by
    /// a fingerprint of the picture's pixels, so the same picture is read
    /// once however often it is covered. Nil when Vision could not read it:
    /// that is counted (`failures`), and nothing of it is kept, so the
    /// picture is read afresh the next time.
    private static func linesRead(in image: CGImage, remember: Bool) -> [TextLine]? {
        let print = remember ? Readings.fingerprint(of: image) : nil
        if let print, let known = readings.lines(for: print) { return known }
        guard let found = recognize(image) else {
            failed()
            return nil
        }
        var lines = readingBlocksAgain(found, in: image)
        let first = lines
        let small = Array(first.indices.filter { i in
            first[i].box.height * CGFloat(image.height) < smallPrint && mayHoldDetail(first[i].string)
        }.prefix(secondReadings))
        // The lines of small print are read again side by side, not one after another.
        var again = [TextLine?](repeating: nil, count: small.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: small.count) { n in
            let line = readAgain(first[small[n]], in: image)
            lock.lock()
            again[n] = line
            lock.unlock()
        }
        for (n, i) in small.enumerated() {
            if let line = again[n] { lines[i] = line }
        }
        if let print { readings.keep(lines, for: print) }
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
        guard let found = recognize(large)?.min(by: { abs($0.box.midY - middle) < abs($1.box.midY - middle) }),
              abs(found.box.midY - middle) < 0.25 else { return nil }
        return found.placed(box: line.box, frame: frame)
    }

    /// The Latin-script languages a block is read again in.
    private static let latin = ["de-DE", "en-US", "fr-FR", "es-ES", "pt-BR", "it-IT"]

    /// Lines read as one sign: a block of small lines, often links in a
    /// colour, that Vision took for a single character of another script,
    /// like "三" for the three lines under "Kunde" on a shop's order page.
    /// Each such block is read again on its own, in the Latin-script
    /// languages, line by line. It stays as it was unless several lines are
    /// read, so a large heading of a sign or two keeps its own script.
    private static func readingBlocksAgain(_ lines: [TextLine], in image: CGImage) -> [TextLine] {
        let heights = lines.map(\.box.height).sorted()
        guard !heights.isEmpty else { return lines }
        let usual = heights[heights.count / 2]
        return lines.flatMap { line -> [TextLine] in
            guard isBlockReadAsSign(line.string, height: line.box.height, usual: usual) else { return [line] }
            let again = readBlock(line, room: usual, in: image)
            return again.count >= 2 ? again : [line]
        }
    }

    /// A sign or two in a box as tall as several of the picture's usual lines.
    static func isBlockReadAsSign(_ text: String, height: CGFloat, usual: CGFloat) -> Bool {
        text.filter { !$0.isWhitespace }.count <= 3 && height >= usual * 2.5
    }

    /// The block's part of the picture, with a line's room around it, read
    /// in the Latin-script languages, each line where it is in the picture.
    private static func readBlock(_ line: TextLine, room: CGFloat, in image: CGImage) -> [TextLine] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let area = line.box.insetBy(dx: -room * 2, dy: -room).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // Cut from the top left, as pictures are.
        let pixels = CGRect(x: area.minX * width, y: (1 - area.maxY) * height,
                            width: area.width * width, height: area.height * height).integral
        guard let piece = image.cropping(to: pixels) else { return [] }
        let frame = CGRect(x: pixels.minX / width, y: 1 - pixels.maxY / height,
                           width: pixels.width / width, height: pixels.height / height)
        return (recognize(piece, languages: latin) ?? []).map { found -> TextLine in
            let box = CGRect(x: frame.minX + found.box.minX * frame.width, y: frame.minY + found.box.minY * frame.height,
                             width: found.box.width * frame.width, height: found.box.height * frame.height)
            return found.placed(box: box, frame: frame)
        }
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

    /// Every line of text Vision reads in a picture, in the language it
    /// finds, or in these languages only; nil when Vision could not read it.
    private static func recognize(_ image: CGImage, languages: [String]? = nil) -> [TextLine]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Numbers and addresses are read as they are, not corrected into words.
        request.usesLanguageCorrection = false
        if let languages {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = languages
        } else {
            request.automaticallyDetectsLanguage = true
        }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            log.error("Could not read a screenshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { TextLine(text: $0, box: observation.boundingBox) }
        }
    }

    /// All the text at once, a line per row, so a match that runs over two
    /// lines, like an address, is still found.
    fileprivate struct Text {
        let strings: [String]
        /// Where each line is, from 0 to 1 from the bottom left.
        let boxes: [CGRect]
        let full: String
        let starts: [Int]

        init(_ strings: [String], boxes: [CGRect]) {
            self.strings = strings
            self.boxes = boxes
            var full = ""
            var starts: [Int] = []
            for string in strings {
                starts.append(full.utf16.count)
                full += string + "\n"
            }
            self.full = full
            self.starts = starts
        }

        init(_ lines: [TextLine]) {
            self.init(lines.map(\.string), boxes: lines.map(\.box))
        }

        var whole: NSRange { NSRange(full.startIndex..., in: full) }

        /// A range of the whole text, line by line, covered as this kind.
        func hits(_ range: NSRange, _ kind: PrivateDetail?) -> [Hit] {
            strings.indices.compactMap { i -> Hit? in
                let span = NSRange(location: starts[i], length: strings[i].utf16.count)
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
        /// covered code says, where it is printed, as the kind the code is
        /// covered as.
        func hits(forPatterns patterns: [(pattern: String, kind: PrivateDetail)]) -> [Hit] {
            patterns.flatMap { found in matches(found.pattern, .caseInsensitive).flatMap { hits($0, found.kind) } }
        }
    }

    private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#

    /// Details that are private wherever they appear.
    private static func patterns(in text: Text, _ chosen: Set<PrivateDetail>) -> [Hit] {
        // Kind by kind, so each place is known by the kind that found it,
        // and always in the same order, so a place two kinds find is the
        // same kind's at every launch.
        var hits = PrivateDetail.allCases.filter(chosen.contains).flatMap { kind in
            patternRanges(in: text.full, [kind]).flatMap { text.hits($0, kind) }
        }
        if chosen.contains(.addresses),
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            for match in addresses.matches(in: text.full, range: text.whole) {
                let lines = text.hits(match.range, .addresses)
                // Words with a number that only count something are no address, wherever they stand.
                if lines.contains(where: { countsOnly(text.strings[$0.line]) }) { continue }
                hits += lines
                // The detector often stops at the street. The postcode, the
                // town and the country follow just below.
                guard var last = lines.last?.line else { continue }
                for _ in 0..<3 {
                    guard let next = Self.line(below: last, in: text.boxes, gap: 1.1),
                          looksLikeAddress(text.strings[next]) else { break }
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
            // IBANs, in groups of four with or without spaces between them;
            // read with a space after the country, as small print often is,
            // only at that country's length.
            let ibans = matches(#"\b[A-Z]{2} ?\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#)
                .filter { isIBANShaped(text.substring(with: $0)) }
            found += ibans
            // A bank's BIC, beside an IBAN or the word itself: "DAAEDEDDXXX".
            if !ibans.isEmpty || full.range(of: #"\b(?:BIC|SWIFT)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                found += matches(#"\b[A-Z]{4}(?:"# + bicCountries + #")[A-Z0-9]{2}(?:[A-Z0-9]{3})?\b"#)
            }
            // Card numbers: 13 to 19 digits, grouped or not, that pass the Luhn check.
            found += matches(#"\b\d(?:[ -]?\d){12,18}\b"#).filter { passesLuhn(text.substring(with: $0)) }
            // Crypto wallets: an Ethereum address, and Bitcoin's two kinds.
            found += matches(#"\b0x[0-9a-fA-F]{40}\b"#)
            found += matches(#"\b(?:bc1|tb1)[02-9ac-hj-np-z]{25,62}\b"#)
            found += matches(#"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#).filter { hasBothCases(text.substring(with: $0)) }
        }
        if chosen.contains(.addresses) {
            // A street and its number, a comma, and a postcode with its town,
            // on one line, as a letter's subject writes an address, or a
            // message: "Atatürk Caddesi No: 61, 06420 Çankaya/Ankara".
            found += matches(#"\b\p{Lu}[\p{L}'’.\-]+(?:[ \-][\p{L}'’.\-]+){0,3}\s(?:(?:No|Nº|N°|nº|n°)[.:]?\s?)?\d{1,4}\s?[a-zA-Z]?(?:\s?[-/]\s?\d{1,4}\s?[a-zA-Z]?)?\s?,\s?(?:[A-Z]{1,2}(?:\s?[-–]\s?|\s))?\d{4,5}\s\p{Lu}[\p{L}'’.\-]+(?:/\p{Lu}[\p{L}'’.\-]+|\s(?:am|an der|im|in der|bei|ob der|vor der)\s\p{Lu}[\p{L}'’.\-]+)?"#)
            // A Turkish street by the word that makes it one, with "No" and
            // its number: "Bağdat Caddesi No: 46".
            found += matches(#"\b\p{Lu}[\p{L}'’.\-]+(?: \p{Lu}[\p{L}'’.\-]+){0,2} (?:Caddesi|Cad\.|Cd\.|Sokak|Sokağı|Sok\.|Sk\.|Bulvarı|Blv\.) No ?[.:]? ?\d{1,4}[a-zA-Z]?(?:/\d{1,4})?(?!\d)"#)
            // An Arabic street by the word that makes it one, with its number
            // and maybe its town and postcode, inside a sentence too:
            // "أرسله إلى شارع العليا 76، الرياض 12271"; never "عن طريق", "by way of".
            found += matches(#"(?<![\p{L}\p{M}])(?<!عن )(?:شارع|طريق|جادة)(?: \p{Lo}[\p{Lo}\p{M}]*){1,4} \d{1,4}(?: ?[,،] ?\p{Lo}[\p{Lo}\p{M}]*(?: \p{Lo}[\p{Lo}\p{M}]*){0,2} \d{5})?(?!\d)"#)
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
            found += matches(#"\b(?:Bestellung|Bestell-?Nr|Auftrag|Auftrags-?Nr|Order|Rechnung|Rechnungs-?Nr|Invoice|Kundennummer|Kunden-?Nr|Customer|Beleg|Vorgang|Transaktion|Transaction|Vertrag|Vertrags-?Nr|Contract|Policy|Mitglied|Mitglieds-?Nr|Member|Buchung|Buchungs-?Nr|Booking|Reservierung|Reservation|Ticket|Referenz|Reference|Aktenzeichen|Unser Zeichen|Ihr Zeichen)\.?[ \t]*(?:-?nummer|-?Nr\.?|No\.?|Number|ID|#)?[ \t]*[:#]?[ \t]*((?=[A-Z0-9/-]*\d)[A-Z0-9][A-Z0-9/-]{2,})\b"#,
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
            // The German tax ID, eleven digits that pass its check: grouped
            // as the tax office prints it, "10 234 568 786", anywhere; and
            // after its name, with or without a colon, "Steuer-IdNr. 12345678903".
            found += matches(#"(?<!\d)(?<!\d )\d{2} \d{3} \d{3} \d{3}(?! ?\d)"#)
                .filter { isSteuerID(text.substring(with: $0)) }
            found += matches(#"\b(?:Steuer-?ID|Steuer-?IdNr|IdNr|Steuer-?Identifikationsnummer|steuerliche Identifikationsnummer|Identifikationsnummer)\.?[ \t]*(?:\(IdNr\.?\)[ \t]*)?:?[ \t]*(\d(?:[ /]?\d){10})(?!\d)"#,
                             .caseInsensitive, group: 1)
                .filter { isSteuerID(text.substring(with: $0)) }
        }
        if chosen.contains(.codes) {
            // "Dein Code lautet 482913", "PIN: 1234", "TAN 123 456": the digits after the word.
            found += matches(#"\b(?:code|pin|tan|otp|passwort|password|kennwort)\b[^\n\d]{0,30}?(\d(?:[ -]?\d){3,7})(?!\d)"#,
                             .caseInsensitive, group: 1)
            // The same in Spanish, Portuguese, Turkish and Arabic: "Tu código
            // de verificación es 202886", "Doğrulama kodun 271030", "رمز التحقق
            // الخاص بك هو 042088". Never a postcode: "código postal", "posta kodu".
            found += matches(#"(?<!posta )\b(?:código|codigo|kod(?:u|un|unuz)?|şifre(?:n|niz)?|senha|contraseña|رمز)\b(?!\s*postal)[^\n\d]{0,30}?(\d(?:[ -]?\d){3,7})(?!\d)"#,
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
        if chosen.contains(.birthDates) {
            // The date after a word for birth: "geb. 12.03.1985",
            // "Geburtsdatum: 12.03.1985", "* 12.03.1985", "DOB 1985-03-12".
            found += matches(birthPattern, .caseInsensitive, group: 1)
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

    /// A date of birth after its word: the date is group 1.
    private static let birthPattern = #"(?:\bgeb(?:oren)?\.?(?:\s?am)?|\bgeburtsdatum|\bgeb\.?-?\s?dat(?:um|\.)?|\bdate of birth|\bd\.?o\.?b\.?|\bborn(?:\s+on)?|\bnée? le|\bdate de naissance|\bnacid[oa] el|\bfecha de nacimiento|\bf\. ?nac\.|\bdata de nascimento|\bnascid[oa] em|\bdoğum tarihi|\bd\. ?tarihi|تاريخ الميلاد|تاريخ الولادة|дата рождения|(?<![\w*])\*)\s*:?\s*(\d{1,2}\s?[./-]\s?\d{1,2}\s?[./-]\s?(?:\d{4}|\d{2})\b|\d{4}-\d{2}-\d{2}\b|\d{1,2}\.?\s(?:Jan|Feb|Mär|Mar|Apr|Mai|May|Jun|Jul|Aug|Sep|Okt|Oct|Nov|Dez|Dec)[a-zäöüé]*\.?\s\d{4}\b)"#

    /// The countries a BIC names, in its fifth and sixth letters.
    private static let bicCountries = "DE|AT|CH|LI|LU|NL|BE|FR|IT|ES|PT|GB|IE|PL|CZ|SK|HU|SI|HR|DK|SE|NO|FI|EE|LV|LT|GR|CY|MT|BG|RO|TR|US|CA|AE|SA|QA|KW|BH|OM|JO|LB|EG|MA|TN|IL|UA|RS|BA|AL|MK|IS|AU|NZ|SG|HK|JP|CN|IN|KR|BR|MX|ZA"

    /// Each country's IBAN length, for an IBAN read with a space after its country.
    private static let ibanLengths: [String: Int] = [
        "DE": 22, "AT": 20, "CH": 21, "LI": 21, "LU": 20, "NL": 18, "BE": 16, "FR": 27, "IT": 27, "ES": 24, "PT": 25,
        "GB": 22, "IE": 22, "PL": 28, "CZ": 24, "SK": 24, "HU": 28, "SI": 19, "HR": 21, "DK": 18, "SE": 24, "NO": 15,
        "FI": 18, "EE": 20, "LV": 21, "LT": 20, "GR": 27, "CY": 28, "MT": 31, "BG": 22, "RO": 24, "TR": 26, "AE": 23,
        "SA": 24, "QA": 29, "KW": 30, "BH": 22, "JO": 30, "LB": 28, "EG": 29, "MA": 28, "TN": 24, "IL": 23, "UA": 29,
        "RS": 22, "BA": 20, "AL": 28, "MK": 19, "IS": 26,
    ]

    /// Whether a run shaped like an IBAN is one: as read when written
    /// together, and with a space after its country only at its length.
    static func isIBANShaped(_ run: String) -> Bool {
        guard run.dropFirst(2).first == " " else { return true }
        let compact = run.replacingOccurrences(of: " ", with: "")
        return ibanLengths[String(compact.prefix(2))] == compact.count
    }

    /// A postcode with its town, or a town or a country on its own, as
    /// goes on under an address the detector found.
    private static func looksLikeAddress(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        if line.range(of: #"(?:^|\s|\b[A-Z]{1,2}\s?[-–]\s?)\d{4,6}(?:\s|$)"#, options: .regularExpression) != nil {
            return words.count <= 6 && !countsSomething(line)
        }
        // Without a postcode, only a country: a letter's subject right under
        // the address, "Bestätigung Ihrer Kündigung", is none.
        return isCountryLine(line)
    }

    /// Details announced by a label: on the same line, as in "IBAN: DE89…",
    /// beside it in the next column, as a shop's order page lists
    /// "Vorname:" and "Nachname:", or in the lines under it, as a name and an
    /// address under "Rechnungsadresse".
    /// `part` says where part of a line is.
    static func labelled(_ strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?,
                         _ chosen: Set<PrivateDetail>, learned: inout Set<String>) -> [Hit] {
        var hits: [Hit] = []
        // Whether a line sits on the row of another label, to its right, as
        // the next row of a list of labels and values does: a known label,
        // or any few words ending in a colon, like "Rechnung:".
        func besideALabel(_ index: Int) -> Bool {
            strings.indices.contains { other in
                let words = strings[other].trimmingCharacters(in: .whitespaces)
                let shaped = words.hasSuffix(":") && words.split(separator: " ").count <= 4
                return other != index && (shaped || isLabel(words)) && line(beside: other, in: boxes) == index
            }
        }
        /// The parts of a line a label announces, as found: kinds the owner
        /// did not choose are left for the policy to drop.
        func add(_ index: Int, from start: String.Index, first: Bool, in block: Block, role: NameRole?) {
            let string = strings[index]
            for part in parts(of: string, from: start, first: first, in: block) where chosen.contains(part.kind) {
                hits.append(Hit(line: index, range: part.range.map { NSRange($0, in: string) }, kind: part.kind,
                                role: part.kind == .names ? role : nil, check: part.check))
                if part.kind == .names { learn(String(string[part.range ?? string.startIndex..<string.endIndex]), into: &learned) }
            }
        }
        for (i, string) in strings.enumerated() {
            let text = string.trimmingCharacters(in: .whitespaces)
            var label = normalized(text)
            if let colon = text.firstIndex(of: ":"), let block = labels[normalized(String(text[..<colon]))] {
                let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    let range = string.range(of: value)
                    let role = DocumentSense.nameRole(ofLabel: String(text[..<colon]))
                    if let range { add(i, from: range.lowerBound, first: true, in: block, role: role) }
                    // The rest of a block, like the address after a name,
                    // follows under the value, in its column.
                    guard block.lines > 1, let range, var above = part(i, range) else { continue }
                    var last = i
                    for _ in 1..<block.lines {
                        guard let next = Self.line(under: above, in: boxes, gap: 1.1, skipping: last),
                              labels[normalized(strings[next])] == nil, !besideALabel(next) else { break }
                        if chosen.contains(block.rest) { hits.append(Hit(line: next, range: nil, kind: block.rest)) }
                        above = boxes[next]
                        last = next
                    }
                    continue
                }
                label = normalized(String(text[..<colon]))
            }
            guard let block = labels[label] else { continue }
            // A word that goes on beside it on its row, as "Fachärztin" and
            // "für Chirurgie" read in two pieces, is no label: a phrase.
            if !text.hasSuffix(":"), let next = Self.line(beside: i, in: boxes),
               boxes[next].minX - boxes[i].maxX < boxes[i].height * 1.5,
               let word = strings[next].split(separator: " ").first.map({ $0.lowercased() }),
               continuations.contains(word) { continue }
            let role = DocumentSense.nameRole(ofLabel: label)
            var last = i
            var first = 0
            // A label with a colon and its value beside it, in the next
            // column; the rest of a block follows under that value, until the
            // row of another label.
            let beside = text.hasSuffix(":") ? Self.line(beside: i, in: boxes) : nil
            if let value = beside, labels[normalized(strings[value])] == nil {
                add(value, from: strings[value].startIndex, first: true, in: block, role: role)
                last = value
                first = 1
            }
            for n in first..<max(block.lines, first) {
                // A label sits further from its first line than the lines
                // from each other, as a card's heading does.
                guard let next = Self.line(below: last, in: boxes, gap: n == 0 ? 2.5 : 1.1),
                      labels[normalized(strings[next])] == nil,
                      first == 0 || !besideALabel(next) else { break }
                add(next, from: strings[next].startIndex, first: n == 0, in: block, role: role)
                last = next
            }
        }
        return hits
    }

    /// Small words that carry a phrase on, never the start of a value.
    private static let continuations: Set<String> = ["für", "fur", "der", "des", "und", "&", "/", "-", "of", "for",
                                                     "in", "im", "am"]

    /// The people writing in a chat, by the name before the colon at the
    /// start of their messages: "Lena: Bis morgen!". A name counts when it
    /// starts at least two lines, or one line beside another such name, and
    /// is no label; it is then looked for elsewhere too, like "Hallo Lena".
    /// Words that start a line before a colon without being anyone's name,
    /// as in a log or a list of notes.
    private static let notSpeakers: Set<String> = [
        "error", "warning", "note", "notes", "info", "tip", "todo", "fixme", "status", "result", "update", "question",
        "answer", "re", "fwd", "fw", "aw", "wg", "hinweis", "achtung", "tipp", "frage", "antwort", "ergebnis",
        "fehler", "warnung", "summe", "total", "q", "a",
    ]

    /// The date and time before a writer's name, as a chat's export or a
    /// copied message has it: "[12.03.26, 14:05:12] ", "12.03.26, 14:05 - ".
    private static let messageTime = #"^\[?\d{1,2}[./]\d{1,2}[./]\d{2,4},?\s\d{1,2}:\d{2}(?::\d{2})?\]?\s(?:-\s)?"#

    static func speakers(_ strings: [String], _ chosen: Set<PrivateDetail>, learned: inout Set<String>) -> [Hit] {
        var lines: [String: [Int]] = [:]
        var starts: [Int: String.Index] = [:]
        var timed = Set<String>()
        for (index, string) in strings.enumerated() {
            let start = string.range(of: messageTime, options: .regularExpression)?.upperBound ?? string.startIndex
            guard let colon = string[start...].firstIndex(of: ":"), string.index(after: colon) < string.endIndex,
                  string[string.index(after: colon)] == " " else { continue }
            let word = String(string[start..<colon])
            guard (2...20).contains(word.count), word.allSatisfy({ $0.isLetter || "'’-".contains($0) }),
                  let first = word.first, first.isUppercase || first.isLetter && !first.isLowercase,
                  labels[normalized(word)] == nil, !notSpeakers.contains(normalized(word)) else { continue }
            lines[word, default: []].append(index)
            starts[index] = start
            if start > string.startIndex { timed.insert(word) }
        }
        // A writer after a message's date and time counts from one message.
        let speaking = lines.filter { $0.value.count >= 2 || timed.contains($0.key) }
        guard !speaking.isEmpty, speaking.count >= 2 || speaking.values.contains(where: { $0.count >= 3 }) else {
            return []
        }
        var hits: [Hit] = []
        for (word, indices) in speaking {
            learned.insert(fold(word))
            guard chosen.contains(.names) else { continue }
            for index in indices {
                let string = strings[index]
                let start = starts[index] ?? string.startIndex
                hits.append(Hit(line: index, range: NSRange(start..<string[start...].firstIndex(of: ":")!, in: string),
                                kind: .names))
            }
        }
        return hits
    }

    /// What a label announces in a line, from `start`, part by part: a
    /// company where a person was announced; a name cut where it ends, with
    /// the rest of an address after it; or the line as the block's kind. So
    /// "Patient: Mustermann, Max, geb. 01.02.1960" covers the name as a
    /// name, and leaves the date to Dates. A nil range is the whole line.
    private static func parts(of string: String, from start: String.Index, first: Bool, in block: Block)
        -> [(range: Range<String.Index>?, kind: PrivateDetail, check: Bool)] {
        let value = string[start...].trimmingCharacters(in: .whitespaces)
        let whole: Range<String.Index>? = start == string.startIndex ? nil
            : string.range(of: value, range: start..<string.endIndex)
        guard first else { return [(whole, block.rest, false)] }
        guard block.first == .names else { return [(whole, block.first, false)] }
        let head = String(value.prefix { !",;(".contains($0) })
        if DocumentSense.isOrganization(head) { return [(whole, .organizations, false)] }
        // What a form prints, like a doctor's field under "Fachärztin", is no one's name.
        if DocumentSense.isFormText(value) { return [] }
        // An address's label announces a name first, then the address.
        let address = block.rest != .names
        if let name = DocumentSense.leadingName(in: string, from: start) {
            let rest = string[name.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–"))
            let followedByComma = string[name.upperBound...].first == ","
            // An email's sender or recipient: the name, then the address in
            // angle brackets, "Mehmet Yılmaz <mehmet@example.com>".
            let mailbox = rest.hasPrefix("<") && rest.contains("@")
            if !address || mailbox || DocumentSense.nameWords(value) != nil
                || followedByComma && string[name].split(separator: " ").count >= 2 {
                // The name alone, without a title before it, like "Dr. med.".
                guard !rest.isEmpty else { return [(String(string[name]) == value ? whole : name, .names, false)] }
                var found: [(range: Range<String.Index>?, kind: PrivateDetail, check: Bool)] = [(name, .names, false)]
                if address, !mailbox, let after = string.range(of: rest, range: name.upperBound..<string.endIndex) {
                    found.append((after, block.rest, false))
                }
                return found
            }
        }
        // Not shaped like a name: in an address, the address; under a name's
        // own label, covered as one, for the owner to check.
        return address ? [(whole, block.rest, false)] : [(whole, .names, true)]
    }

    /// A name found is looked for elsewhere too; a first or last name on its
    /// own, from beside "Vorname" or "Nachname", as one word of a name.
    private static func learn(_ name: String, into learned: inout Set<String>) {
        if let words = DocumentSense.nameWords(name) {
            learned.formUnion(words)
        } else if let words = caselessNameWords(name) {
            learned.formUnion(words)
        } else {
            let word = name.trimmingCharacters(in: .whitespaces)
            if word.count >= 2, !word.contains(" "), word.first?.isUppercase == true,
               word.allSatisfy({ $0.isLetter || "'’-".contains($0) }) {
                learned.insert(fold(word))
            }
        }
    }

    /// The words of a name in a script without capitals, like Arabic, that
    /// a label or a chat vouched for: "مريم الحسن". Nil for any other.
    static func caselessNameWords(_ name: String) -> [String]? {
        let words = name.split(separator: " ").map(String.init)
        guard (1...5).contains(words.count),
              words.allSatisfy({ isCaseless($0) && DocumentSense.isNameWord($0) }) else { return nil }
        let names = words.filter { $0.count >= 2 && !DocumentSense.isParticle($0) }.map(fold)
        return names.isEmpty ? nil : names
    }

    /// Whether a word is written in a script without capitals, like Arabic.
    static func isCaseless(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return first.isLetter && !first.isUppercase && !first.isLowercase
    }

    /// The line right under another, starting in the same column, or nil
    /// when the gap is one a new section would leave. The gap counts in the
    /// taller of the two lines: a word with nothing below its baseline, like
    /// "Kunde", is read shorter than the name under it.
    static func line(below index: Int, in boxes: [CGRect], gap: CGFloat) -> Int? {
        line(under: boxes[index], in: boxes, gap: gap, skipping: index)
    }

    /// The line right under a part of the picture, like a value read on the
    /// same line as its label, starting in its column.
    static func line(under above: CGRect, in boxes: [CGRect], gap: CGFloat, skipping index: Int) -> Int? {
        var best: Int?
        for (i, box) in boxes.enumerated() where i != index {
            guard box.maxY <= above.minY + above.height * 0.3,
                  above.minY - box.maxY < max(above.height, box.height) * gap,
                  abs(box.minX - above.minX) < 0.03 else { continue }
            if let current = best, boxes[current].maxY >= box.maxY { continue }
            best = i
        }
        return best
    }

    /// The line beside another on its row, in the next column to its right,
    /// as a value sits beside its label; the nearest, or nil without one.
    static func line(beside index: Int, in boxes: [CGRect]) -> Int? {
        let label = boxes[index]
        var best: Int?
        for (i, box) in boxes.enumerated() where i != index {
            let overlap = min(label.maxY, box.maxY) - max(label.minY, box.minY)
            guard overlap > min(label.height, box.height) * 0.5,
                  box.minX >= label.maxX - 0.005, box.minX - label.maxX < 0.3 else { continue }
            if let current = best, boxes[current].minX <= box.minX { continue }
            best = i
        }
        return best
    }

    /// What the label at the start of a line announces, like Health for
    /// "Diagnose: Gastritis"; nil without one.
    private static func announced(in line: String) -> PrivateDetail? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        return labels[normalized(String(line[..<colon]))]?.first
    }

    /// Whether a line is a label that announces what follows it.
    static func isLabel(_ line: String) -> Bool {
        labels[normalized(line)] != nil
    }

    /// A label as the list has it: lowercased, without the colon after it,
    /// or the dots of a menu read on its row, as in "Kunde ⋯".
    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":.…⋯•·"))).lowercased()
    }

    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Names, found by what stands round them and by their shape. A name
    /// after a title, like "Frau Lena Weber"; after a word that says whose
    /// it is, like "Ihren Patienten Max Mustermann"; before a date of birth;
    /// on the line under a title alone, as in a letter's address; in a
    /// table's row under a header of name labels; and what the Natural
    /// Language framework calls one in a sentence. A line shaped like a name
    /// counts once something vouches for it: the framework, an email
    /// address, or a name met elsewhere. In a medical, banking or shop
    /// document one that nothing vouches for is covered and marked for the
    /// owner to check; elsewhere, and in an invoice's column of what it
    /// charges for, beside its price, it is only offered, as German
    /// capitalizes every noun. The words of the names found are covered
    /// wherever they come again, read as loosely as text recognition reads
    /// them.
    /// - Parameter own: the words of the owner's own name (`ownWords`): a
    ///   line or a word of it is a name for sure, read as loosely as a
    ///   misread letter in a word of five letters or more.
    /// - Parameter blocks: the page's postal blocks (`postalBlocks`).
    /// - Parameter document: the document's kind, where it is known already.
    private static func names(in text: Text, learned: Set<String>, own: Set<String> = [],
                              blocks: [PostalBlock] = [], kind document: DocumentKind? = nil) -> Findings {
        var known = learned.union(own)
        var hits: [Hit] = []
        let kind = document ?? DocumentSense.kind(of: text.strings)
        func add(_ i: Int, _ range: Range<String.Index>, title: String? = nil) {
            let string = text.strings[i]
            hits.append(Hit(line: i, range: NSRange(range, in: string), kind: .names, title: title))
            learn(String(string[range]), into: &known)
        }
        for (i, string) in text.strings.enumerated() {
            for found in DocumentSense.titledNames(in: string) { add(i, found.range, title: found.title) }
            for range in DocumentSense.cuedNames(in: string, kind: kind) { add(i, range) }
            for range in DocumentSense.bornNames(in: string, kind: kind) { add(i, range) }
            // A title alone on its line, the name on the line under it.
            if let title = DocumentSense.isTitleLine(string),
               let below = Self.line(below: i, in: text.boxes, gap: 1.6),
               let range = DocumentSense.nameAtStart(of: text.strings[below]) {
                add(below, range, title: title.title)
            }
            // A name before its address on one line, as a contract's parties
            // or a list of addresses write it: "Miriam Brandt, Birkenallee 146, 10115 Berlin".
            if let comma = string.firstIndex(of: ","),
               DocumentSense.nameWords(String(string[..<comma])) != nil,
               !DocumentSense.isOrganization(String(string[..<comma])),
               isAddress(string[string.index(after: comma)...].trimmingCharacters(in: .whitespaces)) {
                add(i, string.startIndex..<comma)
            }
            // A table's header of name labels, the names in the row under it.
            if isNameHeader(string), let below = Self.line(below: i, in: text.boxes, gap: 2.5),
               let range = DocumentSense.nameAtStart(of: text.strings[below]) {
                add(below, range)
            }
        }
        // A letter's or a form's postal block, with no label read: the
        // name's lines over its street and town. Two words or more on one
        // line are a name, and so are a form's two lines; one word alone may
        // be a heading, like "Impressum", and is only checked. One person's
        // lines take one role: the surest the words round them give, or,
        // with the date of birth's label read on their rows, whose the
        // document is, as a medical one's patient.
        var lone: [Hit] = []
        for block in blocks {
            let parts = block.names.compactMap { i in DocumentSense.namePart(of: text.strings[i]).map { (line: i, range: $0) } }
            guard let first = parts.first else { continue }
            let words = parts.reduce(0) { $0 + text.strings[$1.line][$1.range].split(separator: " ").count }
            let read = parts.map { DocumentSense.role(ofNameIn: $0.line, at: $0.range, lines: text.strings, kind: kind) }
            let role = read.first(where: \.isSure)
                ?? (block.born ? NameRole(role: DocumentSense.subject(in: kind), confidence: kind == .medical ? 0.75 : 0.6,
                                          reason: "birth") : nil)
            if parts.count >= 2 || words >= 2 {
                for part in parts {
                    hits.append(Hit(line: part.line, range: NSRange(part.range, in: text.strings[part.line]), kind: .names,
                                    role: role))
                    learn(String(text.strings[part.line][part.range]), into: &known)
                }
            } else {
                lone.append(Hit(line: first.line, range: NSRange(first.range, in: text.strings[first.line]), kind: .names,
                                role: role, check: true))
            }
        }
        var tagged = Set<Int>()
        var spans: [NSRange] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text.full
        tagger.enumerateTags(in: text.full.startIndex..<text.full.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            // A whole name, not a lone word: German capitalizes every noun,
            // and the tagger takes some of them for names.
            let span = String(text.full[range])
            guard tag == .personalName, span.contains(" "), !span.contains("\n") else { return true }
            for hit in text.hits(NSRange(range, in: text.full), .names) { tagged.insert(hit.line) }
            let words = span.split(separator: " ").map(String.init)
            // Words in capitals are a heading as often as a name: the tagger alone does not tell.
            if (2...4).contains(words.count), words.allSatisfy({ DocumentSense.isNameWord($0, caseless: false) }),
               !DocumentSense.isOrganization(span), span != span.uppercased() {
                spans.append(NSRange(range, in: text.full))
            }
            return true
        }
        let emails = text.matches(emailPattern, .caseInsensitive).map { range -> String in
            let address = (text.full as NSString).substring(with: range)
            return fold(String(address.prefix { $0 != "@" }))
        }

        let candidates = text.strings.indices.compactMap { i in
            DocumentSense.nameWords(text.strings[i]).map { (i, $0) }
        }
        // A letter vouches for a name by where it puts it: over its street
        // or its postcode and town, or beside or over a date of birth.
        func placed(_ i: Int) -> Bool {
            if let below = Self.line(below: i, in: text.boxes, gap: 3) {
                let next = text.strings[below].trimmingCharacters(in: .whitespaces)
                if isStreetLine(next) || isTownLine(next) || DocumentSense.startsWithBirth(next) { return true }
            }
            return Self.line(beside: i, in: text.boxes).map { DocumentSense.startsWithBirth(text.strings[$0]) } ?? false
        }
        // A line in capitals, as a letterhead writes its headings, needs
        // more than the tagger's word to be a name.
        func capitals(_ i: Int) -> Bool {
            let line = text.strings[i]
            return line.contains(where: \.isLetter) && line == line.uppercased()
        }
        var found = Set<Int>()
        // Twice, so a name vouched for further down covers its earlier
        // mentions too.
        for _ in 0..<2 {
            for (i, words) in candidates where !found.contains(i) {
                let inEmail = words.contains { word in word.count >= 4 && emails.contains { $0.contains(word) } }
                if tagged.contains(i) && !capitals(i) || inEmail || placed(i)
                    || words.allSatisfy({ isKnown($0, in: known, own: own) }) {
                    found.insert(i)
                    known.formUnion(words)
                }
            }
        }
        hits += found.map { Hit(line: $0, range: nil, kind: .names) }
        // A name in a sentence the framework vouches for, just its words:
        // not a title before it, not part of a company's name, and not in
        // what a label announces as something else, like a disease named
        // after a person beside "Diagnose:".
        for span in spans {
            for hit in text.hits(span, .names) where !found.contains(hit.line) {
                let line = text.strings[hit.line]
                guard let range = hit.range.flatMap({ Range($0, in: line) }),
                      announced(in: line).map({ $0 == .names }) ?? true,
                      !DocumentSense.organizationRanges(in: line).contains(where: { $0.overlaps(range) }),
                      let name = DocumentSense.trimmingTitles(range, in: line) else { continue }
                hits.append(Hit(line: hit.line, range: NSRange(name, in: line), kind: .names))
                learn(String(line[name]), into: &known)
            }
        }
        // A line shaped like a name that nothing vouches for: in a document
        // about a person's health, money or order, covered and checked;
        // elsewhere, written in capitals, as a letterhead writes its
        // headings, or one of the things an invoice charges for, as
        // "Druckpatronen Schwarz", only offered.
        let unvouched = candidates.filter { !found.contains($0.0) }.map(\.0)
        let sensitive = kind != .general
        let headings = unvouched.filter { capitals($0) || kind == .invoice && isItem($0, in: text) }
        if sensitive {
            let covered = unvouched.filter { !headings.contains($0) }
            hits += covered.map { Hit(line: $0, range: nil, kind: .names, check: true) }
            found.formUnion(covered)
        }
        hits += repeats(of: known, in: text, skipping: found, own: own)
        hits += mentions(of: own, in: text, skipping: found)
        let offered = sensitive ? headings : unvouched
        var possible = offered.map { Hit(line: $0, range: nil, kind: .names, check: true) }
        if sensitive { hits += lone } else { possible += lone }
        return Findings(hits: hits, possible: possible)
    }

    /// Words that head a table's columns of a person's details: "Name",
    /// "Vorname", "Geburtsdatum".
    private static let headerWords: Set<String> = ["name", "vorname", "nachname", "familienname", "patient",
                                                   "patientin", "patientenname", "geburtsdatum", "geb.-datum",
                                                   "geb.datum", "geb", "geboren", "first", "last", "surname",
                                                   "given", "date", "of", "birth", "dob", "versicherter",
                                                   "versicherte", "kunde", "kundin"]

    /// Whether a line is a table's header of a person's details, two words
    /// or more, all of them such words.
    private static func isNameHeader(_ line: String) -> Bool {
        let words = line.lowercased().split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":.,;")) }.filter { !$0.isEmpty }
        return words.count >= 2 && words.allSatisfy(headerWords.contains)
            && words.contains { ["name", "vorname", "nachname", "familienname", "patient", "patientin",
                                 "patientenname", "surname", "kunde", "kundin"].contains($0) }
    }

    /// Words that head an invoice's column of what it charges for.
    private static let itemColumns: Set<String> = ["beschreibung", "bezeichnung", "artikel", "leistung", "leistungen",
                                                   "produkt", "produkte", "ware", "waren", "position", "positionen",
                                                   "posten", "description", "item", "items", "product", "products",
                                                   "service", "services", "article", "articles", "goods"]
    /// Words that head a column of people, whose rows are names whatever
    /// stands beside them.
    private static let peopleColumns: Set<String> = ["name", "namen", "vorname", "nachname", "familienname",
                                                     "teilnehmer", "teilnehmerin", "teilnehmende", "kunde", "kundin",
                                                     "empfänger", "empfängerin", "auftraggeber", "mitarbeiter",
                                                     "mitarbeiterin", "person", "personen", "gast", "gäste",
                                                     "reisender", "reisende", "passagier", "patient", "patientin",
                                                     "mitglied", "schüler", "schülerin", "fahrer", "fahrerin",
                                                     "participant", "participants", "attendee", "guest", "passenger",
                                                     "employee", "customer", "recipient", "payee", "member", "student"]
    /// Words that head an invoice's other columns.
    private static let otherColumns: Set<String> = ["pos", "nr", "art.-nr", "artikelnr", "artikelnummer", "menge",
                                                    "anzahl", "stk", "stück", "einheit", "me", "preis", "einzelpreis",
                                                    "e-preis", "gesamtpreis", "gesamt", "betrag", "summe", "netto",
                                                    "brutto", "mwst", "ust", "steuer", "rabatt", "datum", "zeitraum",
                                                    "stunden", "std", "in", "€", "eur", "chf", "$", "usd", "%", "no",
                                                    "qty", "quantity", "unit", "price", "amount", "total", "tax",
                                                    "vat", "date", "rate", "hours", "each"]

    /// The words of a line, as a table's header has them: small letters,
    /// without the punctuation round them.
    private static func columnWords(_ line: String) -> [String] {
        line.lowercased().split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "\t" || $0 == "/" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":.,;()")) }.filter { !$0.isEmpty }
    }

    /// Whether a word heads an invoice's column of what it charges for:
    /// one of those words, or a compound ending in one, as
    /// "Artikelbezeichnung" or "Leistungsbeschreibung".
    private static func isItemColumn(_ word: String) -> Bool {
        itemColumns.contains(word) || word.hasSuffix("bezeichnung") || word.hasSuffix("beschreibung")
    }

    /// Whether a line holds a price, as an invoice's row does: "24,90 €",
    /// "€ 5.90", "1.234,56". A quantity alone, as "2", or a date, is none.
    static func isPrice(_ line: String) -> Bool {
        line.range(of: #"(?:€|£|\$|\bEUR|\bUSD|\bGBP|\bCHF)\s?\d|\d\s?(?:€|£|EUR\b|USD\b|GBP\b|CHF\b)|(?<![\d.,])\d{1,3}(?:[.,\x{00A0} ]\d{3})*[.,]\d{2}(?![\d.,]*\d)"#,
                   options: .regularExpression) != nil
    }

    /// Whether a line of an invoice is one of the things it charges for, as
    /// its table lists them: with a price on its row, under a header that
    /// names its column so, like "Beschreibung" or "Artikel", the nearest
    /// up its column. A column of people, like "Teilnehmer", holds names
    /// whatever their price; so does a line without one, as the customer's
    /// name in the address, and one under no header.
    static func isItem(_ index: Int, strings: [String], boxes: [CGRect]) -> Bool {
        let box = boxes[index]
        let priced = boxes.indices.contains { other in
            let beside = boxes[other]
            let overlap = min(box.maxY, beside.maxY) - max(box.minY, beside.minY)
            return other != index && overlap > min(box.height, beside.height) * 0.5 && isPrice(strings[other])
        }
        guard priced else { return false }
        // Up its column, line by line, to the first that heads it; a gap a
        // new section would leave ends the column.
        let above = boxes.indices.filter { other in
            let line = boxes[other]
            return other != index && line.minY >= box.maxY - box.height * 0.3
                && min(line.maxX, box.maxX) - max(line.minX, box.minX) > 0
        }.sorted { boxes[$0].minY < boxes[$1].minY }
        var last = box
        for other in above {
            let line = boxes[other]
            guard line.minY - last.maxY < max(line.height, last.height) * 3 else { return false }
            let words = columnWords(strings[other])
            if (1...8).contains(words.count),
               words.allSatisfy({ isItemColumn($0) || peopleColumns.contains($0) || otherColumns.contains($0) }) {
                return words.contains(where: isItemColumn) && !words.contains(where: peopleColumns.contains)
            }
            last = line
        }
        return false
    }

    fileprivate static func isItem(_ index: Int, in text: Text) -> Bool {
        isItem(index, strings: text.strings, boxes: text.boxes)
    }

    /// Whether a word is one of the names found, or that word as text
    /// recognition may misread it: a letter off in a long word, or in a
    /// word of five letters or more of the owner's own name.
    private static func isKnown(_ word: String, in known: Set<String>, own: Set<String> = []) -> Bool {
        if known.contains(word) { return true }
        if word.count >= 5, own.contains(where: { $0.count >= 5 && abs($0.count - word.count) <= 1 && differsByOne($0, word) }) {
            return true
        }
        guard word.count >= 6 else { return false }
        return known.contains { $0.count >= 6 && abs($0.count - word.count) <= 1 && differsByOne($0, word) }
    }

    /// Whether two words differ by one letter at most: one changed, added
    /// or left out.
    static func differsByOne(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if x == y { return true }
        if x.count == y.count { return zip(x, y).filter { $0 != $1 }.count == 1 }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        guard long.count - short.count == 1 else { return false }
        var i = 0, j = 0, skipped = false
        while i < short.count, j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
            } else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }

    /// The words of the names found, met again on other lines, each where it
    /// is: "Mustermann" in "Herr Mustermann klagt über …", once "Mustermann,
    /// Max" was found beside "Patient:".
    private static func repeats(of known: Set<String>, in text: Text, skipping whole: Set<Int>,
                                own: Set<String> = []) -> [Hit] {
        let words = known.filter { $0.count >= 3 }
        guard !words.isEmpty else { return [] }
        var hits: [Hit] = []
        for (i, string) in text.strings.enumerated() where !whole.contains(i) {
            for match in Self.word.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                guard let range = Range(match.range, in: string) else { continue }
                let raw = String(string[range]).trimmingCharacters(in: CharacterSet.punctuationCharacters)
                // A title is no one's name, wherever it comes again: "Herr" in "Sehr geehrter Herr Kollege".
                // In a script without capitals, like Arabic, a name met before is enough: "مرحبا مريم".
                let caseless = isCaseless(raw)
                guard raw.count >= 3, raw.first?.isUppercase == true || caseless, !DocumentSense.isTitle(raw),
                      isKnown(fold(raw), in: words, own: own), DocumentSense.isNameWord(raw, caseless: caseless),
                      var inner = string.range(of: raw, range: range) else { continue }
                // An initial before it goes with it: "M. Mustermann".
                if let initial = string.range(of: #"\p{Lu}\.\s?$"#, options: .regularExpression,
                                              range: string.startIndex..<inner.lowerBound) {
                    inner = initial.lowerBound..<inner.upperBound
                }
                hits.append(Hit(line: i, range: NSRange(inner, in: string), kind: .names))
            }
        }
        return hits
    }

    /// The owner's own name wherever it is written, in any case, in any
    /// order, with commas between, each run of its words as one place:
    /// "erika musterfrau", "MUSTERFRAU, Erika", "Musterfrau" alone.
    private static func mentions(of own: Set<String>, in text: Text, skipping whole: Set<Int>) -> [Hit] {
        guard !own.isEmpty else { return [] }
        var hits: [Hit] = []
        for (i, string) in text.strings.enumerated() where !whole.contains(i) {
            var run: Range<String.Index>?
            func close() {
                // A short word of it alone in small letters is a word, like "max" in "max. 5".
                if let found = run, found.isEmpty == false,
                   string[found].contains(" ") || string[found].count >= 4 || string[found].first?.isUppercase == true {
                    hits.append(Hit(line: i, range: NSRange(found, in: string), kind: .names))
                }
                run = nil
            }
            for match in Self.word.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                guard let range = Range(match.range, in: string) else { continue }
                let raw = String(string[range]).trimmingCharacters(in: CharacterSet.punctuationCharacters)
                guard raw.count >= 2, raw.allSatisfy({ $0.isLetter || "'’-".contains($0) }),
                      isKnown(fold(raw), in: own, own: own), let inner = string.range(of: raw, range: range) else {
                    close()
                    continue
                }
                // The run goes on over a space or a comma, as "Musterfrau, Erika".
                if let begun = run, string[begun.upperBound..<inner.lowerBound].allSatisfy({ $0 == " " || $0 == "," }) {
                    run = begun.lowerBound..<inner.upperBound
                } else {
                    close()
                    run = inner
                }
            }
            close()
        }
        return hits
    }

    /// Companies and organizations: a run of capitalized words round a word
    /// that names one, like "Radiologie Zentrum Nord GmbH", and what the
    /// Natural Language framework calls one, of two words or more.
    private static func organizations(in text: Text) -> [Hit] {
        var hits: [Hit] = []
        for (i, string) in text.strings.enumerated() {
            hits += DocumentSense.organizationRanges(in: string).map {
                Hit(line: i, range: NSRange($0, in: string), kind: .organizations)
            }
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text.full
        tagger.enumerateTags(in: text.full.startIndex..<text.full.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            let span = text.full[range]
            if tag == .organizationName, span.contains(" "), !span.contains("\n") {
                hits += text.hits(NSRange(range, in: text.full), .organizations)
            }
            return true
        }
        return hits
    }

    /// The places kept as the owner chose: a kind that is chosen, and a
    /// name only when it is the name of someone whose names are covered. A
    /// name whose role is not clear is kept, and marked for the owner to
    /// check. The owner's own rules always count.
    /// - Parameter own: the words of the owner's own name (`ownWords`).
    /// - Parameter doctors: the lines a letterhead lists among its doctors
    ///   (`doctorsColumn`), where a name with nothing round it is a doctor's.
    /// - Parameter kind: the document's kind, where it is known already.
    private static func decided(_ hits: [Hit], in strings: [String], _ chosen: Set<PrivateDetail>,
                                scope: NameScope, own: Set<String> = [], doctors: Set<Int> = [],
                                kind: DocumentKind? = nil) -> [Hit] {
        let document = kind ?? DocumentSense.kind(of: strings)
        var kept: [Hit] = []
        var named: [Hit] = []
        // The places of the owner's own name, by their place in `named`.
        var mine = Set<Int>()
        for var hit in hits {
            guard let kind = hit.kind else { kept.append(hit); continue }
            guard chosen.contains(kind) else { continue }
            let line = strings[hit.line]
            let range = hit.range.flatMap { Range($0, in: line) }
            // A segment of the spine or a disease named after someone is no
            // one's name and no one's number.
            if !notMedical.contains(kind), let range,
               DocumentSense.medicalRanges(in: line, medical: document == .medical).contains(where: { $0.overlaps(range) }) {
                continue
            }
            guard kind == .names else { kept.append(hit); continue }
            if hit.role == nil {
                hit.role = DocumentSense.role(ofNameIn: hit.line, at: range, title: hit.title, lines: strings, kind: document)
            }
            if hit.role?.isSure != true, doctors.contains(hit.line) {
                hit.role = NameRole(role: .doctor, confidence: 0.7, reason: "column")
            }
            // The owner's own name is a name for sure, never to check for
            // that; where nothing says whose it is, it is whose the
            // document is, as the patient's in a medical letter. Whoever it
            // is there, it is covered with any of the names' switches on.
            let words = (range.map { String(line[$0]) } ?? line).split(whereSeparator: { !$0.isLetter })
                .map { fold(String($0)) }.filter { $0.count >= 2 }
            if !own.isEmpty, !words.isEmpty, words.allSatisfy({ isKnown($0, in: own, own: own) }) {
                hit.check = false
                if hit.role?.isSure != true {
                    hit.role = NameRole(role: DocumentSense.subject(in: document), confidence: 0.7, reason: "own name")
                }
                mine.insert(named.count)
            }
            named.append(hit)
        }
        guard !named.isEmpty else { return kept }
        // A name met where nothing says whose it is takes the role it has
        // where something does: "Herr Mustermann" is the patient named above.
        func words(of hit: Hit) -> [String] {
            let line = strings[hit.line]
            let text = hit.range.flatMap { Range($0, in: line) }.map { String(line[$0]) } ?? line
            return text.split(whereSeparator: { !$0.isLetter }).map { fold(String($0)) }.filter { $0.count >= 3 }
        }
        var sure: [String: NameRole] = [:]
        for hit in named where hit.role?.isSure == true {
            for word in words(of: hit) where sure[word] == nil { sure[word] = hit.role }
        }
        // As read: a letter misread, as "Mustermamn", is still the same name.
        func role(of word: String) -> NameRole? {
            sure[word] ?? (word.count >= 6 ? sure.first { differsByOne($0.key, word) }?.value : nil)
        }
        for (index, found) in named.enumerated() {
            var hit = found
            if hit.role?.isSure != true, let known = words(of: hit).lazy.compactMap(role(of:)).first {
                hit.role = known
            }
            if mine.contains(index) {
                kept.append(hit)
                continue
            }
            switch scope.decide(hit.role ?? .unknown) {
            case .cover:
                kept.append(hit)
            case .coverAndCheck:
                hit.check = true
                kept.append(hit)
            case .leave:
                continue
            }
        }
        return kept
    }

    /// The lines of a column of doctors, as a practice's letterhead lists
    /// them, that name someone with nothing round the name to say whose it
    /// is, like a doctor written without "Dr. med.": in a medical document,
    /// a line shaped like a name right between two doctors' names in its
    /// column. Each is read as a doctor's. A name after the doctors, as a
    /// patient's may be, is not.
    /// - Parameter kind: the document's kind, where it is known already.
    static func doctorsColumn(_ strings: [String], boxes: [CGRect], kind: DocumentKind? = nil) -> Set<Int> {
        guard boxes.count == strings.count, (kind ?? DocumentSense.kind(of: strings)) == .medical else { return [] }
        let doctors = Set(strings.indices.filter { DocumentSense.namesADoctor(strings[$0]) })
        guard doctors.count >= 2 else { return [] }
        // Each line's neighbours in its column, the nearest above and below.
        var below = [Int?](repeating: nil, count: strings.count)
        var above = [Int?](repeating: nil, count: strings.count)
        for i in strings.indices {
            guard let under = line(below: i, in: boxes, gap: 1.6) else { continue }
            below[i] = under
            if let over = above[under], boxes[over].minY <= boxes[i].minY { continue }
            above[under] = i
        }
        return Set(strings.indices.filter { i in
            guard !doctors.contains(i), let up = above[i], let down = below[i],
                  doctors.contains(up), doctors.contains(down) else { return false }
            return DocumentSense.nameWords(strings[i]) != nil
        })
    }

    /// The kinds a medical term may be: a finding is health, never a name
    /// or a number.
    private static let notMedical: Set<PrivateDetail> = [.health, .dates, .organizations, .addresses, .amounts,
                                                         .links, .emails, .faces, .barcodes]

    /// Lines with a dose or a pharmacy number, where medicines are named.
    private static func medicines(in lines: [String]) -> [Hit] {
        let dose = #"\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ml|ie|iu|tbl|tabletten|tablets?|kapseln|capsules?)\b"#
        let pharmacy = #"\bPZN[:\s-]*\d{7,8}\b"#
        return lines.indices.compactMap { i -> Hit? in
            let line = lines[i]
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

    /// Whether eleven digits are a German tax ID: no zero first, one digit
    /// of the first ten there twice or three times, and the last the
    /// check digit of ISO 7064, MOD 11,10.
    static func isSteuerID(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard digits.count == 11, digits[0] != 0 else { return false }
        let repeated = Dictionary(grouping: digits.prefix(10), by: { $0 }).values.map(\.count).filter { $0 > 1 }
        guard repeated.count == 1, (2...3).contains(repeated[0]) else { return false }
        var product = 10
        for digit in digits.prefix(10) {
            var sum = (digit + product) % 10
            if sum == 0 { sum = 10 }
            product = sum * 2 % 11
        }
        return (11 - product) % 10 == digits[10]
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

extension Finder {
    // MARK: Phone numbers

    /// Words that say the number after them, or the one under them, is a
    /// phone number, folded, in the app's languages: a word of its own,
    private static let phoneWords: Set<String> = [
        "tel", "fon", "fax", "ph", "mob", "cell", "gsm", "sms", "hotline", "call", "ring", "ruf", "ara",
        "faks", "zəng", "movil", "mobil", "mobile", "handy", "celular", "cel", "fone", "tlf", "tfno", "telf",
        "portable", "helpline", "liga",
    ]
    /// the start of one, as "Telefonnummer", "appelez" or "llámame",
    private static let phoneWordStarts = ["telefon", "telephon", "phone", "mobil", "handy", "rufnummer", "durchwahl",
                                          "anruf", "ruckruf", "notruf", "erreichbar", "appel", "llam", "ligu", "ligar",
                                          "chama", "telefax", "whatsapp"]
    /// or a word in a script written without spaces, or a sign.
    private static let phoneSigns = ["هاتف", "جوال", "موبايل", "فاكس", "اتصل", "تلفون", "واتساب", "फ़ोन", "फोन",
                                     "मोबाइल", "कॉल", "दूरभाष", "電話", "携帯", "ファックス", "ファクス", "전화", "휴대폰",
                                     "핸드폰", "팩스", "电话", "手机", "传真", "致电", "☎", "📞", "✆", "📱", "℡"]

    private static func folded(_ text: Substring) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether a piece of a line holds a word that says a phone number
    /// follows: "Tel.", "Fax:", "Mobil", "Ruf mich an unter", "هاتف", "电话";
    /// a single letter before a colon, as a letterhead prints "T: …".
    static func hasPhoneWord(_ text: Substring) -> Bool {
        let text = folded(text)
        if phoneSigns.contains(where: { text.contains(folded($0[...])) }) { return true }
        // "Tel." as small print, or a signature over it, reads it: "Te!.", "TeI.".
        if text.range(of: #"(?<!\p{L})te[l1i!|](?!\p{L})"#, options: .regularExpression) != nil { return true }
        var start: String.Index?
        for i in text.indices + [text.endIndex] {
            if i < text.endIndex, text[i].isLetter {
                if start == nil { start = i }
                continue
            }
            guard let from = start else { continue }
            start = nil
            let word = String(text[from..<i])
            if phoneWords.contains(word) || phoneWordStarts.contains(where: word.hasPrefix) { return true }
            if word.count == 1, "tfm".contains(word), i < text.endIndex, ":.".contains(text[i]) { return true }
        }
        return false
    }

    /// Whether a number is written as a phone number is dialled: after a
    /// country's code, "+49 …", "0049 …", or in groups, "040 1234567",
    /// "(030) 12 34 56", "0176-1234567".
    static func isDialled(_ number: Substring) -> Bool {
        let number = number.trimmingCharacters(in: .whitespaces)
        return hasCountryCode(number[...])
            || number.hasPrefix("(") || number.range(of: #"\d[ \-–/.()\x{00A0}]+\d"#, options: .regularExpression) != nil
    }

    private static func hasCountryCode(_ number: Substring) -> Bool {
        let number = number.trimmingCharacters(in: .whitespaces)
        return number.hasPrefix("+") || number.range(of: #"^00[1-9]"#, options: .regularExpression) != nil
    }

    /// What stands before a number on its line, back to the number before
    /// it or the line's start: its label, as "Fax: " in
    /// "Tel. 040 1234567 Fax: 040 1234568".
    static func label(before range: Range<String.Index>, in line: String) -> Substring {
        var start = range.lowerBound
        while start > line.startIndex, !line[line.index(before: start)].isNumber { start = line.index(before: start) }
        return line[start..<range.lowerBound]
    }

    /// Whether a line is a phone number's label alone, as over a column of
    /// numbers: "Telefon", "Tel.:", "Mobil / WhatsApp".
    static func isPhoneLabel(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        return (1...3).contains(words.count) && !line.contains(where: \.isNumber) && hasPhoneWord(line[...])
    }

    /// Whether what the phone numbers' detector found is one. A number
    /// written as one is dialled, or after a word that says it is one, on
    /// its line, as the label over it or, for a hit, beside it on its row,
    /// is, on any page. A bare run of
    /// digits is only on a page that is no document, like a chat, where
    /// numbers are typed so: a form, an invoice or a letter prints its
    /// numbers with their labels, and a bare run there is a practice's, a
    /// doctor's or a customer's number.
    /// - Parameter above: the line over it, in its column.
    static func isPhone(_ range: Range<String.Index>, in line: String, above: String?, document: DocumentKind) -> Bool {
        isDialled(line[range]) || hasPhoneWord(label(before: range, in: line)) || above.map(isPhoneLabel) == true
            || document == .general
    }

    /// The same for a hit, with its label found by its place: over it in
    /// its column, or before it on its row, read as a line of its own, as
    /// an invoice prints "Telefon" and, a column on, "040123456".
    static func isPhone(_ hit: Hit, in strings: [String], boxes: [CGRect], document: DocumentKind) -> Bool {
        let string = strings[hit.line]
        guard let range = hit.range.flatMap({ Range($0, in: string) }) else { return true }
        guard boxes.count == strings.count else { return isPhone(range, in: string, above: nil, document: document) }
        let above = line(above: hit.line, in: boxes, gap: 1.6).map { strings[$0] }
        if isPhone(range, in: string, above: above, document: document) { return true }
        // A label beside it counts for the first number on its line only.
        guard !label(before: range, in: string).contains(where: \.isLetter) else { return false }
        return strings.indices.contains { i in
            i != hit.line && isPhoneLabel(strings[i]) && line(beside: i, in: boxes) == hit.line
        }
    }

    /// Whether a bare run of digits is shaped like a number dialled at
    /// home, as most countries write one: a 0, then nine to eleven digits.
    /// On a document, with no word to say so, it is covered for the owner
    /// to check.
    static func isNationalNumber(_ number: Substring) -> Bool {
        number.range(of: #"^0[1-9]\d{8,10}$"#, options: .regularExpression) != nil
    }

    /// Whether a phone number says so itself: a word like "Tel." before it,
    /// or a country's code, which no other kind of number has.
    private static func saysPhone(_ hit: Hit, in strings: [String]) -> Bool {
        let string = strings[hit.line]
        guard let range = hit.range.flatMap({ Range($0, in: string) }) else { return false }
        return hasCountryCode(string[range]) || hasPhoneWord(label(before: range, in: string))
    }

    /// The line right over another, starting in its column, as a label
    /// over its value.
    static func line(above index: Int, in boxes: [CGRect], gap: CGFloat) -> Int? {
        let below = boxes[index]
        var best: Int?
        for (i, box) in boxes.enumerated() where i != index {
            guard box.minY >= below.maxY - below.height * 0.3,
                  box.minY - below.maxY < max(box.height, below.height) * gap,
                  abs(box.minX - below.minX) < 0.03 else { continue }
            if let current = best, boxes[current].minY <= box.minY { continue }
            best = i
        }
        return best
    }

    // MARK: One kind for each number

    /// Whether nine digits are a German doctor's lifetime number (LANR):
    /// the seventh digit is the check digit of the first six, weighted 4
    /// and 9 in turn. One run of nine digits in ten passes by chance, so it
    /// counts only for a bare run in a medical document.
    static func isDoctorNumber(_ number: Substring) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard digits.count == 9, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let sum = zip(digits, [4, 9, 4, 9, 4, 9]).map(*).reduce(0, +)
        return (10 - sum % 10) % 10 == digits[6]
    }

    /// What the page itself says a number is, and whose: nil where it is
    /// a code the form prints, like the insured person's status.
    struct NamedNumber: Equatable {
        let kind: PrivateDetail?
        let role: NameRole?
    }

    /// A number as numbers are compared: its digits, six at least, as a
    /// shorter one may be anything.
    static func numberKey(_ text: Substring) -> String? {
        let digits = String(text.filter { $0.isASCII && $0.isNumber })
        return digits.count >= 6 ? digits : nil
    }

    /// The numbers the page names, by their digits: a form field's by its
    /// label ("Arzt-Nr.", "Versicherten-Nr.", "Status"), a medical letter's
    /// reference, one after an order's or an ID's label ("Kundennummer",
    /// "Steuernummer"); the first that names one wins. Whatever the kinds
    /// chosen, so a number named so is never a phone number.
    static func namedNumbers(_ strings: [String], boxes: [CGRect], form: FormFields.Reading,
                             document: DocumentKind) -> [String: NamedNumber] {
        var named: [String: NamedNumber] = [:]
        func name(_ hit: Hit, as number: NamedNumber) {
            let string = strings[hit.line]
            guard let range = hit.range.flatMap({ Range($0, in: string) }), let key = numberKey(string[range]),
                  named[key] == nil else { return }
            named[key] = number
        }
        let fields: [FormFields.Entity] = [.healthInsuranceNumber, .identificationNumber, .institutionNumber, .formCode]
        for value in form.values where value.confidence == .high && fields.contains(value.entity) {
            guard let key = numberKey(strings[value.line][value.range]), named[key] == nil else { continue }
            named[key] = NamedNumber(kind: value.entity.detail,
                                     role: value.role.map { NameRole(role: $0, confidence: 0.9, reason: "form") })
        }
        let text = Text(strings, boxes: boxes)
        // A medical letter's reference is the patient's case, as `collect` reads it.
        if document == .medical {
            for hit in references(in: text) {
                name(hit, as: NamedNumber(kind: .ids, role: NameRole(role: .patient, confidence: 0.7, reason: "reference")))
            }
        }
        for kind in [PrivateDetail.ids, .orders] {
            for range in patternRanges(in: text.full, [kind]) {
                for hit in text.hits(range, kind) { name(hit, as: NamedNumber(kind: kind, role: nil)) }
            }
        }
        return named
    }

    /// A number as it is printed again: its digits, maybe after a capital or two.
    private static let numberRun = try! NSRegularExpression(pattern: #"(?<![\p{L}\d])\p{Lu}{0,2}\d{6,15}(?![\p{L}\d])"#)

    /// What the page names the number a hit is, if it does.
    static func namedNumber(of hit: Hit, in strings: [String], _ named: [String: NamedNumber]) -> NamedNumber? {
        let string = strings[hit.line]
        return hit.range.flatMap { Range($0, in: string) }.flatMap { numberKey(string[$0]) }.flatMap { named[$0] }
    }

    /// The kinds of number, the one that wins first where two find one
    /// place: a bank's account and an ID by their checks and labels, an
    /// order's by its label, then a parcel's by its length alone.
    private static let numberKinds: [PrivateDetail] = [.bank, .ids, .orders, .codes, .tracking, .phones]

    /// One kind for each number, as a person reads a page, between finding
    /// the places and keeping those the owner chose (`decided`). A phone
    /// number the detector found is one where it is written as one is
    /// dialled or said to be one, or on a page that is no document; a bare
    /// run on a document shaped like a number dialled at home is covered
    /// for the owner to check, and any other is a number of another kind:
    /// in a medical document an ID, covered for the owner to check, as a
    /// practice's or an insurer's number is where its label is misread.
    /// A number the page names by its label is that kind wherever it is
    /// printed again, as a practice's stamp repeats the numbers of a form's
    /// header; never a phone number too, unless "Tel." or a country's code
    /// says so where it stands. In a medical document, a bare run of nine
    /// digits that passes a doctor's number's check is one, the doctor's
    /// where it is in the block of a doctor's name. And a place two kinds
    /// of number found is one place of one kind, so it is listed once.
    static func oneKind(_ hits: [Hit], named: [String: NamedNumber], in strings: [String], boxes: [CGRect],
                        _ chosen: Set<PrivateDetail>, document: DocumentKind) -> [Hit] {
        var kept: [Hit] = []
        for hit in hits {
            guard hit.kind == .phones else { kept.append(hit); continue }
            let number = namedNumber(of: hit, in: strings, named)
            if let number, number.kind != .phones, !saysPhone(hit, in: strings) {
                // A number the page names as another kind is that kind, never a phone number too.
                guard let kind = number.kind, chosen.contains(kind),
                      !hits.contains(where: { $0.line == hit.line && $0.kind == kind && overlap($0.range, hit.range) })
                else { continue }
                kept.append(Hit(line: hit.line, range: hit.range, kind: kind, role: number.role))
            } else if isPhone(hit, in: strings, boxes: boxes, document: document) {
                kept.append(hit)
            } else if number == nil, let range = hit.range.flatMap({ Range($0, in: strings[hit.line]) }),
                      isNationalNumber(Substring(strings[hit.line][range].trimmingCharacters(in: .whitespaces))) {
                // Shaped like a number dialled at home, with no word to say so: covered, for the owner to check.
                var checked = hit
                checked.check = true
                kept.append(checked)
            } else if number == nil, document == .medical, chosen.contains(.ids),
                      let range = hit.range.flatMap({ Range($0, in: strings[hit.line]) }),
                      let key = numberKey(strings[hit.line][range]), key.count >= 7,
                      !isDoctorNumber(Substring(strings[hit.line][range].trimmingCharacters(in: .whitespaces))) {
                // In a medical document, a bare run nothing names is most likely an ID, a
                // practice's, an insurer's or a case's: covered as one, for the owner to check.
                kept.append(Hit(line: hit.line, range: hit.range, kind: .ids, check: true))
            }
            // Any other bare run on a document is a number of another kind, no phone number.
        }
        // Each place a named number is printed again, and a doctor's number by its check.
        func add(_ line: Int, _ range: NSRange, _ kind: PrivateDetail, _ role: NameRole?) {
            guard chosen.contains(kind),
                  !kept.contains(where: { $0.line == line && $0.kind != .phones && overlap($0.range, range) }) else { return }
            kept.append(Hit(line: line, range: range, kind: kind, role: role))
        }
        let doctors = document == .medical ? strings.indices.filter { DocumentSense.namesADoctor(strings[$0]) } : []
        for (i, string) in strings.enumerated() {
            for match in numberRun.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                guard let range = Range(match.range, in: string), let key = numberKey(string[range]) else { continue }
                if let number = named[key], let kind = number.kind {
                    add(i, match.range, kind, number.role)
                } else if named[key] == nil, document == .medical, isDoctorNumber(string[range]),
                          !hasPhoneWord(label(before: range, in: string)) {
                    // The doctor's, in the block of a doctor's name: their stamp.
                    let near = boxes.count == strings.count && doctors.contains { d in
                        abs(boxes[d].minX - boxes[i].minX) < 0.05 && abs(boxes[d].midY - boxes[i].midY) < boxes[i].height * 12
                    }
                    add(i, match.range, .ids, near ? NameRole(role: .doctor, confidence: 0.7, reason: "check digit") : nil)
                }
            }
        }
        // One kind for each place: a phone number that says so wins; else
        // the kind first in `numberKinds`, over the whole of both.
        var placed: [Hit] = []
        for hit in kept {
            guard let kind = hit.kind, let rank = numberKinds.firstIndex(of: kind),
                  let i = placed.firstIndex(where: { other in
                      other.line == hit.line && other.kind != kind && other.kind.map(numberKinds.contains) == true
                          && overlap(other.range, hit.range)
                  }), let otherKind = placed[i].kind, let otherRank = numberKinds.firstIndex(of: otherKind)
            else { placed.append(hit); continue }
            let other = placed[i]
            let phone = kind == .phones ? hit : otherKind == .phones ? other : nil
            let wins = phone.map { saysPhone($0, in: strings) == (kind == .phones) } ?? (rank < otherRank)
            var winner = wins ? hit : other
            winner.range = union(hit.range, other.range)
            placed[i] = winner
        }
        return placed
    }
}

/// The lines of the pictures read lately, each kept by a fingerprint of its
/// pixels, from any thread. In memory only, a few pictures at a time, and
/// never written anywhere: what was read stays as private as the picture.
private final class Readings: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [(print: Data, lines: [Finder.TextLine])] = []
    /// A few pictures: the one being covered and those just before it.
    private let room = 6

    /// The picture's pixels and their layout, hashed, so two pictures share
    /// a fingerprint only when they are the same. Nil when its pixels can't
    /// be had; such a picture is read each time.
    static func fingerprint(of image: CGImage) -> Data? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        var hash = SHA256()
        hash.update(data: Data("\(image.width)x\(image.height) \(image.bytesPerRow) \(image.bitsPerPixel) \(image.bitmapInfo.rawValue)".utf8))
        hash.update(bufferPointer: UnsafeRawBufferPointer(start: bytes, count: CFDataGetLength(data)))
        return Data(hash.finalize())
    }

    func lines(for print: Data) -> [Finder.TextLine]? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = kept.firstIndex(where: { $0.print == print }) else { return nil }
        // The newest last, so the oldest goes first.
        let found = kept.remove(at: index)
        kept.append(found)
        return found.lines
    }

    func keep(_ lines: [Finder.TextLine], for print: Data) {
        lock.lock()
        defer { lock.unlock() }
        kept.removeAll { $0.print == print }
        kept.append((print, lines))
        if kept.count > room { kept.removeFirst(kept.count - room) }
    }

    func forget() {
        lock.lock()
        defer { lock.unlock() }
        kept.removeAll()
    }
}
