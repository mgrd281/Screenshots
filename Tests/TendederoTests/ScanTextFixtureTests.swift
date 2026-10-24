#if DEBUG && canImport(Vision) && canImport(CoreImage) && canImport(CoreText)
import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Small grey print through the whole scan, as Vision reads it: a made-up
/// practice's letter (`ScanSample.textLetter`) with a column of 7 pt grey
/// print in a light face, blue headings, an e-mail address, an IBAN-like
/// number and words with ä, ö, ü, ß and É, printed at 200 dots an inch and,
/// softer, at 150, photographed and made ready as the Scan tab makes a page.
/// Cleaning may make text clearer, never different: a line read surely
/// before cleaning reads the same after, every dot and accent; the grey
/// print comes out dark, its strokes whole, and the blue stays blue. With
/// SCAN_CAPTURES set, crops of the photo and the page at 100 % and 300 %
/// are kept, with the numbers. Made-up data only.
final class ScanTextFixtureTests: XCTestCase {
    private struct Made {
        let photo: ScanSample.Photo
        let prepared: ScanCleaner.Prepared
        let seconds: Double
        let before: [Finder.TextLine]
        let after: [Finder.TextLine]
    }

    private static var made: [Int: Made] = [:]

    private func made(dpi: Int) async throws -> Made {
        if let made = Self.made[dpi] { return made }
        let page = try XCTUnwrap(ScanSample.textLetter(dpi: Double(dpi)))
        let photo = try XCTUnwrap(ScanSample.photographed(page))
        let start = Date()
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: photo.quad, mode: .color))
        let seconds = Date().timeIntervalSince(start)
        let before = try XCTUnwrap(Finder.lines(in: prepared.straightened))
        let made = Made(photo: photo, prepared: prepared, seconds: seconds, before: before, after: prepared.checked.reading)
        Self.made[dpi] = made
        keep(made, dpi: dpi)
        return made
    }

    // MARK: Reading

    /// What a reading says on the row of the line most like `text`: its
    /// lines there, left to right, joined, without spaces; and where.
    private func said(_ lines: [Finder.TextLine], _ text: String) -> (text: String, box: CGRect, sure: Float)? {
        let wanted = ScanContent.compact(text)
        guard let best = lines.min(by: {
            distance(ScanContent.compact($0.string), wanted) < distance(ScanContent.compact($1.string), wanted)
        }) else { return nil }
        let row = lines.filter { ScanContent.sameRow($0.box, best.box) && abs($0.box.minX - best.box.minX) < 0.3 }
            .sorted { $0.box.minX < $1.box.minX }
        let joined = ScanContent.compact(row.map(\.string).joined())
        // A neighbour's words joined to the line are no part of it.
        let part = closest(in: joined, to: wanted)
        return (part, row.map(\.box).reduce(best.box) { $0.union($1) }, best.confidence)
    }

    /// The stretch of `text` most like `wanted`, as long as it.
    private func closest(in text: String, to wanted: String) -> String {
        let characters = Array(text), length = wanted.count
        guard characters.count > length else { return text }
        var best = text, bestDistance = Int.max
        for start in 0...(characters.count - length) {
            let part = String(characters[start..<(start + length)])
            let d = distance(part, wanted)
            if d < bestDistance { bestDistance = d; best = part }
        }
        return best
    }

    /// How many characters must change, be added or taken away to make one
    /// text the other.
    private func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var row = Array(0...y.count)
        for i in 1...x.count {
            var previous = row[0]
            row[0] = i
            for j in 1...y.count {
                let kept = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (x[i - 1] == y[j - 1] ? 0 : 1))
                previous = kept
            }
        }
        return row[y.count]
    }

    /// Each printed line's characters as read before and after cleaning:
    /// how many differ from the truth.
    private struct Line {
        let print: ScanSample.Print
        let text: String
        let before: Int
        let after: Int
        let sure: Float
        let box: CGRect?
        let readBefore: String
        let readAfter: String
    }

    private func lines(_ made: Made) -> [Line] {
        ScanSample.textLines.map { print, text in
            let truth = ScanContent.compact(text)
            let before = said(made.before, text), after = said(made.after, text)
            return Line(print: print, text: text, before: before.map { distance($0.text, truth) } ?? truth.count,
                        after: after.map { distance($0.text, truth) } ?? truth.count, sure: before?.sure ?? 0,
                        box: after?.box, readBefore: before?.text ?? "", readAfter: after?.text ?? "")
        }
    }

    private func report(_ dpi: Int, _ made: Made, _ lines: [Line]) {
        let done = made.prepared.guarded
        var text = "text letter at \(dpi) dpi: prepared in \(String(format: "%.1f", made.seconds)) s on this Mac (debug build)\n"
        text += "  guard: \(done.changed) lines read otherwise after cleaning; \(done.alone) read as before on their own, "
            + "\(done.gently) cleaned again gently, \(done.evened) kept as evened, \(done.otherwise) read otherwise even as evened\n"
        for line in lines {
            text += "  \(line.print.rawValue) \(line.text): before \(line.before), after \(line.after) wrong, sure \(String(format: "%.2f", line.sure))"
            if line.before > 0 || line.after > 0 { text += " (read \"\(line.readBefore)\", then \"\(line.readAfter)\")" }
            text += "\n"
        }
        print(text)
        ScanFixtureTests.write("text-\(dpi).txt", text)
    }

    // MARK: Checks

    /// Cleaning never changes a character read right: not a dot, not an
    /// accent, not a digit. Every line read surely and as printed before
    /// reads as printed after, and the letter as a whole reads no worse.
    func testCleaningChangesNoCharacterOfALineReadSurely() async throws {
        for dpi in [200, 150] {
            let made = try await made(dpi: dpi)
            let lines = lines(made)
            report(dpi, made, lines)
            for line in lines where line.sure >= ScanContent.sure && line.before == 0 {
                XCTAssertEqual(line.after, 0, "\(dpi) dpi: \(line.text) read as \"\(line.readAfter)\" after cleaning")
            }
            XCTAssertLessThanOrEqual(lines.reduce(0) { $0 + $1.after }, lines.reduce(0) { $0 + $1.before },
                                     "\(dpi) dpi: the letter reads no worse")
        }
    }

    /// At 200 dots an inch every line reads as printed, after cleaning: the
    /// body all of it, the grey column 99.5 % of its characters. A dash or a
    /// centred dot read as another of its kind is the same character
    /// (`ScanContent.compact`).
    func testTheLetterReadsAsPrintedAfterCleaning() async throws {
        let made = try await made(dpi: 200)
        let lines = lines(made)
        let body = lines.filter { $0.print == .body }, grey = lines.filter { $0.print != .body }
        let greyCharacters = grey.reduce(0) { $0 + ScanContent.compact($1.text).count }
        let greyAccuracy = 1 - Double(grey.reduce(0) { $0 + $1.after }) / Double(greyCharacters)
        print("TEXT 200 dpi: grey column \(String(format: "%.4f", greyAccuracy)), body changed \(body.reduce(0) { $0 + $1.after })")
        XCTAssertEqual(body.reduce(0) { $0 + $1.after }, 0, "the body as printed: \(body.filter { $0.after > 0 }.map(\.text))")
        XCTAssertGreaterThanOrEqual(greyAccuracy, 0.995,
                                    "the grey column: \(grey.filter { $0.after > 0 }.map { "\($0.text) read \($0.readAfter)" })")
    }

    /// The grey print comes out dark: in each of its lines, the middle of
    /// the darkest 30 % of the pixels in the box round its ink at 70 or
    /// darker; and the blue headings keep their hue. Vision's own box, with
    /// its margin of paper, is reported beside it.
    func testTheGreyPrintIsDarkAndTheBlueStaysBlue() async throws {
        for dpi in [200, 150] {
            let made = try await made(dpi: dpi)
            let page = try XCTUnwrap(ScanCleaner.bitmap(made.prepared.cleaned))
            let photo = try XCTUnwrap(ScanCleaner.bitmap(made.prepared.straightened))
            for line in lines(made) where line.print != .body {
                let box = try XCTUnwrap(line.box, "\(line.text) is read")
                let pixels = self.pixels(page, in: box)
                if line.print == .grey {
                    let inked = self.inked(page, in: box)
                    let middle = self.darkest(self.pixels(page, in: inked)), was = self.darkest(self.pixels(photo, in: inked))
                    print("TEXT \(dpi) dpi darkest 30 %: \(line.text) \(was) -> \(middle), in Vision's box \(self.darkest(pixels))")
                    XCTAssertLessThanOrEqual(middle, 70, "\(dpi) dpi: \(line.text) dark enough")
                } else {
                    let inked = pixels.filter { ScanClean.brightness($0.0, $0.1, $0.2) < 200 }
                    XCTAssertGreaterThan(inked.count, 20, "\(dpi) dpi: \(line.text) has ink")
                    let mean = inked.reduce((0.0, 0.0, 0.0)) { ($0.0 + Double($1.0), $0.1 + Double($1.1), $0.2 + Double($1.2)) }
                    let n = Double(max(1, inked.count))
                    let hue = ScanColourSample.hue(mean.0 / n, mean.1 / n, mean.2 / n)
                    XCTAssertLessThanOrEqual(ScanColourSample.apart(hue, ScanColourSample.hue(64, 128, 196)), 10,
                                             "\(dpi) dpi: \(line.text) keeps its blue")
                }
            }
        }
    }

    /// The part of a box its ink reaches: the rows and columns with a pixel
    /// darker than 160.
    private func inked(_ page: ScanBitmap, in box: CGRect) -> CGRect {
        let w = Double(page.width), h = Double(page.height)
        let x0 = max(0, Int(box.minX * w)), x1 = min(page.width, Int(box.maxX * w))
        let y0 = max(0, Int((1 - box.maxY) * h)), y1 = min(page.height, Int((1 - box.minY) * h))
        var left = x1, right = x0, top = y1, bottom = y0
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                let i = (y * page.width + x) * 4
                guard ScanClean.brightness(page.pixels[i], page.pixels[i + 1], page.pixels[i + 2]) < 160 else { continue }
                left = min(left, x); right = max(right, x + 1); top = min(top, y); bottom = max(bottom, y + 1)
            }
        }
        guard right > left, bottom > top else { return box }
        return CGRect(x: Double(left) / w, y: 1 - Double(bottom) / h, width: Double(right - left) / w, height: Double(bottom - top) / h)
    }

    /// The middle of the darkest 30 % of a box's pixels.
    private func darkest(_ pixels: [(UInt8, UInt8, UInt8)]) -> Int {
        let values = pixels.map { Int(ScanClean.brightness($0.0, $0.1, $0.2)) }.sorted()
        let darkest = values.prefix(max(1, values.count * 3 / 10))
        return darkest[darkest.startIndex + darkest.count / 2]
    }

    private func pixels(_ page: ScanBitmap, in box: CGRect) -> [(UInt8, UInt8, UInt8)] {
        let w = Double(page.width), h = Double(page.height)
        let x0 = max(0, Int(box.minX * w)), x1 = min(page.width, Int(box.maxX * w))
        let y0 = max(0, Int((1 - box.maxY) * h)), y1 = min(page.height, Int((1 - box.minY) * h))
        var out: [(UInt8, UInt8, UInt8)] = []
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                let i = (y * page.width + x) * 4
                out.append((page.pixels[i], page.pixels[i + 1], page.pixels[i + 2]))
            }
        }
        return out
    }

    // MARK: Captures

    /// The grey column, an umlaut line, the e-mail line, a blue heading and
    /// the digits, before cleaning and after, at 100 % and at 300 %.
    private func keep(_ made: Made, dpi: Int) {
        guard ProcessInfo.processInfo.environment["SCAN_CAPTURES"] != nil else { return }
        let parts: [(String, [String])] = [
            ("column", ["RADIOLOGIE AM MUSTERWALL", "Radiologie Süderstraße"]),
            ("umlauts", ["Ärzte für Radiologie", "Dr. med. René Brückner"]),
            ("email", ["praxis@radiologie-musterwall.de", "praxis@radiologie-musterwall.de"]),
            ("blue", ["RADIOLOGIE AM MUSTERWALL", "MAMMA-DIAGNOSTIK"]),
            ("digits", ["DE12 3456 7890 1234 5678 90", "BIC MUSTDEHHXXX"]),
        ]
        for (name, ends) in parts {
            guard let first = said(made.after, ends[0]), let last = said(made.after, ends[1]) else { continue }
            let box = first.box.union(last.box).insetBy(dx: -0.01, dy: -0.006)
            for (which, picture) in [("before", made.prepared.straightened), ("after", made.prepared.cleaned)] {
                let w = CGFloat(picture.width), h = CGFloat(picture.height)
                let rect = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h).integral
                guard let crop = picture.cropping(to: rect) else { continue }
                ScanFixtureTests.keep(crop, "text-\(dpi)-\(name)-\(which)", longest: 4000)
                if let large = Self.enlarged(crop, by: 3) {
                    ScanFixtureTests.keep(large, "text-\(dpi)-\(name)-\(which)-300", longest: 4000)
                }
            }
        }
    }

    /// A picture three times as large, each pixel a square, as a loupe shows it.
    private static func enlarged(_ image: CGImage, by scale: Int) -> CGImage? {
        let width = image.width * scale, height = image.height * scale
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
#endif
