import AppKit
import UniformTypeIdentifiers

/// Several screenshots joined into one image, to send one tidy picture
/// instead of a handful. Each keeps its size, so nothing gets blurry, and
/// they follow the order they hang in, on white with a little room between.
/// Or into one PDF, a page each, to send as a document; a whole page of a
/// website on as many sheets of paper as it needs.
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let target = newFile("Combined \(formatter.string(from: Date()))", "png")
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, joined, nil)
        return CGImageDestinationFinalize(destination) ? target : nil
    }

    /// One PDF with a page for each image, as Finder's Create PDF makes it:
    /// every page the size its screenshot shows on screen, with every pixel
    /// kept. A whole page of a website goes on sheets of A4 or US Letter
    /// instead, as the region uses, cut between lines (`PaperPages`), its
    /// pictures one after the other as one when it took more than one.
    /// Saved in Snapfly's folder under the name given.
    /// - Parameter pages: each image to draw, with the screenshot it stands
    ///   for, whose resolution sets the page size.
    static func pdf(_ pages: [(image: URL, original: URL)], named name: String) -> URL? {
        guard !pages.isEmpty else { return nil }
        let target = newFile(name, "pdf")
        let info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly"]
        guard let context = CGContext(target as CFURL, mediaBox: nil, info as CFDictionary) else { return nil }
        let paper = PaperSize.blank(region: Locale.current.region?.identifier)
        var drawn = 0
        var i = 0
        while i < pages.count {
            let page = pages[i]
            if FullPage.isWholePage(page.original) {
                // The pictures that follow it of the same page, in order.
                var run = [page.image]
                var last = FullPage.part(of: page.original)
                while i + run.count < pages.count, let part = last,
                      let next = FullPage.part(of: pages[i + run.count].original),
                      next.capture == part.capture, next.number == part.number + 1 {
                    run.append(pages[i + run.count].image)
                    last = next
                }
                if sheets(run, on: paper, into: context) { drawn += run.count }
                i += run.count
                continue
            }
            i += 1
            guard let source = CGImageSourceCreateWithURL(page.image as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            // A Retina screenshot says 144 dpi, so its page is half its size
            // in pixels. A covered copy may not say, so the original decides.
            let scale = 72 / dpi(of: page.original)
            var box = CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.beginPage(mediaBox: &box)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            context.interpolationQuality = .high
            context.draw(image, in: box)
            context.endPage()
            drawn += 1
        }
        context.closePDF()
        guard drawn == pages.count else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return target
    }

    /// The pictures of a whole page, top first, on sheets of paper one below
    /// the other as if they were one: each as wide as the paper less its
    /// margin and at the top of the sheet, so its words are the same size on
    /// every sheet. A sheet may hold the end of one picture and the start of
    /// the next. Each picture is read once to find where to cut, and once
    /// more to draw, so no more than one is held at a time.
    private static func sheets(_ pictures: [URL], on paper: CGSize, into context: CGContext) -> Bool {
        let decoded = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        func read(_ url: URL) -> CGImage? {
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, decoded) }
        }
        var rows: [[UInt8]] = []
        var heights: [Int] = []
        var width = 0
        for url in pictures {
            let measured: Bool = autoreleasepool {
                guard let image = read(url), let sampled = samples(of: image) else { return false }
                width = max(width, image.width)
                heights.append(image.height)
                rows += sampled
                return true
            }
            guard measured else { return false }
        }
        let room = PaperPages.room(on: paper)
        let scale = PaperPages.scale(width: width, paper: paper)
        let tops = heights.indices.map { heights[..<$0].reduce(0, +) }
        var held: (index: Int, image: CGImage)?
        for cut in PaperPages.cuts(quiet: PaperPages.quiet(rows),
                                   perPage: PaperPages.rowsPerPage(width: width, paper: paper)) {
            let done: Bool = autoreleasepool {
                var box = CGRect(origin: .zero, size: paper)
                context.beginPage(mediaBox: &box)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(box)
                for index in pictures.indices {
                    let part = tops[index]..<(tops[index] + heights[index])
                    let shown = part.clamped(to: cut)
                    guard !shown.isEmpty else { continue }
                    if held?.index != index {
                        held = nil
                        guard let image = read(pictures[index]) else { return false }
                        held = (index, image)
                    }
                    guard let image = held?.image,
                          let piece = image.cropping(to: CGRect(x: 0, y: shown.lowerBound - part.lowerBound,
                                                                width: image.width, height: shown.count))
                    else { return false }
                    let across = CGFloat(image.width) * scale, down = CGFloat(shown.count) * scale
                    let below = CGFloat(shown.upperBound - cut.lowerBound) * scale
                    context.draw(piece, in: CGRect(x: room.midX - across / 2, y: room.maxY - below,
                                                   width: across, height: down))
                }
                context.endPage()
                return true
            }
            guard done else { return false }
        }
        return true
    }

    /// The rows of a picture in gray, 256 samples across, to find where it
    /// can be cut.
    private static func samples(of image: CGImage) -> [[UInt8]]? {
        let width = 256, height = image.height
        guard height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height)
        // A bitmap context keeps its top row first in memory.
        return (0..<height).map { Array(UnsafeBufferPointer(start: bytes + $0 * width, count: width)) }
    }

    private static func dpi(of url: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpi >= 72 else { return 72 }
        return CGFloat(dpi)
    }

    /// A name not taken yet in Snapfly's folder, where taking the file down
    /// sends it to the Trash.
    static func newFile(_ base: String, _ ext: String) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
        var target = Inbox.folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = Inbox.folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return target
    }
}
