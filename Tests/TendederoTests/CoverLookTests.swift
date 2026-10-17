import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// How covers look: every look hides for good, the soft ones take the colors
/// around what they cover, a label says what is covered, and the last four
/// digits of a long number can stay.
final class CoverLookTests: XCTestCase {
    /// Where the "text" is, from 0 to 1 from the bottom left, with room
    /// around it, as a line of text is covered.
    private let place = CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.2)

    func testEveryLookHidesForGood() throws {
        // Two pages alike but for what is under the cover.
        let first = try page(ground: (1, 1, 1), text: 1)
        let second = try page(ground: (1, 1, 1), text: 2)
        XCTAssertNotEqual(pixels(first), pixels(second))
        for style in CoverStyle.allCases {
            let a = try XCTUnwrap(Finder.cover(first, areas: [Finder.Area(rect: place, kind: .names)], style: style))
            let b = try XCTUnwrap(Finder.cover(second, areas: [Finder.Area(rect: place, kind: .names)], style: style))
            XCTAssertEqual(pixels(a), pixels(b), "\(style) shows something of what it covers")
            XCTAssertNotEqual(pixels(a), pixels(first), "\(style) covers nothing")
        }
    }

    func testInkIsAsItWas() throws {
        let white = try page(ground: (1, 1, 1), text: 1)
        let covered = try XCTUnwrap(Finder.cover(white, areas: [Finder.Area(rect: place, kind: .emails)], style: .ink))
        // Dark grey ink, the same in each part, whatever was under it.
        let middle = color(in: covered, at: CGPoint(x: 0.45, y: 0.5))
        XCTAssertLessThan(Int(middle.red), 45)
        XCTAssertEqual(Int(middle.red), Int(middle.green), accuracy: 2)
        XCTAssertEqual(Int(middle.red), Int(middle.blue), accuracy: 2)
    }

    func testTheSoftLooksTakeTheColorsAround() throws {
        // Blue all round, with dark "text" under the cover.
        let blue = try page(ground: (0.2, 0.4, 0.8), text: 1)
        let area = [Finder.Area(rect: place, kind: .names)]
        let erased = try XCTUnwrap(Finder.cover(blue, areas: area, style: .erase))
        let middle = color(in: erased, at: CGPoint(x: 0.45, y: 0.5))
        XCTAssertEqual(Double(middle.red), 51, accuracy: 3)
        XCTAssertEqual(Double(middle.green), 102, accuracy: 3)
        XCTAssertEqual(Double(middle.blue), 204, accuracy: 3)
        // Above the row of dots, the ground goes on.
        let dots = try XCTUnwrap(Finder.cover(blue, areas: area, style: .dots))
        let above = color(in: dots, at: CGPoint(x: 0.45, y: 0.585))
        XCTAssertEqual(Double(above.blue), 204, accuracy: 4)
        for style in [CoverStyle.blur, .pixels] {
            let covered = try XCTUnwrap(Finder.cover(blue, areas: area, style: style))
            let corner = color(in: covered, at: CGPoint(x: 0.205, y: 0.41))
            XCTAssertGreaterThan(Int(corner.blue), Int(corner.red) + 60, "\(style) is not made of the blue around")
        }
    }

    func testALabelSaysWhatIsCoveredWhereItFits() throws {
        let white = try page(ground: (1, 1, 1), text: 1)
        let labelled = try XCTUnwrap(Finder.cover(white, areas: [Finder.Area(rect: place, kind: .names)], style: .label))
        XCTAssertGreaterThan(brightest(in: labelled, place), 180, "no word on the ink")
        // A line too thin for a word stays plain ink.
        let thin = CGRect(x: 0.2, y: 0.5, width: 0.5, height: 0.03)
        let plain = try XCTUnwrap(Finder.cover(white, areas: [Finder.Area(rect: thin, kind: .names)], style: .label))
        XCTAssertLessThan(brightest(in: plain, thin.insetBy(dx: 0, dy: 0.008)), 60)
    }

    func testTheLastFourDigitsCanStay() {
        func kept(_ line: String, _ range: NSRange? = nil) -> String {
            let covered = Finder.keepingLastDigits(range, in: line) ?? NSRange(location: 0, length: (line as NSString).length)
            return (line as NSString).replacingCharacters(in: covered, with: "•")
        }
        XCTAssertEqual(kept("4111 1111 1111 1111"), "• 1111")
        XCTAssertEqual(kept("+49 151 23456789"), "•6789")
        XCTAssertEqual(kept("IBAN: DE89 3704 0044 0532 0130 00", NSRange(location: 6, length: 27)), "IBAN: •30 00")
        // A short number is covered whole.
        XCTAssertEqual(kept("Order #1024", NSRange(location: 7, length: 4)), "Order #•")
        XCTAssertNil(Finder.keepingLastDigits(nil, in: "1024"))
        XCTAssertEqual(Finder.lastDigitKinds, [.bank, .phones, .ids, .orders, .tracking])
    }

    func testTheLookIsKept() {
        let key = "coverStyle"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(CoverStyle.current, .ink, "ink until another look is chosen")
        CoverStyle.current = .pixels
        XCTAssertEqual(CoverStyle.current, .pixels)
        XCTAssertTrue(Finder.lookKey.hasPrefix("pixels,"))
    }

    func testEveryKindHasAShortWordForItsLabel() {
        for kind in PrivateDetail.allCases {
            XCTAssertFalse(kind.label.isEmpty, "\(kind)")
            XCTAssertLessThanOrEqual(kind.label.count, 12, "\(kind)")
        }
    }

    func testEveryLookHasASampleForSettings() throws {
        for style in CoverStyle.allCases {
            for dark in [false, true] {
                let sample = try XCTUnwrap(style.sample(dark: dark), "\(style)")
                XCTAssertEqual(sample.width, 264)
                XCTAssertEqual(sample.height, 165)
            }
        }
        let ink = try XCTUnwrap(CoverStyle.ink.sample(dark: false))
        let erased = try XCTUnwrap(CoverStyle.erase.sample(dark: false))
        XCTAssertNotEqual(pixels(ink), pixels(erased))
    }

    // MARK: Helpers

    /// A page 400 by 200 of one color, with a line of dark "text" in the
    /// middle of the place: blocks where the seed puts them.
    private func page(ground: (CGFloat, CGFloat, CGFloat), text seed: Int) throws -> CGImage {
        let width = 400, height = 200
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: ground.0, green: ground.1, blue: ground.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        // Inside the place, which runs from 80 to 280 across and 80 to 120 up.
        var x = 96
        var step = seed
        while x < 250 {
            step = (step * 37 + 11) % 23
            let letter = 4 + step % 9
            context.fill(CGRect(x: x, y: 88 + step % 5, width: letter, height: 22 - step % 7))
            x += letter + 3
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    /// The color at a point, from 0 to 1 from the bottom left.
    private func color(in image: CGImage, at point: CGPoint) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let data = pixels(image)
        let x = min(image.width - 1, Int(point.x * CGFloat(image.width)))
        let y = min(image.height - 1, Int(point.y * CGFloat(image.height)))
        let offset = ((image.height - 1 - y) * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    /// The lightest gray inside a place, from 0 to 1 from the bottom left.
    private func brightest(in image: CGImage, _ rect: CGRect) -> Int {
        let data = pixels(image)
        var best = 0
        let minX = Int(rect.minX * CGFloat(image.width)), maxX = Int(rect.maxX * CGFloat(image.width))
        let minY = Int(rect.minY * CGFloat(image.height)), maxY = Int(rect.maxY * CGFloat(image.height))
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = ((image.height - 1 - y) * image.width + x) * 4
                best = max(best, Int(data[offset]))
            }
        }
        return best
    }
}
