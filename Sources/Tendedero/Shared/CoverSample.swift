import Foundation

/// A made-up invoice's lines, as the iPhone's Cover Style page covers them
/// in its preview: what shows of each with Keep the last four digits and
/// Strongest protection, worked out as the covering works it out.
struct CoverSampleLine: Identifiable, Equatable {
    /// What stands before the value, like "IBAN"; nil when the value is
    /// the line alone.
    let label: String?
    let value: String
    let kind: PrivateDetail

    var id: String { value }

    /// "Rechnung an", then a name, an IBAN and a phone number, the ones
    /// banks and phone books print as examples.
    static let invoice = [
        CoverSampleLine(label: nil, value: "Max Mustermann", kind: .names),
        CoverSampleLine(label: L("IBAN"), value: "DE89 3704 0044 0532 0130 00", kind: .bank),
        CoverSampleLine(label: L("Phone"), value: "+49 170 1234567", kind: .phones),
    ]

    /// The value split where its cover ends: the part covered, and the last
    /// four digits Keep the last four digits leaves, which Strongest
    /// protection covers too, with the whole line (`Finder.keepingLastDigits`).
    func split(keepsLastDigits: Bool, strongest: Bool) -> (covered: String, kept: String) {
        guard keepsLastDigits, !strongest, Finder.lastDigitKinds.contains(kind),
              let range = Finder.keepingLastDigits(NSRange(location: 0, length: (value as NSString).length), in: value)
        else { return (value, "") }
        let text = value as NSString
        return (text.substring(to: range.location + range.length), text.substring(from: range.location + range.length))
    }
}
