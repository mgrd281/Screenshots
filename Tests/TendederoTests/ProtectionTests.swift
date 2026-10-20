import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Tendedero

/// The protection around covering: every copy read again as anyone could
/// read it, the strongest protection covering whole lines, and Apple
/// Intelligence taken at its word only where its words are on the page.
final class ProtectionTests: XCTestCase {
    private let keys = ["strongestCover", "intelligenceOff", "aiFindsPrivate"]
    private var before: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        before = keys.reduce(into: [:]) { kept, key in kept[key] = UserDefaults.standard.object(forKey: key) }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.set(before[key], forKey: key) }
        super.tearDown()
    }

    /// A cover that leaves the end of an email showing: the check finds the
    /// piece beside it and covers that too.
    func testAPieceLeftBesideItsCoverIsCoveredToo() throws {
        let image = try drawn(["Mail lena.hoffmann@example.com"])
        let line = try XCTUnwrap(Finder.textLines(in: image).first { $0.string.contains("@") })
        let start = try XCTUnwrap(line.string.range(of: "lena"), line.string)
        let email = try XCTUnwrap(line.box(for: start.lowerBound..<line.string.endIndex))
        // Over the first part of the address only.
        let short = Finder.Area(rect: CGRect(x: email.minX, y: email.minY - email.height * 0.2,
                                             width: email.width * 0.4, height: email.height * 1.4),
                                kind: .emails, text: "lena.hoffmann@example.com")
        let covered = try XCTUnwrap(Finder.cover(image, areas: [short], style: .ink))
        let more = Finder.stillReadable(in: covered, hidden: [short], [.emails], rules: [])
        XCTAssertTrue(more.contains { $0.rect.maxX > short.rect.maxX && $0.kind == .emails }, "\(more)")
    }

    /// Covered and checked: nothing private can be read in what leaves.
    func testNothingPrivateCanBeReadInWhatLeaves() throws {
        let image = try drawn(["Mail lena.hoffmann@example.com", "Tel. +49 151 23456789"])
        let made = try XCTUnwrap(Finder.covered(image, [.emails, .phones], rules: [], intelligence: false, style: .ink))
        XCTAssertGreaterThanOrEqual(made.areas.count, 2)
        let read = Finder.textLines(in: made.image).map(\.string).joined(separator: " ")
        XCTAssertFalse(read.contains("@"), read)
        XCTAssertFalse(read.contains("hoffmann"), read)
        XCTAssertFalse(read.contains("23456789"), read)
    }

    /// A copy leaves only from a picture Vision could read: an ordinary one
    /// is read without a failure, and its copy is made, covered and checked.
    /// One read while Vision failed, as iOS may make it in the background,
    /// would give none (`CoveredCopy`).
    func testACoveredCopyIsMadeFromAPictureReadWithoutAFailure() async throws {
        let image = try drawn(["Mail lena.hoffmann@example.com"])
        let failures = Finder.failures
        let made = await CoveredCopy.make(image, [.emails], rules: [], style: .ink, intelligence: false)
        XCTAssertGreaterThanOrEqual(made?.report.kinds[.emails] ?? 0, 1)
        XCTAssertEqual(Finder.failures, failures)
    }

    func testTheStrongestProtectionCoversWholeLinesWithMoreRoom() throws {
        let image = try drawn(["Mail lena.hoffmann@example.com"])
        Finder.strongest = false
        let part = try XCTUnwrap(Finder.coveredAreas(in: image, [.emails], rules: [], intelligence: false).first)
        Finder.strongest = true
        let whole = try XCTUnwrap(Finder.coveredAreas(in: image, [.emails], rules: [], intelligence: false).first)
        XCTAssertLessThan(whole.rect.minX, part.rect.minX, "the label goes too")
        XCTAssertGreaterThan(whole.rect.height, part.rect.height, "more room above and below")
        XCTAssertEqual(whole.kind, .emails)
    }

    func testAppleIntelligenceIsTakenAtItsWordOnly() {
        let lines = ["Hallo Ahmed Ali,", "Ihre Bestellung", "Diagnose: Diabetes Typ 2", "Berlin"]
        let answer = """
            1: name: Ahmed Ali
            3: health: Diabetes Typ 2
            4: weather: sunny
            2: name: Lena Hoffmann
            9: name: Nobody
            none
            """
        XCTAssertEqual(Finder.parsePrivate(answer, lines: lines), [
            Finder.IntelligentPiece(line: 0, kind: .names, words: "Ahmed Ali"),
            Finder.IntelligentPiece(line: 2, kind: .health, words: "Diabetes Typ 2"),
        ])
        // A bullet, a capital and quotes are read through.
        XCTAssertEqual(Finder.parsePrivate("- 1: Name: \"Ahmed Ali\"", lines: lines).first?.words, "Ahmed Ali")
        XCTAssertTrue(Finder.parsePrivate("none", lines: []).isEmpty)
        // The screen is never held up waiting for an answer.
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertNil(Finder.intelligentPieces(for: ["Hallo Ahmed Ali, ich bin es."]))
    }

    func testTheProtectionChoicesAreKept() {
        XCTAssertFalse(Finder.strongest, "off until turned on")
        XCTAssertTrue(Finder.usesIntelligence, "on until turned off")
        Finder.strongest = true
        Finder.usesIntelligence = false
        XCTAssertTrue(Finder.strongest)
        XCTAssertFalse(Finder.usesIntelligence)
        // The AI assistant reads along only with a key and when turned on.
        XCTAssertFalse(Finder.asksAssistant)
        // Each tells covered copies apart.
        XCTAssertTrue(Finder.lookKey.hasSuffix(",true,false,false"), Finder.lookKey)
    }

    func testTheTimesKeptGiveTheMiddleAndTheSlowest() throws {
        XCTAssertNil(Timing.percentile([], 0.5))
        let times = Array(1...20).map { $0 * 100 }
        XCTAssertEqual(Timing.percentile(times, 0.5), 1000)
        XCTAssertEqual(Timing.percentile(times, 0.95), 1900)
        XCTAssertEqual(Timing.percentile([700], 0.95), 700)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TimingTests"))
        defaults.removePersistentDomain(forName: "TimingTests")
        for time in 1...60 { Timing.record(.ready, time, in: defaults) }
        XCTAssertEqual(Timing.recent(.ready, in: defaults).count, Timing.remembered, "the newest only")
        XCTAssertEqual(Timing.recent(.ready, in: defaults).first, 11)
        XCTAssertTrue(Timing.recent(.shown, in: defaults).isEmpty)
        defaults.removePersistentDomain(forName: "TimingTests")
    }

    // MARK: Helpers

    /// Lines of large black text on white, one under another.
    private func drawn(_ lines: [String]) throws -> CGImage {
        let width = 1600, height = 120 * lines.count + 80
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 100 - 120 * i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        return try XCTUnwrap(context.makeImage())
    }
}
