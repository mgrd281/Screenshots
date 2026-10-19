import Foundation

/// The fields of a printed form, read as a person reads one: a label, like
/// "Name, Vorname des Versicherten" or "Arzt-Nr.", and its value after it,
/// beside it, or under it in its column, on one line or several. A value is
/// what its label says it is, not what it looks like: a date under
/// "Arbeitsunfähig seit" is a health detail, a number under
/// "Versicherten-Nr." an insurance number, and a disease named after a
/// person under "Diagnose" no name. Pure, so all of it is checked without a
/// picture; `Finder` brings the lines and where they are.
enum FormFields {
    /// What a field holds, as its label says.
    enum Entity: String, CaseIterable, Sendable {
        case personName, address, dateOfBirth, healthInsuranceNumber, identificationNumber, institution,
             institutionNumber, medicalDiagnosis, medicalDate, date
        /// A code the form prints that is no one's private detail, like the
        /// insured person's status: read so nothing else takes it for one.
        case formCode

        /// Whether its value has a shape of its own, a date or a number:
        /// then it may follow its label on the line without a colon, and is
        /// read only where that shape is found.
        var isTyped: Bool {
            switch self {
            case .dateOfBirth, .medicalDate, .date, .healthInsuranceNumber, .identificationNumber, .institutionNumber:
                true
            // A word as common as "Status" counts only as a heading or before a colon.
            case .personName, .address, .institution, .medicalDiagnosis, .formCode:
                false
            }
        }
    }

    /// How sure a reading is, from what it was read from rather than a
    /// score: sure when the label says what the value is and the value is
    /// shaped like it; to check when its shape agrees only in part; only
    /// offered when it barely does.
    enum Confidence: Int, Comparable, Sendable {
        case low, medium, high

        static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }
    }

    /// Where a label is: printed text that is never covered.
    struct Label: Equatable {
        let line: Int
        let range: Range<String.Index>
    }

    /// A field's value: where it is, what it is and whose.
    struct Value: Equatable {
        let line: Int
        let range: Range<String.Index>
        let entity: Entity
        /// Whose it is, where the label says: the insured person's, the doctor's.
        let role: PersonRole?
        let confidence: Confidence
        /// The label it was read from, as written.
        let label: String
    }

    /// What a page's fields hold.
    struct Reading: Equatable {
        var labels: [Label] = []
        var values: [Value] = []

        /// Whether part of a line, or all of it, is nothing but labels: every
        /// letter and digit in it is a label's. A place that reaches past a
        /// label, like a date read with "geb. am" before it, is not.
        func isLabel(_ range: Range<String.Index>?, in line: Int, of string: String) -> Bool {
            let here = labels.filter { $0.line == line }
            let span = range ?? string.startIndex..<string.endIndex
            guard here.contains(where: { $0.range.overlaps(span) }) else { return false }
            var i = span.lowerBound
            while i < span.upperBound {
                if string[i].isLetter || string[i].isNumber, !here.contains(where: { $0.range.contains(i) }) {
                    return false
                }
                i = string.index(after: i)
            }
            return true
        }

        /// The value read at part of a line, or at all of it when the value
        /// fills the line.
        func value(at range: Range<String.Index>?, in line: Int, of string: String) -> Value? {
            values.first { value in
                guard value.line == line else { return false }
                guard let range else {
                    return string[value.range].trimmingCharacters(in: .whitespaces)
                        == string.trimmingCharacters(in: .whitespaces)
                }
                return value.range.overlaps(range)
            }
        }
    }

    // MARK: Labels

    /// A kind of field: its label, as a pattern, and what follows it.
    private struct Field {
        let regex: NSRegularExpression
        let entity: Entity
        /// What the lines after the first hold, like the address under a name.
        let then: Entity?
        /// How many lines its value may take.
        let lines: Int
        let role: PersonRole?
    }

    private static func field(_ pattern: String, _ entity: Entity, then: Entity? = nil, lines: Int = 1,
                              role: PersonRole? = nil) -> Field {
        // A whole label, not part of a longer word.
        let regex = try! NSRegularExpression(pattern: #"(?<![\p{L}\d])(?:"# + pattern + #")(?![\p{L}\d])"#,
                                             options: [.caseInsensitive])
        return Field(regex: regex, entity: entity, then: then, lines: lines, role: role)
    }

    /// The labels of German health insurance and medical forms, like the
    /// certificate of incapacity for work, prescriptions and referrals, and
    /// the plain labels of a person's details. Each as text recognition
    /// reads it: with or without its hyphen, its dot or its umlaut.
    private static let fields: [Field] = [
        // The insured person: the name, on a line or two, then the address.
        field(#"(?:name\s*,\s*vorname|vorname\s*,\s*name|name|nachname)\s+de[sr]\s+versicherten"#, .personName,
              then: .address, lines: 5, role: .patient),
        field(#"vorname\s+de[sr]\s+versicherten"#, .personName, role: .patient),
        field(#"(?:name|nachname|familienname)\s*,\s*vorname|vorname\s*,\s*(?:name|nachname)"#, .personName, lines: 2),
        field(#"vorname|nachname|familienname|geburtsname|name"#, .personName),
        field(#"geb(?:oren|\.)?\s*am|geburtsdatum|geb\.?\s*-?\s*datum|date\s+of\s+birth"#, .dateOfBirth),
        field(#"krankenkasse\s+bzw\.?\s+kostentr[äa]ger|kostentr[äa]ger|krankenkasse|krankenversicherung"#,
              .institution),
        field(#"kostentr[äa]ger\s*-?\s*kennung|kassen\s*-?\s*nr\.?|kassennummer|institutionskennzeichen|ik\s*-\s*nr\.?"#,
              .institutionNumber),
        field(#"versicherten\s*-?\s*nr\.?|(?:kranken)?versichertennummer|kv\s*-\s*nr\.?"#, .healthInsuranceNumber,
              role: .patient),
        field(#"betriebsst[äa]tten\s*-?\s*nr\.?|betriebsst[äa]ttennummer|bsnr"#, .institutionNumber),
        field(#"arzt\s*-?\s*nr\.?|arztnummer|lanr"#, .identificationNumber, role: .doctor),
        field(#"status"#, .formCode),
        field(#"datum"#, .date),
        field(#"arbeitsunf[äa]hig\s+seit"#, .medicalDate),
        field(#"voraussichtlich\s+arbeitsunf[äa]hig\s+bis(?:\s+einschl(?:ie(?:ß|ss)lich|\.))?(?:\s+oder\s+letzter\s+tag\s+der\s+arbeitsunf[äa]higkeit)?"#,
              .medicalDate),
        field(#"festgestellt\s+am"#, .medicalDate),
        field(#"(?:au\s*-?\s*begr[üu]ndende\s+)?diagnose(?:\s*\(n\)|n)?(?:\s*\(icd\s*-?\s*10\))?|diagnos[ei]s"#,
              .medicalDiagnosis, lines: 4),
        field(#"icd\s*-?\s*10(?:\s*-?\s*codes?)?"#, .medicalDiagnosis, lines: 3),
    ]

    /// The labels in a line, each with its field, left to right. A label
    /// counts at the start of a line or right after another, as a row of a
    /// form's headings reads; one whose value has a shape of its own, like
    /// "geb. am", anywhere after a space.
    private static func labels(in line: String) -> [(range: Range<String.Index>, field: Field)] {
        let whole = NSRange(line.startIndex..., in: line)
        var all: [(range: Range<String.Index>, field: Field)] = []
        for field in fields {
            for match in field.regex.matches(in: line, range: whole) {
                if let range = Range(match.range, in: line) { all.append((range, field)) }
            }
        }
        // The longest label wins where two overlap: "Name, Vorname" over "Name".
        all.sort { line.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
            > line.distance(from: $1.range.lowerBound, to: $1.range.upperBound) }
        var kept: [(range: Range<String.Index>, field: Field)] = []
        for label in all where !kept.contains(where: { $0.range.overlaps(label.range) }) { kept.append(label) }
        kept.sort { $0.range.lowerBound < $1.range.lowerBound }
        var accepted: [(range: Range<String.Index>, field: Field)] = []
        var from = line.startIndex
        for label in kept {
            let before = line[from..<label.range.lowerBound]
            let headed = before.allSatisfy { $0.isWhitespace || ":|/,;.-–".contains($0) }
            let typed = label.field.entity.isTyped
                && (label.range.lowerBound == line.startIndex || line[line.index(before: label.range.lowerBound)].isWhitespace)
            guard headed || typed else { continue }
            accepted.append(label)
            from = label.range.upperBound
        }
        return accepted
    }

    // MARK: Reading the fields

    private struct Found {
        let line: Int
        let range: Range<String.Index>
        let field: Field
        let box: CGRect
    }

    /// The fields of a page's lines: each label and the value it announces.
    /// `boxes` are the lines' places, from 0 to 1 from the bottom left, and
    /// `part` says where part of a line is.
    static func read(_ strings: [String], boxes: [CGRect], part: (Int, Range<String.Index>) -> CGRect?) -> Reading {
        func place(_ line: Int, _ range: Range<String.Index>) -> CGRect {
            if let box = part(line, range) { return box }
            // By its share of the line's letters, where the reading has no place for it.
            let string = strings[line], box = boxes[line]
            let count = CGFloat(max(1, string.count))
            let start = CGFloat(string.distance(from: string.startIndex, to: range.lowerBound)) / count
            let end = CGFloat(string.distance(from: string.startIndex, to: range.upperBound)) / count
            return CGRect(x: box.minX + start * box.width, y: box.minY, width: (end - start) * box.width,
                          height: box.height)
        }
        var found: [Found] = []
        for (i, string) in strings.enumerated() where i < boxes.count {
            for label in labels(in: string) {
                found.append(Found(line: i, range: label.range, field: label.field, box: place(i, label.range)))
            }
        }
        var reading = Reading(labels: found.map { Label(line: $0.line, range: $0.range) })
        var taken = Set<String>()
        for label in found {
            for value in values(of: label, among: found, strings, boxes: boxes, place: place) {
                // A value read for two labels counts for the first.
                let key = "\(value.line)|\(strings[value.line].distance(from: strings[value.line].startIndex, to: value.range.lowerBound))"
                if taken.insert(key).inserted { reading.values.append(value) }
            }
        }
        return reading
    }

    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) * 0.5
    }

    /// How far left of its label a value may start, as forms are printed
    /// a little off their boxes.
    private static let slack: CGFloat = 0.04

    private static func values(of label: Found, among found: [Found], _ strings: [String], boxes: [CGRect],
                               place: (Int, Range<String.Index>) -> CGRect) -> [Value] {
        let entity = label.field.entity
        let string = strings[label.line]
        let labelText = String(string[label.range])
        func value(_ line: Int, _ range: Range<String.Index>, _ entity: Entity, _ confidence: Confidence) -> Value {
            Value(line: line, range: range, entity: entity, role: label.field.role, confidence: confidence,
                  label: labelText)
        }
        // The next label on its line ends what follows it there.
        let nextOnLine = found.filter { $0.line == label.line && $0.range.lowerBound >= label.range.upperBound }
            .map(\.range.lowerBound).min() ?? string.endIndex
        var start = label.range.upperBound
        var colon = false
        while start < nextOnLine, string[start].isWhitespace || ":.-–".contains(string[start]) {
            if string[start] == ":" { colon = true }
            start = string.index(after: start)
        }
        let inline = trimmed(start..<nextOnLine, in: string)
        if !inline.isEmpty {
            // On its line: after a colon, or a date or a number of its own.
            guard colon || entity.isTyped, let read = shaped(inline, in: string, as: entity) else { return [] }
            return [value(label.line, read.range, entity, read.confidence)]
        }
        // Its row: the next label to its right ends its column.
        let right = found.filter { $0.line != label.line || $0.range != label.range }
            .filter { sameRow($0.box, label.box) && $0.box.minX > label.box.maxX - 0.002 }
            .map(\.box.minX).min()
        let headed = found.contains { sameRow($0.box, label.box) && $0.box.maxX <= label.box.minX + 0.002 }

        // Beside it on its row, as "Vorname:" and its value in the next column.
        let beside = boxes.indices.filter { i in
            i != label.line && i < strings.count && sameRow(boxes[i], label.box)
                && boxes[i].minX >= label.box.maxX - 0.005 && boxes[i].minX < (right ?? label.box.maxX + 0.35)
        }.min { boxes[$0].minX < boxes[$1].minX }
        if let beside {
            let line = strings[beside]
            let end = found.filter { $0.line == beside }.map(\.range.lowerBound).min() ?? line.endIndex
            let range = trimmed(line.startIndex..<end, in: line)
            if !range.isEmpty, let read = shaped(range, in: line, as: entity) {
                return [value(beside, read.range, entity, read.confidence)]
            }
        }

        // Under it, in its column, on as many lines as the field takes.
        let left = label.box.minX - slack
        let columnRight = right.map { $0 - 0.005 } ?? .greatestFiniteMagnitude
        var values: [Value] = []
        var above = label.box
        var used = Set<Int>([label.line])
        var names = 0
        for n in 0..<label.field.lines {
            var best: (line: Int, range: Range<String.Index>, box: CGRect)?
            // The nearest line under it; of two on one row, the one that
            // starts nearest its column.
            func nearer(_ box: CGRect, than other: CGRect) -> Bool {
                if abs(box.maxY - other.maxY) < min(box.height, other.height) * 0.5 {
                    return abs(box.minX - label.box.minX) < abs(other.minX - label.box.minX)
                }
                return box.maxY > other.maxY
            }
            for (i, box) in boxes.enumerated() where i < strings.count && !used.contains(i) {
                guard box.maxY <= above.minY + above.height * 0.3,
                      above.minY - box.maxY < max(above.height, box.height) * (n == 0 ? 1.8 : 1.2),
                      // A line under a label alone on its row starts in its column.
                      headed || box.minX >= left,
                      let cut = column(of: i, in: strings[i], from: left, to: columnRight, place: place) else { continue }
                let cutBox = place(i, cut)
                if let current = best, !nearer(cutBox, than: current.box) { continue }
                best = (i, cut, cutBox)
            }
            guard let best else { break }
            // The next row of labels ends the value.
            if found.contains(where: { $0.line == best.line && $0.range.overlaps(best.range) }) { break }
            let line = strings[best.line]
            let range = found.filter { $0.line == best.line && $0.range.lowerBound > best.range.lowerBound }
                .map(\.range.lowerBound).min().map { trimmed(best.range.lowerBound..<min($0, best.range.upperBound), in: line) }
                ?? best.range
            guard !range.isEmpty else { break }
            // A doctor's stamp, or an address, right under a diagnosis is no part of it.
            if n > 0, entity != .personName, entity != .address {
                let piece = String(line[range])
                let titled = DocumentSense.titledNames(in: piece).first.map { piece.hasPrefix($0.title) } ?? false
                if titled || isAddress(line[range]) { break }
            }
            var kind = entity
            if entity == .personName {
                // A name on a line or two, then, where the field holds one, the address.
                if label.field.then == .address, names > 0, isAddress(line[range]) {
                    kind = .address
                } else if names >= 2 || values.last?.entity == .address {
                    if label.field.then == .address { kind = .address } else { break }
                } else if isAddress(line[range]) {
                    break
                }
            }
            guard let read = shaped(range, in: line, as: kind) else { break }
            if kind == .personName { names += 1 }
            values.append(value(best.line, read.range, kind, read.confidence))
            used.insert(best.line)
            above = best.box
            // A value of a shape of its own takes one line.
            if entity.isTyped { break }
        }
        return values
    }

    /// The part of a line in a column: from its first word that starts in
    /// it to its last, or nil when no word does.
    private static func column(of index: Int, in line: String, from left: CGFloat, to right: CGFloat,
                               place: (Int, Range<String.Index>) -> CGRect) -> Range<String.Index>? {
        var first: String.Index?, last: String.Index?
        for word in words(in: line) {
            let box = place(index, word)
            guard box.midX >= left, box.midX < right else {
                if first != nil, box.midX >= right { break }
                continue
            }
            if first == nil { first = word.lowerBound }
            last = word.upperBound
        }
        guard let first, let last else { return nil }
        return first..<last
    }

    private static func words(in line: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start: String.Index?
        var i = line.startIndex
        while i < line.endIndex {
            if line[i].isWhitespace {
                if let s = start { found.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
            i = line.index(after: i)
        }
        if let s = start { found.append(s..<line.endIndex) }
        return found
    }

    private static func trimmed(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var lower = range.lowerBound, upper = range.upperBound
        while lower < upper, line[lower].isWhitespace { lower = line.index(after: lower) }
        while upper > lower, line[line.index(before: upper)].isWhitespace || line[line.index(before: upper)] == ":" {
            upper = line.index(before: upper)
        }
        return lower..<upper
    }

    // MARK: Values by their shape

    private static let datePattern = #"(?<!\d)\d{1,2}\s?[./]\s?\d{1,2}\s?[./]\s?(?:\d{4}|\d{2})(?!\d)"#
    private static let numberPattern = #"(?<![\p{L}\d])\p{Lu}{0,2}\d{5,15}(?![\p{L}\d])"#
    private static let shortNumberPattern = #"(?<![\p{L}\d])\p{Lu}{0,2}\d{3,4}(?![\p{L}\d])"#

    /// A street with its number, or a postcode with its town.
    static func isAddress(_ text: Substring) -> Bool {
        let text = String(text)
        return text.range(of: #"^\p{L}[\p{L}.\-' ]*\s\d{1,4}\s?[a-zA-Z]?(?:[\s,]|$)"#, options: .regularExpression) != nil
            || text.range(of: #"^(?:[A-Z]{1,2}\s?-?\s?)?\d{4,5}\s+\p{L}"#, options: .regularExpression) != nil
    }

    /// Where the value is in a part of a line, read as what its label says
    /// it is, and how sure that is; nil when it is not shaped like one.
    private static func shaped(_ range: Range<String.Index>, in line: String, as entity: Entity)
        -> (range: Range<String.Index>, confidence: Confidence)? {
        let text = line[range]
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        func first(_ pattern: String) -> Range<String.Index>? {
            line.range(of: pattern, options: .regularExpression, range: range)
        }
        switch entity {
        case .dateOfBirth, .medicalDate, .date:
            return first(datePattern).map { ($0, .high) }
        case .healthInsuranceNumber, .identificationNumber, .institutionNumber:
            if let number = first(numberPattern) { return (number, .high) }
            return first(shortNumberPattern).map { ($0, .low) }
        case .formCode:
            return (first(numberPattern) ?? first(shortNumberPattern)).map { ($0, .high) }
        case .personName:
            // A person's name, without the title before it and what follows it.
            let piece = String(text)
            if DocumentSense.isOrganization(piece) { return nil }
            if let name = DocumentSense.leadingName(in: piece, from: piece.startIndex) {
                return (moved(name, from: piece, into: line, at: range.lowerBound), .high)
            }
            // Letters alone, though not written as a name usually is.
            let letters = piece.allSatisfy { $0.isLetter || " ,'’.-".contains($0) }
            return letters && piece.count >= 2 ? (range, .medium) : nil
        case .address:
            return (range, isAddress(text) || text.contains(where: \.isNumber) ? .high : .medium)
        case .institution, .medicalDiagnosis:
            return (range, .high)
        }
    }

    /// A range found in a piece of a line, where it is in the line.
    private static func moved(_ inner: Range<String.Index>, from piece: String, into line: String,
                              at start: String.Index) -> Range<String.Index> {
        let offset = line.utf16.distance(from: line.startIndex, to: start)
        let lower = piece.utf16.distance(from: piece.startIndex, to: inner.lowerBound) + offset
        let upper = piece.utf16.distance(from: piece.startIndex, to: inner.upperBound) + offset
        return line.utf16.index(line.startIndex, offsetBy: lower)..<line.utf16.index(line.startIndex, offsetBy: upper)
    }
}
