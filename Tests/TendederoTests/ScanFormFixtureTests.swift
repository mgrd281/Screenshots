#if DEBUG && canImport(Vision) && canImport(CoreImage)
import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The scan on made-up photos of a folded, typed sick note (`ScanForm`), as
/// a real one was photographed: pink carbon-copy paper folded a little over
/// halfway, light typewriter print, a blue signature across the fax number,
/// a grey printed header and a grey patch, on a grey floor, at an angle.
/// And the same on white and yellow paper, folded twice, and with a hand's
/// shadow. Each page is made ready once, as on an iPhone, and measured as
/// the brief's targets say; with SCAN_CAPTURES set, each photo is kept with
/// its page before and after and the numbers. Made-up data only.
final class ScanFormFixtureTests: XCTestCase {
    private static var made: [ScanForm.Variant: (photo: ScanForm.Photo, prepared: ScanCleaner.Prepared,
                                                 measures: ScanFormMeasures, seconds: Double)] = [:]

    /// The variant photographed, made ready in colour as the Scan tab does,
    /// and measured; once for all the tests.
    private func made(_ variant: ScanForm.Variant) async throws
        -> (photo: ScanForm.Photo, prepared: ScanCleaner.Prepared, measures: ScanFormMeasures, seconds: Double) {
        if let done = Self.made[variant] { return done }
        let photo = try XCTUnwrap(ScanForm.photographed(variant))
        // As the Scan tab does: the page found by Vision, then made ready.
        let quad = try XCTUnwrap(ScanCleaner.page(in: photo.image)?.quad, "Vision finds the sheet")
        let start = Date()
        let prepared = try XCTUnwrapAsync(await ScanCleaner.prepare(photo.image, quad: quad, mode: .color))
        let seconds = Date().timeIntervalSince(start)
        let bitmap = try XCTUnwrap(ScanCleaner.bitmap(prepared.cleaned))
        let measures = ScanFormMeasure.measure(bitmap, reading: prepared.checked.reading, variant: variant)
        let done = (photo, prepared, measures, seconds)
        Self.made[variant] = done
        ScanFixtureTests.keep(photo.image, "form-\(variant.rawValue)-photo", longest: 1600)
        ScanFixtureTests.keep(prepared.straightened, "form-\(variant.rawValue)-before", longest: 1600)
        ScanFixtureTests.keep(prepared.cleaned, "form-\(variant.rawValue)-after", longest: 1600)
        ScanFixtureTests.write("form-\(variant.rawValue).txt", """
            \(variant.rawValue): photo \(photo.image.width)×\(photo.image.height), \
            straightened \(prepared.straightened.width)×\(prepared.straightened.height), \
            cleaned \(prepared.cleaned.width)×\(prepared.cleaned.height) \
            (\(Int(ScanGeometry.dpi(width: prepared.cleaned.width, height: prepared.cleaned.height))) dpi on A4), \
            \(String(format: "%.1f", seconds)) s on this Mac (debug build)
            \(measures)
            issues: \(prepared.checked.issues.map(\.kind.rawValue))

            """)
        print("FORM \(variant.rawValue): \(measures) issues \(prepared.checked.issues.map(\.kind.rawValue))")
        return done
    }
// MARK: The brief's targets

    /// The fold is found where it is: both its ends at the height the
    /// made-up sheet was folded, within 4 pixels, each on the page's own
    /// side as it is cut, so the parts are laid true.
    func testTheFoldIsFoundWhereItIs() throws {
        let photo = try XCTUnwrap(ScanForm.photographed(.pink))
        let quad = try XCTUnwrap(ScanCleaner.page(in: photo.image)?.quad, "Vision finds the sheet")
        let found = ScanCleaner.folds(in: photo.image, quad: quad)
        XCTAssertEqual(found.count, photo.folds.count, "a sheet folded once, one fold found")
        let width = Double(photo.image.width), height = Double(photo.image.height)
        let corners = quad.pixels(in: CGSize(width: width, height: height))
        // The page's own side at a height, where its parts are cut.
        func side(_ top: CGPoint, _ bottom: CGPoint, at y: Double) -> Double {
            let span = Double(bottom.y - top.y)
            let t = abs(span) > 1e-6 ? (y - Double(top.y)) / span : 0
            return Double(top.x) + Double(bottom.x - top.x) * t
        }
        for (seen, truth) in zip(found, photo.folds) {
            let left = Double(seen.left.y) * height, right = Double(seen.right.y) * height
            XCTAssertEqual(left, truth.left.y * height, accuracy: 4, "the fold's left end, down")
            XCTAssertEqual(right, truth.right.y * height, accuracy: 4, "the fold's right end, down")
            XCTAssertEqual(Double(seen.left.x) * width, side(corners.topLeft, corners.bottomLeft, at: left), accuracy: 1,
                           "the fold's left end on the page's side")
            XCTAssertEqual(Double(seen.right.x) * width, side(corners.topRight, corners.bottomRight, at: right), accuracy: 1,
                           "the fold's right end on the page's side")
        }
    }

    /// The paper, fold included, comes out white and even: at least 98 % of
    /// its pixels at 250 and brighter, the mean of its brightest and its
    /// dimmest band of rows within 3 levels, its grey without a cast.
    func testThePaperComesOutWhiteAndEven() async throws {
        for variant in ScanForm.Variant.allCases {
            let (_, _, measures, _) = try await made(variant)
            XCTAssertGreaterThanOrEqual(measures.paperWhite, 0.98, "\(variant): paper white")
            XCTAssertLessThanOrEqual(measures.paperRows, 3, "\(variant): rows even, the fold among them")
            XCTAssertLessThanOrEqual(measures.paperSaturation, 0.02, "\(variant): the paper is grey, its cast gone")
        }
    }

    /// The print of a typewriter or a carbon copy comes out dark enough to
    /// read: the middle of the darkest 5 % of the pixels in the boxes Vision
    /// reads at 45 or under, the brief's 30 with room either way.
    func testThePrintComesOutDark() async throws {
        for variant in ScanForm.Variant.allCases {
            let (_, _, measures, _) = try await made(variant)
            XCTAssertLessThanOrEqual(measures.printDarkness, 45, "\(variant): print dark")
            XCTAssertGreaterThanOrEqual(measures.printDarkness, 1, "\(variant): and not one flat black")
        }
    }

    /// The ballpoint's blue across the fax number stays blue: its hue within
    /// 15° of the ink's, its strokes still coloured.
    func testTheSignatureStaysBlue() async throws {
        let (_, _, measures, _) = try await made(.pink)
        XCTAssertLessThanOrEqual(measures.signatureHueOff, 15, "the signature keeps its hue")
        XCTAssertGreaterThanOrEqual(measures.signatureSaturation, 0.5, "and its colour")
    }

    /// Nothing of the table or the floor is left along the page's edges.
    func testNothingOfTheTableIsLeft() async throws {
        for variant in ScanForm.Variant.allCases {
            let (_, _, measures, _) = try await made(variant)
            XCTAssertEqual(measures.edgePixels, 0, "\(variant): no background at the edges")
        }
    }

    /// The long lines run straight at 300 dots an inch, 2 pixels' wander at
    /// most, and the box's upright lines meet at the fold without a step.
    func testTheLinesAndTheFoldAreStraight() async throws {
        for variant in ScanForm.Variant.allCases {
            let (_, _, measures, _) = try await made(variant)
            XCTAssertEqual(measures.lineSpread.count, ScanForm.ruledLines.count, "\(variant): every rule found")
            for (index, spread) in measures.lineSpread.enumerated() {
                XCTAssertLessThanOrEqual(spread, 2, "\(variant): rule \(index) is straight, \(spread) px")
            }
            if variant.folds.count == 1 {
                let step = try XCTUnwrap(measures.foldStep, "the box's upright lines are found at the fold")
                XCTAssertLessThanOrEqual(step, 2, "\(variant): no step at the fold, \(step) px")
            }
        }
    }

    /// The header and the photo printed in grey keep their grey: a shade
    /// between black and white with its own texture, not flattened to one.
    func testTheGreyHeaderAndPhotoKeepTheirGrey() async throws {
        let (_, prepared, _, _) = try await made(.pink)
        let page = try XCTUnwrap(ScanCleaner.bitmap(prepared.cleaned))
        let header = ScanFormMeasure.shade(page, of: ScanForm.header)
        XCTAssertGreaterThanOrEqual(header.mean, 90, "the header stays grey, not black")
        XCTAssertLessThanOrEqual(header.mean, 235, "and not paper white")
        XCTAssertGreaterThanOrEqual(header.spread, 8, "with its texture")
        let patch = ScanFormMeasure.shade(page, of: ScanForm.patch)
        XCTAssertGreaterThanOrEqual(patch.mean, 60, "the printed photo stays grey, not black")
        XCTAssertLessThanOrEqual(patch.mean, 220, "and not paper white")
        XCTAssertGreaterThanOrEqual(patch.spread, 12, "with its texture")
    }

    /// Every number read on the page before cleaning is read after it, the
    /// fax number under the signature among them, and every line too.
    func testNoNumberIsLost() async throws {
        for variant in ScanForm.Variant.allCases {
            let (_, prepared, _, _) = try await made(variant)
            XCTAssertTrue(prepared.checked.textKept ?? false, "\(variant): every line reads after cleaning")
            XCTAssertFalse(prepared.checked.issues.contains { $0.kind == .lessText }, "\(variant): no text lost")
            // The form's own numbers, each as its digits: those read before
            // cleaning must be read after, a typewriter's Z or O read either
            // way, a reading that splits or spaces them otherwise alike.
            let known = Set(ScanForm.text.flatMap { ScanContent.numbers(in: $0) })
            func digits(_ lines: [Finder.TextLine]) -> [String] {
                lines.map { ScanContent.digits(in: ScanContent.readAsDigits($0.string)) }
            }
            let before = digits(Finder.lines(in: prepared.straightened) ?? []), after = digits(prepared.checked.reading)
            let read = known.filter { number in before.contains { $0.contains(number) } }
            let lost = read.filter { number in !after.contains { $0.contains(number) } }
            XCTAssertFalse(read.isEmpty, "\(variant): the form's numbers are read before cleaning")
            XCTAssertTrue(lost.isEmpty, "\(variant): numbers lost \(lost.sorted())")
        }
    }
}
#endif
