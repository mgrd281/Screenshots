import Foundation

/// Whether the camera is ready to take a page, measured on its preview
/// several times a second: the print sharp, the phone still for a moment,
/// the smallest letters large enough in the full photo, no reflection on the
/// paper. When all of that holds the page is taken by itself; otherwise one
/// short hint at a time says what to do, the most important first.
enum ScanReadiness {
    /// What to do, the most important first.
    enum Hint: String, CaseIterable, Sendable {
        case steady, closer, glare, light, smudge

        /// The hint as the camera's bar says it.
        var message: String {
            switch self {
            case .steady: L("Hold still")
            case .closer: L("Move closer")
            case .glare: L("Reflection: tilt the iPhone a little")
            case .light: L("More light")
            case .smudge: L("Clean the lens")
            }
        }
    }

    struct Tuning: Equatable, Sendable {
        /// The smallest letters' x-height, in pixels of the full photo, at least.
        var smallestLetters = 16.0
        /// A line of text read is about twice as tall as its x-height.
        var lineToLetters = 0.5
        /// The phone still this many seconds before the page is taken.
        var steadyFor = 0.3
        /// The print's edges at least this steep (`focus`).
        var sharpEdges: Float = 0.35
        /// A reflection: this share of the paper white out, where the paper
        /// itself is no lighter than `dullPaper`.
        var glareShare = 0.01
        var glareWhite: UInt8 = 250
        var dullPaper = 235.0
        /// Paper darker than this asks for more light.
        var darkPaper = 100.0
        /// Whether a page must be seen: not for a close-up of its small
        /// print (`closeUp`), which shows only a part of it.
        var needsPage = true

        /// For a close-up of small print: no whole page in view, and the
        /// letters at least half again as tall as a page's need be.
        static let closeUp = Tuning(smallestLetters: 24, needsPage: false)
    }

    /// What the preview shows: its brightness, from its top left; where the
    /// page and its lines of text are, from 0 to 1 from the bottom left, as
    /// Vision gives them; how tall the full photo will be; how long the
    /// phone has been still; and whether the lens looks smudged.
    struct Look: Sendable {
        var plane: [UInt8]
        var width: Int
        var height: Int
        var page: CGRect?
        var lines: [CGRect]
        var photoHeight: Int
        var still: Double
        var smudged = false
    }

    /// Whether to take the page, the one hint to show, and what was measured.
    struct State: Equatable, Sendable {
        let ready: Bool
        let hint: Hint?
        /// The smallest letters' x-height in the full photo, in pixels; 0 without text.
        let letters: Double
        let sharpness: Float
    }

    static func state(of look: Look, tuning: Tuning = .init()) -> State {
        let letters = Self.letters(look, tuning: tuning)
        let sharpness = Self.sharpness(look)
        let paper = Self.paper(look)
        let glare = paper.median <= tuning.dullPaper && paper.white >= tuning.glareShare
        let steady = look.still >= tuning.steadyFor
        let sharp = sharpness >= tuning.sharpEdges
        let large = letters >= tuning.smallestLetters
        let found = (look.page != nil || !tuning.needsPage) && !look.lines.isEmpty
        let ready = found && steady && sharp && large && !glare
        var hint: Hint?
        if found, !ready {
            if !steady || !sharp {
                hint = .steady
            } else if !large {
                hint = .closer
            } else if glare {
                hint = .glare
            }
        }
        if hint == nil, found, paper.median < tuning.darkPaper { hint = .light }
        if hint == nil, look.smudged { hint = .smudge }
        return State(ready: ready, hint: hint, letters: letters, sharpness: sharpness)
    }

    /// The smallest letters' x-height in the full photo: the shortest line
    /// of text read, of those inside the page, at about half its height.
    static func letters(_ look: Look, tuning: Tuning = .init()) -> Double {
        let lines = look.lines.filter { line in look.page.map { $0.insetBy(dx: -0.02, dy: -0.02).contains(line) } ?? true }
        guard let shortest = lines.map(\.height).min() else { return 0 }
        return Double(shortest) * Double(look.photoHeight) * tuning.lineToLetters
    }

    /// How sharp the print is where text was read: its sharpest line, cut
    /// out of the preview (`focus`).
    static func sharpness(_ look: Look) -> Float {
        let w = look.width, h = look.height
        var best: Float = 0
        for line in look.lines.prefix(8) {
            let x0 = max(0, Int(line.minX * Double(w))), x1 = min(w, Int(line.maxX * Double(w)))
            let y0 = max(0, Int((1 - line.maxY) * Double(h)) - 2), y1 = min(h, Int((1 - line.minY) * Double(h)) + 2)
            guard x1 - x0 > 8, y1 - y0 > 6 else { continue }
            var piece = ScanBitmap(width: x1 - x0, height: y1 - y0, red: 255, green: 255, blue: 255)
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let v = look.plane[y * w + x], i = ((y - y0) * piece.width + x - x0) * 4
                    piece.pixels[i] = v
                    piece.pixels[i + 1] = v
                    piece.pixels[i + 2] = v
                }
            }
            best = max(best, Self.focus(of: piece))
        }
        return best
    }

    /// How sharp a preview's print is in focus, whatever its contrast: at
    /// the print's edges, how steeply the brightness turns from one pixel to the next
    /// against how far it turns within three pixels either way, across and
    /// down apart and the lesser of the two, as a shake blurs one way only.
    /// A sharp edge turns in a pixel or two (about 0.5), a blurred one over
    /// many (0.2 and less). Its grain is taken out first
    /// (`ScanQuality.despeckled`) so grain is not taken for edges; 0 without
    /// print. A shake that smears thin strokes leaves their edges steep and
    /// takes their darkness instead; the phone's stillness tells that.
    static func focus(of frame: ScanBitmap) -> Float {
        let w = frame.width, h = frame.height
        guard w > 8, h > 8 else { return 0 }
        let plane = ScanQuality.despeckled(frame.brightness, width: w, height: h)
        let least = max(20, ScanBurst.contrast(of: frame) / 3)
        guard least < 255 else { return 0 }
        func steepness(step: Int, along: Int, across: Int) -> Float {
            var ratios = [Int](repeating: 0, count: 101)
            var total = 0
            for a in 3..<(across - 3) {
                for b in 3..<(along - 3) {
                    let p = step == 1 ? a * w + b : b * w + a
                    var low = 255, high = 0
                    for k in -3...3 {
                        let v = Int(plane[p + k * step])
                        low = min(low, v)
                        high = max(high, v)
                    }
                    let range = high - low
                    guard Float(range) >= least else { continue }
                    let turn = abs(Int(plane[p + step]) - Int(plane[p - step])) / 2
                    ratios[min(100, turn * 100 / range)] += 1
                    total += 1
                }
            }
            guard total >= 20 else { return 0 }
            // The mean of the steepest tenth.
            var left = max(1, total / 10), sum = 0, n = 0
            for ratio in stride(from: 100, through: 0, by: -1) where left > 0 {
                let take = min(left, ratios[ratio])
                sum += take * ratio
                n += take
                left -= take
            }
            return n > 0 ? Float(sum) / Float(n) / 100 : 0
        }
        return min(steepness(step: 1, along: w, across: h), steepness(step: w, along: h, across: w))
    }

    /// The page's paper in the preview: how bright it commonly is, and the
    /// share of it white out.
    static func paper(_ look: Look, tuning: Tuning = .init()) -> (median: Double, white: Double) {
        let w = look.width, h = look.height
        let area = look.page ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let x0 = max(0, Int(area.minX * Double(w))), x1 = min(w, Int(area.maxX * Double(w)))
        let y0 = max(0, Int((1 - area.maxY) * Double(h))), y1 = min(h, Int((1 - area.minY) * Double(h)))
        guard x1 > x0, y1 > y0 else { return (0, 0) }
        var counts = [Int](repeating: 0, count: 256)
        var total = 0
        let step = max(1, (x1 - x0) * (y1 - y0) / 40_000)
        var n = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                n += 1
                guard n % step == 0 else { continue }
                counts[Int(look.plane[y * w + x])] += 1
                total += 1
            }
        }
        guard total > 0 else { return (0, 0) }
        // Most of a page is paper, so the middle of its pixels is the paper's.
        var seen = 0, median = 255
        for value in 0..<256 {
            seen += counts[value]
            if seen * 2 >= total { median = value; break }
        }
        let white = counts[Int(tuning.glareWhite)...].reduce(0, +)
        return (Double(median), Double(white) / Double(total))
    }
}
