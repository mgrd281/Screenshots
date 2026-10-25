import XCTest
@testable import Tendedero

/// Cleaning a scanned page: the light evened and the paper white, while
/// every mark keeps what it is: print stays dark, a logo keeps its colour, a
/// dark box stays dark, a pale stamp stays visible in colour and grey. Made
/// on made-up pages drawn here, lit unevenly with a lamp's warm cast.
final class ScanCleanTests: XCTestCase {
    func testUnevenLightBecomesEvenWhitePaper() {
        let page = ScanPaperFixture.page()
        let cleaned = ScanClean.clean(page.bitmap, .color)
        var lightest = 0, darkest = 255
        for (x, y) in page.paperSpots {
            let (red, green, blue) = cleaned.color(x: x, y: y)
            lightest = max(lightest, Int(min(red, green, blue)))
            darkest = min(darkest, Int(min(red, green, blue)))
        }
        // Before: from bright warm paper to half as bright.
        let before = page.paperSpots.map { Int(page.bitmap.brightness(x: $0.0, y: $0.1)) }
        XCTAssertGreaterThan(before.max()! - before.min()!, 80, "the made-up light is uneven")
        XCTAssertGreaterThanOrEqual(darkest, 248, "the paper is white everywhere, in every channel")
        XCTAssertLessThanOrEqual(lightest - darkest, 7)
    }

    func testAShadowOverSpeckledPaperComesOutAsWhiteAsTheRest() {
        // The phone's shadow over the bottom right, and a camera's bright
        // specks on a sixth of the pixels, as a photo in dim light has them.
        var page = ScanPaperFixture.page(width: 600)
        let width = page.bitmap.width, height = page.bitmap.height
        var seed: UInt32 = 3
        for y in 0..<height {
            for x in 0..<width {
                let across: Float = Float(x) / Float(width), down: Float = Float(y) / Float(height)
                let into: Float = across + down - 1.2
                let ramp: Float = min(max(into * 10, 0), 1)
                let kept: Float = 1 - 0.3 * ramp
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let high: UInt32 = seed >> 16
                let speck: Float = high % 6 == 0 ? 40 : 0
                let (red, green, blue) = page.bitmap.color(x: x, y: y)
                page.bitmap.set(x: x, y: y, Self.shaded(red, kept, speck), Self.shaded(green, kept, speck),
                                Self.shaded(blue, kept, speck))
            }
        }
        let color = ScanClean.clean(page.bitmap, .color)
        let black = ScanClean.clean(page.bitmap, .blackAndWhite)
        let inShadow = page.paperSpots.filter { spot in
            let across: Float = Float(spot.0) / Float(width), down: Float = Float(spot.1) / Float(height)
            return across + down > 1.3
        }
        XCTAssertGreaterThanOrEqual(inShadow.count, 4, "some of the paper lies in the shadow")
        for (x, y) in page.paperSpots {
            // The paper as most of it is around the spot, not one speck or the gap beside it.
            var values: [Int] = []
            var blackPixels = 0
            for dy in -3...3 {
                for dx in -3...3 {
                    let (red, green, blue) = color.color(x: x + dx, y: y + dy)
                    values.append(Int(min(red, green, blue)))
                    if black.brightness(x: x + dx, y: y + dy) == 0 { blackPixels += 1 }
                }
            }
            values.sort()
            XCTAssertGreaterThanOrEqual(values[values.count / 2], 248, "the paper is white at \(x), \(y)")
            XCTAssertEqual(blackPixels, 0, "and has no black specks in black and white at \(x), \(y)")
        }
    }

    func testPrintKeepsItsDarknessEvenWhereTheLightIsDim() {
        let page = ScanPaperFixture.page()
        let cleaned = ScanClean.clean(page.bitmap, .color)
        for (x, y) in page.inkSpots {
            XCTAssertLessThanOrEqual(cleaned.brightness(x: x, y: y), 70, "print at \(x), \(y)")
        }
    }

    func testALogoKeepsItsColour() {
        let page = ScanPaperFixture.page()
        let cleaned = ScanClean.clean(page.bitmap, .color)
        let (red, green, blue) = cleaned.color(x: page.logo.0, y: page.logo.1)
        XCTAssertGreaterThan(Int(blue) - Int(red), 80, "still blue: \(red), \(green), \(blue)")
        XCTAssertLessThan(Int(red), 120)
    }

    func testADarkBoxStaysDarkInsideAndOut() {
        let page = ScanPaperFixture.page()
        for mode in ScanColor.allCases {
            let cleaned = ScanClean.clean(page.bitmap, mode)
            for (x, y) in page.boxSpots {
                XCTAssertLessThanOrEqual(cleaned.brightness(x: x, y: y), 110, "\(mode) at \(x), \(y)")
            }
        }
    }

    func testAPaleStampStaysVisibleInColourAndGrey() {
        let page = ScanPaperFixture.page()
        let color = ScanClean.clean(page.bitmap, .color)
        let (red, green, blue) = color.color(x: page.stamp.0, y: page.stamp.1)
        XCTAssertLessThanOrEqual(Int(green), 230, "the stamp shows: \(red), \(green), \(blue)")
        XCTAssertGreaterThan(Int(red) - Int(green), 15, "and is still reddish")
        let gray = ScanClean.clean(page.bitmap, .gray)
        XCTAssertLessThanOrEqual(gray.brightness(x: page.stamp.0, y: page.stamp.1), 238)
    }

    /// A pink form, as a sick note is printed on: Color makes its paper
    /// white, Original Color keeps it pink, as even as Color makes white,
    /// the print as dark.
    func testOriginalColorKeepsThePapersOwnColour() {
        let page = ScanPaperFixture.page(paper: (250, 222, 226))
        let white = ScanClean.clean(page.bitmap, .color)
        let pink = ScanClean.clean(page.bitmap, .original)
        var reds: [Int] = [], greens: [Int] = [], brightness: [Int] = []
        for (x, y) in page.paperSpots {
            let (red, green, _) = pink.color(x: x, y: y)
            reds.append(Int(red))
            greens.append(Int(green))
            brightness.append(Int(pink.brightness(x: x, y: y)))
            XCTAssertGreaterThanOrEqual(Int(white.color(x: x, y: y).green), 245, "Color: white paper")
        }
        XCTAssertGreaterThanOrEqual(reds.min()!, 245, "the paper as bright as its brightest")
        XCTAssertGreaterThanOrEqual(reds.min()! - greens.max()!, 18, "and pink")
        XCTAssertLessThanOrEqual(brightness.max()! - brightness.min()!, 8, "evenly, the lamp's fall-off gone")
        for (x, y) in page.inkSpots {
            XCTAssertLessThanOrEqual(Int(pink.brightness(x: x, y: y)), Int(white.brightness(x: x, y: y)) + 2, "print as dark")
        }
    }

    func testGreyHasNoColourAndBlackAndWhiteHasTwoValues() {
        let page = ScanPaperFixture.page()
        let gray = ScanClean.clean(page.bitmap, .gray)
        for i in stride(from: 0, to: gray.pixels.count, by: 4) {
            XCTAssertEqual(gray.pixels[i], gray.pixels[i + 1])
            XCTAssertEqual(gray.pixels[i], gray.pixels[i + 2])
        }
        let black = ScanClean.clean(page.bitmap, .blackAndWhite)
        XCTAssertEqual(Set(black.brightness), [0, 255])
        for (x, y) in page.inkSpots { XCTAssertEqual(black.brightness(x: x, y: y), 0, "print at \(x), \(y)") }
        for (x, y) in page.paperSpots { XCTAssertEqual(black.brightness(x: x, y: y), 255, "paper at \(x), \(y)") }
    }

    func testADarkPageKeepsItsLight() {
        // A dark screen photographed: white words on near black.
        var page = ScanBitmap(width: 300, height: 400, red: 30, green: 32, blue: 36)
        for y in 100..<110 { for x in 40..<260 { page.set(x: x, y: y, 235, 235, 235) } }
        let evened = ScanClean.evened(page)
        XCTAssertEqual(evened, page)
        let cleaned = ScanClean.clean(page, .color)
        XCTAssertLessThan(cleaned.brightness(x: 20, y: 20), 60)
        XCTAssertGreaterThan(cleaned.brightness(x: 150, y: 105), 200)
    }

    func testCleaningIsTheSameEachTime() {
        let page = ScanPaperFixture.page()
        XCTAssertEqual(ScanClean.clean(page.bitmap, .color), ScanClean.clean(page.bitmap, .color))
    }

    func testTheCurveWhitensThePaperAndKeepsItsOrder() {
        let curve = ScanClean.curve(.standard)
        XCTAssertEqual(curve.count, 256)
        XCTAssertEqual(curve[0], 0)
        XCTAssertEqual(curve[255], 255)
        XCTAssertEqual(curve[245], 255, "paper a little under its commonest value is white")
        XCTAssertLessThan(curve[240], 255, "a light grey a little further under is not")
        XCTAssertLessThan(curve[128], 128, "mid greys a little darker")
        XCTAssertEqual(curve, curve.sorted(), "never out of order")
    }

    func testAGreyTableHeaderKeepsItsGrey() {
        var page = ScanPaperFixture.page(width: 420, grain: 3)
        // A band of light grey across the page, as a table's header has.
        let top = page.bitmap.height * 7 / 10, rows = page.bitmap.height / 25
        for y in top..<(top + rows) {
            for x in 20..<(page.bitmap.width - 20) {
                let (red, green, blue) = page.bitmap.color(x: x, y: y)
                page.bitmap.set(x: x, y: y, Self.dimmed(red, 0.86), Self.dimmed(green, 0.86), Self.dimmed(blue, 0.86))
            }
        }
        let cleaned = ScanClean.clean(page.bitmap, .color)
        let band = cleaned.brightness(x: page.bitmap.width / 2, y: top + rows / 2)
        let above = cleaned.brightness(x: page.bitmap.width / 2, y: top - rows)
        XCTAssertLessThanOrEqual(band, 243, "the header stays grey")
        XCTAssertGreaterThanOrEqual(Int(above) - Int(band), 12, "and stands apart from the paper above it")
    }

    func testThePapersGrainIsSmoothedAndAnEdgeIsNot() {
        var page = ScanBitmap(width: 60, height: 40, red: 240, green: 240, blue: 240)
        var seed: UInt32 = 7
        for y in 0..<40 {
            for x in 0..<60 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let high: UInt32 = seed >> 29
                let grain: Int = Int(high) - 4
                let level: Int = x < 30 ? 240 + grain : 30 + grain
                let value = UInt8(level)
                page.set(x: x, y: y, value, value, value)
            }
        }
        let smooth = ScanClean.denoised(page, grain: 10)
        func spread(_ bitmap: ScanBitmap) -> Int {
            let values = (5..<35).flatMap { y in (5..<25).map { x in Int(bitmap.brightness(x: x, y: y)) } }
            return values.max()! - values.min()!
        }
        XCTAssertLessThan(spread(smooth), spread(page))
        for y in 1..<39 {
            XCTAssertGreaterThan(smooth.brightness(x: 29, y: y), 200, "the light side of the edge stays light")
            XCTAssertLessThan(smooth.brightness(x: 30, y: y), 60, "and the dark side dark")
        }
    }

    func testAPaleLineIsKeptOrLeftOutWholeInBlackAndWhite() {
        for grey: Float in [0.70, 0.78, 0.84, 0.88] {
            var page = ScanPaperFixture.page(width: 420, grain: 4)
            let y0 = page.bitmap.height * 9 / 10
            for y in y0..<(y0 + 2) {
                for x in 30..<(page.bitmap.width - 30) {
                    let (red, green, blue) = page.bitmap.color(x: x, y: y)
                    page.bitmap.set(x: x, y: y, Self.dimmed(red, grey), Self.dimmed(green, grey), Self.dimmed(blue, grey))
                }
            }
            let black = ScanClean.clean(page.bitmap, .blackAndWhite)
            let along = (30..<(page.bitmap.width - 30)).map { x in
                black.brightness(x: x, y: y0) == 0 || black.brightness(x: x, y: y0 + 1) == 0
            }
            let dark: Int = along.filter { $0 }.count
            let share: Double = Double(dark) / Double(along.count)
            XCTAssertTrue(share == 0 || share > 0.97, "a line of \(grey) is \(Int(share * 100)) % black")
        }
    }

    func testABoxBlurKeepsAnEvenPlaneAndSoftensAnEdge() {
        let even = [UInt8](repeating: 200, count: 40 * 30)
        XCTAssertEqual(ScanClean.blurred(even, width: 40, height: 30, radius: 3), even)
        var edge = [UInt8](repeating: 255, count: 40 * 30)
        for y in 0..<30 { for x in 0..<20 { edge[y * 40 + x] = 0 } }
        let soft = ScanClean.blurred(edge, width: 40, height: 30, radius: 2)
        XCTAssertEqual(soft[15 * 40 + 5], 0)
        XCTAssertEqual(soft[15 * 40 + 35], 255)
        let middle: UInt8 = soft[15 * 40 + 20]
        XCTAssertTrue((40...220).contains(middle), "\(middle)")
    }

    /// A channel darkened to `share` of itself, as a grey band drawn over the page.
    private static func dimmed(_ value: UInt8, _ share: Float) -> UInt8 {
        let darker: Float = Float(value) * share
        return UInt8(darker)
    }

    /// A channel kept to `share` of its light by a shadow, with a speck's
    /// brightness added.
    private static func shaded(_ value: UInt8, _ share: Float, _ speck: Float) -> UInt8 {
        let shown: Float = Float(value) * share + speck
        return UInt8(min(shown, 255))
    }
}

/// Made-up pages to clean, drawn pixel by pixel: warm paper under a lamp
/// that fades across it, lines of print as bars of letters, a blue logo, a
/// dark box and a pale red stamp, with where each of them is.
enum ScanPaperFixture {
    struct Page {
        var bitmap: ScanBitmap
        /// Places with nothing but paper, away from everything.
        var paperSpots: [(Int, Int)] = []
        /// The middles of strokes of print.
        var inkSpots: [(Int, Int)] = []
        var logo = (0, 0)
        var stamp = (0, 0)
        var boxSpots: [(Int, Int)] = []
    }

    /// An A4-shaped page, `width` wide: lit from its top left, half as
    /// bright at its bottom right, its paper warm, with a camera's grain of
    /// up to `grain` levels either way, its print down to `printTo` of its
    /// height.
    static func page(width: Int = 420, grain: Int = 0, printTo: Double = 5.0 / 8,
                     paper: (Float, Float, Float) = (246, 245, 241)) -> Page {
        let height = Int((Double(width) * 1.4142).rounded())
        var bitmap = ScanBitmap(width: width, height: height, red: 0, green: 0, blue: 0)
        func light(_ x: Int, _ y: Int) -> Float {
            let across: Float = Float(x) / Float(width), down: Float = Float(y) / Float(height)
            let t: Float = (across + down) / 2
            return 1 - 0.5 * t
        }
        var marks = [UInt8](repeating: 0, count: width * height)
        var colors: [Int: (Float, Float, Float)] = [:]
        // Lines of print: words of letters, each letter a few strokes.
        var page = Page(bitmap: bitmap)
        let unit = max(1, width / 140)
        var y = height / 8
        var line = 0
        while y < Int(Double(height) * printTo) {
            var x = width / 12
            var word = 0
            while x < width * 11 / 12 - 6 * unit {
                let letters = 3 + (line * 7 + word * 3) % 5
                for _ in 0..<letters {
                    // A letter: two upright strokes and a bar.
                    for dy in 0..<(5 * unit) {
                        for dx in 0..<unit {
                            marks[(y + dy) * width + x + dx] = 1
                            marks[(y + dy) * width + x + 3 * unit + dx] = 1
                        }
                    }
                    for dx in 0..<(4 * unit) {
                        for dy in 0..<unit { marks[(y + 2 * unit + dy) * width + x + dx] = 1 }
                    }
                    if page.inkSpots.count < 400, (line + word) % 3 == 0 {
                        page.inkSpots.append((x + unit / 2, y + 2 * unit + unit / 2))
                    }
                    x += 5 * unit
                    if x >= width * 11 / 12 - 6 * unit { break }
                }
                x += 3 * unit
                word += 1
            }
            y += 9 * unit
            line += 1
        }
        // A blue logo at the top right, a dark box and a pale red stamp lower down.
        let logo = (x: width * 3 / 4, y: height / 60, size: width / 12)
        for yy in logo.y..<(logo.y + logo.size) {
            for xx in logo.x..<(logo.x + logo.size) {
                marks[yy * width + xx] = 2
                colors[2] = (40, 90, 200)
            }
        }
        page.logo = (logo.x + logo.size / 2, logo.y + logo.size / 2)
        let box = (x: width / 10, y: height * 2 / 3, w: width / 3, h: height / 8)
        for yy in box.y..<(box.y + box.h) {
            for xx in box.x..<(box.x + box.w) { marks[yy * width + xx] = 3 }
        }
        colors[3] = (60, 58, 55)
        for k in 0..<5 {
            page.boxSpots.append((box.x + box.w * (k + 1) / 6, box.y + box.h / 2))
            page.boxSpots.append((box.x + 3, box.y + box.h * (k + 1) / 6))
        }
        let stamp = (x: width * 2 / 3, y: height * 3 / 4, r: width / 10)
        for yy in (stamp.y - stamp.r)...(stamp.y + stamp.r) {
            for xx in (stamp.x - stamp.r)...(stamp.x + stamp.r) {
                let dx = Float(xx - stamp.x), dy = Float(yy - stamp.y)
                let d: Float = hypot(dx, dy)
                let outer = Float(stamp.r), ring = Float(max(3, unit * 2))
                let inner: Float = outer - ring
                if d <= outer, d >= inner { marks[yy * width + xx] = 4 }
            }
        }
        colors[4] = (240, 180, 180)
        page.stamp = (stamp.x + stamp.r - max(1, unit), stamp.y)
        // Paper away from everything: the bottom margin and the left edge.
        for k in 0..<12 {
            page.paperSpots.append((width / 24 + k * width / 13, height - height / 30))
            page.paperSpots.append((width / 30, height / 10 + k * height / 14))
        }
        page.paperSpots = page.paperSpots.filter { spot in
            let (x, y) = spot
            for dy in -4...4 { for dx in -4...4 {
                let xx = min(max(x + dx, 0), width - 1), yy = min(max(y + dy, 0), height - 1)
                if marks[yy * width + xx] != 0 { return false }
            } }
            return true
        }
        colors[0] = paper
        colors[1] = (30, 30, 35)
        // The lamp's warm cast, over everything on the page alike.
        let cast: (Float, Float, Float) = (1, 0.95, 0.84)
        var seed: UInt32 = 11
        func noise() -> Float {
            guard grain > 0 else { return 0 }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let high: UInt32 = seed >> 16
            let spread: Int = 2 * grain + 1
            let value: Int = Int(high) % spread - grain
            return Float(value)
        }
        for yy in 0..<height {
            for xx in 0..<width {
                let shade = light(xx, yy)
                let base = colors[Int(marks[yy * width + xx])] ?? paper
                // Red, green and blue each take the next of the grain, in that order.
                let red = Self.channel(base.0 * cast.0 * shade, noise())
                let green = Self.channel(base.1 * cast.1 * shade, noise())
                let blue = Self.channel(base.2 * cast.2 * shade, noise())
                bitmap.set(x: xx, y: yy, red, green, blue)
            }
        }
        page.bitmap = bitmap
        return page
    }

    /// One channel of a pixel: its colour under the lamp with the camera's
    /// grain, kept between 0 and 255.
    static func channel(_ value: Float, _ noise: Float) -> UInt8 {
        let grained: Float = value + noise
        let kept: Float = min(max(grained, 0), 255)
        return UInt8(kept)
    }
}

extension ScanBitmap {
    mutating func set(x: Int, y: Int, _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        let i = (y * width + x) * 4
        pixels[i] = red
        pixels[i + 1] = green
        pixels[i + 2] = blue
    }
}
