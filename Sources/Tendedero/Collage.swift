import AppKit
import UniformTypeIdentifiers

/// Several screenshots joined into one image, to send one tidy picture
/// instead of a handful. Each keeps its size, so nothing gets blurry, and
/// they follow the order they hang in, on white with a little room between.
enum Collage {
    enum Arrangement {
        case stacked, sideBySide
    }

    /// Draws the images into one and saves it in Tendedero's folder, where
    /// taking it down sends it to the Trash. Without an arrangement, wide
    /// screenshots go one under another and tall ones side by side.
    static func join(_ urls: [URL], _ arrangement: Arrangement? = nil) -> URL? {
        let images = urls.compactMap { url -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard images.count == urls.count, images.count > 1 else { return nil }
        let wide = images.map { Double($0.width) / Double(max($0.height, 1)) }.reduce(0, +) / Double(images.count) >= 1
        let stacked = (arrangement ?? (wide ? .stacked : .sideBySide)) == .stacked

        let gap = 24
        let width = stacked ? images.map(\.width).max()! + 2 * gap
            : images.reduce(0) { $0 + $1.width } + gap * (images.count + 1)
        let height = stacked ? images.reduce(0) { $0 + $1.height } + gap * (images.count + 1)
            : images.map(\.height).max()! + 2 * gap
        let space = images[0].colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Core Graphics counts from the bottom, so the first one goes at the top.
        var offset = gap
        for image in images {
            if stacked {
                let rect = CGRect(x: (width - image.width) / 2, y: height - offset - image.height,
                                  width: image.width, height: image.height)
                context.draw(image, in: rect)
                offset += image.height + gap
            } else {
                let rect = CGRect(x: offset, y: height - gap - image.height, width: image.width, height: image.height)
                context.draw(image, in: rect)
                offset += image.width + gap
            }
        }
        guard let joined = context.makeImage() else { return nil }

        let fm = FileManager.default
        try? fm.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Combined \(formatter.string(from: Date()))"
        var target = Inbox.folder.appendingPathComponent(base).appendingPathExtension("png")
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = Inbox.folder.appendingPathComponent("\(base) \(n)").appendingPathExtension("png")
            n += 1
        }
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, joined, nil)
        return CGImageDestinationFinalize(destination) ? target : nil
    }
}
