#if DEBUG && canImport(Vision) && canImport(CoreImage) && canImport(CoreText) && canImport(PDFKit)
import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// What Vision reads on made-up pages, put in reading order (`ScanReading`):
/// the invoice, the practice's letter with its column down the right, the
/// same letter with its small grey print, a receipt and a page turned on its
/// side. The text goes to the log (and, with SCAN_CAPTURES set, to a file
/// each), so the engine is tuned on what Vision really gives and not on
/// what it was thought to give. What is asserted holds whatever the order:
/// words are read, and a covered place hides every word of its line. Made-up
/// data only.
final class ScanReadingFixtureTests: XCTestCase {
    private func pages() throws -> [(name: String, image: CGImage)] {
        [("invoice", try XCTUnwrap(ScanSample.page())),
         ("letter", try XCTUnwrap(ScanSample.letter())),
         ("small-print", try XCTUnwrap(ScanSample.textLetter(dpi: 200))),
         ("receipt", try XCTUnwrap(PDFFixtures.receipt())),
         ("sideways", try XCTUnwrap(PDFFixtures.sideways()))]
    }

    private func keep(_ name: String, _ text: String) {
        guard let path = ProcessInfo.processInfo.environment["SCAN_CAPTURES"], !path.isEmpty else { return }
        try? text.write(to: URL(fileURLWithPath: path).appendingPathComponent("reading-\(name).txt"), atomically: true, encoding: .utf8)
    }

    func testMadeUpPagesAreReadAndTheirTextIsKept() throws {
        for (name, image) in try pages() {
            let lines = try XCTUnwrap(Finder.lines(in: image), name)
            let page = ScanCleaner.page(lines, aspect: ScanCleaner.aspect(of: image))
            let text = ScanReading.text(page)
            let confidences = Dictionary(grouping: lines.map { String(format: "%.2f", $0.confidence) }, by: { $0 })
                .map { "\($0.key)×\($0.value.count)" }.sorted().joined(separator: " ")
            let shape = page.blocks.map { block -> String in
                switch block {
                case .paragraph(let paragraph):
                    return "\(paragraph.heading ? "heading" : paragraph.flows ? "prose" : "lines")(\(paragraph.lines.count))"
                case .table(let table):
                    return "table(\(table.rows.count)×\(table.rows.map(\.count).max() ?? 0))"
                }
            }.joined(separator: " ")
            print("READING \(name) (\(lines.count) lines; confidence \(confidences); blocks \(shape))\n\(text)\n--")
            keep(name, text)
            XCTAssertFalse(text.isEmpty, name)
            // What Vision gave, line by line with its words' places, to make tests from.
            let raw = lines.map { line -> String in
                let words = line.words.compactMap { word -> String? in
                    guard let range = Range(word.range, in: line.string) else { return nil }
                    return String(format: "%@@%.4f,%.4f,%.4f,%.4f", String(line.string[range]),
                                  word.box.minX, word.box.minY, word.box.width, word.box.height)
                }
                return String(format: "%.2f ", line.confidence) + words.joined(separator: " ")
            }
            print("RAW \(name) \(ScanCleaner.aspect(of: image))\n\(raw.joined(separator: "\n"))\n--")
        }
    }

    func testACoveredLineIsAMarkAndNeverItsWords() throws {
        let image = try XCTUnwrap(ScanSample.letter())
        let lines = try XCTUnwrap(Finder.lines(in: image))
        let hidden = lines.filter { $0.string.contains("Brandtner") || $0.string.contains("Brandtnar") }.map(\.box)
        XCTAssertFalse(hidden.isEmpty, "Vision reads the owner's name on the letter")
        let text = ScanReading.text(ScanCleaner.page(lines, hiding: hidden, aspect: ScanCleaner.aspect(of: image)))
        print("READING letter, covered\n\(text)\n--")
        XCTAssertFalse(text.contains("Brandtner"), text)
        XCTAssertFalse(text.contains("Brandtnar"), text)
        XCTAssertTrue(text.contains(ScanReading.mark), text)
    }
}
#endif
