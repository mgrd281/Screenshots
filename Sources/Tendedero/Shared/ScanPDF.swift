import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scanned pages, covered, as one PDF to send or keep: a picture of each
/// page and nothing else, so no text can be copied out of it, and nothing
/// is said of who made it but the app.
enum ScanPDF {
    /// The shorter side of every page, in points: A4's, so a page prints at
    /// its size.
    static let shortSide: CGFloat = 595.28
    /// A page larger than this on its longer side, in pixels, is made
    /// smaller: 300 dots an inch on A4.
    static let longest = 3508

    /// One page for each picture, in their order; nil without pictures or
    /// when one could not be put in.
    static func make(_ pages: [CGImage], quality: CGFloat = 0.82) -> Data? {
        guard let first = pages.first else { return nil }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: size(of: first))
        let info: [CFString: Any] = [kCGPDFContextCreator: "Snapfly"]
        guard let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return nil }
        for page in pages {
            guard let picture = compressed(page, quality: quality) else {
                context.closePDF()
                return nil
            }
            let bounds = CGRect(origin: .zero, size: size(of: page))
            let mediaBox = withUnsafeBytes(of: bounds) { Data($0) }
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: mediaBox as CFData]
            context.beginPDFPage(pageInfo as CFDictionary)
            context.interpolationQuality = .high
            context.draw(picture, in: bounds)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// A page's size in points: its shorter side as wide as A4's, its
    /// longer one as the picture is.
    static func size(of image: CGImage) -> CGSize {
        let width = CGFloat(max(1, image.width)), height = CGFloat(max(1, image.height))
        return width <= height
            ? CGSize(width: shortSide, height: shortSide * height / width)
            : CGSize(width: shortSide * width / height, height: shortSide)
    }

    /// The picture on white, no larger than `longest`, as a JPEG, so the PDF
    /// stays small enough to send.
    static func compressed(_ image: CGImage, quality: CGFloat) -> CGImage? {
        let scale = min(1, CGFloat(longest) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        canvas.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        canvas.fill(whole)
        canvas.interpolationQuality = .high
        canvas.draw(image, in: whole)
        guard let flat = canvas.makeImage() else { return nil }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(jpeg as Data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
