import Foundation

/// The owner's own details (`OwnRule.Kind.details`): found in text in the
/// ways they are written there, shown with most of them hidden, and checked
/// while they are typed. A name in the forms `nameVariants` lists; an
/// address's street with its house number, and its postcode with its town;
/// a card's number, whole or by its last four digits after a mask; an
/// account's IBAN, with or without spaces, and a German or Austrian
/// account's number. A name or a number broken over two lines is found too,
/// and one misread letter or digit in a long one. Pure text, so it is
/// checked without a picture, on Linux too.
enum OwnDetails {
    // MARK: Finding them

    /// Where the owner's details stand in text of many lines, as ranges of
    /// the whole: a name or a number also where it runs on into the next
    /// line, an address line by line, as it is printed. Masking, for the
    /// words that go to the AI assistant, also takes a word of the name in
    /// small letters, and the first given name alone.
    static func ranges(in full: String, _ rules: [OwnRule], masking: Bool = false) -> [NSRange] {
        let details = rules.filter { $0.kind.isDetail && $0.isActive }
        guard !details.isEmpty else { return [] }
        var found: [NSRange] = []
        for detail in details where detail.kind != .address {
            found += ranges(in: full, of: detail, masking: masking).map { NSRange($0, in: full) }
        }
        let addresses = details.filter { $0.kind == .address }
        if !addresses.isEmpty {
            var offset = 0
            for line in full.components(separatedBy: "\n") {
                for detail in addresses {
                    for range in address(detail, in: line) {
                        let place = NSRange(range, in: line)
                        found.append(NSRange(location: place.location + offset, length: place.length))
                    }
                }
                offset += line.utf16.count + 1
            }
        }
        var seen = Set<NSRange>()
        return found.filter { seen.insert($0).inserted }
    }

    /// A line with the owner's details in it hidden, as it is sent to the
    /// AI assistant: they are covered anyway, so they never leave. Places
    /// that overlap are hidden as one.
    static func masking(_ line: String, _ rules: [OwnRule]) -> String {
        let places = rules.filter { $0.kind.isDetail && $0.isActive }.flatMap { ranges(in: line, of: $0, masking: true) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for place in places {
            if let last = merged.last, place.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, place.upperBound)
            } else {
                merged.append(place)
            }
        }
        var masked = line
        for place in merged.reversed() {
            masked.replaceSubrange(place, with: "•••")
        }
        return masked
    }

    /// Where one of the owner's details stands in a text, each place once.
    static func ranges(in text: String, of detail: OwnRule, masking: Bool = false) -> [Range<String.Index>] {
        let found: [Range<String.Index>] = switch detail.kind {
        case .name: name(detail.text, in: text, masking: masking)
        case .address: address(detail, in: text)
        case .card: card(digits(detail.text), in: text)
        case .account: account(compact(iban: detail.text), in: text)
        case .word, .label, .pattern: []
        }
        var seen = Set<Range<String.Index>>()
        return found.filter { seen.insert($0).inserted }
    }

    // MARK: Names

    /// A name's given names and its surname, as typed. Snapfly's two fields
    /// keep it as "Surname, Given names" (`nameText`), so the comma says
    /// where the surname ends; typed on one line, as before there were two,
    /// the surname is the last word with the particles before it, as "van
    /// Berg". One word alone is a surname.
    static func nameParts(_ text: String) -> (given: [String], surname: [String]) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = typed.firstIndex(of: ",") {
            return (plainWords(typed[typed.index(after: comma)...]), plainWords(typed[..<comma]))
        }
        let words = plainWords(typed[...])
        guard words.count > 1 else { return ([], words) }
        var split = words.count - 1
        while split > 1, particles.contains(fold(words[split - 1])) { split -= 1 }
        return (Array(words[..<split]), Array(words[split...]))
    }

    /// The name as kept, from its two fields: "Mustermann, Max", or the one
    /// that was filled in, a given name alone after its comma.
    static func nameText(given: String, surname: String) -> String {
        let given = plainWords(given[...]).joined(separator: " ")
        let surname = plainWords(surname[...]).joined(separator: " ")
        if given.isEmpty { return surname }
        return surname.isEmpty ? ", " + given : surname + ", " + given
    }

    /// The name as a person reads it: "Max Mustermann".
    static func displayName(_ text: String) -> String {
        let (given, surname) = nameParts(text)
        return (given + surname).joined(separator: " ")
    }

    /// The ways the owner's name is looked for, as they are written, the
    /// name itself first: surname first, in capitals too, with the first
    /// given name alone, with its initial before or after the surname, the
    /// surname alone, and the first given name alone from four letters. The
    /// sheet shows these, and the covering looks for these and no others
    /// (`nameForms`), in any case and with any spacing or punctuation
    /// between their words.
    static func nameVariants(_ text: String) -> [String] {
        let (given, surname) = nameParts(text)
        let first = given.joined(separator: " "), last = surname.joined(separator: " ")
        var shown: [String] = []
        if given.isEmpty || surname.isEmpty {
            let alone = first.isEmpty ? last : first
            if !alone.isEmpty { shown = [alone, alone.uppercased()] }
        } else if let given1 = given.first, let core = surname.last {
            let initial = String(given1.prefix(1)) + "."
            shown = ["\(first) \(last)", "\(last.uppercased()), \(first)", "\(last), \(first)"]
            if given.count > 1 { shown += ["\(given1) \(last)", "\(last), \(given1)"] }
            shown += ["\(initial) \(last)", "\(last), \(initial)", core]
            // A short given name alone is too often a word, like "Max" in "Max. 5".
            if fold(given1).count >= 4 { shown.append(given1) }
        }
        var seen = Set<String>()
        return shown.filter { seen.insert($0).inserted }
    }

    /// The forms of a name the covering looks for, each as its words
    /// folded, the longest first: the `nameVariants`, and nothing else.
    static func nameForms(_ text: String) -> [[String]] {
        var seen = Set<[String]>()
        return nameVariants(text).map { words(of: $0.replacingOccurrences(of: ",", with: " ")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Words that join a surname, as "von" in "von Weizsäcker".
    private static let particles: Set<String> = ["von", "van", "de", "der", "den", "del", "della", "di", "da", "du",
                                                 "le", "la", "al", "el", "bin", "ibn", "ter", "ten", "zu", "zum", "zur"]

    private static func name(_ text: String, in line: String, masking: Bool) -> [Range<String.Index>] {
        var forms = nameForms(text)
        // What goes to the AI assistant hides the first given name alone too.
        if masking, let first = nameParts(text).given.first.map(fold), first.count >= 3, !forms.contains([first]) {
            forms.append([first])
        }
        guard !forms.isEmpty else { return [] }
        let tokens = tokens(in: line)
        var found: [Range<String.Index>] = []
        var i = 0
        while i < tokens.count {
            var matched = 0
            // The name in more words first, then with its spaces left out or
            // put in, then a word of it alone.
            for form in forms where form.count > 1 && i + form.count <= tokens.count
                && fits(form, tokens[i..<i + form.count], in: line, masking: masking) {
                matched = form.count
                break
            }
            if matched == 0 { matched = joined(forms, tokens[i...], in: line) }
            if matched == 0, forms.contains(where: { $0.count == 1 && fits($0, tokens[i...i], in: line, masking: masking) }) {
                matched = 1
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

    /// How many words from the first of these are a form of the name of
    /// two words or more written with its spaces left out or put in, as
    /// "ErikaMusterfrau" or "Erika Muster frau": its words together, the
    /// same but for one letter misread in six or more; 0 where none is.
    private static func joined(_ forms: [[String]], _ tokens: ArraySlice<Token>, in line: String) -> Int {
        // Never a form with an initial: one letter more or less would be all of it.
        for form in forms where form.count >= 2 && form.allSatisfy({ $0.count >= 3 }) {
            let whole = form.joined()
            var read = ""
            var previous: Token?
            for (n, token) in tokens.prefix(form.count + 2).enumerated() {
                if let previous, !joins(previous, token, in: line) { break }
                read += token.folded
                previous = token
                guard read.count <= whole.count + 1 else { break }
                // As many words as the form has is the form, read word by word (`fits`).
                guard n + 1 != form.count else { continue }
                if same(whole, read, misreadFrom: 6) { return n + 1 }
            }
        }
        return 0
    }

    /// Whether these words of a text are this form of the name: each word
    /// the same, but for one at most, read as loosely as a misread letter,
    /// in a word of five letters or more beside the rest of the name, or of
    /// seven alone; with no more than a comma, a dot, a semicolon, a slash
    /// and a space between them, or the end of a line. A word alone counts
    /// when it begins with a capital, so "koch" in a sentence is a word; an
    /// initial, only beside the surname. Masking takes a word alone in any
    /// case, and misread from five letters.
    private static func fits(_ form: [String], _ tokens: ArraySlice<Token>, in line: String, masking: Bool) -> Bool {
        let loosely = form.count == 1 && !masking ? 7 : 5
        var misread = false
        for (word, token) in zip(form, tokens) where word != token.folded && readAlike(word) != token.alike {
            guard !misread, same(word, token.folded, misreadFrom: loosely) else { return false }
            misread = true
        }
        if form.count == 1 {
            guard let token = tokens.first, form[0].count >= 3 else { return false }
            return masking || line[token.range].first?.isUppercase == true
        }
        var previous: Token?
        for token in tokens {
            if let previous, !joins(previous, token, in: line) { return false }
            previous = token
        }
        return true
    }

    /// Whether two words of a line are close enough to be one name: no more
    /// than a comma, a dot, a semicolon, a slash and a space between them,
    /// or the end of a line.
    private static func joins(_ previous: Token, _ token: Token, in line: String) -> Bool {
        let gap = line[previous.range.upperBound..<token.range.lowerBound]
        return gap.count <= 3 && gap.filter(\.isNewline).count <= 1
            && gap.allSatisfy { $0.isNewline || " ,.;/·\t".contains($0) }
    }

    /// Whether a word read is this one: as it is, or as text recognition
    /// reads letters alike (`readAlike`), or with one letter misread in a
    /// word of `misreadFrom` letters or more.
    private static func same(_ word: String, _ read: String, misreadFrom least: Int) -> Bool {
        if word == read { return true }
        let wanted = readAlike(word), seen = readAlike(read)
        if wanted == seen { return true }
        guard min(word.count, read.count) >= least else { return false }
        return Finder.differsByOne(word, read) || Finder.differsByOne(wanted, seen)
    }

    /// A folded word as text recognition may read it, so a misread letter
    /// of the kinds it often makes costs nothing: "rn" as "m", an l, a 1 or
    /// a stroke as an i, a 0 as an o.
    static func readAlike(_ folded: String) -> String {
        String(folded.replacingOccurrences(of: "rn", with: "m").map { character -> Character in
            switch character {
            case "l", "1", "|": "i"
            case "0": "o"
            default: character
            }
        })
    }

    /// A word of a line, where it is and how it is compared.
    private struct Token {
        let range: Range<String.Index>
        let folded: String
        /// As text recognition reads letters alike (`readAlike`).
        let alike: String
    }

    /// The words of a line: letters, with an apostrophe or a hyphen inside,
    /// and a 0, a 1 or a stroke among them that text recognition read for
    /// a letter, as in "Mo1lmann".
    private static func tokens(in line: String) -> [Token] {
        let whole = NSRange(line.startIndex..., in: line)
        return wordPattern.matches(in: line, range: whole).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            let read = String(line[range]).replacingOccurrences(of: "|", with: "l")
            let folded = fold(read)
            return Token(range: range, folded: folded, alike: readAlike(folded))
        }
    }

    private static let wordPattern = try! NSRegularExpression(
        pattern: #"\p{L}(?:[\p{L}\p{M}]|[01|](?=\p{L}))*(?:['’\-]\p{L}(?:[\p{L}\p{M}]|[01|](?=\p{L}))*)*"#)

    /// A name's words as typed, folded, without what stands round them.
    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    /// A name's words as typed, as they are shown: without spaces, commas or
    /// dots round them.
    private static func plainWords(_ text: Substring) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".;")) }
            .filter { !$0.isEmpty }
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

    /// The street with its house number, and the postcode with the town,
    /// each where they stand together; a letter misread in a street's or a
    /// town's name of five letters or more, never in a number.
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
        let misread = street.count >= 5
        if !house.isEmpty, street.count >= 3 {
            found += folded.places(of: street + house, in: line, loose: misread ? 0..<street.count : nil)
            found += folded.places(of: house + street, in: line,
                                   loose: misread ? house.count..<house.count + street.count : nil)
        } else if house.isEmpty, street.count >= 4 {
            found += folded.places(of: street, in: line)
        }
        // The postcode with its town, as on a letter's last address line, never one without the other.
        let postcode = Folded(detail.postcode).chars, city = Folded(detail.city).chars
        if !postcode.isEmpty, !city.isEmpty {
            found += folded.places(of: postcode + city, in: line,
                                   loose: city.count >= 5 ? postcode.count..<postcode.count + city.count : nil)
        }
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
        /// in "14a". Within `loose`, one of them may be misread: another,
        /// left out, or one too many.
        func places(of needle: [Character], in line: String, loose: Range<Int>? = nil) -> [Range<String.Index>] {
            guard !needle.isEmpty, needle.count - (loose == nil ? 0 : 1) <= chars.count else { return [] }
            var found: [Range<String.Index>] = []
            var i = 0
            while i < chars.count {
                guard let length = length(of: needle, at: i, loose: loose), length > 0 else {
                    i += 1
                    continue
                }
                let start = starts[i], end = ends[i + length - 1]
                let before = start > line.startIndex ? line[line.index(before: start)] : nil
                let after = end < line.endIndex ? line[end] : nil
                if before.map({ $0.isLetter || $0.isNumber }) != true, after.map({ $0.isLetter || $0.isNumber }) != true {
                    found.append(start..<end)
                    i += length
                } else {
                    i += 1
                }
            }
            return found
        }

        /// How many characters from `i` on are these, exactly or with one
        /// misread within `loose`; nil when they are not.
        private func length(of needle: [Character], at i: Int, loose: Range<Int>?) -> Int? {
            var n = 0, c = i
            while n < needle.count, c < chars.count, chars[c] == needle[n] {
                n += 1
                c += 1
            }
            if n == needle.count { return c - i }
            guard let loose, loose.contains(n) else { return nil }
            // The rest exactly, after one changed, left out or one too many.
            for (skipped, extra) in [(1, 1), (1, 0), (0, 1)] {
                let from = n + skipped, at = c + extra, count = needle.count - from
                guard at + count <= chars.count, at + count > i,
                      chars[at..<at + count].elementsEqual(needle[from...]) else { continue }
                return at + count - i
            }
            return nil
        }
    }

    // MARK: Cards

    /// The digits of what was typed.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    private static func card(_ number: String, in line: String) -> [Range<String.Index>] {
        guard number.count >= 8 else { return [] }
        // A digit misread in a number that adds up is that number still: no other card's is one digit from it.
        var found = runs(of: number, in: line, misread: number.count >= 12 && passesLuhn(number))
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
        // A character misread in an IBAN that adds up is that IBAN still: no other one is a character from it.
        var found = runs(of: iban, in: line, letters: true, misread: ibanIsValid(iban))
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
    /// stand in a text, in groups or not: with spaces, dashes or dots
    /// between the groups, or the end of a line, read as loosely as text
    /// recognition reads an O for a 0, and, for a number that adds up, with
    /// one other character misread; whole, never the middle of a longer
    /// number.
    private static func runs(of value: String, in line: String, letters: Bool = false,
                             misread: Bool = false) -> [Range<String.Index>] {
        let wanted = Array(value)
        var found: [Range<String.Index>] = []
        for run in runs(in: line, letters: letters) where run.chars.count >= wanted.count {
            var i = 0
            while i + wanted.count <= run.chars.count {
                let end = i + wanted.count
                if run.starts[i], end == run.chars.count || run.starts[end] {
                    let wrong = zip(wanted, run.chars[i..<end]).enumerated()
                        .filter { !same($1.0, $1.1, letters: letters && $0 >= 2) }.count
                    if wrong == 0 || misread && wrong == 1 {
                        found.append(run.places[i].lowerBound..<run.places[end - 1].upperBound)
                        i = end
                        continue
                    }
                }
                i += 1
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
            } else if !run.chars.isEmpty, gap < 2, c.isNewline || " \u{00A0}\u{2009}\u{202F}-.".contains(c) {
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

    /// Whether a detail holds enough to cover something, and nothing that
    /// cannot be right: a name, a street or a postcode with its town, a
    /// card's number of twelve to nineteen digits that adds up, an IBAN that
    /// adds up.
    static func canKeep(_ detail: OwnRule) -> Bool {
        let kept = cleaned(detail)
        switch kept.kind {
        case .name:
            let parts = nameParts(kept.text)
            return !parts.given.isEmpty || !parts.surname.isEmpty
        case .address: return !kept.text.isEmpty || !kept.postcode.isEmpty && !kept.city.isEmpty
        case .card: return (12...19).contains(kept.text.count) && passesLuhn(kept.text)
        case .account: return ibanIsValid(kept.text)
        case .word, .label, .pattern: return false
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

    /// A detail's value as the rows show it, on one line: a name as it
    /// reads, an address by its street and town, a card's or an IBAN's
    /// number by its last four digits alone: "•••• 4242", "•••• 3000".
    static func masked(_ detail: OwnRule) -> String {
        switch detail.kind {
        case .name:
            return displayName(detail.text)
        case .card:
            return "•••• " + String(digits(detail.text).suffix(4))
        case .account:
            return "•••• " + String(compact(iban: detail.text).suffix(4))
        case .address:
            // On one line: the street with its number, and the town.
            let street = detail.text.trimmingCharacters(in: .whitespaces)
            let town = detail.city.trimmingCharacters(in: .whitespaces)
            let place = town.isEmpty ? detail.postcode.trimmingCharacters(in: .whitespaces) : town
            return [street, place].filter { !$0.isEmpty }.joined(separator: ", ")
        default:
            return summary(of: detail)
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

    /// Some of the other ways a name is found, as written: "MUSTERFRAU,
    /// Erika", "Musterfrau, Erika", "E. Musterfrau". None for a name of one
    /// part.
    static func examples(of name: String) -> [String] {
        let parts = nameParts(name)
        guard !parts.given.isEmpty, !parts.surname.isEmpty else { return [] }
        return Array(nameVariants(name).dropFirst().prefix(3))
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
