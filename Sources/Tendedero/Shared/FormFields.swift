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
        // What the certificate prints beside its checkboxes and under its
        // stamp, never anyone's detail: labels that announce nothing, and end
        // the value above them.
        field(#"arbeitsunfall(?:\s*,\s*arbeitsunfallfolgen)?(?:\s*,\s*berufskrankheit)?|dem\s+durchgangsarzt\s+zugewiesen"#,
              .formCode, lines: 0),
        field(#"sonstiger\s+unfall(?:\s*,\s*unfallfolgen)?|versorgungsleiden(?:\s*\(\s*bvg\s*\))?"#, .formCode, lines: 0),
        field(#"(?:erst|folge|arbeitsunf[äa]higkeits)\s*-?\s*bescheinigung|vertragsarztstempel(?:\s*/\s*unterschrift\s+des\s+arztes)?"#,
              .formCode, lines: 0),
    ]

    /// The labels in a line, each with its field, left to right. A label
    /// counts at the start of a line or right after another, as a row of a
    /// form's headings reads; one whose value has a shape of its own, like
    /// "geb. am", anywhere after a space.
    private static func labels(in line: String) -> [(range: Range<String.Index>, field: Field)] {
        // Matched in the line as its labels' words are meant, each back where it was read.
        let (meant, origin) = readable(line)
        let whole = NSRange(meant.startIndex..., in: meant)
        var all: [(range: Range<String.Index>, field: Field)] = []
        for field in fields {
            for match in field.regex.matches(in: meant, range: whole) {
                guard let range = Range(match.range, in: meant) else { continue }
                let lower = origin[meant.distance(from: meant.startIndex, to: range.lowerBound)]
                let upper = origin[meant.distance(from: meant.startIndex, to: range.upperBound)]
                if lower < upper { all.append((lower..<upper, field)) }
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

    // MARK: Labels as tiny print is read

    /// The long words of the labels, as printed. Text recognition often
    /// reads small print a letter off, "Vomame", "Versicherlen",
    /// "Kostentrâgerkennung", "Betriebsstätlen", and a word that close to
    /// one of these is read as it, as a person reading the form would.
    private static let labelWords = [
        "krankenkasse", "kostenträger", "kostenträgerkennung", "krankenversicherung", "vorname", "nachname",
        "familienname", "geburtsname", "geburtsdatum", "versicherten", "versichertennummer",
        "krankenversichertennummer", "kassennummer", "institutionskennzeichen", "betriebsstätten",
        "betriebsstättennummer", "arztnummer", "arbeitsunfähig", "arbeitsunfähigkeit", "voraussichtlich",
        "einschließlich", "festgestellt", "begründende", "diagnose",
    ]

    /// A word as misreadings leave it the same: small letters, no accents,
    /// "ß" as one letter, often read as "B", and "rn" as the "m" it is often
    /// read as.
    static func misreadFold(_ word: some StringProtocol) -> [Character] {
        Array(String(word).lowercased().replacingOccurrences(of: "ß", with: "s")
            .folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "rn", with: "m"))
    }

    /// Whether a word, as text recognition read it, is `meant`: the same once
    /// misreadings are folded away, "Vomame" for "Vorname"; or, in a long word,
    /// one letter read as another, two from fourteen letters on. A letter more
    /// or less never counts: "Nachnahme" is no "Nachname".
    static func reads(_ word: some StringProtocol, as meant: String) -> Bool {
        reads(folded: misreadFold(word), as: misreadFold(meant))
    }

    /// The same, for words already folded, as a page's words are held
    /// against many labels' or phrases' words.
    static func reads(folded read: [Character], as label: [Character]) -> Bool {
        guard read.count == label.count, read.first == label.first else { return false }
        let allowed = label.count >= 14 ? 2 : label.count >= 7 ? 1 : 0
        return zip(read, label).filter { $0 != $1 }.count <= allowed
    }

    /// The labels' words folded once, as every word of a page is held against them.
    private static let foldedLabelWords = labelWords.map { (word: $0, folded: misreadFold($0)) }

    /// The label's word a word was meant as, where it is one misread: a
    /// letter read as another, two in a long word, or "rn" read as "m".
    /// A letter more or less is left alone: "Nachnahme" is no "Nachname",
    /// and "arbeitsfähig" no "arbeitsunfähig".
    private static func labelWord(near word: Substring) -> String? {
        guard word.count >= 6 else { return nil }
        let read = misreadFold(word)
        return foldedLabelWords.first { reads(folded: read, as: $0.folded) }?.word
    }

    /// Whether a word is one of a form's labels' long words, as printed or
    /// a letter off: "Kostenträgerkennung", "Geburtsdatum", "Versicherlen".
    static func isLabelWord(_ word: some StringProtocol) -> Bool {
        labelWord(near: Substring(word.trimmingCharacters(in: CharacterSet.letters.inverted))) != nil
    }

    /// The line with each misread label's word as it is meant, and where
    /// in the line each of its letters, and its end, was read.
    private static func readable(_ line: String) -> (text: String, origin: [String.Index]) {
        var text = "", origin: [String.Index] = []
        var i = line.startIndex
        while i < line.endIndex {
            guard line[i].isLetter else {
                text.append(line[i]); origin.append(i); i = line.index(after: i); continue
            }
            var j = i
            while j < line.endIndex, line[j].isLetter { j = line.index(after: j) }
            if let meant = labelWord(near: line[i..<j]) {
                let count = line.distance(from: i, to: j)
                for (k, letter) in meant.enumerated() {
                    text.append(letter)
                    origin.append(line.index(i, offsetBy: min(k, count - 1)))
                }
            } else {
                for k in line[i..<j].indices { text.append(line[k]); origin.append(k) }
            }
            i = j
        }
        origin.append(line.endIndex)
        return (text, origin)
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
        reading.values += repeats(of: reading.values, in: strings)
        return reading
    }

    /// A number a label announces, printed again elsewhere on the page
    /// without it, is the same field's value there: a doctor's stamp
    /// repeats the practice's and the doctor's numbers from the form's
    /// boxes, and neither is a phone number for that.
    private static func repeats(of values: [Value], in strings: [String]) -> [Value] {
        var found: [Value] = []
        for value in values where [.healthInsuranceNumber, .identificationNumber, .institutionNumber].contains(value.entity) {
            let digits = String(strings[value.line][value.range].filter(\.isNumber))
            guard digits.count >= 7 else { continue }
            for (i, line) in strings.enumerated() {
                var from = line.startIndex
                while let place = line.range(of: digits, range: from..<line.endIndex) {
                    from = place.upperBound
                    // The whole number, not part of a longer one, nor a place already read.
                    guard place.lowerBound == line.startIndex || !line[line.index(before: place.lowerBound)].isNumber,
                          place.upperBound == line.endIndex || !line[place.upperBound].isNumber,
                          !(values + found).contains(where: { $0.line == i && $0.range.overlaps(place) }) else { continue }
                    found.append(Value(line: i, range: place, entity: value.entity, role: value.role,
                                       confidence: value.confidence, label: value.label))
                }
            }
        }
        return found
    }

    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) * 0.5
    }

    /// How far left of its label a value may start, as forms are printed
    /// a little off their boxes.
    private static let slack: CGFloat = 0.04

    private static func values(of label: Found, among found: [Found], _ strings: [String], boxes: [CGRect],
                               place: (Int, Range<String.Index>) -> CGRect) -> [Value] {
        // A caption announces nothing.
        guard label.field.lines > 0 else { return [] }
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
        let framed = unframed(trimmed(start..<nextOnLine, in: string), in: string)
        // A border or a comma read after a label, "Arzt-Nr. |", "Arzt-Nr.,", is no value: look beside and under it.
        let inline = string[framed].contains(where: { $0.isLetter || $0.isNumber }) ? framed : framed.upperBound..<framed.upperBound
        // What is read far along the label's line, apart from it, is another
        // column's, as a checkbox's words across the page: it ends the label's.
        var far: CGFloat?
        if !inline.isEmpty {
            // On its line: after a colon, or a date or a number of its own.
            if colon || entity.isTyped, let read = shaped(inline, in: string, as: entity) {
                return [value(label.line, read.range, entity, read.confidence)]
            }
            let after = place(label.line, inline)
            let letter = label.box.width / CGFloat(max(1, string.distance(from: label.range.lowerBound, to: label.range.upperBound)))
            guard after.minX - label.box.maxX > letter * 4 else { return [] }
            far = after.minX
        }
        // Its row: the next label to its right ends its column.
        let nextLabel = found.filter { $0.line != label.line || $0.range != label.range }
            .filter { sameRow($0.box, label.box) && $0.box.minX > label.box.maxX - 0.002 }
            .map(\.box.minX).min()
        let right = [nextLabel, far].compactMap { $0 }.min()
        let headed = found.contains { sameRow($0.box, label.box) && $0.box.maxX <= label.box.minX + 0.002 }

        // Beside it on its row, as "Vorname:" and its value in the next column.
        let beside = boxes.indices.filter { i in
            i != label.line && i < strings.count && sameRow(boxes[i], label.box)
                && boxes[i].minX >= label.box.maxX - 0.005 && boxes[i].minX < (right ?? label.box.maxX + 0.35)
        }.min { boxes[$0].minX < boxes[$1].minX }
        // A value beside its label is sure by its colon, by a shape of its own, a
        // date or a number, or as a name of one line close by, as a shop's
        // "Vorname | Max". Else it counts only where nothing is under the label: a
        // form's box holds its value under it, and words beside it, like a doctor's
        // stamp beside "Diagnose" or a box's caption beside the insured person's
        // name, are another column's.
        var besideValue: Value?
        if let beside {
            let line = strings[beside]
            let end = found.filter { $0.line == beside }.map(\.range.lowerBound).min() ?? line.endIndex
            let range = unframed(trimmed(line.startIndex..<end, in: line), in: line)
            if !range.isEmpty, let read = shaped(range, in: line, as: entity) {
                let near = value(beside, read.range, entity, read.confidence)
                let close = boxes[beside].minX - label.box.maxX <= label.box.width
                if colon || entity.isTyped
                    || entity == .personName && label.field.lines == 1 && read.confidence == .high && close {
                    return [near]
                }
                besideValue = near
            }
        }

        // Under it, in its column, on as many lines as the field takes.
        let left = label.box.minX - slack
        let columnRight = right.map { $0 - 0.005 } ?? .greatestFiniteMagnitude
        var values: [Value] = []
        var above = label.box
        var used = Set<Int>([label.line])
        var names = 0
        // Where the value's first line starts: the lines after it start there too.
        var opening: CGRect?
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
                guard let cut = column(of: i, in: strings[i], from: left, to: columnRight, place: place) else { continue }
                // Where the part that would be the value is: a small label read
                // on its line, like "geb. am" between two rows, is not.
                let end = found.filter { $0.line == i && $0.range.lowerBound > cut.lowerBound }.map(\.range.lowerBound).min()
                let piece = end.map { trimmed(cut.lowerBound..<min($0, cut.upperBound), in: strings[i]) } ?? cut
                // What the form prints in the column, like a box's caption
                // beside the name's box, is no line of a person's details.
                if entity == .personName, DocumentSense.isFormText(String(strings[i][piece])) { continue }
                // A border read on its own, "|", is no line of the value.
                guard !unframed(piece, in: strings[i]).isEmpty else { continue }
                let pieceBox = place(i, piece)
                // Under the last line; or the first, printed over its label, as
                // a printer off the form's boxes types it: starting within the
                // label, no higher, and reaching below it.
                let over = n == 0 && pieceBox.maxY <= label.box.maxY + 0.002 && pieceBox.minY < label.box.minY
                    && pieceBox.minX < label.box.maxX - 0.005
                guard pieceBox.maxY <= above.minY + above.height * 0.3 || over,
                      above.minY - pieceBox.maxY < max(above.height, pieceBox.height) * (n == 0 ? 1.8 : 1.2) else { continue }
                // A line under a label alone on its row starts in its column,
                // unless its part there stands apart from the words before it,
                // as a box's value does where a row of boxes is read as one line.
                guard headed || nextLabel != nil || box.minX >= left || apart(cut, of: i, in: strings[i], place: place)
                else { continue }
                // A value starts under its label, not across the page.
                if opening == nil, pieceBox.minX > label.box.maxX + slack { continue }
                // The lines of one value start where its first does: what starts
                // further along, like "geb. am" beside a name, is another field's.
                if let opening, abs(place(i, unframed(cut, in: strings[i])).minX - opening.minX) > slack { continue }
                if let current = best, !nearer(pieceBox, than: current.box) { continue }
                best = (i, cut, pieceBox)
            }
            guard let best else { break }
            // The next row of labels ends the value; a label further along
            // the line, like "geb. am" after a given name, ends only its part.
            if found.contains(where: { $0.line == best.line && $0.range.overlaps(best.range)
                && $0.range.lowerBound <= best.range.lowerBound }) { break }
            let line = strings[best.line]
            let range = unframed(found.filter { $0.line == best.line && $0.range.lowerBound > best.range.lowerBound }
                .map(\.range.lowerBound).min().map { trimmed(best.range.lowerBound..<min($0, best.range.upperBound), in: line) }
                ?? best.range, in: line)
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
            if opening == nil { opening = place(best.line, range) }
            // A value of a shape of its own takes one line.
            if entity.isTyped { break }
        }
        if values.isEmpty, let besideValue { return [besideValue] }
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

    /// Whether the part of a line in a column stands apart from the word
    /// before it by more than a space or two, as the values of a row of
    /// boxes do when they are read as one line, and no sentence's words do.
    private static func apart(_ cut: Range<String.Index>, of index: Int, in line: String,
                              place: (Int, Range<String.Index>) -> CGRect) -> Bool {
        let all = words(in: line)
        guard let previous = all.last(where: { $0.upperBound <= cut.lowerBound }),
              let first = all.first(where: { $0.lowerBound >= cut.lowerBound }) else { return true }
        let box = place(index, first)
        let letter = box.width / CGFloat(max(1, line.distance(from: first.lowerBound, to: first.upperBound)))
        return box.minX - place(index, previous).maxX > letter * 2.5
    }

    /// Strokes text recognition reads a box's border as.
    private static let strokes: Set<Character> = ["|", "¦", "l", "I", "ł", "!", "[", "]"]

    /// A value without the box's borders read at its edges: "| Mustermann",
    /// "Sonnenhang 9 |", "l345678812", "05.10.2026ł". A stroke on its own is
    /// dropped, and one stuck to a word only where no word has it: a bar
    /// anywhere, a small "l" before a number's digits, one after them. The
    /// postal block reads its lines so too (`Finder.bare`,
    /// `DocumentSense.namePart`).
    static func unframed(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var lower = range.lowerBound, upper = range.upperBound
        while lower < upper {
            if line[lower].isWhitespace { lower = line.index(after: lower); continue }
            let last = line.index(before: upper)
            if line[last].isWhitespace { upper = last; continue }
            let second = line.index(after: lower)
            let first = line[lower]
            if strokes.contains(first), second == upper || line[second].isWhitespace || "|¦[]".contains(first)
                || "lł".contains(first) && line[second].isNumber {
                lower = second
                continue
            }
            let end = line[last]
            if strokes.contains(end), last == lower || line[line.index(before: last)].isWhitespace || "|¦[]".contains(end)
                || "lłI".contains(end) && line[line.index(before: last)].isNumber {
                upper = last
                continue
            }
            break
        }
        return lower..<upper
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
            // What the form prints, like a box's label beside the field, is no one's.
            if DocumentSense.isOrganization(piece) || DocumentSense.isFormText(piece) { return nil }
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
