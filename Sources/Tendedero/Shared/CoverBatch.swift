import Foundation

/// Cover Files: many PDFs and pictures at once, even a thousand, each saved
/// as a covered copy in a new folder, with the folders they came in kept as
/// they were. These are its rules, without a screen: which files it takes,
/// where each copy goes, and how a run is summed up. The files themselves
/// are never changed.
enum CoverBatch {
    enum Kind: Sendable {
        case document, picture
    }

    /// One file to cover, and where it sits among what was brought: its name
    /// for a file brought on its own, or under its folder's name for a file
    /// found in a folder.
    struct Item: Identifiable, Equatable, Sendable {
        var url: URL
        var relative: String
        var kind: Kind

        var id: String { url.resolvingSymlinksInPath().path }
    }

    /// The files found, and those that cannot be covered, which get no copy.
    struct Scan: Equatable, Sendable {
        var items: [Item] = []
        var unsupported: [URL] = []
    }

    /// Pictures the Mac reads, by their ending; PDFs are documents.
    static let pictureExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif",
                                                 "webp", "bmp"]

    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .document }
        return pictureExtensions.contains(ext) ? .picture : nil
    }

    /// What was brought, folders opened all the way down, in the order
    /// brought and then by name. Hidden files are passed over, a file met
    /// twice counts once, and no more than `limit` are taken.
    static func scan(_ urls: [URL], limit: Int = 10_000, fileManager: FileManager = .default) -> Scan {
        var scan = Scan()
        var seen = Set<String>()
        func take(_ url: URL, relative: String) {
            guard scan.items.count < limit, seen.insert(url.resolvingSymlinksInPath().path).inserted else { return }
            if let kind = kind(of: url) {
                scan.items.append(Item(url: url, relative: relative, kind: kind))
            } else {
                scan.unsupported.append(url)
            }
        }
        for url in urls {
            var isFolder: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else {
                take(url, relative: url.lastPathComponent)
                continue
            }
            let base = url.resolvingSymlinksInPath().pathComponents
            let found = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var files: [URL] = []
            while let next = found?.nextObject() as? URL {
                let values = try? next.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true { files.append(next) }
            }
            files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            for file in files {
                let inside = file.resolvingSymlinksInPath().pathComponents.dropFirst(base.count)
                take(file, relative: ([url.lastPathComponent] + inside).joined(separator: "/"))
            }
        }
        return scan
    }

    /// Where each copy goes inside the new folder: where its file sat, a
    /// PDF as a PDF and a picture as a PNG, and a name never given twice.
    static func outputs(for items: [Item]) -> [String] {
        var taken = Set<String>()
        return items.map { item in
            let ext = item.kind == .document ? "pdf" : "png"
            let path = (item.relative as NSString).deletingPathExtension
            var candidate = "\(path).\(ext)"
            var n = 2
            while !taken.insert(candidate.lowercased()).inserted {
                candidate = "\(path) \(n).\(ext)"
                n += 1
            }
            return candidate
        }
    }

    /// The new folder's name, like "Covered 2026-10-19 08.15".
    static func folderName(at date: Date, calendar: Calendar = .current, prefix: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%@ %04d-%02d-%02d %02d.%02d", prefix, c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0)
    }

    /// How long the rest should take, from how long those done took; nil
    /// until there is enough to tell.
    static func remaining(done: Int, total: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard done >= 3, elapsed > 0, total > done else { return nil }
        return elapsed / Double(done) * Double(total - done)
    }
}
