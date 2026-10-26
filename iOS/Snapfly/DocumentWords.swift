import CoreGraphics
import Foundation

/// The words on each page of the documents kept on this iPhone, for
/// searching them all (`DocumentSearch`): a PDF's own text where it has
/// some, else what Vision reads on the page, read once on this iPhone and
/// kept beside the document, in a file closed while the iPhone is locked
/// and deleted with it. Never sent, and never shown: a search says only
/// where the words stand.
actor DocumentWords {
    static let shared = DocumentWords()

    /// Each page's words, in the document's order: "" for a blank page or
    /// one without words, and for one that cannot be read now, as a locked
    /// PDF's, which is read again next time.
    func words(of project: PDFProject) -> [String] {
        let url = ProjectStore.folder(project.id).appendingPathComponent("Words.json")
        var kept = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        var sources: [UUID: PDFSource] = [:]
        var changed = false
        let words = project.pages.map { page -> String in
            guard let key = Self.key(page.source) else { return "" }
            if let known = kept[key] { return known }
            guard let read = read(page.source, of: project, sources: &sources) else { return "" }
            kept[key] = read
            changed = true
            return read
        }
        if changed, let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
        return words
    }

    /// What a page says, or nil where it cannot be read now.
    private func read(_ source: PageSource, of project: PDFProject, sources: inout [UUID: PDFSource]) -> String? {
        guard let id = source.file, let stored = project.file(id)?.stored else { return nil }
        let url = ProjectStore.filesFolder(project.id).appendingPathComponent(stored)
        switch source {
        case .pdf(_, let index):
            if sources[id] == nil { sources[id] = PDFSource(url: url) }
            guard let pdf = sources[id], !pdf.isLocked else { return nil }
            if let text = pdf.text(index) { return text }
            // A scanned page without text: what Vision reads on it.
            return pdf.render(index, turns: 0, dpi: 200, longest: 2400).flatMap(Self.seen)
        case .picture:
            return PictureTools.read(url, longest: 2400).flatMap(Self.seen)
        case .blank:
            return ""
        }
    }

    /// The lines Vision reads on a picture, one under another.
    private static func seen(_ image: CGImage) -> String? {
        Finder.lines(in: image).map { $0.map(\.string).joined(separator: "\n") }
    }

    /// The same page of the same file reads the same, however it is turned.
    private static func key(_ source: PageSource) -> String? {
        switch source {
        case .pdf(let file, let index): "pdf-\(file.uuidString)-\(index)"
        case .picture(let file, _, _): "picture-\(file.uuidString)"
        case .blank: nil
        }
    }
}
