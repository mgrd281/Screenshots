import Foundation

/// The owner's own details (`OwnRule.Kind.details`): found in a line of
/// text however they are written there, shown with most of them hidden, and
/// checked while they are typed. A name in every form; an address's street
/// with its house number, and its postcode with its town; a card's number,
/// whole or by its last four digits after a mask; an account's IBAN, with
/// or without spaces, and a German or Austrian account's number. Pure text,
/// so it is checked without a picture, on Linux too.
enum OwnDetails {
    // MARK: Finding them

    /// Where the owner's details stand in text of many lines, as ranges of
    /// the whole. Each is looked for within a line.
    static func ranges(in full: String, _ rules: [OwnRule]) -> [NSRange] {
        let details = rules.filter { $0.kind.isDetail && !$0.isBlank }
        guard !details.isEmpty else { return [] }
        var found: [NSRange] = []
        var offset = 0
        for line in full.components(separatedBy: "\n") {
            for detail in details {
                for range in ranges(in: line, of: detail) {
                    let place = NSRange(range, in: line)
                    found.append(NSRange(location: place.location + offset, length: place.length))
                }
            }
            offset += line.utf16.count + 1
        }
        return found
    }

    /// A line with the owner's details in it hidden, as it is sent to the
    /// AI assistant: they are covered anyway, so they never leave.
    static func masking(_ line: String, _ rules: [OwnRule]) -> String {
        let places = rules.filter { $0.kind.isDetail && !$0.isBlank }.flatMap { ranges(in: line, of: $0) }
            .sorted { $0.lowerBound > $1.lowerBound }
        var masked = line
        var below = masked.endIndex
        for place in places where place.upperBound <= below {
            masked.replaceSubrange(place, with: "•••")
            below = place.lowerBound
        }
        return masked
    }

    /// Where one of the owner's details stands in one line, each place once.
    static func ranges(in line: String, of detail: OwnRule) -> [Range<String.Index>] {
        let found: [Range<String.Index>] = switch detail.kind {
        case .name: name(detail.text, in: line)
        case .address: address(detail, in: line)
        case .card: card(digits(detail.text), in: line)
        case .account: account(compact(iban: detail.text), in: line)
        case .word, .label, .pattern: []
        }
        var seen = Set<Range<String.Index>>()
        return found.filter { seen.insert($0).inserted }
    }

    // MARK: Names

    /// The ways a name is written, each as its words folded: as typed,
    /// surname first, with the first given name alone, with its initial,
    /// and the surname or the first given name on its own. "Musterfrau,
    /// Erika", typed with a comma, is surname first.
    static func nameForms(_ text: String) -> [[String]] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let surnameFirst = typed.contains(",")
        let words = words(of: typed.replacingOccurrences(of: ",", with: " "))
        guard !words.isEmpty else { return [] }
        guard words.count > 1 else { return [words] }
        // The surname is the last word with the particles before it, as "van Berg".
        var split = words.count - 1
        if surnameFirst {
            split = typed.split(separator: ",", maxSplits: 1).first.map { Self.words(of: String($0)).count } ?? 1
        } else {
            while split > 1, particles.contains(words[split - 1]) { split -= 1 }
        }
        let surname = surnameFirst ? Array(words[..<split]) : Array(words[split...])
        let given = surnameFirst ? Array(words[split...]) : Array(words[..<split])
        guard let first = given.first, let core = surname.last else { return [words] }
        let initial = String(first.prefix(1))
        var forms: [[String]] = [given + surname, surname + given]
        forms += [[first] + surname, surname + [first], [initial] + surname, surname + [initial], [core]]
        // A short given name alone is too often a word, like "Max" in "Max. 5".
        if first.count >= 4 { forms.append([first]) }
        // Each once, the longest first.
        var seen = Set<[String]>()
        forms = forms.filter { !$0.isEmpty && seen.insert($0).inserted }
        return forms.sorted { $0.count > $1.count }
    }

    /// Words that join a surname, as "von" in "von Weizsäcker".
    private static let particles: Set<String> = ["von", "van", "de", "der", "den", "del", "della", "di", "da", "du",
                                                 "le", "la", "al", "el", "bin", "ibn", "ter", "ten", "zu", "zum", "zur"]

    private static func name(_ text: String, in line: String) -> [Range<String.Index>] {
        let forms = nameForms(text)
        guard !forms.isEmpty else { return [] }
        let tokens = tokens(in: line)
        var found: [Range<String.Index>] = []
        var i = 0
        while i < tokens.count {
            var matched = 0
            for form in forms where i + form.count <= tokens.count && fits(form, tokens[i..<i + form.count], in: line) {
                matched = form.count
                break
            }
            if matched > 0 {
                found.append(tokens[i].range.lowerBound..<tokens[i + matched - 1].range.upperBound)
                i += matched
            } else {
                i += 1
            }
        }
        return found
    }

    /// Whether these words of a line are this form of the name: each word
    /// the same, read as loosely as a misread letter in a word of five
    /// letters or more beside the rest of the name, or of seven alone, with
    /// no more than a comma, a dot and a space between them. A word alone
    /// counts when it begins with a capital, so "koch" in a sentence is a
    /// word; an initial, only beside the surname.
    private static func fits(_ form: [String], _ tokens: ArraySlice<Token>, in line: String) -> Bool {
        let loosely = form.count == 1 ? 7 : 5
        for (word, token) in zip(form, tokens) {
            guard word == token.folded
                || min(word.count, token.folded.count) >= loosely && Finder.differsByOne(word, token.folded) else { return false }
        }
        if form.count == 1 {
            guard let token = tokens.first, form[0].count >= 3,
                  line[token.range].first?.isUppercase == true else { return false }
            return true
        }
        var previous: Token?
        for token in tokens {
            if let previous {
                let gap = line[previous.range.upperBound..<token.range.lowerBound]
                guard gap.count <= 3, gap.allSatisfy({ $0 == " " || $0 == "," || $0 == "." }) else { return false }
            }
            previous = token
        }
        return true
    }

    /// A word of a line, where it is and how it is compared.
    private struct Token {
        let range: Range<String.Index>
        let folded: String
    }

    /// The words of a line: letters, with an apostrophe or a hyphen inside.
    private static func tokens(in line: String) -> [Token] {
        let whole = NSRange(line.startIndex..., in: line)
        return wordPattern.matches(in: line, range: whole).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            return Token(range: range, folded: fold(String(line[range])))
        }
    }

    private static let wordPattern = try! NSRegularExpression(pattern: #"\p{L}[\p{L}\p{M}]*(?:['’\-]\p{L}[\p{L}\p{M}]*)*"#)

    /// A name's words as typed, folded, without what stands round them.
    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    /// A word as it is compared: in small letters, without accents,
    /// apostrophes or hyphens, "ß" as "ss".
    static func fold(_ word: String) -> String {
        word.replacingOccurrences(of: "ß", with: "ss").replacingOccurrences(of: "ẞ", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Addresses

    /// A street as typed, as its name and house number: "Kastanienweg 14a"
    /// and "12 rue de la Paix" alike. No number, the street alone.
    static func street(_ text: String) -> (name: String, number: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = #"\d+\s?[A-Za-z]?(?:\s?[-–/]\s?\d+\s?[A-Za-z]?)?"#
        if let found = typed.range(of: #"\s*,?\s*"# + number + "$", options: .regularExpression),
           found.lowerBound > typed.startIndex {
            let part = typed[found].trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            return (String(typed[..<found.lowerBound]), part)
        }
        if let found = typed.range(of: "^" + number + #"\s*,?\s+"#, options: .regularExpression),
           found.upperBound < typed.endIndex {
            let part = typed[found].trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            return (String(typed[found.upperBound...]), part)
        }
        return (typed, "")
    }

    private static func address(_ detail: OwnRule, in line: String) -> [Range<String.Index>] {
        let (name, number) = street(detail.text)
        // Most lines hold neither the house number nor the postcode: those are passed by at once.
        let marks = [digits(number), digits(detail.postcode)].filter { !$0.isEmpty }
        if !marks.isEmpty {
            let read = digits(line)
            guard marks.contains(where: { read.contains($0) }) else { return [] }
        }
        let folded = Folded(line)
        var found: [Range<String.Index>] = []
        let street = Folded(name).chars, house = Folded(number).chars
        if !house.isEmpty, street.count >= 3 {
            found += folded.places(of: street + house, in: line)
            found += folded.places(of: house + street, in: line)
        } else if house.isEmpty, street.count >= 4 {
            found += folded.places(of: street, in: line)
        }
        // The postcode with its town, as on a letter's last address line, never one without the other.
        let postcode = Folded(detail.postcode).chars, city = Folded(detail.city).chars
        if !postcode.isEmpty, !city.isEmpty { found += folded.places(of: postcode + city, in: line) }
        return found
    }

    /// A line as an address is compared: its letters and digits alone, in
    /// small letters, without accents, "ß" as "ss" and "Straße" as "Str",
    /// each with where in the line it came from.
    private struct Folded {
        var chars: [Character] = []
        var starts: [String.Index] = []
        var ends: [String.Index] = []

        init(_ line: String) {
            var i = line.startIndex
            while i < line.endIndex {
                let next = line.index(after: i)
                let c = line[i]
                // Plain letters and digits, as most are, without the cost of folding each.
                let folded: String = c.isASCII ? (c.isLetter || c.isNumber ? c.lowercased() : "") : OwnDetails.fold(String(c))
                for f in folded {
                    chars.append(f)
                    starts.append(i)
                    ends.append(next)
                }
                i = next
            }
            shortenStreets()
        }

        /// "strasse" as "str", as "Str." is written for it.
        private mutating func shortenStreets() {
            let long = Array("strasse")
            var i = 0
            while i + long.count <= chars.count {
                if Array(chars[i..<i + long.count]) == long {
                    let gone = (i + 3)..<(i + long.count)
                    ends[i + 2] = ends[i + long.count - 1]
                    chars.removeSubrange(gone)
                    starts.removeSubrange(gone)
                    ends.removeSubrange(gone)
                    i += 3
                } else {
                    i += 1
                }
            }
        }

        /// Every place these characters stand, whole: not after a letter or
        /// a digit, nor before one, as "Weg 5" in "Kastanienweg 5" or "14"
        /// in "14a".
        func places(of needle: [Character], in line: String) -> [Range<String.Index>] {
            guard !needle.isEmpty, needle.count <= chars.count else { return [] }
            var found: [Range<String.Index>] = []
            var i = 0
            while i + needle.count <= chars.count {
                guard Array(chars[i..<i + needle.count]) == needle else {
                    i += 1
                    continue
                }
                let start = starts[i], end = ends[i + needle.count - 1]
                let before = start > line.startIndex ? line[line.index(before: start)] : nil
                let after = end < line.endIndex ? line[end] : nil
                if before.map({ $0.isLetter || $0.isNumber }) != true, after.map({ $0.isLetter || $0.isNumber }) != true {
                    found.append(start..<end)
                    i += needle.count
                } else {
                    i += 1
                }
            }
            return found
        }
    }

    // MARK: Cards

    /// The digits of what was typed.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    private static func card(_ number: String, in line: String) -> [Range<String.Index>] {
        guard number.count >= 8 else { return [] }
        var found = runs(of: number, in: line)
        let last = String(number.suffix(4))
        guard number.count >= 12, digits(line).contains(last) else { return found }
        // With all but its last four digits hidden: "•••• 4242", "**** **** **** 4242", "XXXX-XXXX-XXXX-4242".
        found += matches(#"(?<![\p{L}\d])(?:[•·∙●*xX#]{2,}[ \-]?){1,4} ?"# + last + #"(?!\d)"#, in: line)
        // Or after the card's name or a word that says so: "Visa 4242", "endet auf 4242".
        found += matches(#"(?i)(?:\b(?:visa|master\s?card|maestro|amex|american express|girocard|discover|diners(?: club)?|jcb|unionpay|v\s?pay)\b|endet auf|endend auf|endet mit|ending in|ends in|ending with|se termine par|terminant par|termina en|terminada en|termina in|terminando em|termina com|ile biten)[\s:]*((?:[•·∙●*xX#]+[ \-]?)*"#
                         + last + #")(?!\d)"#, in: line, group: 1)
        return found
    }

    /// Whether a card's number adds up, as every card's number does.
    static func passesLuhn(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard !values.isEmpty else { return false }
        var sum = 0
        for (i, digit) in values.reversed().enumerated() {
            let doubled = digit * 2
            sum += i % 2 == 1 ? (doubled > 9 ? doubled - 9 : doubled) : digit
        }
        return sum % 10 == 0
    }

    /// The networks a card's number tells, by how it begins.
    enum Brand: String, CaseIterable {
        case visa, mastercard, amex, discover, jcb, diners, unionpay, maestro

        /// The network's own name, written as it writes it.
        var name: String {
            switch self {
            case .visa: "Visa"
            case .mastercard: "Mastercard"
            case .amex: "American Express"
            case .discover: "Discover"
            case .jcb: "JCB"
            case .diners: "Diners Club"
            case .unionpay: "UnionPay"
            case .maestro: "Maestro"
            }
        }
    }

    static func brand(of digits: String) -> Brand? {
        func begins(_ length: Int, _ ranges: ClosedRange<Int>...) -> Bool {
            guard digits.count >= length, let start = Int(digits.prefix(length)) else { return false }
            return ranges.contains { $0.contains(start) }
        }
        if begins(1, 4...4) { return .visa }
        if begins(2, 34...34, 37...37) { return .amex }
        if begins(2, 51...55) || begins(4, 2221...2720) { return .mastercard }
        if begins(4, 6011...6011) || begins(3, 644...649) || begins(2, 65...65) { return .discover }
        if begins(4, 3528...3589) { return .jcb }
        if begins(3, 300...305) || begins(2, 36...36, 38...39) { return .diners }
        if begins(2, 62...62) { return .unionpay }
        if begins(2, 50...50, 56...69) { return .maestro }
        return nil
    }

    /// A card's number in the groups its network prints: four by four,
    /// American Express four, six and five.
    static func grouped(card text: String) -> String {
        let number = digits(text)
        let sizes: [Int]
        switch (brand(of: number), number.count) {
        case (.amex, _): sizes = [4, 6, 5]
        case (.diners, 14): sizes = [4, 6, 4]
        default: sizes = Array(repeating: 4, count: 5)
        }
        var groups: [String] = []
        var rest = Substring(number)
        for size in sizes where !rest.isEmpty {
            groups.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        if !rest.isEmpty { groups.append(String(rest)) }
        return groups.joined(separator: " ")
    }

    /// What is wrong with a card's number as typed; nil while it may yet be right.
    static func cardProblem(_ text: String) -> String? {
        let number = digits(text)
        guard !number.isEmpty else { return nil }
        if number.count > 19 { return L("A card number has 19 digits at most.") }
        if number.count >= 13, !passesLuhn(number) { return L("This card number does not add up. Check it again.") }
        return nil
    }

    // MARK: Accounts

    /// An IBAN as compared: its letters and digits alone, in capitals.
    static func compact(iban text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// An IBAN in groups of four, as a bank prints it.
    static func grouped(iban text: String) -> String {
        var groups: [String] = []
        var rest = Substring(compact(iban: text))
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return groups.joined(separator: " ")
    }

    /// Whether an IBAN is whole and adds up: its country's length, and the
    /// remainder of 97 its check digits leave.
    static func ibanIsValid(_ text: String) -> Bool {
        let iban = compact(iban: text)
        guard iban.count >= 15, iban.count <= 34, iban.prefix(2).allSatisfy(\.isLetter),
              iban.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else { return false }
        if let length = ibanLengths[String(iban.prefix(2))], length != iban.count { return false }
        var remainder = 0
        for c in iban.dropFirst(4) + iban.prefix(4) {
            let value = c.isNumber ? String(c) : String(Int(c.asciiValue ?? 0) - 55)
            for digit in value {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    /// What is wrong with an IBAN as typed; nil while it may yet be right.
    static func ibanProblem(_ text: String) -> String? {
        let iban = compact(iban: text)
        guard iban.count >= 4 else { return nil }
        guard iban.prefix(2).allSatisfy(\.isLetter), iban.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else {
            return L("An IBAN begins with its country’s two letters and two digits, like DE89.")
        }
        let length = ibanLengths[String(iban.prefix(2))] ?? 34
        if iban.count > length { return L("This IBAN is too long.") }
        if iban.count == length || iban.count >= 15 && ibanLengths[String(iban.prefix(2))] == nil, !ibanIsValid(iban) {
            return L("This IBAN does not add up. Check it again.")
        }
        return nil
    }

    /// Each country's IBAN length.
    static let ibanLengths: [String: Int] = [
        "DE": 22, "AT": 20, "CH": 21, "LI": 21, "LU": 20, "NL": 18, "BE": 16, "FR": 27, "IT": 27, "ES": 24, "PT": 25,
        "GB": 22, "IE": 22, "PL": 28, "CZ": 24, "SK": 24, "HU": 28, "SI": 19, "HR": 21, "DK": 18, "SE": 24, "NO": 15,
        "FI": 18, "EE": 20, "LV": 21, "LT": 20, "GR": 27, "CY": 28, "MT": 31, "BG": 22, "RO": 24, "TR": 26, "AE": 23,
        "SA": 24, "QA": 29, "KW": 30, "BH": 22, "JO": 30, "LB": 28, "EG": 29, "MA": 28, "TN": 24, "IL": 23, "UA": 29,
        "RS": 22, "BA": 20, "AL": 28, "MK": 19, "IS": 26,
    ]

    /// A German or Austrian account's number, as statements print it
    /// without its leading zeros; nil for other countries, or one too short
    /// to tell from other numbers.
    static func accountNumber(of text: String) -> String? {
        let iban = compact(iban: text)
        let number: Substring
        switch (iban.prefix(2), iban.count) {
        case ("DE", 22): number = iban.suffix(10)
        case ("AT", 20): number = iban.suffix(11)
        default: return nil
        }
        let plain = String(number.drop { $0 == "0" })
        return plain.count >= 6 && plain.allSatisfy(\.isNumber) ? plain : nil
    }

    private static func account(_ iban: String, in line: String) -> [Range<String.Index>] {
        guard iban.count >= 12 else { return [] }
        var found = runs(of: iban, in: line, letters: true)
        if let number = accountNumber(of: iban) { found += runs(of: number, in: line) }
        guard digits(line).contains(String(iban.suffix(4))) else { return found }
        // With its middle hidden: "DE89 •••• •••• 3000", "DE89 3704 **** **30 00", "IBAN: …3000".
        let head = String(iban.prefix(2)) + #"\s?"# + String(iban.dropFirst(2).prefix(2))
        let tail = iban.suffix(4).map { String($0) }.joined(separator: #"\s?"#)
        found += matches("(?i)(?<![A-Z0-9])" + head + #"[\s\d•·∙●*xX.…]*?[•·∙●*xX…][\s\d•·∙●*xX.…]*?"# + tail + #"(?!\d)"#,
                         in: line)
        found += matches(#"(?i)\biban\b\s*:?\s*((?:[•·∙●*xX…]+\s?)+"# + tail + #")(?!\d)"#, in: line, group: 1)
        return found
    }

    // MARK: Numbers in a line

    /// Every place these digits, or for an IBAN these letters and digits,
    /// stand in a line, in groups or not: with spaces, dashes or dots
    /// between the groups, read as loosely as text recognition reads an O
    /// for a 0; whole, never the middle of a longer number.
    private static func runs(of value: String, in line: String, letters: Bool = false) -> [Range<String.Index>] {
        let wanted = Array(value)
        var found: [Range<String.Index>] = []
        for run in runs(in: line, letters: letters) where run.chars.count >= wanted.count {
            var i = 0
            while i + wanted.count <= run.chars.count {
                let end = i + wanted.count
                if run.starts[i], end == run.chars.count || run.starts[end],
                   zip(wanted, run.chars[i..<end]).enumerated().allSatisfy({ same($1.0, $1.1, letters: letters && $0 >= 2) }) {
                    found.append(run.places[i].lowerBound..<run.places[end - 1].upperBound)
                    i = end
                } else {
                    i += 1
                }
            }
        }
        return found
    }

    /// A run of digits, or of letters and digits, with single separators.
    private struct Run {
        var chars: [Character] = []
        var places: [Range<String.Index>] = []
        /// Whether a group begins with this character.
        var starts: [Bool] = []
    }

    private static func runs(in line: String, letters: Bool) -> [Run] {
        var runs: [Run] = []
        var run = Run()
        var gap = 0
        var i = line.startIndex
        func close() {
            if !run.chars.isEmpty { runs.append(run) }
            run = Run()
            gap = 0
        }
        while i < line.endIndex {
            let next = line.index(after: i)
            let c = line[i]
            if c.isASCII, c.isNumber || letters && c.isLetter {
                run.starts.append(run.chars.isEmpty || gap > 0)
                run.chars.append(Character(c.uppercased()))
                run.places.append(i..<next)
                gap = 0
            } else if !run.chars.isEmpty, gap < 2, " \u{00A0}\u{2009}\u{202F}-.".contains(c) {
                gap += 1
            } else {
                close()
            }
            i = next
        }
        close()
        return runs
    }

    /// Whether a character read is the one wanted; past an IBAN's country,
    /// a letter text recognition reads for a digit counts as that digit.
    private static func same(_ wanted: Character, _ read: Character, letters loosely: Bool) -> Bool {
        if wanted == read { return true }
        guard loosely else { return false }
        let alike: [Character: Character] = ["O": "0", "D": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2"]
        return alike[read] == wanted || alike[wanted] == read
    }

    private static func matches(_ pattern: String, in line: String, group: Int = 0) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            Range(match.range(at: group), in: line)
        }
    }

    // MARK: Keeping one

    /// A detail as kept: without spaces round what was typed, a card's
    /// number as its digits, an IBAN as its letters and digits.
    static func cleaned(_ detail: OwnRule) -> OwnRule {
        var kept = detail
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch detail.kind {
        case .card: kept.text = digits(detail.text)
        case .account: kept.text = compact(iban: detail.text)
        default: kept.text = trim(detail.text)
        }
        kept.postcode = trim(detail.postcode)
        kept.city = trim(detail.city)
        kept.caption = trim(detail.caption)
        return kept
    }

    /// Whether a detail holds enough to cover something: a name, a street
    /// or a postcode with its town, a card's number of eight to nineteen
    /// digits, an IBAN that adds up.
    static func canKeep(_ detail: OwnRule) -> Bool {
        let kept = cleaned(detail)
        switch kept.kind {
        case .name: return !kept.text.isEmpty
        case .address: return !kept.text.isEmpty || !kept.postcode.isEmpty && !kept.city.isEmpty
        case .card: return (8...19).contains(kept.text.count)
        case .account: return ibanIsValid(kept.text)
        case .word, .label, .pattern: return false
        }
    }

    /// What a detail's sheet says under its fields: what is wrong with what
    /// was typed, or how it is covered.
    static func note(for detail: OwnRule) -> (text: String, isProblem: Bool) {
        switch detail.kind {
        case .name:
            let shown = examples(of: detail.text)
            return (shown.isEmpty
                ? L("Covered however it is written: surname first, in capitals, with an initial, or a part of it alone.")
                : String(format: L("Covered however it is written, like %@."), shown.joined(separator: " · ")), false)
        case .address:
            return (L("Covered: the street with its house number, and the postcode with the town where they stand together. A town or a postcode alone is everyone’s, so it stays."), false)
        case .card:
            if let problem = cardProblem(detail.text) { return (problem, true) }
            return (L("Covered whole, however it is grouped, and where only its last four digits show, like “•••• 4242”."), false)
        case .account:
            if let problem = ibanProblem(detail.text) { return (problem, true) }
            return (L("Covered with and without spaces, where only its last digits show, and a German or Austrian account’s number on its own."), false)
        case .word, .label, .pattern:
            return ("", false)
        }
    }

    // MARK: As shown

    /// A detail as a row shows it, most of a number hidden: "Visa", "•••• 4242".
    static func title(of detail: OwnRule) -> String {
        let caption = detail.caption.trimmingCharacters(in: .whitespaces)
        if !caption.isEmpty { return caption }
        if detail.kind == .card, let brand = brand(of: digits(detail.text)) { return brand.name }
        return detail.kind.title
    }

    static func summary(of detail: OwnRule) -> String {
        switch detail.kind {
        case .card:
            let number = digits(detail.text)
            return number.count >= 4 ? "•••• " + String(number.suffix(4)) : number
        case .account:
            let iban = compact(iban: detail.text)
            return iban.count >= 8 ? String(iban.prefix(4)) + " •••• " + String(iban.suffix(4)) : iban
        case .address:
            let place = [detail.postcode, detail.city].map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            return [detail.text.trimmingCharacters(in: .whitespaces), place].filter { !$0.isEmpty }.joined(separator: ", ")
        default:
            return detail.text.trimmingCharacters(in: .whitespaces)
        }
    }

    /// A detail as VoiceOver says it, a number by its last four digits:
    /// "Visa, ending in 4242".
    static func spoken(_ detail: OwnRule) -> String {
        let last: String
        switch detail.kind {
        case .card: last = String(digits(detail.text).suffix(4))
        case .account: last = String(compact(iban: detail.text).suffix(4))
        default: return "\(title(of: detail)), \(summary(of: detail))"
        }
        return "\(title(of: detail)), " + String(format: L("ending in %@"), last)
    }

    /// Some of the other ways a name is found, as written: "Musterfrau,
    /// Erika", "E. Musterfrau", "MUSTERFRAU".
    static func examples(of name: String) -> [String] {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.contains(",") else { return [] }
        let words = typed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, let first = words.first, let last = words.last else { return [] }
        return ["\(last), \(words.dropLast().joined(separator: " "))", "\(first.prefix(1)). \(last)", last.uppercased()]
    }

    /// A check sum of the details, so a change to them reads the pictures
    /// again, without any of them written into the key.
    static func checksum(_ details: [OwnRule]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let joined = details.map { [$0.kind.rawValue, $0.text, $0.postcode, $0.city].joined(separator: "\u{1}") }
            .joined(separator: "\u{2}")
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
