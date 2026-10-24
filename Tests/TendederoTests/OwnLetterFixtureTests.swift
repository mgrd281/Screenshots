#if DEBUG && canImport(Vision) && canImport(CoreImage) && canImport(CoreText)
import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The owner's name and address, kept in Always Hide, covered on a made-up
/// letter as Vision reads it (`ScanSample.letter`): printed, and
/// photographed then made ready as the Scan tab makes a page, whatever
/// kinds are on, in every way the letter writes them (`ownVariants`). The
/// date of birth too, where its kind is on. With SCAN_CAPTURES set, the
/// photo and the covered page are kept. Made-up data only.
final class OwnLetterFixtureTests: XCTestCase {
    private static var made: ScanCleaner.Prepared?
    private let rules = [ScanSample.ownName, ScanSample.ownAddress]

    private func printed() throws -> CGImage {
        try XCTUnwrap(ScanSample.letter())
    }

    /// The letter photographed and made ready, once for the tests.
    private func scanned() async throws -> CGImage {
        if let made = Self.made { return made.cleaned }
        let photo = try XCTUnwrap(ScanSample.photographed(try printed()))
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        Self.made = prepared
        ScanFixtureTests.keep(photo.image, "own-letter-photo", longest: 1600)
        return prepared.cleaned
    }

    /// Where a part of a line is, as Vision read the page: the shortest
    /// line with the words round it, a space after a comma or not.
    private func place(of part: (line: String, part: String), in lines: [Finder.TextLine]) -> CGRect? {
        func pattern(_ text: String) -> String {
            NSRegularExpression.escapedPattern(for: text)
                .replacingOccurrences(of: ",", with: #",\s?"#)
                .replacingOccurrences(of: " ", with: #"\s+"#)
        }
        let found = lines.filter { $0.string.range(of: pattern(part.line), options: .regularExpression) != nil }
            .min { $0.string.count < $1.string.count }
        guard let line = found,
              let range = line.string.range(of: pattern(part.part), options: [.regularExpression, .backwards])
        else { return nil }
        return line.box(for: range)
    }

    /// Every way the letter writes the owner's details, on this page, under
    /// a cover; what was not read or not covered is named.
    private func check(_ image: CGImage, _ chosen: Set<PrivateDetail>, _ page: String) -> [String] {
        let lines = Finder.textLines(in: image)
        let found = Finder.analysis(in: image, chosen, rules: rules, intelligence: false, spare: true)
        var missed: [String] = []
        for variant in ScanSample.ownVariants {
            for part in variant.parts {
                guard let box = place(of: part, in: lines) else {
                    missed.append("\(variant.name): \"\(part.part)\" not read")
                    continue
                }
                let middle = CGPoint(x: box.midX, y: box.midY)
                if !found.areas.contains(where: { $0.rect.contains(middle) }) {
                    missed.append("\(variant.name): \"\(part.part)\" not covered")
                }
            }
        }
        print("OWN LETTER \(page) \(chosen.map(\.rawValue).sorted()): \(missed.isEmpty ? "all covered" : missed.joined(separator: "; "))")
        print("OWN LETTER read: \(lines.map(\.string))")
        return missed
    }

    func testTheOwnersDetailsAreCoveredOnThePrintedLetterWithEveryKindOff() throws {
        XCTAssertEqual(check(try printed(), [], "printed"), [])
    }

    func testTheOwnersDetailsAreCoveredOnTheScannedLetterWithEveryKindOff() async throws {
        let image = try await scanned()
        XCTAssertEqual(check(image, [], "scanned"), [])
    }

    func testTheOwnersDetailsAndTheBirthDateAreCoveredWithTheKindsOn() async throws {
        let image = try await scanned()
        let chosen = PrivateDetail.recommended.union([.names, .addresses, .birthDates])
        XCTAssertEqual(check(image, chosen, "scanned"), [])
        let lines = Finder.textLines(in: image)
        let found = Finder.analysis(in: image, chosen, rules: rules, intelligence: false, spare: true)
        let born = try XCTUnwrap(place(of: (ScanSample.birthDate, ScanSample.birthDate), in: lines), "the date of birth is read")
        XCTAssertTrue(found.areas.contains { $0.rect.contains(CGPoint(x: born.midX, y: born.midY)) }, "the date of birth is covered")
        if let covered = Finder.covered(image, chosen, rules: rules, intelligence: false, style: .ink)?.image {
            ScanFixtureTests.keep(covered, "own-letter-covered", longest: 1600)
        }
    }
}
#endif
