import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The copy Hide private details saves beside a photo or PDF from Finder: a
/// new file with what was chosen covered, and nothing of where or with what
/// the photo was taken. The original is never changed, and the owner picks
/// the place and the name before anything is written.
enum SaveCopy {
    /// A PDF stays a PDF; a PNG stays a PNG; any other photo goes as JPEG,
    /// the kind a photo sent to a chat is in.
    static func fileType(for url: URL) -> UTType {
        if isPDF(url) { return .pdf }
        return url.pathExtension.lowercased() == "png" ? .png : .jpeg
    }

    /// The original's name with a mark, so the copy is never taken for it.
    static func suggestedName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return String(format: L("%@ (covered)"), stem) + "." + fileExtension(for: url)
    }

    static func fileExtension(for url: URL) -> String {
        if isPDF(url) { return "pdf" }
        return url.pathExtension.lowercased() == "png" ? "png" : "jpg"
    }

    private static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// Writes the copy to `target`, replacing a file there. A photo gets the
    /// chosen details and the parts hidden by hand covered; a PDF gets them
    /// on each page, its boxes kept by page number from 1. Returns what was
    /// covered in the copy, so a note says "covered" only when something
    /// was, or nil when it was not written; nothing half done is left behind.
    static func write(_ url: URL, _ chosen: Set<PrivateDetail>, hand: [CGRect], pages: [Int: [CGRect]],
                      to target: URL) -> CoverReport? {
        if isPDF(url) {
            return DocumentCover.write(url, chosen, hand: pages, to: target)
        }
        guard let made = Cover.covered(of: url, chosen, hand: hand),
              writePicture(made.image, to: target, type: fileType(for: url)) else { return nil }
        return made.report
    }

    /// Only the pixels are written: the picture comes out without the
    /// metadata it had, since none is given to the encoder.
    private static func writePicture(_ image: CGImage, to target: URL, type: UTType) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: target)
            return false
        }
        return true
    }
}
