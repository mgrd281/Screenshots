import CoreGraphics
import Foundation

/// Text with its private details covered, as an AI app is given it: each
/// detail stands as a tag of its kind, like [NAME 1], the same tag wherever
/// the same detail comes again, so a reply can still say who is who without
/// the AI app ever reading it. Found as a screenshot's words are
/// (`Finder.findings`), with the owner's own details and rules.
enum TextCover {
    /// The text covered, and how many details were.
    struct Covered: Equatable {
        let text: String
        let count: Int
    }

    static func covered(_ text: String, _ chosen: Set<PrivateDetail>, rules: [OwnRule]) -> Covered {
        let lines = text.components(separatedBy: "\n")
        let page = layout(lines)
        let hits = Finder.findings(page.strings, boxes: page.boxes, part: page.part, chosen, rules: rules).hits
        // Each line's places, merged where they overlap, with the kind of the first.
        var places = [[(range: NSRange, kind: PrivateDetail?)]](repeating: [], count: lines.count)
        for hit in hits where lines.indices.contains(hit.line) {
            let length = (lines[hit.line] as NSString).length
            let range = hit.range ?? NSRange(location: 0, length: length)
            guard range.length > 0, range.location + range.length <= length else { continue }
            places[hit.line].append((range: range, kind: hit.kind))
        }
        var numbers: [String: Int] = [:]
        var counts: [String: Int] = [:]
        var count = 0
        let covered = lines.indices.map { i -> String in
            let line = lines[i] as NSString
            var kept = ""
            var from = 0
            for place in merged(places[i]) where place.range.location >= from {
                let found = line.substring(with: place.range)
                let label = tag(for: place.kind)
                // The same detail keeps its number, so a reply can follow it.
                let key = label + "|" + found.lowercased().trimmingCharacters(in: .whitespaces)
                let number: Int
                if let known = numbers[key] {
                    number = known
                } else {
                    number = (counts[label] ?? 0) + 1
                    counts[label] = number
                    numbers[key] = number
                }
                kept += line.substring(with: NSRange(location: from, length: place.range.location - from))
                kept += "[\(label) \(number)]"
                from = place.range.location + place.range.length
                count += 1
            }
            return kept + line.substring(from: from)
        }
        return Covered(text: covered.joined(separator: "\n"), count: count)
    }

    /// The tag a detail of this kind stands as, in English, as AI apps read it.
    static func tag(for kind: PrivateDetail?) -> String {
        switch kind {
        case .names?, .patientNames?, .otherPeople?: "NAME"
        case .addresses?: "ADDRESS"
        case .birthDates?: "BIRTH DATE"
        case .emails?: "EMAIL"
        case .phones?: "PHONE"
        case .bank?: "BANK DETAIL"
        case .health?: "HEALTH DETAIL"
        case .usernames?: "USERNAME"
        case .ipAddresses?: "IP ADDRESS"
        case .ids?: "ID NUMBER"
        case .codes?: "CODE"
        case .keys?: "KEY"
        case .orders?: "ORDER NUMBER"
        case .tracking?: "TRACKING NUMBER"
        case .amounts?: "AMOUNT"
        case .dates?: "DATE"
        case .links?: "LINK"
        case .organizations?: "COMPANY"
        case .faces?, .barcodes?, nil: "HIDDEN"
        }
    }

    /// Places that overlap or touch, as one, in order, keeping the first kind.
    static func merged(_ places: [(range: NSRange, kind: PrivateDetail?)]) -> [(range: NSRange, kind: PrivateDetail?)] {
        var merged: [(range: NSRange, kind: PrivateDetail?)] = []
        for place in places.sorted(by: { $0.range.location < $1.range.location }) {
            if let last = merged.last, place.range.location <= last.range.location + last.range.length {
                let end = max(last.range.location + last.range.length, place.range.location + place.range.length)
                merged[merged.count - 1].range = NSRange(location: last.range.location, length: end - last.range.location)
            } else {
                merged.append(place)
            }
        }
        return merged
    }

    /// Lines one under another, as a page prints them, so they are read as
    /// a screenshot's lines are.
    static func layout(_ lines: [String]) -> (strings: [String], boxes: [CGRect],
                                               part: (Int, Range<String.Index>) -> CGRect?) {
        // As a page's lines, three hundredths apart, closer where there are many.
        let spacing = min(0.03, 0.9 / Double(max(lines.count, 1)))
        let boxes: [CGRect] = lines.indices.map { i in
            CGRect(x: 0.05, y: 0.95 - Double(i + 1) * spacing, width: min(0.9, Double(lines[i].count) * 0.01),
                   height: spacing * 2 / 3)
        }
        let part: (Int, Range<String.Index>) -> CGRect? = { index, range in
            let line = lines[index]
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let count = line.distance(from: range.lowerBound, to: range.upperBound)
            let box = boxes[index]
            let unit = Double(box.width) / Double(max(line.count, 1))
            return CGRect(x: Double(box.minX) + Double(start) * unit, y: Double(box.minY),
                          width: Double(count) * unit, height: Double(box.height))
        }
        return (lines, boxes, part)
    }
}
