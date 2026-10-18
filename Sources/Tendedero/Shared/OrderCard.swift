import Foundation

/// The details of an order read off a screenshot, for the order card: the
/// order number, the date, the total, who it is for and how it is sent,
/// each ready to copy. Read on the device, from what the kinds of private
/// detail find, so it holds the details as they are, not covered.
enum OrderCard {
    enum Part: CaseIterable {
        /// What was bought comes last, so a row's columns stay where they were;
        /// only the AI assistant reads it.
        case order, date, total, name, address, email, phone, tracking, code, product

        var label: String {
            switch self {
            case .order: L("Order")
            case .date: L("Date")
            case .total: L("Total")
            case .name: L("Name")
            case .address: L("Address")
            case .email: L("Email")
            case .phone: L("Phone")
            case .tracking: L("Tracking number")
            case .code: L("Code")
            case .product: L("Product")
            }
        }
    }

    struct Field: Equatable, Identifiable {
        let part: Part
        let value: String
        var id: Part { part }
        var label: String { part.label }
    }

    /// Words that stand before the amount to pay, in the languages
    /// screenshots tend to come in.
    private static let totalWords = ["gesamt", "summe", "endbetrag", "zu zahlen", "rechnungsbetrag", "betrag",
                                     "total", "amount due", "grand total", "balance due",
                                     "المجموع", "الإجمالي", "المبلغ"]

    /// From what the kinds found, top to bottom, with the lines they are
    /// on: each part the first one found, but the address, which is every
    /// line of it, and the total, which is the amount by a word like
    /// "Total", else the largest. A code adds what it says.
    static func fields(from found: [(kind: PrivateDetail, text: String, line: Int)], lines: [String],
                       codes: [String] = []) -> [Field] {
        func first(_ kind: PrivateDetail) -> String? { found.first { $0.kind == kind }?.text }
        var values: [Part: String] = [:]
        values[.order] = first(.orders)
        values[.date] = first(.dates)
        values[.total] = total(of: found.filter { $0.kind == .amounts }, lines: lines)
        values[.name] = first(.names)
        let address = found.filter { $0.kind == .addresses }.map(\.text)
        if !address.isEmpty { values[.address] = address.joined(separator: ", ") }
        values[.email] = first(.emails)
        values[.phone] = first(.phones)
        values[.tracking] = first(.tracking)
        if let code = codes.first {
            // A transfer reads as who is paid, the account, the amount and
            // what for; its amount is the total when the text has none.
            if let payment = payment(in: code) {
                values[.code] = payment.summary
                if values[.total] == nil, !payment.amount.isEmpty { values[.total] = payment.amount }
            } else {
                values[.code] = code.split(whereSeparator: \.isNewline).joined(separator: " · ")
            }
        }
        return Part.allCases.compactMap { part in values[part].map { Field(part: part, value: $0) } }
    }

    /// A transfer a code holds: the GiroCode of European banks or the Swiss
    /// QR bill.
    struct Payment: Equatable {
        var name = ""
        var iban = ""
        var amount = ""
        var reference = ""

        /// "DE89 3704 0044 0532 0130 00 · Lena Hoffmann · EUR 74.00 · RE-1024"
        var summary: String {
            let account = stride(from: 0, to: iban.count, by: 4).map { start -> String in
                let from = iban.index(iban.startIndex, offsetBy: start)
                return String(iban[from..<(iban.index(from, offsetBy: 4, limitedBy: iban.endIndex) ?? iban.endIndex)])
            }.joined(separator: " ")
            return [account, name, amount, reference].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// The transfer in a code's text, line by line as the two formats lay
    /// it out; nil for anything else, or one without an account.
    static func payment(in payload: String) -> Payment? {
        let lines = payload.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func line(_ i: Int) -> String {
            lines.indices.contains(i) ? lines[i].trimmingCharacters(in: .whitespaces) : ""
        }
        var payment: Payment
        switch line(0) {
        case "BCD":
            // EPC: version, characters, SCT, BIC, name, IBAN, amount like
            // "EUR74.00", purpose, reference, text.
            var amount = line(7)
            if amount.count > 3, amount.prefix(3).allSatisfy(\.isLetter) {
                amount = String(amount.prefix(3)) + " " + String(amount.dropFirst(3))
            }
            payment = Payment(name: line(5), iban: line(6), amount: amount,
                              reference: line(9).isEmpty ? line(10) : line(9))
        case "SPC":
            // Swiss: version, coding, IBAN, the creditor's seven lines, seven
            // empty ones, amount, currency, the debtor's seven, then the
            // reference's type, the reference and a message.
            payment = Payment(name: line(5), iban: line(3),
                              amount: line(18).isEmpty ? "" : line(19) + " " + line(18),
                              reference: line(28).isEmpty ? line(29) : line(28))
        default:
            return nil
        }
        payment.iban = payment.iban.filter { !$0.isWhitespace }
        return payment.iban.isEmpty ? nil : payment
    }

    /// The amount to pay: the one on a line with a word like "Total", the
    /// last of those, else the largest amount.
    static func total(of amounts: [(kind: PrivateDetail, text: String, line: Int)], lines: [String]) -> String? {
        let marked = amounts.filter { amount in
            guard lines.indices.contains(amount.line) else { return false }
            let line = lines[amount.line].lowercased()
            return totalWords.contains { line.contains($0) }
        }
        if let last = marked.last { return last.text }
        return amounts.max { (value(of: $0.text) ?? 0) < (value(of: $1.text) ?? 0) }?.text
    }

    /// What an amount like "1.250,00 €" or "$1,250.00" comes to. The last
    /// comma or point is the decimal one when two digits or fewer follow it.
    static func value(of amount: String) -> Double? {
        let digits = amount.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard let mark = digits.lastIndex(where: { $0 == "," || $0 == "." }) else { return Double(digits) }
        let after = String(digits[digits.index(after: mark)...])
        let whole = String(digits[..<mark].filter(\.isNumber))
        if after.count <= 2, !after.isEmpty {
            return Double(whole + "." + after)
        }
        return Double(digits.filter(\.isNumber))
    }

    /// Every part's value in one row, in a fixed order with empty cells for
    /// what was not found, separated by tabs: a row to paste into a
    /// spreadsheet.
    static func row(_ fields: [Field]) -> String {
        Part.allCases.map { part in fields.first { $0.part == part }?.value ?? "" }.joined(separator: "\t")
    }

    /// The fields as lines of "Label: value", to copy all at once.
    static func text(_ fields: [Field]) -> String {
        fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }
}
