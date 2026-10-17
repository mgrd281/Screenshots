import Foundation

/// The details of an order read off a screenshot, for the order card: the
/// order number, the date, the total, who it is for and how it is sent,
/// each ready to copy. Read on the device, from what the kinds of private
/// detail find, so it holds the details as they are, not covered.
enum OrderCard {
    enum Part: CaseIterable {
        case order, date, total, name, address, email, phone, tracking, code

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
        values[.code] = codes.first.map { $0.split(whereSeparator: \.isNewline).joined(separator: " · ") }
        return Part.allCases.compactMap { part in values[part].map { Field(part: part, value: $0) } }
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
