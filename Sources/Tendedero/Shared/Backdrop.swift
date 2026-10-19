import Foundation

/// Background: the photo set on a colour, with room round it, rounded
/// corners and a soft shadow, as a picture for a post, a shop or a slide. It
/// is kept with the photo, like a drawing, and put round the copy that
/// leaves the line, after what is covered, drawn and stamped; the file
/// itself stays as it is.
struct Backdrop: Codable, Equatable, Sendable {
    /// The colours to set it on: the brand's three, and calm ones beside
    /// them. Each is two or three stops, from the top left to the bottom
    /// right, fixed so it looks the same on every Mac.
    enum Fill: String, Codable, CaseIterable, Sendable {
        case sunset, emerald, orange, ocean, lilac, graphite, mist, white

        /// Red, green and blue from 0 to 1, top left first.
        var stops: [(red: Double, green: Double, blue: Double)] {
            switch self {
            case .sunset: return [Self.hex(0xFFC45C), Self.hex(0xFF5E62), Self.hex(0xB234D6)]
            case .emerald: return [Self.hex(0x34D399), Self.hex(0x0E7490)]
            case .orange: return [Self.hex(0xFFB340), Self.hex(0xFF5E3A)]
            case .ocean: return [Self.hex(0x5AC8FA), Self.hex(0x007AFF)]
            case .lilac: return [Self.hex(0xD8B4FE), Self.hex(0x6366F1)]
            case .graphite: return [Self.hex(0x48484A), Self.hex(0x1C1C1E)]
            case .mist: return [Self.hex(0xF5F5F7), Self.hex(0xDCDCE1)]
            case .white: return [Self.hex(0xFFFFFF), Self.hex(0xFFFFFF)]
            }
        }

        private static func hex(_ value: Int) -> (red: Double, green: Double, blue: Double) {
            (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
        }
    }

    /// The shape of the whole picture: round the photo, or the shape a post
    /// or a slide wants, with the photo in the middle.
    enum Ratio: String, Codable, CaseIterable, Sendable {
        case fit, square, wide, portrait, story

        /// Across over down; nil to follow the photo.
        var value: Double? {
            switch self {
            case .fit: return nil
            case .square: return 1
            case .wide: return 16.0 / 9
            case .portrait: return 4.0 / 5
            case .story: return 9.0 / 16
            }
        }
    }

    var fill = Fill.sunset
    /// The room round the photo, as a share of its unit.
    var padding = 0.08
    /// How round the photo's corners are, from 0 (square) to 1.
    var corners = 0.5
    var shadow = true
    var ratio = Ratio.fit

    static let paddings: ClosedRange<Double> = 0.02...0.2

    /// What sizes are measured in: about the photo's side, so the room and
    /// the corners look the same on a small screenshot and a large one.
    static func unit(width: Double, height: Double) -> Double {
        max((width * height).squareRoot(), 1)
    }

    /// Where the photo sits on the whole picture, in pixels from the bottom
    /// left, and how round its corners are.
    struct Layout: Equatable {
        var canvas: CGSize
        var picture: CGRect
        var radius: CGFloat
        /// The shadow's blur and how far down it falls, nothing without one.
        var blur: CGFloat
        var drop: CGFloat
    }

    func layout(width: Int, height: Int) -> Layout {
        let w = Double(max(1, width)), h = Double(max(1, height))
        let unit = Self.unit(width: w, height: h)
        let room = (min(max(padding, Self.paddings.lowerBound), Self.paddings.upperBound) * unit).rounded()
        var canvasW = w + 2 * room, canvasH = h + 2 * room
        if let ratio = ratio.value {
            // Grow the short way only, so the room is never less than chosen.
            if canvasW / canvasH < ratio { canvasW = (canvasH * ratio).rounded() } else { canvasH = (canvasW / ratio).rounded() }
        }
        let x = ((canvasW - w) / 2).rounded(.down), y = ((canvasH - h) / 2).rounded(.down)
        let radius = (min(max(corners, 0), 1) * 0.045 * unit).rounded()
        return Layout(canvas: CGSize(width: canvasW, height: canvasH),
                      picture: CGRect(x: x, y: y, width: w, height: h),
                      radius: min(radius, min(w, h) / 2),
                      blur: shadow ? (0.035 * unit).rounded() : 0,
                      drop: shadow ? (0.012 * unit).rounded() : 0)
    }

    /// A place on the photo, from 0 to 1 from its bottom left, as it is on
    /// the whole picture.
    static func place(_ rect: CGRect, in layout: Layout) -> CGRect {
        let c = layout.canvas, p = layout.picture
        guard c.width > 0, c.height > 0 else { return rect }
        return CGRect(x: (p.minX + rect.minX * p.width) / c.width, y: (p.minY + rect.minY * p.height) / c.height,
                      width: rect.width * p.width / c.width, height: rect.height * p.height / c.height)
    }

    /// Everything that changes the picture, so the copy is made again when
    /// any of it does.
    var key: String {
        "\(fill.rawValue),\(padding),\(corners),\(shadow),\(ratio.rawValue)"
    }
}
