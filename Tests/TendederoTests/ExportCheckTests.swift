import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// The last check before a copy leaves: every place meant to be covered is
/// changed where the original showed something, in every look.
final class ExportCheckTests: XCTestCase {
    /// White, with a row of dark bars where a line of letters would be.
    private func page() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        for i in 0..<20 {
            context.fill(CGRect(x: 40 + i * 8, y: 130, width: 3, height: 20))
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testACopyWithItsCoversPassesInEveryLook() throws {
        let original = try page()
        let place = CGRect(x: 0.05, y: 0.6, width: 0.5, height: 0.2)
        for style in CoverStyle.allCases {
            let covered = try XCTUnwrap(Finder.cover(original, areas: [Finder.Area(rect: place, kind: .names)], style: style))
            XCTAssertTrue(Finder.coversHold(original: original, covered: covered, areas: [place]), "\(style)")
        }
    }

    func testACopyWithoutItsCoverFails() throws {
        let original = try page()
        let place = CGRect(x: 0.05, y: 0.6, width: 0.5, height: 0.2)
        XCTAssertFalse(Finder.coversHold(original: original, covered: original, areas: [place]))
        // Covered somewhere else, as a cover turned upside down would be.
        let astray = try XCTUnwrap(Finder.cover(original, areas: [Finder.Area(rect: CGRect(x: 0.05, y: 0.2, width: 0.5,
                                                                                            height: 0.2), kind: .names)]))
        XCTAssertFalse(Finder.coversHold(original: original, covered: astray, areas: [place]))
    }

    func testAPlaceWithNothingInItNeedsNoChange() throws {
        let original = try page()
        XCTAssertTrue(Finder.coversHold(original: original, covered: original,
                                        areas: [CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.2)]))
        XCTAssertTrue(Finder.coversHold(original: original, covered: original, areas: []))
    }
}
