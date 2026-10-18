import Foundation

/// A point in the picture's own pixels, counted from its top left.
struct VectorPoint: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// One step of an outline: a straight line to a point, or a cubic curve to
/// it through two control points.
enum VectorSegment: Equatable {
    case line(VectorPoint)
    case curve(VectorPoint, VectorPoint, VectorPoint)

    var end: VectorPoint {
        switch self {
        case .line(let point): point
        case .curve(_, _, let point): point
        }
    }
}

/// A closed outline: where it starts, and the steps that lead round to it.
struct VectorContour: Equatable {
    var start: VectorPoint
    var segments: [VectorSegment]
}

struct VectorColor: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    /// "#rrggbb", as SVG writes it.
    var hex: String {
        let digits = Array("0123456789abcdef")
        var text = "#"
        for value in [red, green, blue] {
            text.append(digits[Int(value >> 4)])
            text.append(digits[Int(value & 15)])
        }
        return text
    }
}

/// Everything of one colour: the outlines of its shapes, filled with the
/// even-odd rule so that a hole is an outline inside an outline.
struct VectorLayer: Equatable {
    var color: VectorColor
    var contours: [VectorContour]
    /// It fills the whole picture, so it is written as a rectangle.
    var fillsPicture = false
}

/// A picture as shapes: layers from the bottom up, each painted over the one
/// before, in the picture's own pixel size.
struct VectorImage: Equatable {
    var width: Int
    var height: Int
    var layers: [VectorLayer]

    var contourCount: Int { layers.reduce(0) { $0 + $1.contours.count } }
}

// MARK: SVG

extension VectorImage {
    /// The picture as an SVG document: one path to a colour, in the picture's
    /// pixels, numbers to two places and written from the one before so they
    /// stay short.
    ///
    /// `size` is the size the picture is shown at: a picture too big to trace
    /// was made smaller, and the SVG still opens at its own size.
    func svg(size: (width: Int, height: Int)? = nil) -> String {
        let shownWidth = size?.width ?? width, shownHeight = size?.height ?? height
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(shownWidth)\" height=\"\(shownHeight)\" viewBox=\"0 0 \(width) \(height)\">"
        for layer in layers {
            if layer.fillsPicture {
                out += "<rect width=\"\(width)\" height=\"\(height)\" fill=\"\(layer.color.hex)\"/>"
                continue
            }
            guard !layer.contours.isEmpty else { continue }
            out += "<path fill=\"\(layer.color.hex)\" fill-rule=\"evenodd\" d=\""
            for contour in layer.contours {
                VectorImage.write(contour, to: &out)
            }
            out += "\"/>"
        }
        out += "</svg>"
        return out
    }

    /// A number in hundredths, as text: 1234 is "12.34", -50 is "-.5".
    static func number(hundredths value: Int) -> String {
        if value == 0 { return "0" }
        let magnitude = value < 0 ? -value : value
        let whole = magnitude / 100
        let part = magnitude % 100
        var text = value < 0 ? "-" : ""
        if whole > 0 { text += String(whole) }
        if part > 0 {
            text += "."
            if part % 10 == 0 {
                text += String(part / 10)
            } else {
                text += part < 10 ? "0" + String(part) : String(part)
            }
        }
        return text
    }

    private static func hundredths(_ value: Double) -> Int {
        // A point never lies far outside the picture; this keeps a broken one from overflowing.
        Int((max(-1e7, min(1e7, value)) * 100).rounded())
    }

    /// Appends a path's text: "M" with the start, then "l" and "c" with every
    /// number from the point before it, rounded as a whole so none drifts.
    private static func write(_ contour: VectorContour, to out: inout String) {
        var x = hundredths(contour.start.x)
        var y = hundredths(contour.start.y)
        out += "M" + number(hundredths: x) + " " + number(hundredths: y)
        var lastWasLine = false
        var lastWasCurve = false
        func append(_ numbers: [Int], command: Character, repeated: Bool) {
            if !repeated { out.append(command) }
            for (index, value) in numbers.enumerated() {
                let text = number(hundredths: value)
                // A minus sign already parts one number from the last, and so does a command letter.
                if !text.hasPrefix("-") && (index > 0 || repeated) { out += " " }
                out += text
            }
        }
        for segment in contour.segments {
            switch segment {
            case .line(let end):
                let ex = hundredths(end.x), ey = hundredths(end.y)
                append([ex - x, ey - y], command: "l", repeated: lastWasLine)
                x = ex
                y = ey
                lastWasLine = true
                lastWasCurve = false
            case .curve(let c1, let c2, let end):
                let c1x = hundredths(c1.x), c1y = hundredths(c1.y)
                let c2x = hundredths(c2.x), c2y = hundredths(c2.y)
                let ex = hundredths(end.x), ey = hundredths(end.y)
                append([c1x - x, c1y - y, c2x - x, c2y - y, ex - x, ey - y], command: "c", repeated: lastWasCurve)
                x = ex
                y = ey
                lastWasLine = false
                lastWasCurve = true
            }
        }
        out += "z"
    }
}
