#if canImport(PDFKit) && canImport(CoreGraphics)
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// A PDF a project's pages come from, opened from its copy in the project,
/// never from the file itself and never written: how many pages it has,
/// whether it is locked with a password or signed, each page as a picture,
/// upright and turned as the owner turned it, and the words it holds as
/// text, in lines as the covers read them. PDFKit lets one thread at a time
/// at a document, so every look at it waits its turn.
final class PDFSource: @unchecked Sendable {
    let url: URL
    private let document: PDFDocument
    private let lock = NSLock()
    /// Whether it was signed when it came, so editing it breaks the signature.
    let isSigned: Bool

    init?(url: URL) {
        // Read whole rather than mapped: the copy is closed while the iPhone is locked.
        guard let data = try? Data(contentsOf: url), PDFFacts.isPDF(data),
              let document = PDFDocument(data: data) else { return nil }
        self.url = url
        self.document = document
        isSigned = PDFFacts.isSigned(data)
    }

    /// Whether it waits for its password before its pages can be read.
    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return document.isLocked
    }

    /// Opens it with its password, in memory only: the password is never kept.
    func unlock(_ password: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return document.unlock(withPassword: password)
    }

    var pageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return document.pageCount
    }

    /// A page's size as it shows, turned by its own rotation and by the
    /// owner's quarter turns, in points.
    func size(of index: Int, turns: Int) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        guard !document.isLocked, let page = document.page(at: index) else { return nil }
        return Self.shown(page, turns: turns)
    }

    private static func shown(_ page: PDFPage, turns: Int) -> CGSize {
        let box = page.bounds(for: .cropBox)
        return PDFPageGeometry.shown(box, rotation: PDFPageGeometry.rotation(page: page.rotation, turns: turns))
    }

    /// A page as a picture, on white, with what is drawn on it, as it shows
    /// on screen: no side longer than `longest` pixels, nor sharper than
    /// `dpi`. Nil while the document is locked.
    func render(_ index: Int, turns: Int, dpi: Double, longest: Int) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard !document.isLocked, let page = document.page(at: index) else { return nil }
        // As the page shows with its own rotation, before the owner's turns.
        let upright = Self.shown(page, turns: 0)
        let shown = Self.shown(page, turns: turns)
        guard upright.width > 0, upright.height > 0 else { return nil }
        let scale = min(CGFloat(dpi / 72), CGFloat(longest) / max(shown.width, shown.height))
        let width = max(1, Int((shown.width * scale).rounded())), height = max(1, Int((shown.height * scale).rounded()))
        guard let context = PictureTools.context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        let turn = PDFPageGeometry.map(box: CGRect(origin: .zero, size: upright),
                                       rotation: PDFPageGeometry.rotation(page: 0, turns: turns), scale: scale)
        context.concatenate(CGAffineTransform(a: turn.a, b: turn.b, c: turn.c, d: turn.d, tx: turn.tx, ty: turn.ty))
        // PDFKit turns a page by its own rotation and starts at its box's corner itself.
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// The words a page holds as text, in lines and where each word is,
    /// from 0 to 1 from the bottom left of the page as it shows. Nil where
    /// the page holds no text worth reading, as a scan without text has none,
    /// or where its letters cannot be told apart from PDFKit's characters:
    /// then the page is read from its picture, as a scan is.
    func lines(_ index: Int, turns: Int) -> [Finder.TextLine]? {
        lock.lock()
        defer { lock.unlock() }
        guard !document.isLocked, let page = document.page(at: index), let text = page.string,
              PDFTextLayer.holdsText(text) else { return nil }
        let box = page.bounds(for: .cropBox)
        let rotation = PDFPageGeometry.rotation(page: page.rotation, turns: turns)
        // Each of PDFKit's characters with its own text and place, asked together, so the two always agree.
        let pieces = (0..<page.numberOfCharacters).map { page.selection(for: NSRange(location: $0, length: 1)) }
        let characters = PDFTextLayer.characters(of: text, count: pieces.count) { pieces[$0]?.string }
        guard PDFTextLayer.share(found: characters, of: text) >= 0.95 else { return nil }
        let found = PDFTextLayer.lines(text) { unit -> CGRect? in
            guard characters.indices.contains(unit), let character = characters[unit],
                  let place = pieces[character]?.bounds(for: page) else { return nil }
            guard !place.isNull, place.width > 0 || place.height > 0 else { return nil }
            let shown = PDFPageGeometry.normalized(place, box: box, rotation: rotation)
            // Text beyond the page as it is cut, which a PDF cropped in Preview keeps, is not on it.
            let onPage = shown.isNull ? shown : shown.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return onPage.isNull ? nil : onPage
        }
        return found.map { line in
            Finder.TextLine(string: line.string, box: line.box,
                            words: line.words.map { Finder.TextLine.Word(range: $0.range, box: $0.box) })
        }
    }

    /// The page itself, copied, turned by the owner's quarter turns as well,
    /// for a PDF that keeps its pages as they are.
    func copy(_ index: Int, turns: Int) -> PDFPage? {
        lock.lock()
        defer { lock.unlock() }
        guard !document.isLocked, let page = document.page(at: index), let copy = page.copy() as? PDFPage else { return nil }
        copy.rotation = PDFPageGeometry.rotation(page: page.rotation, turns: turns)
        return copy
    }

    /// The bytes a page holds on average in the file, to tell how large a
    /// PDF that keeps its pages will be.
    var bytesPerPage: Int {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size / max(1, pageCount)
    }
}

/// Pictures for a project: read as they came, upright, turned as the owner
/// turned them, smaller, and kept as a JPEG with nothing said about them.
enum PictureTools {
    /// A picture's pixels drawn on white, in sRGB.
    static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// A picture file read upright, as its notes say it was taken, no side
    /// longer than `longest`; nil when it is no picture.
    static func read(_ url: URL, longest: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: longest]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A picture file's size upright, in pixels, without reading its pixels.
    static func size(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // Orientations 5 to 8 stand the picture on its side.
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The picture turned clockwise by quarter turns.
    static func turned(_ image: CGImage, quarters: Int) -> CGImage? {
        let rotation = PDFPageGeometry.rotation(page: 0, turns: quarters)
        guard rotation != 0 else { return image }
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let size = PDFPageGeometry.shown(box, rotation: rotation)
        guard let context = context(width: Int(size.width), height: Int(size.height)) else { return nil }
        let turn = PDFPageGeometry.map(box: box, rotation: rotation, scale: 1)
        context.concatenate(CGAffineTransform(a: turn.a, b: turn.b, c: turn.c, d: turn.d, tx: turn.tx, ty: turn.ty))
        context.draw(image, in: box)
        return context.makeImage()
    }

    /// The picture drawn at another size, smoothly, on white.
    static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width != image.width || height != image.height else { return image }
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// An empty white page.
    static func blank(width: Int, height: Int) -> CGImage? {
        context(width: width, height: height)?.makeImage()
    }

    /// A JPEG of the picture with nothing but the picture in it.
    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ScanPDF.stripped(jpeg: data as Data)
    }
}

/// A project's pages as one PDF. With covers, every page is a picture with
/// its private details covered, and its words, where asked, are read again
/// from the covered picture, so none comes from under a cover. Without
/// covers, a PDF's pages stay as they are, with their own text, and only the
/// pictures are drawn; or, without searchable text, every page is a picture.
/// Pictures sit on their pages as `PaperSize` says, as sharp as
/// `ExportQuality` asks, never sharper than they are.
enum PDFComposer {
    /// Where a picture goes: on a page its own size, filling it; or on paper.
    static func frame(width: Int, height: Int, ownPage: CGSize?, paper: PaperSize) -> ScanPDF.Frame {
        if let ownPage {
            return ScanPDF.Frame(page: ownPage, picture: CGRect(origin: .zero, size: ownPage))
        }
        let layout = paper.layout(width: width, height: height)
        return ScanPDF.Frame(page: layout.page, picture: layout.picture)
    }

    /// A picture as a page of the PDF: drawn no sharper than the quality
    /// asks for the room it fills, kept as a JPEG without notes, with the
    /// words given laid invisibly over it.
    static func page(_ image: CGImage, ownPage: CGSize?, paper: PaperSize, quality: ExportQuality,
                     words: [ScanPDF.Word]) -> ScanPDF.Page? {
        let frame = frame(width: image.width, height: image.height, ownPage: ownPage, paper: paper)
        let pixels = quality.pixels(width: image.width, height: image.height, filling: frame.picture.size)
        guard let drawn = PictureTools.resized(image, width: pixels.width, height: pixels.height),
              let jpeg = PictureTools.jpeg(drawn, quality: quality.jpeg) else { return nil }
        return ScanPDF.Page(picture: .jpeg(jpeg, width: drawn.width, height: drawn.height, gray: false), words: words,
                            frame: frame)
    }

    /// An empty page, as small as a page can be: one white pixel over all of it.
    static func blank(_ size: CGSize) -> ScanPDF.Page {
        ScanPDF.Page(picture: .bits(Data([0x80]), width: 1, height: 1), words: [],
                     frame: ScanPDF.Frame(page: size, picture: CGRect(origin: .zero, size: size)))
    }

    /// The pages as one PDF: pictures only, as `ScanPDF` writes them, when
    /// no page is kept as it is; else PDFKit puts the kept pages and the
    /// pictures' pages together, in their order.
    static func make(_ pages: [Either]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let pictures = pages.compactMap { page -> ScanPDF.Page? in
            if case .made(let made) = page { return made }
            return nil
        }
        if pictures.count == pages.count { return ScanPDF.make(pictures) }
        // The pictures' pages, written once, then taken one by one into their places.
        let drawn = pictures.isEmpty ? nil : ScanPDF.make(pictures).flatMap(PDFDocument.init(data:))
        let out = PDFDocument()
        var next = 0
        for page in pages {
            switch page {
            case .kept(let kept):
                out.insert(kept, at: out.pageCount)
            case .made:
                guard let drawn, let made = drawn.page(at: next)?.copy() as? PDFPage else { return nil }
                next += 1
                out.insert(made, at: out.pageCount)
            }
        }
        out.documentAttributes = [PDFDocumentAttribute.producerAttribute: "Snapfly"]
        return out.dataRepresentation()
    }

    /// A page as it goes into the PDF: drawn by Snapfly, or kept as it is.
    enum Either {
        case made(ScanPDF.Page)
        case kept(PDFPage)
    }
}
#endif
