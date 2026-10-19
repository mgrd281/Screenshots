import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Shapes drawn by hand, without a picture: where they reach, what a finger
/// on them means, and where a copy must have changed under them.
final class HandShapeTests: XCTestCase {
    func testAStrokeIsAsWideEveryWayOnATallPicture() {
        let stroke = HandShape.stroke([CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.5)], width: 0.04)
        let bounds = stroke.bounds(aspect: 0.5)
        XCTAssertEqual(bounds.minX, 0.18, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxX, 0.62, accuracy: 0.0001)
        // Half as wide as tall: the same width is half as much of the height.
        XCTAssertEqual(bounds.height, 0.02, accuracy: 0.0001)
        XCTAssertTrue(stroke.contains(CGPoint(x: 0.4, y: 0.505), aspect: 0.5))
        XCTAssertFalse(stroke.contains(CGPoint(x: 0.4, y: 0.52), aspect: 0.5))
    }

    func testATurnedBoxStaysSquare() {
        // 0.2 of the width and 0.1 of the height: square on a picture half as wide as tall.
        let box = HandShape.box(CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.1), angle: .pi / 4)
        let bounds = box.bounds(aspect: 0.5)
        XCTAssertEqual(bounds.height, 0.1 * 2.squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 0.2 * 2.squareRoot(), accuracy: 0.0001)
        XCTAssertTrue(box.contains(CGPoint(x: 0.5, y: 0.5), aspect: 0.5))
        XCTAssertFalse(box.contains(CGPoint(x: 0.405, y: 0.455), aspect: 0.5), "a corner turned away")
        XCTAssertEqual(box.turned(by: -.pi / 4), .box(CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.1), angle: 0))
    }

    func testAnOutlineCrossedOverIsFilledBothSides() {
        let eight = HandShape.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.3, y: 0.1),
                                       CGPoint(x: 0.1, y: 0.3)])
        // A bow tie: both its halves, and nothing between them.
        XCTAssertTrue(eight.contains(CGPoint(x: 0.13, y: 0.2), aspect: 1))
        XCTAssertTrue(eight.contains(CGPoint(x: 0.27, y: 0.2), aspect: 1))
        XCTAssertFalse(eight.contains(CGPoint(x: 0.2, y: 0.12), aspect: 1))
        XCTAssertFalse(eight.contains(CGPoint(x: 0.5, y: 0.5), aspect: 1))
    }

    func testMovingAndResizingKeepTheShape() {
        let outline = HandShape.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.2, y: 0.3)])
        XCTAssertEqual(outline.moved(by: CGPoint(x: 0.1, y: 0)).bounds(aspect: 1).minX, 0.2, accuracy: 0.0001)
        let bigger = outline.resized(to: CGRect(x: 0, y: 0, width: 0.4, height: 0.4), aspect: 1)
        XCTAssertEqual(bigger.bounds(aspect: 1), CGRect(x: 0, y: 0, width: 0.4, height: 0.4))
        let stroke = HandShape.stroke([CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.6)], width: 0.04)
        let resized = stroke.resized(to: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3), aspect: 1)
        let bounds = resized.bounds(aspect: 1)
        XCTAssertEqual(bounds.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, 0.4, accuracy: 0.0001)
        XCTAssertEqual(resized.widened(to: 0.02), .stroke(resized.corners(aspect: 1), width: 0.02))
    }

    func testTheCheckLooksOnlyWhereTheInkIs() {
        let stroke = HandShape.stroke([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)], width: 0.03)
        let insides = stroke.insides(aspect: 1)
        XCTAssertFalse(insides.isEmpty)
        XCTAssertLessThanOrEqual(insides.count, 48)
        for square in insides {
            XCTAssertTrue(stroke.contains(CGPoint(x: square.minX, y: square.minY), aspect: 1), "\(square)")
            XCTAssertTrue(stroke.contains(CGPoint(x: square.maxX, y: square.maxY), aspect: 1), "\(square)")
        }
        let box = HandShape.box(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2), angle: 0.3)
        let inBox = box.insides(aspect: 0.6)
        XCTAssertGreaterThan(inBox.count, 10)
        for square in inBox {
            for corner in [CGPoint(x: square.minX, y: square.minY), CGPoint(x: square.maxX, y: square.maxY)] {
                XCTAssertTrue(box.contains(corner, aspect: 0.6), "\(square)")
            }
        }
        // A dot of the marker is checked too.
        XCTAssertEqual(HandShape.stroke([CGPoint(x: 0.5, y: 0.5)], width: 0.03).insides(aspect: 1).count, 1)
    }
}
