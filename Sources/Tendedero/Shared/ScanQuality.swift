import Foundation

/// Something on a scanned page that makes it harder to read, said beside
/// the page, never on it: text read less after cleaning, a reflection,
/// blur, a smudged lens or a page too small in the picture.
struct ScanIssue: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Less is read on the cleaned page than on the page before it was cleaned.
        case lessText
        /// A reflection of the light makes part of the page white.
        case glare
        case blurred
        /// The camera's lens looks smudged.
        case smudge
        /// Too few pixels for a page: fine print may not read.
        case small
    }

    /// Which part of the page, top to bottom, for the words.
    enum Part: Equatable, Sendable {
        case top, middle, bottom, whole
    }

    let kind: Kind
    /// Where on the page, from 0 to 1 from the bottom left; nil for all of it.
    let area: CGRect?

    init(_ kind: Kind, area: CGRect? = nil) {
        self.kind = kind
        self.area = area
    }

    /// The part of the page the area is in: its middle's third, or the whole
    /// page when it reaches over most of it.
    var part: Part {
        guard let area, area.height < 0.7 else { return .whole }
        if area.midY >= 2.0 / 3 { return .top }
        if area.midY <= 1.0 / 3 { return .bottom }
        return .middle
    }

    /// Whether taking the page again is the way to a clear one; text read
    /// less after cleaning is compared, not taken again.
    var asksForRetake: Bool { kind != .lessText }

    /// What is wrong and what to do, as the status over the page says it.
    func message(in mode: ScanColor) -> String {
        switch (kind, part) {
        case (.lessText, _):
            mode == .blackAndWhite
                ? L("In black and white, less text reads at the marked place. Choose Color or Grayscale.")
                : L("Less text reads at the marked place after brightening. Compare it with Before.")
        case (.blurred, .top): L("At the top the text is blurred. Take it again for a clear result.")
        case (.blurred, .middle): L("In the middle the text is blurred. Take it again for a clear result.")
        case (.blurred, .bottom): L("At the bottom the text is blurred. Take it again for a clear result.")
        case (.blurred, .whole): L("The text is blurred. Take it again for a clear result.")
        case (.glare, .top): L("At the top a reflection hides text. Take it again for a clear result.")
        case (.glare, .middle): L("In the middle a reflection hides text. Take it again for a clear result.")
        case (.glare, .bottom): L("At the bottom a reflection hides text. Take it again for a clear result.")
        case (.glare, .whole): L("A reflection hides text. Take it again for a clear result.")
        case (.smudge, _): L("The camera lens looks smudged. Wipe it and take the page again.")
        case (.small, _): L("The page is small in the picture, so fine print may not read. Take it again closer.")
        }
    }

    /// The most important first: what was read less, then what hides text.
    static func ordered(_ issues: [ScanIssue]) -> [ScanIssue] {
        let rank: [Kind: Int] = [.lessText: 0, .glare: 1, .blurred: 2, .smudge: 3, .small: 4]
        return issues.enumerated().sorted { a, b in
            let first: Int = rank[a.element.kind] ?? 9, second: Int = rank[b.element.kind] ?? 9
            return first != second ? first < second : a.offset < b.offset
        }.map(\.element)
    }
}

/// How well a page can be read as it was taken, before it is cleaned:
/// blurred parts, a reflection, and too few pixels for its size. Blur is
/// measured in tiles that hold print: how sharply the brightness turns at
/// the print's edges (the Laplacian's spread there), against how dark the
/// print is, so faint print is not taken for blurred. The page is measured
/// at about the same size whatever the camera, so the measures mean the same.
enum ScanQuality {
    struct Tuning: Equatable, Sendable {
        /// The page is measured at about this many pixels on its longer side, or more.
        var measuredSide = 1600
        /// Tiles of this many pixels, at that size.
        var tile = 64
        /// A tile holds print when its dark and its light differ this much.
        var printContrast: Float = 50
        /// Edges less sharp than this are blurred: about a Gaussian blur of
        /// 1.7 pixels at the measured size, where small print starts to blur.
        var sharpEdges: Float = 0.12
        /// A part of the page is blurred when this share of its tiles with
        /// print is, and there are at least `fewestTiles` of them.
        var blurredShare = 0.5
        var fewestTiles = 3
        /// A reflection: this share of a tile's pixels at `glareWhite` or
        /// over, on a page whose paper is no lighter than `dullPaper`, and
        /// at least `glareTiles` such tiles.
        var glareShare: Float = 0.4
        var glareWhite: UInt8 = 250
        var dullPaper: Float = 235
        var glareTiles = 2
        /// Fewer dots an inch than this, as the page would be printed, is small.
        var smallest = 150.0
    }

    struct Tile: Equatable {
        /// In pixels of the measured page, from its top left.
        let x: Int
        let y: Int
        let size: Int
        let hasPrint: Bool
        /// How sharp its print's edges are; 0 without print.
        let sharpness: Float
        /// The share of its pixels that are white out.
        let white: Float
        /// How bright its paper is.
        let paper: Float
    }

    /// The page's tiles, measured, and the measured page's size.
    static func tiles(of page: ScanBitmap, tuning: Tuning = .init()) -> (tiles: [Tile], width: Int, height: Int) {
        let factor = max(1, max(page.width, page.height) / max(1, tuning.measuredSide))
        let (plane, w, h) = shrunk(page.brightness, width: page.width, height: page.height, by: factor)
        let size = tuning.tile
        var tiles: [Tile] = []
        var values = [UInt8](repeating: 0, count: size * size)
        for ty in stride(from: 0, through: h - size, by: size) {
            for tx in stride(from: 0, through: w - size, by: size) {
                for y in 0..<size {
                    let row: Int = (ty + y) * w + tx
                    for x in 0..<size { values[y * size + x] = plane[row + x] }
                }
                tiles.append(measure(values, size: size, x: tx, y: ty, tuning: tuning))
            }
        }
        return (tiles, w, h)
    }

    /// What is wrong with the page as it was taken; `dpi` as it would be
    /// printed (`ScanGeometry.dpi`).
    static func issues(in page: ScanBitmap, dpi: Double, tuning: Tuning = .init()) -> [ScanIssue] {
        let measured = tiles(of: page, tuning: tuning)
        var issues: [ScanIssue] = []
        if let area = blurred(measured.tiles, width: measured.width, height: measured.height, tuning: tuning) {
            issues.append(ScanIssue(.blurred, area: area.isWhole ? nil : area.rect))
        }
        if let area = glare(measured.tiles, width: measured.width, height: measured.height, tuning: tuning) {
            issues.append(ScanIssue(.glare, area: area))
        }
        if dpi < tuning.smallest { issues.append(ScanIssue(.small)) }
        return issues
    }

    // MARK: Blur

    /// Where the page is blurred: in thirds, top to bottom, each with enough
    /// tiles of print, the thirds that are mostly blurred; nil when none is.
    static func blurred(_ tiles: [Tile], width: Int, height: Int,
                        tuning: Tuning = .init()) -> (rect: CGRect, isWhole: Bool)? {
        let printed = tiles.filter(\.hasPrint)
        var blurredThirds: [Int] = [], measuredThirds = 0
        for third in 0..<3 {
            let inThird = printed.filter { Self.third(of: $0, height: height) == third }
            guard inThird.count >= tuning.fewestTiles else { continue }
            measuredThirds += 1
            let soft = inThird.filter { $0.sharpness < tuning.sharpEdges }.count
            let share: Double = Double(soft) / Double(inThird.count)
            if share >= tuning.blurredShare { blurredThirds.append(third) }
        }
        guard !blurredThirds.isEmpty else { return nil }
        let blurredTiles = printed.filter { tile in
            tile.sharpness < tuning.sharpEdges && blurredThirds.contains(Self.third(of: tile, height: height))
        }
        let rect = normalized(blurredTiles, width: width, height: height)
        return (rect, blurredThirds.count == measuredThirds && measuredThirds >= 2)
    }

    /// Which third of the page, top to bottom from 0, a tile's middle is in.
    private static func third(of tile: Tile, height: Int) -> Int {
        let middle = Double(tile.y + tile.size / 2)
        let share: Double = middle / Double(height)
        return min(2, Int(share * 3))
    }

    // MARK: Glare

    /// Where a reflection whitens the page: tiles mostly white out on a page
    /// whose paper is duller; nil without enough of them.
    static func glare(_ tiles: [Tile], width: Int, height: Int, tuning: Tuning = .init()) -> CGRect? {
        let papers = tiles.map(\.paper).sorted()
        guard !papers.isEmpty, papers[papers.count / 2] <= tuning.dullPaper else { return nil }
        let white = tiles.filter { $0.white >= tuning.glareShare }
        guard white.count >= tuning.glareTiles else { return nil }
        return normalized(white, width: width, height: height)
    }

    // MARK: Measuring

    /// A tile's print, edges, whiteness and paper.
    static func measure(_ values: [UInt8], size: Int, x: Int, y: Int, tuning: Tuning) -> Tile {
        var counts = [Int](repeating: 0, count: 256)
        for value in values { counts[Int(value)] += 1 }
        func percentile(_ share: Double) -> Float {
            let count = Double(values.count)
            let rank = Int(count * share)
            var seen = 0
            for value in 0..<256 {
                seen += counts[value]
                if seen > rank { return Float(value) }
            }
            return 255
        }
        let low = percentile(0.05), high = percentile(0.95), paper = percentile(0.9)
        let contrast: Float = high - low
        let whiteCount = counts[Int(tuning.glareWhite)...].reduce(0, +)
        let white: Float = Float(whiteCount) / Float(values.count)
        let darkLine: Float = high - contrast / 2
        var darkCount = 0
        for value in values where Float(value) < darkLine { darkCount += 1 }
        let darkShare: Float = Float(darkCount) / Float(values.count)
        guard contrast >= tuning.printContrast, darkShare >= 0.01, darkShare <= 0.6 else {
            return Tile(x: x, y: y, size: size, hasPrint: false, sharpness: 0, white: white, paper: paper)
        }
        // The Laplacian's spread where the brightness turns, against the contrast.
        var sum: Float = 0, edges = 0
        for row in 1..<(size - 1) {
            for column in 1..<(size - 1) {
                let p = row * size + column
                let middle = Float(values[p])
                let left = Float(values[p - 1]), right = Float(values[p + 1])
                let up = Float(values[p - size]), down = Float(values[p + size])
                let across: Float = abs(right - left), downwards: Float = abs(down - up)
                let turn: Float = max(across, downwards) / 2
                guard turn >= 0.15 * contrast else { continue }
                let around: Float = left + right + up + down
                let laplacian: Float = 4 * middle - around
                sum += laplacian * laplacian
                edges += 1
            }
        }
        guard edges >= 20 else {
            return Tile(x: x, y: y, size: size, hasPrint: false, sharpness: 0, white: white, paper: paper)
        }
        let spread: Float = (sum / Float(edges)).squareRoot()
        let sharpness: Float = spread / contrast
        return Tile(x: x, y: y, size: size, hasPrint: true, sharpness: sharpness, white: white, paper: paper)
    }

    /// The plane made smaller by a whole factor, each pixel the mean of its square.
    static func shrunk(_ plane: [UInt8], width: Int, height: Int, by factor: Int) -> ([UInt8], Int, Int) {
        guard factor > 1 else { return (plane, width, height) }
        let w = width / factor, h = height / factor
        var out = [UInt8](repeating: 0, count: w * h)
        let area = factor * factor
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0
                for dy in 0..<factor {
                    let line: Int = y * factor + dy
                    let row: Int = line * width + x * factor
                    for dx in 0..<factor { sum += Int(plane[row + dx]) }
                }
                let mean: Int = sum / area
                out[y * w + x] = UInt8(mean)
            }
        }
        return (out, w, h)
    }

    /// The box round some tiles, from 0 to 1 from the bottom left.
    static func normalized(_ tiles: [Tile], width: Int, height: Int) -> CGRect {
        guard let first = tiles.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x + first.size, maxY = first.y + first.size
        for tile in tiles {
            minX = min(minX, tile.x)
            minY = min(minY, tile.y)
            maxX = max(maxX, tile.x + tile.size)
            maxY = max(maxY, tile.y + tile.size)
        }
        let w = CGFloat(width), h = CGFloat(height)
        let left: CGFloat = CGFloat(minX) / w, bottom: CGFloat = 1 - CGFloat(maxY) / h
        let across: CGFloat = CGFloat(maxX - minX) / w, down: CGFloat = CGFloat(maxY - minY) / h
        return CGRect(x: left, y: bottom, width: across, height: down)
    }
}
