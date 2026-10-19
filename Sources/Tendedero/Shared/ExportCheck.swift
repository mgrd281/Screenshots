import CoreGraphics
import Foundation

extension Finder {
    /// Whether every place meant to be covered is covered in the copy: where
    /// the original shows something, like letters, the copy is changed too.
    /// A last check before a copy leaves, so a cover that went astray is
    /// never missed. A place with nothing in it, one even colour, needs no
    /// change. Places are from 0 to 1 from the bottom left.
    static func coversHold(original: CGImage, covered: CGImage, areas: [CGRect]) -> Bool {
        guard original.width == covered.width, original.height == covered.height else { return false }
        guard !areas.isEmpty else { return true }
        // Small, to be quick: what matters is whether the letters are gone.
        let scale = min(1, 1200 / CGFloat(max(original.width, original.height)))
        let width = max(1, Int(CGFloat(original.width) * scale)), height = max(1, Int(CGFloat(original.height) * scale))
        guard let before = pixels(of: original, width: width, height: height),
              let after = pixels(of: covered, width: width, height: height) else { return false }
        func luma(_ p: [UInt8], _ i: Int) -> Int { (Int(p[i]) * 3 + Int(p[i + 1]) * 6 + Int(p[i + 2])) / 10 }
        for area in areas {
            // The rows run from the top; the places are measured from the bottom.
            let x0 = max(0, Int(area.minX * CGFloat(width))), x1 = min(width, Int((area.maxX * CGFloat(width)).rounded(.up)))
            let y0 = max(0, Int((1 - area.maxY) * CGFloat(height)))
            let y1 = min(height, Int(((1 - area.minY) * CGFloat(height)).rounded(.up)))
            guard x1 > x0, y1 > y0 else { continue }
            var lumas: [Int] = []
            lumas.reserveCapacity((x1 - x0) * (y1 - y0))
            for y in y0..<y1 {
                for x in x0..<x1 { lumas.append(luma(before, (y * width + x) * 4)) }
            }
            let middle = lumas.sorted()[lumas.count / 2]
            var detail = 0, changed = 0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * width + x) * 4
                    if abs(luma(before, i) - middle) > 40 { detail += 1 }
                    let difference = abs(Int(before[i]) - Int(after[i])) + abs(Int(before[i + 1]) - Int(after[i + 1]))
                        + abs(Int(before[i + 2]) - Int(after[i + 2]))
                    if difference > 24 { changed += 1 }
                }
            }
            // At least as much changed as half of what showed there.
            if detail > 0, changed * 2 < detail { return false }
        }
        return true
    }

    /// A picture's pixels at this size, four bytes each, rows from the top.
    private static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
