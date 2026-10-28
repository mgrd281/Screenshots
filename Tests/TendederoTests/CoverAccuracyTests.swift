import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// How well the recommended kinds cover the made-up documents of
/// `CoverCorpus`: of each kind, in each language and each sort of document,
/// how many details are covered whole, and how much of what should stay is
/// covered anyway. The log says it line by line ("ACCURACY", "MISSED",
/// "OVER"), and the test fails when a kind falls below its floor, so a
/// change that covers less than before is seen at once. Raise a floor when
/// the engine gets better; never lower one to let a change through.
final class CoverAccuracyTests: XCTestCase {
    /// The least share of each kind that must be covered whole, as last
    /// measured.
    static let floors: [PrivateDetail: Double] = [:]
    /// The most of what should stay that may be covered.
    static let overCoverCeiling = 1.0

    struct Tally {
        var whole = 0
        var partly = 0
        var total = 0
        var share: Double { total == 0 ? 1 : Double(whole) / Double(total) }
        var said: String {
            String(format: "%d/%d (%.1f%%), %d partly", whole, total, share * 100, partly)
        }
    }

    func testTheMadeUpDocumentsAreCoveredAsWellAsBefore() {
        var kinds: [PrivateDetail: Tally] = [:], languages: [String: Tally] = [:], types: [String: Tally] = [:]
        var all = Tally(), kept = 0, touched = 0
        var missed: [String] = [], over: [String] = []
        for document in CoverCorpus.documents {
            let covered = coveredCharacters(document)
            for secret in document.secrets {
                let characters = significant(secret, in: document)
                let hidden = characters.filter { covered[secret.line]?.contains($0) == true }.count
                let whole = hidden == characters.count
                let kind = secret.kind!
                kinds[kind, default: Tally()].total += 1
                if whole { kinds[kind]!.whole += 1 } else if hidden > 0 { kinds[kind]!.partly += 1 }
                languages[document.language, default: Tally()].total += 1
                types[document.type, default: Tally()].total += 1
                all.total += 1
                if whole {
                    languages[document.language]!.whole += 1
                    types[document.type]!.whole += 1
                    all.whole += 1
                } else {
                    if hidden > 0 { all.partly += 1 }
                    let partly = hidden > 0 ? " (partly)" : ""
                    missed.append("MISSED \(document.name) \(kind.rawValue)\(partly): \"\(secret.text)\" in "
                        + "\"\(document.lines[secret.line])\"")
                }
            }
            for part in document.kept {
                kept += 1
                let characters = significant(part, in: document)
                if characters.contains(where: { covered[part.line]?.contains($0) == true }) {
                    touched += 1
                    over.append("OVER \(document.name): \"\(part.text)\" in \"\(document.lines[part.line])\"")
                }
            }
        }

        print("ACCURACY all \(all.said)")
        for kind in PrivateDetail.allCases {
            if let tally = kinds[kind] { print("ACCURACY kind \(kind.rawValue) \(tally.said)") }
        }
        for (language, tally) in languages.sorted(by: { $0.key < $1.key }) {
            print("ACCURACY language \(language) \(tally.said)")
        }
        for (type, tally) in types.sorted(by: { $0.key < $1.key }) {
            print("ACCURACY type \(type) \(tally.said)")
        }
        let overShare = kept == 0 ? 0 : Double(touched) / Double(kept)
        print(String(format: "ACCURACY kept %d of %d stayed (%.1f%% covered anyway)", kept - touched, kept,
                     overShare * 100))
        missed.forEach { print($0) }
        over.forEach { print($0) }

        for (kind, floor) in Self.floors {
            let share = kinds[kind]?.share ?? 1
            XCTAssertGreaterThanOrEqual(share, floor,
                                        "\(kind.rawValue) covered less than before: \(kinds[kind]?.said ?? "")")
        }
        XCTAssertLessThanOrEqual(overShare, Self.overCoverCeiling, "more of what should stay is covered than before")
    }

    func testTheCorpusIsWhatItSays() {
        let documents = CoverCorpus.documents
        XCTAssertEqual(documents.count, 98)
        XCTAssertEqual(Set(documents.map(\.language)).count, 7)
        for document in documents {
            for part in document.secrets + document.kept {
                let line = Array(document.lines[part.line])
                XCTAssertEqual(String(line[part.range]), part.text, document.name)
            }
        }
        // Account numbers carry their check digits, as real ones do.
        XCTAssertEqual(CoverCorpus.iban("DE", "370400440532013000"), "DE89 3704 0044 0532 0130 00")
        XCTAssertEqual(CoverCorpus.dni(12_345_678), "12345678Z")
        XCTAssertEqual(CoverCorpus.cpf([1, 2, 3, 4, 5, 6, 7, 8, 9]), "123.456.789-09")
        XCTAssertEqual(CoverCorpus.kimlik([1, 0, 0, 0, 0, 0, 0, 1, 4]), "10000000146")
    }

    // MARK: Measuring

    /// The characters of a part that count: all but spaces.
    private func significant(_ part: CoverCorpus.Marked, in document: CoverCorpus.Document) -> [Int] {
        let line = Array(document.lines[part.line])
        return part.range.filter { !line[$0].isWhitespace }
    }

    /// Which characters of each line the recommended kinds cover, those
    /// marked to check too, as the app shows them; what is only offered is
    /// not covered.
    private func coveredCharacters(_ document: CoverCorpus.Document) -> [Int: Set<Int>] {
        let lines = document.lines
        let boxes = lines.indices.map { i in
            CGRect(x: 0.1, y: 0.9 - CGFloat(i) * 0.03, width: CGFloat(lines[i].count) * 0.01, height: 0.02)
        }
        func part(_ index: Int, _ range: Range<String.Index>) -> CGRect? {
            let line = lines[index]
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let count = line.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: boxes[index].minX + CGFloat(start) * 0.01, y: boxes[index].minY,
                          width: CGFloat(count) * 0.01, height: boxes[index].height)
        }
        let found = Finder.findings(lines, boxes: boxes, part: part, PrivateDetail.recommended)
        var covered: [Int: Set<Int>] = [:]
        for hit in found.hits {
            let line = lines[hit.line]
            let range = hit.range.flatMap { Range($0, in: line) } ?? line.startIndex..<line.endIndex
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let end = line.distance(from: line.startIndex, to: range.upperBound)
            covered[hit.line, default: []].formUnion(start..<end)
        }
        return covered
    }
}
