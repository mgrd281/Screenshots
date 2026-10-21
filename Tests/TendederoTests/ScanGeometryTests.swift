import XCTest
@testable import Tendedero

/// A page's geometry: its true shape from a photo at an angle, A4 and
/// Letter recognised, how far its lines lean, which way up it reads, and
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
        XCTAssertEqual(Double(size.width) / Double(size.height), 1 / 2.0.squareRoot(), accuracy: 0.002)
        let pixels = quad.pixels(in: photo)
        let tallest = max(hypot(pixels.topLeft.x - pixels.bottomLeft.x, pixels.topLeft.y - pixels.bottomLeft.y),
                          hypot(pixels.topRight.x - pixels.bottomRight.x, pixels.topRight.y - pixels.bottomRight.y))
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

    func testLinesThatAgreeSayHowFarThePageLeans() {
        let degree = Double.pi / 180
        let leaning = (0..<8).map { (angle: 2 * degree + Double($0 % 3 - 1) * 0.2 * degree, length: 100.0) }
        XCTAssertEqual(ScanGeometry.skew(of: leaning), 2 * degree, accuracy: 0.25 * degree)
        XCTAssertEqual(ScanGeometry.skew(of: [(angle: 2 * degree, length: 100)]), 0, "one line is not enough")
        let level = (0..<8).map { _ in (angle: 0.1 * degree, length: 100.0) }
        XCTAssertEqual(ScanGeometry.skew(of: level), 0, "too little to straighten")
        let scattered = (0..<9).map { (angle: Double($0 - 4) * 3 * degree, length: 100.0) }
        XCTAssertEqual(ScanGeometry.skew(of: scattered), 0, "lines that do not agree")
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

    /// The corners of a flat page `width` by `height` as a camera sees it,
    /// tilted, turned and rolled by degrees, half a metre away, through a
    /// phone's lens (a focal length of 3000 pixels), in a picture of `size`.
    static func photographed(width: Double, height: Double, tilt: Double, pan: Double, roll: Double,
                             in size: CGSize) -> ScanQuad {
        let r = Double.pi / 180
        let (a, b, c) = (tilt * r, pan * r, roll * r)
        func rotate(_ p: (Double, Double, Double)) -> (Double, Double, Double) {
            // Round the across axis, then up, then the view's axis.
            let x1 = p.0, y1 = p.1 * cos(a) - p.2 * sin(a), z1 = p.1 * sin(a) + p.2 * cos(a)
            let x2 = x1 * cos(b) + z1 * sin(b), y2 = y1, z2 = -x1 * sin(b) + z1 * cos(b)
            return (x2 * cos(c) - y2 * sin(c), x2 * sin(c) + y2 * cos(c), z2)
        }
        let focal = 3000.0, away = 500.0
        func seen(_ x: Double, _ y: Double) -> CGPoint {
            let p = rotate((x, y, 0))
            let z = p.2 + away
            return CGPoint(x: (focal * p.0 / z + Double(size.width) / 2) / Double(size.width),
                           y: (focal * p.1 / z + Double(size.height) / 2) / Double(size.height))
        }
        return ScanQuad(topLeft: seen(-width / 2, height / 2), topRight: seen(width / 2, height / 2),
                        bottomRight: seen(width / 2, -height / 2), bottomLeft: seen(-width / 2, -height / 2))
    }
}
