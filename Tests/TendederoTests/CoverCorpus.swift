import Foundation
@testable import Tendedero

/// Made-up documents to measure covering by: invoices, medical letters,
/// transfers, payslips, chats, emails and forms, in seven languages, each
/// part of each line marked as what it is. A private detail should be
/// covered whole; what is marked to stay, like a shop, an item, an amount
/// or a heading, should stay readable with the recommended kinds. Every
/// person, address and number is made up from the pools below with a fixed
/// seed, so the same documents come back at every run; account and ID
/// numbers carry valid check digits, as real ones do. None is a real
/// document or a real person.
enum CoverCorpus {
    typealias Kind = PrivateDetail

    /// One part of a line: plain text, text that should stay, or a detail
    /// of a kind that should be covered.
    enum Part: ExpressibleByStringInterpolation {
        case plain(String)
        case keep(String)
        case secret(PrivateDetail, String)

        init(stringLiteral value: String) { self = .plain(value) }
        init(stringInterpolation: DefaultStringInterpolation) {
            self = .plain(String(stringInterpolation: stringInterpolation))
        }

        var text: String {
            switch self {
            case .plain(let text), .keep(let text), .secret(_, let text): text
            }
        }
    }

    /// A part of a line with where it stands in it, in characters.
    struct Marked {
        let line: Int
        let range: Range<Int>
        let text: String
        /// Nil for what should stay.
        let kind: PrivateDetail?
    }

    struct Document {
        let language: String
        let type: String
        let lines: [String]
        let secrets: [Marked]
        let kept: [Marked]

        var name: String { "\(language)/\(type)" }

        init(_ language: String, _ type: String, _ rows: [[Part]]) {
            self.language = language
            self.type = type
            var lines: [String] = [], secrets: [Marked] = [], kept: [Marked] = []
            for (index, row) in rows.enumerated() {
                var line = ""
                for part in row {
                    let start = line.count
                    line += part.text
                    let range = start..<line.count
                    switch part {
                    case .plain: break
                    case .keep(let text): kept.append(Marked(line: index, range: range, text: text, kind: nil))
                    case .secret(let kind, let text):
                        secrets.append(Marked(line: index, range: range, text: text, kind: kind))
                    }
                }
                lines.append(line)
            }
            self.lines = lines
            self.secrets = secrets
            self.kept = kept
        }
    }

    // MARK: Made-up values

    /// The same numbers at every run.
    struct Seeded {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...items.count - 1)] }
        mutating func digits(_ count: Int) -> String { (0..<count).map { _ in String(int(0...9)) }.joined() }
    }

    /// An IBAN with its check digits right: the country, then the account.
    static func iban(_ country: String, _ account: String) -> String {
        let rearranged = account + country + "00"
        var remainder = 0
        for character in rearranged {
            let value = character.isNumber ? Int(String(character))! : Int(character.asciiValue! - 55)
            for digit in String(value) { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        }
        let check = String(format: "%02d", 98 - remainder)
        let whole = country + check + account
        return stride(from: 0, to: whole.count, by: 4).map { start -> String in
            let from = whole.index(whole.startIndex, offsetBy: start)
            let to = whole.index(from, offsetBy: min(4, whole.count - start))
            return String(whole[from..<to])
        }.joined(separator: " ")
    }

    /// A Spanish DNI: eight digits and the letter they call for.
    static func dni(_ number: Int) -> String {
        let letters = Array("TRWAGMYFPDXBNJZSQVHLCKE")
        return String(format: "%08d", number) + String(letters[number % 23])
    }

    /// A Turkish ID number, with its two check digits.
    static func kimlik(_ nine: [Int]) -> String {
        let odd = nine[0] + nine[2] + nine[4] + nine[6] + nine[8]
        let even = nine[1] + nine[3] + nine[5] + nine[7]
        let tenth = ((odd * 7 - even) % 10 + 10) % 10
        let eleventh = (nine.reduce(0, +) + tenth) % 10
        return (nine + [tenth, eleventh]).map(String.init).joined()
    }

    /// A Brazilian CPF, with its two check digits.
    static func cpf(_ nine: [Int]) -> String {
        func check(_ digits: [Int]) -> Int {
            let sum = digits.enumerated().reduce(0) { $0 + $1.element * (digits.count + 1 - $1.offset) }
            let rest = sum % 11
            return rest < 2 ? 0 : 11 - rest
        }
        let first = check(nine)
        let second = check(nine + [first])
        let all = (nine + [first, second]).map(String.init)
        return all[0..<3].joined() + "." + all[3..<6].joined() + "." + all[6..<9].joined() + "-" + all[9...].joined()
    }

    /// A German tax ID: ten digits, one of them twice, and its check digit.
    static func steuerID(_ random: inout Seeded) -> String {
        var pool = Array(0...9)
        pool.remove(at: random.int(0...9))
        var digits = pool
        digits.insert(digits[random.int(0...8)], at: random.int(1...9))
        if digits[0] == 0 { digits.swapAt(0, digits.firstIndex { $0 != 0 }!) }
        var product = 10
        for digit in digits {
            var sum = (digit + product) % 10
            if sum == 0 { sum = 10 }
            product = (sum * 2) % 11
        }
        let check = (11 - product) % 10
        let all = (digits + [check]).map(String.init).joined()
        let parts = [all.prefix(2), all.dropFirst(2).prefix(3), all.dropFirst(5).prefix(3), all.dropFirst(8)]
        return parts.map(String.init).joined(separator: " ")
    }

    // MARK: Languages

    /// What a language's documents say, and the made-up people and places
    /// they name.
    struct Language {
        let code: String
        let first: [String]
        let last: [String]
        let streets: [String]
        /// A street and a number as written there.
        let street: (String, Int) -> String
        let towns: [String]
        let phone: (inout Seeded) -> String
        let iban: (inout Seeded) -> String
        let id: (inout Seeded) -> (label: String, value: String)
        let birth: (label: String, value: String)
        let shop: String
        let practice: String
        let items: [String]
        let money: (Int) -> String
        let date: String
        let mister: String
        let doctor: String
        let words: [String: String]

        func word(_ key: String) -> String { words[key] ?? key }
    }

    static let languages: [Language] = [
        Language(
            code: "de",
            first: ["Lena", "Jonas", "Miriam", "Tobias", "Katrin", "Felix", "Sabine", "Lukas"],
            last: ["Hoffmann", "Becker", "Wagner", "Schulz", "Krüger", "Lorenz", "Brandt", "Vogel"],
            streets: ["Lindenstraße", "Birkenallee", "Kastanienweg", "Rosenstraße", "Ahornring", "Am Mühlbach"],
            street: { "\($0) \($1)" },
            towns: ["10115 Berlin", "50667 Köln", "80331 München", "20095 Hamburg", "04109 Leipzig"],
            phone: { "+49 \($0.pick(["30", "221", "89", "40"])) \($0.digits(7))" },
            iban: { iban("DE", $0.digits(18)) },
            id: { ("Steuer-ID", steuerID(&$0)) },
            birth: ("geb.", "14.03.1987"),
            shop: "Nordlicht Versand GmbH",
            practice: "Praxis am Stadtpark",
            items: ["Druckerpapier A4", "Tintenpatrone Schwarz", "Schreibtischlampe"],
            money: { String(format: "%d,%02d €", $0 / 100, $0 % 100) },
            date: "12.03.2026",
            mister: "Herr",
            doctor: "Dr. med.",
            words: [
                "invoice": "Rechnung", "number": "Rechnungsnr.", "date": "Datum", "customer": "Kunde",
                "item": "Beschreibung", "price": "Preis", "total": "Gesamtbetrag", "pay": "Bitte überweisen auf",
                "phone": "Tel.", "email": "E-Mail", "patient": "Patient", "diagnosis": "Diagnose",
                "illness": "Lumboischialgie links", "report": "wir berichten über unseren gemeinsamen Patienten",
                "regards": "Mit freundlichen Grüßen", "transfer": "Überweisung", "sender": "Auftraggeber",
                "recipient": "Empfänger", "purpose": "Verwendungszweck", "amount": "Betrag",
                "payslip": "Gehaltsabrechnung März 2026", "employee": "Mitarbeiter", "gross": "Bruttogehalt",
                "net": "Nettogehalt", "form": "Anmeldung Sportverein", "name": "Name", "address": "Anschrift",
                "from": "Von", "to": "An", "subject": "Betreff", "subjectText": "Ihre Bestellung",
                "hello": "Hallo", "callMe": "Ruf mich bitte an unter", "codeText": "Dein Bestätigungscode lautet",
                "sendAddress": "Schick es bitte an", "thanks": "Danke!", "bank": "Bankverbindung",
            ]),
        Language(
            code: "en",
            first: ["Emily", "Daniel", "Sarah", "Michael", "Olivia", "James", "Hannah", "Ryan"],
            last: ["Carter", "Brooks", "Turner", "Hughes", "Bennett", "Foster", "Murphy", "Reed"],
            streets: ["Maple Street", "Oak Avenue", "Cedar Lane", "Hillside Drive", "Park Road", "Willow Court"],
            street: { "\($1) \($0)" },
            towns: ["Springfield, IL 62704", "Portland, OR 97205", "Austin, TX 78701", "Denver, CO 80202"],
            phone: { "(\($0.int(201...989))) \($0.int(200...989))-\($0.digits(4))" },
            iban: { iban("GB", "NWBK" + $0.digits(14)) },
            id: { ("SSN", "\($0.int(501...665))-\($0.int(10...99))-\($0.int(1000...9999))") },
            birth: ("Date of birth:", "03/14/1987"),
            shop: "Bluefield Supplies Inc.",
            practice: "Riverside Medical Center",
            items: ["Printer paper A4", "Ink cartridge black", "Desk lamp"],
            money: { String(format: "$%d.%02d", $0 / 100, $0 % 100) },
            date: "03/12/2026",
            mister: "Mr.",
            doctor: "Dr.",
            words: [
                "invoice": "Invoice", "number": "Invoice No.", "date": "Date", "customer": "Customer",
                "item": "Description", "price": "Price", "total": "Total due", "pay": "Please pay to",
                "phone": "Phone", "email": "Email", "patient": "Patient", "diagnosis": "Diagnosis",
                "illness": "type 2 diabetes mellitus", "report": "we are writing about our shared patient",
                "regards": "Kind regards", "transfer": "Bank transfer", "sender": "From account",
                "recipient": "Payee", "purpose": "Reference", "amount": "Amount",
                "payslip": "Payslip March 2026", "employee": "Employee", "gross": "Gross pay", "net": "Net pay",
                "form": "Gym membership form", "name": "Name", "address": "Address", "from": "From", "to": "To",
                "subject": "Subject", "subjectText": "Your order", "hello": "Hi", "callMe": "Please call me at",
                "codeText": "Your verification code is", "sendAddress": "Please send it to", "thanks": "Thanks!",
                "bank": "Bank details",
            ]),
        Language(
            code: "fr",
            first: ["Camille", "Julien", "Chloé", "Mathieu", "Léa", "Nicolas", "Manon", "Thomas"],
            last: ["Martin", "Bernard", "Dubois", "Moreau", "Laurent", "Girard", "Roux", "Fournier"],
            streets: ["rue des Lilas", "avenue Victor Hugo", "rue de la Paix", "boulevard Voltaire", "rue Pasteur"],
            street: { "\($1) \($0)" },
            towns: ["75011 Paris", "69002 Lyon", "13001 Marseille", "31000 Toulouse"],
            phone: { "06 \($0.digits(2)) \($0.digits(2)) \($0.digits(2)) \($0.digits(2))" },
            iban: { iban("FR", $0.digits(23)) },
            id: { random in
                let number = "1 87 03 75 \(random.digits(3)) \(random.digits(3))"
                return ("N° de sécurité sociale :", number)
            },
            birth: ("né le", "14/03/1987"),
            shop: "Atelier Lumière SARL",
            practice: "Cabinet médical des Tilleuls",
            items: ["Papier A4", "Cartouche d'encre noire", "Lampe de bureau"],
            money: { String(format: "%d,%02d €", $0 / 100, $0 % 100) },
            date: "12/03/2026",
            mister: "M.",
            doctor: "Dr",
            words: [
                "invoice": "Facture", "number": "Facture n°", "date": "Date", "customer": "Client",
                "item": "Description", "price": "Prix", "total": "Total à payer", "pay": "Merci de régler sur",
                "phone": "Tél.", "email": "E-mail", "patient": "Patient", "diagnosis": "Diagnostic",
                "illness": "hypertension artérielle", "report": "nous vous adressons notre patient commun",
                "regards": "Bien cordialement", "transfer": "Virement", "sender": "Donneur d'ordre",
                "recipient": "Bénéficiaire", "purpose": "Motif", "amount": "Montant",
                "payslip": "Bulletin de paie mars 2026", "employee": "Salarié", "gross": "Salaire brut",
                "net": "Net à payer", "form": "Inscription au club", "name": "Nom", "address": "Adresse",
                "from": "De", "to": "À", "subject": "Objet", "subjectText": "Votre commande", "hello": "Salut",
                "callMe": "Appelle-moi au", "codeText": "Ton code de vérification est",
                "sendAddress": "Envoie-le à", "thanks": "Merci !", "bank": "Coordonnées bancaires",
            ]),
        Language(
            code: "es",
            first: ["Lucía", "Javier", "Carmen", "Pablo", "Elena", "Diego", "Marta", "Sergio"],
            last: ["García", "Martínez", "López", "Sánchez", "Romero", "Navarro", "Torres", "Ruiz"],
            streets: ["Calle Mayor", "Calle de Alcalá", "Avenida del Puerto", "Calle Serrano", "Paseo del Prado"],
            street: { "\($0) \($1)" },
            towns: ["28013 Madrid", "08001 Barcelona", "46001 Valencia", "41001 Sevilla"],
            phone: { "6\($0.digits(2)) \($0.digits(3)) \($0.digits(3))" },
            iban: { iban("ES", $0.digits(20)) },
            id: { ("DNI:", dni($0.int(10_000_000...89_999_999))) },
            birth: ("Fecha de nacimiento:", "14/03/1987"),
            shop: "Suministros Atlántico S.L.",
            practice: "Clínica San Rafael",
            items: ["Papel A4", "Cartucho de tinta negro", "Lámpara de escritorio"],
            money: { String(format: "%d,%02d €", $0 / 100, $0 % 100) },
            date: "12/03/2026",
            mister: "Sr.",
            doctor: "Dr.",
            words: [
                "invoice": "Factura", "number": "Factura n.º", "date": "Fecha", "customer": "Cliente",
                "item": "Descripción", "price": "Precio", "total": "Total a pagar", "pay": "Transferir a",
                "phone": "Tel.", "email": "Correo", "patient": "Paciente", "diagnosis": "Diagnóstico",
                "illness": "asma bronquial", "report": "le remitimos a nuestro paciente común",
                "regards": "Atentamente", "transfer": "Transferencia", "sender": "Ordenante",
                "recipient": "Beneficiario", "purpose": "Concepto", "amount": "Importe",
                "payslip": "Nómina marzo 2026", "employee": "Trabajador", "gross": "Salario bruto",
                "net": "Líquido a percibir", "form": "Inscripción al gimnasio", "name": "Nombre",
                "address": "Dirección", "from": "De", "to": "Para", "subject": "Asunto",
                "subjectText": "Tu pedido", "hello": "Hola", "callMe": "Llámame al",
                "codeText": "Tu código de verificación es", "sendAddress": "Envíalo a", "thanks": "¡Gracias!",
                "bank": "Datos bancarios",
            ]),
        Language(
            code: "tr",
            first: ["Elif", "Mehmet", "Zeynep", "Emre", "Ayşe", "Burak", "Selin", "Can"],
            last: ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Aydın", "Öztürk", "Arslan"],
            streets: ["Atatürk Caddesi", "Bağdat Caddesi", "Gül Sokak", "Çiçek Sokak", "İnönü Caddesi"],
            street: { "\($0) No: \($1)" },
            towns: ["34710 Kadıköy/İstanbul", "06420 Çankaya/Ankara", "35210 Konak/İzmir"],
            phone: { "05\($0.digits(2)) \($0.digits(3)) \($0.digits(2)) \($0.digits(2))" },
            iban: { iban("TR", $0.digits(5) + "0" + $0.digits(16)) },
            id: { random in ("T.C. Kimlik No:", kimlik([random.int(1...9)] + (0..<8).map { _ in random.int(0...9) })) },
            birth: ("Doğum tarihi:", "14.03.1987"),
            shop: "Deniz Ticaret A.Ş.",
            practice: "Moda Sağlık Merkezi",
            items: ["A4 fotokopi kağıdı", "Siyah mürekkep kartuşu", "Masa lambası"],
            money: { String(format: "%d,%02d TL", $0 / 100, $0 % 100) },
            date: "12.03.2026",
            mister: "Sayın",
            doctor: "Dr.",
            words: [
                "invoice": "Fatura", "number": "Fatura No", "date": "Tarih", "customer": "Müşteri",
                "item": "Açıklama", "price": "Fiyat", "total": "Genel toplam", "pay": "Ödeme hesabı",
                "phone": "Tel", "email": "E-posta", "patient": "Hasta", "diagnosis": "Tanı",
                "illness": "tip 2 diyabet", "report": "ortak hastamız hakkında bilgi veriyoruz",
                "regards": "Saygılarımızla", "transfer": "Havale", "sender": "Gönderen", "recipient": "Alıcı",
                "purpose": "Açıklama", "amount": "Tutar", "payslip": "Mart 2026 maaş bordrosu",
                "employee": "Personel", "gross": "Brüt ücret", "net": "Net ücret", "form": "Spor kulübü kaydı",
                "name": "Ad Soyad", "address": "Adres", "from": "Kimden", "to": "Kime", "subject": "Konu",
                "subjectText": "Siparişiniz", "hello": "Merhaba", "callMe": "Beni şu numaradan ara",
                "codeText": "Doğrulama kodun", "sendAddress": "Şu adrese gönder", "thanks": "Teşekkürler!",
                "bank": "Banka bilgileri",
            ]),
        Language(
            code: "ar",
            first: ["محمد", "أحمد", "فاطمة", "ليلى", "يوسف", "مريم", "خالد", "سارة"],
            last: ["الحداد", "الخطيب", "منصور", "العلي", "الشامي", "النجار", "عيسى", "سليمان"],
            streets: ["شارع الملك فهد", "شارع العليا", "شارع التحلية", "طريق الملك عبدالله"],
            street: { "\($0) \($1)" },
            towns: ["الرياض 12271", "جدة 21577", "الدمام 32241"],
            phone: { "+966 5\($0.digits(1)) \($0.digits(3)) \($0.digits(4))" },
            iban: { iban("SA", $0.digits(20)) },
            id: { ("رقم الهوية:", "1" + $0.digits(9)) },
            birth: ("تاريخ الميلاد:", "14/03/1987"),
            shop: "شركة النخيل للتجارة",
            practice: "مستشفى الأمل",
            items: ["ورق طباعة A4", "خرطوشة حبر سوداء", "مصباح مكتب"],
            money: { String(format: "%d.%02d ر.س", $0 / 100, $0 % 100) },
            date: "12/03/2026",
            mister: "السيد",
            doctor: "د.",
            words: [
                "invoice": "فاتورة", "number": "رقم الفاتورة", "date": "التاريخ", "customer": "العميل",
                "item": "الوصف", "price": "السعر", "total": "المبلغ الإجمالي", "pay": "يرجى التحويل إلى",
                "phone": "هاتف", "email": "البريد الإلكتروني", "patient": "المريض", "diagnosis": "التشخيص",
                "illness": "ارتفاع ضغط الدم", "report": "نفيدكم بحالة مريضنا المشترك",
                "regards": "مع خالص التحية", "transfer": "حوالة بنكية", "sender": "المحوِّل",
                "recipient": "المستفيد", "purpose": "الغرض", "amount": "المبلغ",
                "payslip": "كشف راتب مارس 2026", "employee": "الموظف", "gross": "الراتب الإجمالي",
                "net": "صافي الراتب", "form": "استمارة تسجيل النادي", "name": "الاسم", "address": "العنوان",
                "from": "من", "to": "إلى", "subject": "الموضوع", "subjectText": "طلبك", "hello": "مرحبا",
                "callMe": "اتصل بي على", "codeText": "رمز التحقق الخاص بك هو", "sendAddress": "أرسله إلى",
                "thanks": "شكرا!", "bank": "البيانات البنكية",
            ]),
        Language(
            code: "pt",
            first: ["Ana", "João", "Beatriz", "Pedro", "Mariana", "Lucas", "Juliana", "Rafael"],
            last: ["Silva", "Santos", "Oliveira", "Souza", "Costa", "Pereira", "Almeida", "Ferreira"],
            streets: ["Rua das Flores", "Avenida Paulista", "Rua Augusta", "Rua da Consolação", "Avenida Atlântica"],
            street: { "\($0), \($1)" },
            towns: ["01310-100 São Paulo - SP", "22021-001 Rio de Janeiro - RJ", "30130-010 Belo Horizonte - MG"],
            phone: { "(11) 9\($0.digits(4))-\($0.digits(4))" },
            iban: { iban("BR", $0.digits(23) + "C1") },
            id: { random in ("CPF:", cpf((0..<9).map { _ in random.int(0...9) })) },
            birth: ("Data de nascimento:", "14/03/1987"),
            shop: "Distribuidora Horizonte Ltda.",
            practice: "Clínica Bem Viver",
            items: ["Papel A4", "Cartucho de tinta preto", "Luminária de mesa"],
            money: { String(format: "R$ %d,%02d", $0 / 100, $0 % 100) },
            date: "12/03/2026",
            mister: "Sr.",
            doctor: "Dr.",
            words: [
                "invoice": "Nota fiscal", "number": "Nota n.º", "date": "Data", "customer": "Cliente",
                "item": "Descrição", "price": "Preço", "total": "Total a pagar", "pay": "Depositar em",
                "phone": "Tel.", "email": "E-mail", "patient": "Paciente", "diagnosis": "Diagnóstico",
                "illness": "hipertensão arterial", "report": "informamos sobre nosso paciente em comum",
                "regards": "Atenciosamente", "transfer": "Transferência", "sender": "Remetente",
                "recipient": "Favorecido", "purpose": "Descrição", "amount": "Valor",
                "payslip": "Holerite março 2026", "employee": "Funcionário", "gross": "Salário bruto",
                "net": "Salário líquido", "form": "Ficha de inscrição da academia", "name": "Nome",
                "address": "Endereço", "from": "De", "to": "Para", "subject": "Assunto",
                "subjectText": "Seu pedido", "hello": "Oi", "callMe": "Me liga no",
                "codeText": "Seu código de verificação é", "sendAddress": "Manda para", "thanks": "Obrigado!",
                "bank": "Dados bancários",
            ]),
    ]

    // MARK: Documents

    /// A made-up person: a name, where they live and how to reach them.
    struct Person {
        let first: String
        let last: String
        let street: String
        let town: String
        let phone: String
        let email: String
        var name: String { "\(first) \(last)" }
    }

    static func person(_ language: Language, _ random: inout Seeded) -> Person {
        let first = random.pick(language.first), last = random.pick(language.last)
        let street = language.street(random.pick(language.streets), random.int(2...148))
        let town = random.pick(language.towns)
        let phone = language.phone(&random)
        let user = latin(first) + "." + latin(last)
        let email = "\(user)\(random.int(1...99))@\(random.pick(["mail.example", "post.example", "example.net"]))"
        return Person(first: first, last: last, street: street, town: town, phone: phone, email: email)
    }

    /// A name in Latin letters for an email address.
    static func latin(_ text: String) -> String {
        let arabic: [String: String] = [
            "محمد": "mohammed", "أحمد": "ahmed", "فاطمة": "fatima", "ليلى": "layla", "يوسف": "youssef",
            "مريم": "maryam", "خالد": "khaled", "سارة": "sara", "الحداد": "alhaddad", "الخطيب": "alkhatib",
            "منصور": "mansour", "العلي": "alali", "الشامي": "alshami", "النجار": "alnajjar", "عيسى": "issa",
            "سليمان": "suleiman",
        ]
        if let word = arabic[text] { return word }
        return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .lowercased().replacingOccurrences(of: "ı", with: "i")
    }

    /// Every document, the same at every run.
    static var documents: [Document] {
        var random = Seeded(20_261_028)
        var all: [Document] = []
        for language in languages {
            for _ in 0..<2 {
                all.append(invoice(language, &random))
                all.append(letter(language, &random))
                all.append(transfer(language, &random))
                all.append(payslip(language, &random))
                all.append(chat(language, &random))
                all.append(email(language, &random))
                all.append(form(language, &random))
            }
        }
        return all
    }

    static func invoice(_ l: Language, _ random: inout Seeded) -> Document {
        let customer = person(l, &random)
        let prices = (0..<3).map { _ in random.int(390...12_990) }
        let number = "RE-2026-\(random.digits(4))"
        var rows: [[Part]] = [
            [.keep(l.shop)],
            [.keep(l.word("invoice"))],
            ["\(l.word("number")) ", .keep(number)],
            ["\(l.word("date")): ", .keep(l.date)],
            ["\(l.word("customer")): ", .secret(Kind.names, customer.name)],
            [.secret(Kind.addresses, customer.street)],
            [.secret(Kind.addresses, customer.town)],
            ["\(l.word("email")): ", .secret(Kind.emails, customer.email)],
            [.keep(l.word("item")), " ", .keep(l.word("price"))],
        ]
        for (item, price) in zip(l.items, prices) {
            rows.append([.keep(item), " ", .keep(l.money(price))])
        }
        rows.append(["\(l.word("total")): ", .keep(l.money(prices.reduce(0, +)))])
        rows.append(["\(l.word("pay")): ", .secret(Kind.bank, l.iban(&random))])
        return Document(l.code, "invoice", rows)
    }

    static func letter(_ l: Language, _ random: inout Seeded) -> Document {
        let patient = person(l, &random)
        let doctor = "\(random.pick(l.first)) \(random.pick(l.last))"
        let rows: [[Part]] = [
            [.keep(l.practice)],
            [.plain(l.doctor + " "), .secret(Kind.names, doctor)],
            ["\(l.word("date")): ", .keep(l.date)],
            ["\(l.word("patient")): ", .secret(Kind.names, patient.name), ", \(l.birth.label) ",
             .secret(Kind.birthDates, l.birth.value)],
            [.secret(Kind.addresses, patient.street), ", ", .secret(Kind.addresses, patient.town)],
            [.plain(l.word("report") + ".")],
            ["\(l.word("diagnosis")): ", .secret(Kind.health, l.word("illness"))],
            [.keep(l.word("regards"))],
            [.plain(l.doctor + " "), .secret(Kind.names, doctor)],
        ]
        return Document(l.code, "medical letter", rows)
    }

    static func transfer(_ l: Language, _ random: inout Seeded) -> Document {
        let sender = person(l, &random), recipient = person(l, &random)
        let rows: [[Part]] = [
            [.keep(l.word("transfer"))],
            ["\(l.word("sender")): ", .secret(Kind.names, sender.name)],
            ["IBAN: ", .secret(Kind.bank, l.iban(&random))],
            ["\(l.word("recipient")): ", .secret(Kind.names, recipient.name)],
            ["IBAN: ", .secret(Kind.bank, l.iban(&random))],
            ["\(l.word("amount")): ", .keep(l.money(random.int(1_000...99_000)))],
            ["\(l.word("purpose")): ", .keep("\(l.word("invoice")) \(random.digits(6))")],
            ["\(l.word("date")): ", .keep(l.date)],
        ]
        return Document(l.code, "transfer", rows)
    }

    static func payslip(_ l: Language, _ random: inout Seeded) -> Document {
        let employee = person(l, &random)
        let id = l.id(&random)
        let gross = random.int(250_000...650_000)
        let rows: [[Part]] = [
            [.keep(l.shop)],
            [.keep(l.word("payslip"))],
            ["\(l.word("employee")): ", .secret(Kind.names, employee.name)],
            [.secret(Kind.addresses, employee.street)],
            [.secret(Kind.addresses, employee.town)],
            ["\(id.label) ", .secret(Kind.ids, id.value)],
            ["\(l.word("gross")): ", .keep(l.money(gross))],
            ["\(l.word("net")): ", .keep(l.money(gross * 64 / 100))],
            ["\(l.word("bank")): ", .secret(Kind.bank, l.iban(&random))],
        ]
        return Document(l.code, "payslip", rows)
    }

    static func chat(_ l: Language, _ random: inout Seeded) -> Document {
        let one = person(l, &random), other = person(l, &random)
        let code = random.digits(6)
        let rows: [[Part]] = [
            [.secret(Kind.names, one.first), ": \(l.word("hello")) ", .secret(Kind.names, other.first), "!"],
            [.secret(Kind.names, other.first), ": \(l.word("callMe")) ", .secret(Kind.phones, other.phone)],
            [.secret(Kind.names, one.first), ": \(l.word("sendAddress")) ", .secret(Kind.addresses, one.street), ", ",
             .secret(Kind.addresses, one.town)],
            [.secret(Kind.names, other.first), ": \(l.word("codeText")) ", .secret(Kind.codes, code)],
            [.secret(Kind.names, one.first), ": \(l.word("thanks"))"],
        ]
        return Document(l.code, "chat", rows)
    }

    static func email(_ l: Language, _ random: inout Seeded) -> Document {
        let sender = person(l, &random), recipient = person(l, &random)
        let rows: [[Part]] = [
            ["\(l.word("from")): ", .secret(Kind.names, sender.name), " <", .secret(Kind.emails, sender.email), ">"],
            ["\(l.word("to")): ", .secret(Kind.names, recipient.name), " <",
             .secret(Kind.emails, recipient.email), ">"],
            ["\(l.word("subject")): ", .keep(l.word("subjectText"))],
            ["\(l.word("hello")) ", .secret(Kind.names, recipient.first), ","],
            ["\(l.word("callMe")) ", .secret(Kind.phones, sender.phone), "."],
            [.keep(l.word("regards"))],
            [.secret(Kind.names, sender.name)],
            [.secret(Kind.addresses, sender.street), ", ", .secret(Kind.addresses, sender.town)],
        ]
        return Document(l.code, "email", rows)
    }

    static func form(_ l: Language, _ random: inout Seeded) -> Document {
        let member = person(l, &random)
        let id = l.id(&random)
        let rows: [[Part]] = [
            [.keep(l.word("form"))],
            ["\(l.word("name")): ", .secret(Kind.names, member.name)],
            ["\(l.birth.label) ", .secret(Kind.birthDates, l.birth.value)],
            ["\(l.word("address")): ", .secret(Kind.addresses, member.street), ", ",
             .secret(Kind.addresses, member.town)],
            ["\(l.word("phone")): ", .secret(Kind.phones, member.phone)],
            ["\(l.word("email")): ", .secret(Kind.emails, member.email)],
            ["\(id.label) ", .secret(Kind.ids, id.value)],
            ["\(l.word("bank")): ", .secret(Kind.bank, l.iban(&random))],
        ]
        return Document(l.code, "form", rows)
    }
}
