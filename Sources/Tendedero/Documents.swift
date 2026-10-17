import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// A PDF from outside Snapfly, protected the way a screenshot is: every page
/// is read on this Mac and its private details covered, and the pages are
/// drawn into a new PDF. What is covered is gone, not painted over: no text
/// layer, links, form fields or document details come along, so nothing can
/// be copied out from under a cover. The PDF itself is never changed.
enum DocumentCover {
    /// Longer documents are refused, rather than read for minutes.
    static let maxPages = 200
    /// Pages are read and kept at about this resolution: sharp enough for
    /// small print, small enough to send.
    static let dpi: CGFloat = 200
    /// No page is drawn larger than this, so a poster stays manageable.
    static let maxPixels: CGFloat = 4000

    /// A PDF that is not Snapfly's own. Make PDF's are covered as they are
    /// made, from what leaves the line.
    static func protects(_ url: URL) -> Bool {
        isDocument(url) && !url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// Locked with a password, or not readable as a PDF at all.
    static func isLocked(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return true }
        return document.isLocked
    }

    static func pageCount(_ url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    /// How a page shows, in points: turned when the page is turned.
    static func pageSize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .cropBox)
        return abs(page.rotation) % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
    }

    /// One page as a picture, upright and on white, with its annotations and
    /// filled-in form fields, as it shows on screen.
    static func render(_ page: PDFPage) -> CGImage? {
        let size = pageSize(of: page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(dpi / 72, maxPixels / max(size.width, size.height))
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // PDFKit turns a turned page and starts at the box's corner itself.
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// The page images of a PDF, for Hide Part to show.
    static func page(_ number: Int, of url: URL) -> CGImage? {
        guard let document = PDFDocument(url: url), !document.isLocked,
              let page = document.page(at: number - 1) else { return nil }
        return render(page)
    }

    /// A new PDF with the chosen details and the parts hidden by hand
    /// covered on every page, under the same name. Nil when it cannot be
    /// read, or a page could not be drawn: then nothing is handed out
    /// half done.
    /// - Parameter hand: the parts hidden by hand, by page number from 1.
    static func copy(of url: URL, _ chosen: Set<PrivateDetail>, hand: [Int: [CGRect]]) -> URL? {
        covering(url, chosen, hand: hand)?.url
    }

    /// The same copy, with what was covered on its pages.
    static func covering(_ url: URL, _ chosen: Set<PrivateDetail>,
                         hand: [Int: [CGRect]]) -> (url: URL, report: CoverReport)? {
        guard let target = Cover.newCopy(of: url, ext: "pdf"),
              let report = write(url, chosen, hand: hand, to: target) else { return nil }
        return (target, report)
    }

    /// Writes the protected PDF to `target`, replacing a file there, and
    /// says what was covered on its pages. Nil, with nothing left behind,
    /// when a page could not be drawn.
    static func write(_ url: URL, _ chosen: Set<PrivateDetail>, hand: [Int: [CGRect]], to target: URL) -> CoverReport? {
        guard let document = PDFDocument(url: url), !document.isLocked,
              document.pageCount > 0, document.pageCount <= maxPages,
              // Only the app that made it; none of the original's details.
              let context = CGContext(target as CFURL, mediaBox: nil, [kCGPDFContextCreator: "Snapfly"] as CFDictionary)
        else { return nil }
        var drawn = 0
        var report = CoverReport()
        for index in 0..<document.pageCount {
            let done: Bool = autoreleasepool {
                guard let page = document.page(at: index), let image = render(page) else { return false }
                let found = Finder.coveredAreas(in: image, chosen)
                let byHand = hand[index + 1] ?? []
                guard let covered = Finder.cover(image, found.map(\.rect) + byHand) else { return false }
                report.add(CoverReport(found, hand: byHand.count))
                var box = CGRect(origin: .zero, size: pageSize(of: page))
                context.beginPage(mediaBox: &box)
                context.interpolationQuality = .high
                context.draw(compressed(covered) ?? covered, in: box)
                context.endPage()
                return true
            }
            guard done else { break }
            drawn += 1
        }
        context.closePDF()
        guard drawn == document.pageCount else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return report
    }

    /// The page as JPEG, which a PDF keeps as it is: a page of a few hundred
    /// kilobytes instead of several megabytes, ready to send.
    private static func compressed(_ image: CGImage) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
