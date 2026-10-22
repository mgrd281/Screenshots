import XCTest
@testable import Tendedero

/// A page's geometry: its true shape from a photo at an angle, A4 and
/// Letter recognised, how far its print leans, which way up it reads, and
/// where it goes on an A4 page of a PDF, never stretched.
final class ScanGeometryTests: XCTestCase {
    private let photo = CGSize(width: 3024, height: 4032)

    func testAnA4PagePhotographedAtAnAngleKeepsItsShape() {
        for (tilt, pan, roll) in [(30.0, 15.0, 8.0), (-25.0, 5.0, -12.0), (12.0, -20.0, 3.0), (40.0, 0.0, 0.0)] {
            let quad = Self.photographed(width: 210, height: 297, tilt: tilt, pan: pan, roll: roll, in: photo)
            let aspect = ScanGeometry.aspect(of: quad, in: photo)
            XCTAssertEqual(aspect, 210 / 297, accuracy: 0.012, "tilted \(tilt)°, turned \(pan)°, rolled \(roll)°")
            XCTAssertEqual(ScanGeometry.snapped(aspect), 1 / 2.0.squareRoot(), "A4 is A4")
        }
    }

    func testAReceiptAndACardKeepTheirShapes() {
        let receipt = Self.photographed(width: 80, height: 240, tilt: 28, pan: -10, roll: 5, in: photo)
        XCTAssertEqual(ScanGeometry.aspect(of: receipt, in: photo), 80.0 / 240, accuracy: 0.01)
        let card = Self.photographed(width: 85.6, height: 54, tilt: 20, pan: 18, roll: -4, in: photo)
        let aspect = ScanGeometry.aspect(of: card, in: photo)
        XCTAssertEqual(aspect, 85.6 / 54, accuracy: 0.03)
        XCTAssertEqual(ScanGeometry.snapped(aspect), aspect, "a card is no A4")
    }

    func testStraightFromAboveTheSidesSay() {
        let quad = Self.photographed(width: 210, height: 297, tilt: 0, pan: 0, roll: 0, in: photo)
        XCTAssertEqual(ScanGeometry.aspect(of: quad, in: photo), 210 / 297, accuracy: 0.001)
    }

    func testTheFlatPageHasThePhotosPixelsAndNoMore() {
        let quad = Self.photographed(width: 210, height: 297, tilt: 30, pan: 10, roll: 4, in: photo)
        let size = ScanGeometry.size(of: quad, in: photo, aspect: 1 / 2.0.squareRoot(), longest: 4096)
        let shape: Double = Double(size.width) / Double(size.height)
        let a4: Double = 1 / 2.0.squareRoot()
        XCTAssertEqual(shape, a4, accuracy: 0.002)
        let pixels = quad.pixels(in: photo)
        let left: CGFloat = hypot(pixels.topLeft.x - pixels.bottomLeft.x, pixels.topLeft.y - pixels.bottomLeft.y)
        let right: CGFloat = hypot(pixels.topRight.x - pixels.bottomRight.x, pixels.topRight.y - pixels.bottomRight.y)
        let tallest = max(left, right)
        XCTAssertLessThanOrEqual(CGFloat(size.height), tallest * 1.5)
        let small = ScanGeometry.size(of: quad, in: photo, aspect: 1 / 2.0.squareRoot(), longest: 1000)
        XCTAssertEqual(max(small.width, small.height), 1000)
    }

    func testAPageMustBeAPage() {
        XCTAssertTrue(ScanQuad.whole.isUsable)
        XCTAssertTrue(ScanQuad.inset(0.1).isUsable)
        var crossed = ScanQuad.whole
        swap(&crossed.topLeft, &crossed.topRight)
        XCTAssertFalse(crossed.isUsable, "crossed corners")
        let sliver = ScanQuad(topLeft: CGPoint(x: 0.1, y: 0.5), topRight: CGPoint(x: 0.9, y: 0.5),
                              bottomRight: CGPoint(x: 0.9, y: 0.495), bottomLeft: CGPoint(x: 0.1, y: 0.495))
        XCTAssertFalse(sliver.isUsable)
        var outside = ScanQuad.whole
        outside.topLeft = CGPoint(x: -0.2, y: 1.3)
        XCTAssertEqual(outside.clamped.topLeft, CGPoint(x: 0, y: 1))
        XCTAssertEqual(ScanQuad.inset(0.1).area, 0.64, accuracy: 1e-9)
    }

    func testCornersTurnWithTheirPicture() {
        let quad = ScanQuad(topLeft: CGPoint(x: 0.1, y: 0.9), topRight: CGPoint(x: 0.8, y: 0.85),
                            bottomRight: CGPoint(x: 0.85, y: 0.1), bottomLeft: CGPoint(x: 0.15, y: 0.05))
        let once = quad.turned(1)
        // Turned clockwise, the old bottom left is now at the top left.
        XCTAssertEqual(once.topLeft.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(once.topLeft.y, 0.85, accuracy: 1e-9)
        XCTAssertEqual(once.topRight.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(once.topRight.y, 0.9, accuracy: 1e-9)
        XCTAssertTrue(once.isUsable)
        func same(_ a: ScanQuad, _ b: ScanQuad) -> Bool {
            zip(a.corners, b.corners).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 }
        }
        XCTAssertTrue(same(quad.turned(1).turned(3), quad))
        XCTAssertTrue(same(quad.turned(4), quad))
        XCTAssertTrue(same(quad.turned(2).turned(2), quad))
    }

    func testHowFarAPageLeansIsMeasuredFromItsPrint() {
        let page = ScanPaperFixture.page(width: 900, printTo: 0.9).bitmap
        let degree = Double.pi / 180
        XCTAssertEqual(ScanGeometry.lean(of: page), 0, "level")
        for angle in [0.6, -1.2, 2.5, -4.0] {
            let leaning = Self.turned(page, by: angle * degree)
            XCTAssertEqual(ScanGeometry.lean(of: leaning), angle * degree, accuracy: 0.1 * degree, "\(angle)°")
        }
        XCTAssertEqual(ScanGeometry.lean(of: Self.turned(page, by: 0.15 * degree)), 0, "too little to straighten")
    }

    func testAPageWithoutLinesHasNoLean() {
        let blank = ScanBitmap(width: 600, height: 800, red: 240, green: 238, blue: 230)
        XCTAssertEqual(ScanGeometry.lean(of: blank), 0)
        // Dark dots strewn all over, as on a photo: nothing lines up.
        var dots = blank
        var seed: UInt32 = 3
        for _ in 0..<6000 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let across: UInt32 = seed >> 16
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let down: UInt32 = seed >> 16
            dots.set(x: Int(across) % 600, y: Int(down) % 800, 20, 20, 20)
        }
        XCTAssertEqual(ScanGeometry.lean(of: dots), 0)
    }

    func testAPageTurnsOnlyWhenItReadsClearlyBetter() {
        XCTAssertEqual(ScanGeometry.upright([100, 20, 5, 10]), 0)
        XCTAssertEqual(ScanGeometry.upright([10, 120, 5, 8]), 1)
        XCTAssertEqual(ScanGeometry.upright([80, 100, 5, 8]), 0, "not clearly better")
        XCTAssertEqual(ScanGeometry.upright([0, 0, 30, 0]), 2)
        XCTAssertEqual(ScanGeometry.upright([0, 0, 0, 0]), 0)
    }

    func testAnA4PageFillsItsPDFPageAndAnyOtherKeepsItsShapeWithin10mm() {
        let a4 = ScanGeometry.layout(width: 2480, height: 3508)
        XCTAssertEqual(a4.page, ScanGeometry.a4)
        XCTAssertEqual(a4.picture.width, a4.page.width, accuracy: 0.5)
        XCTAssertEqual(a4.picture.height, a4.page.height, accuracy: 0.5)
        let receipt = ScanGeometry.layout(width: 800, height: 2600)
        XCTAssertEqual(receipt.picture.height, ScanGeometry.a4.height - 2 * ScanGeometry.margin, accuracy: 0.01)
        XCTAssertEqual(receipt.picture.width / receipt.picture.height, 800.0 / 2600, accuracy: 0.0001, "never stretched")
        XCTAssertEqual(receipt.picture.midX, ScanGeometry.a4.width / 2, accuracy: 0.01)
        let lying = ScanGeometry.layout(width: 3000, height: 2000)
        XCTAssertEqual(lying.page, CGSize(width: ScanGeometry.a4.height, height: ScanGeometry.a4.width))
        XCTAssertEqual(lying.picture.width / lying.picture.height, 1.5, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(lying.picture.minX, ScanGeometry.margin - 0.01)
        XCTAssertGreaterThanOrEqual(lying.picture.minY, ScanGeometry.margin - 0.01)
    }

    func testDotsAnInchAndHowMuchLargerForThePDF() {
        XCTAssertEqual(ScanGeometry.dpi(width: 2480, height: 3508), 300, accuracy: 0.5)
        XCTAssertEqual(ScanGeometry.dpi(width: 1240, height: 1754), 150, accuracy: 0.5)
        XCTAssertEqual(ScanGeometry.printScale(width: 1240, height: 1754), 2, accuracy: 0.01)
        XCTAssertEqual(ScanGeometry.printScale(width: 2480, height: 3508), 1, accuracy: 0.01)
        XCTAssertEqual(ScanGeometry.printScale(width: 6000, height: 8485), 600 / ScanGeometry.dpi(width: 6000, height: 8485),
                       accuracy: 0.001)
        XCTAssertEqual(ScanGeometry.printScale(width: 300, height: 424), 4, "never more than four times")
    }

    /// The page turned counterclockwise as it is seen, by `angle` radians
    /// about its middle, smoothly, its corners filled with its paper.
    static func turned(_ page: ScanBitmap, by angle: Double) -> ScanBitmap {
        let paper = page.color(x: 0, y: 0)
        var out = ScanBitmap(width: page.width, height: page.height, red: paper.red, green: paper.green, blue: paper.blue)
        let c = cos(angle), s = sin(angle)
        let middleX = Double(page.width) / 2, middleY = Double(page.height) / 2
        for y in 0..<page.height {
            for x in 0..<page.width {
                // Where this pixel was before the turn, rows running down.
                let dx: Double = Double(x) - middleX, dy: Double = Double(y) - middleY
                let sx: Double = middleX + dx * c - dy * s
                let sy: Double = middleY + dx * s + dy * c
                let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down))
                guard x0 >= 0, y0 >= 0, x0 + 1 < page.width, y0 + 1 < page.height else { continue }
                let fx: Double = sx - Double(x0), fy: Double = sy - Double(y0)
                var mixed: [UInt8] = []
                for k in 0..<3 {
                    func at(_ px: Int, _ py: Int) -> Double { Double(page.pixels[(py * page.width + px) * 4 + k]) }
                    let top: Double = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
                    let bottom: Double = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
                    let value: Double = top * (1 - fy) + bottom * fy
                    mixed.append(UInt8(value.rounded()))
                }
                out.set(x: x, y: y, mixed[0], mixed[1], mixed[2])
            }
        }
        return out
    }

    /// The corners of a flat page `width` by `height` as a camera sees it,
    /// tilted, turned and rolled by degrees, half a metre away, through a
    /// phone's lens (a focal length of 3000 pixels), in a picture of `size`.
    static func photographed(width: Double, height: Double, tilt: Double, pan: Double, roll: Double,
                             in size: CGSize) -> ScanQuad {
        let r = Double.pi / 180
        let (a, b, c) = (tilt * r, pan * r, roll * r)
        func rotate(_ p: (Double, Double, Double)) -> (Double, Double, Double) {
            // Round the across axis, then up, then the view's axis.
            let x1: Double = p.0
            let y1: Double = p.1 * cos(a) - p.2 * sin(a)
            let z1: Double = p.1 * sin(a) + p.2 * cos(a)
            let x2: Double = x1 * cos(b) + z1 * sin(b)
            let y2: Double = y1
            let z2: Double = -x1 * sin(b) + z1 * cos(b)
            let x3: Double = x2 * cos(c) - y2 * sin(c)
            let y3: Double = x2 * sin(c) + y2 * cos(c)
            return (x3, y3, z2)
        }
        let focal = 3000.0, away = 500.0
        let wide = Double(size.width), high = Double(size.height)
        func seen(_ x: Double, _ y: Double) -> CGPoint {
            let p = rotate((x, y, 0))
            let z: Double = p.2 + away
            let across: Double = (focal * p.0 / z + wide / 2) / wide
            let down: Double = (focal * p.1 / z + high / 2) / high
            return CGPoint(x: across, y: down)
        }
        let halfWidth: Double = width / 2, halfHeight: Double = height / 2
        return ScanQuad(topLeft: seen(-halfWidth, halfHeight), topRight: seen(halfWidth, halfHeight),
                        bottomRight: seen(halfWidth, -halfHeight), bottomLeft: seen(-halfWidth, -halfHeight))
    }
}
