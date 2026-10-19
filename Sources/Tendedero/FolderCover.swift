import AppKit
import UniformTypeIdentifiers

/// Cover a folder, from Settings › Privacy: every picture or PDF that lands
/// in one folder, like the one invoices are downloaded to, gets a copy with
/// what Settings checks covered, saved under its name in another folder.
/// It works in the background, one file after another, and says once a run
/// is done how many were saved and where nothing was found.
@MainActor
final class FolderCover {
    static let shared = FolderCover()

    private var watcher: ScreenshotWatcher?
    private var opened: [URL] = []
    /// One file at a time, at low priority, however many land at once.
    private let queue = DispatchQueue(label: "Snapfly.FolderCover", qos: .utility)
    /// What happened since the last note.
    private var saved = 0
    private var nothingFound: [String] = []
    private var failed: [String] = []
    private var noting: DispatchWorkItem?

    private static let onKey = "coverFolderOn"
    private static let sourceKey = "coverFolderFrom"
    private static let targetKey = "coverFolderTo"

    /// Off unless turned on.
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: onKey) }
        set { UserDefaults.standard.set(newValue, forKey: onKey) }
    }

    /// The folder watched, and the one the copies go to.
    static var source: URL? {
        get { folder(sourceKey) }
        set { setFolder(newValue, sourceKey) }
    }

    static var target: URL? {
        get { folder(targetKey) }
        set { setFolder(newValue, targetKey) }
    }

    /// The App Store edition keeps a folder as a bookmark, the only way back
    /// in after a relaunch.
    private static func folder(_ key: String) -> URL? {
        if Edition.appStore {
            guard let mark = UserDefaults.standard.data(forKey: key) else { return nil }
            var stale = false
            return try? URL(resolvingBookmarkData: mark, options: .withSecurityScope,
                            relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func setFolder(_ url: URL?, _ key: String) {
        if Edition.appStore {
            let mark = try? url?.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                              relativeTo: nil)
            UserDefaults.standard.set(mark, forKey: key)
        } else {
            UserDefaults.standard.set(url?.path, forKey: key)
        }
    }

    /// Asks for the folder to watch, or the one for the copies; it, or nil
    /// when none was chosen or it is not apart from the other.
    static func choose(source: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = source ? L("Choose the folder to watch.") : L("Choose the folder for the covered copies.")
        panel.prompt = L("Choose")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let other = source ? target : self.source, !areApart(url, other) {
            Notice.show(L("Choose two folders apart from each other."))
            return nil
        }
        if source { self.source = url } else { target = url }
        return url
    }

    /// Two different folders, neither inside the other, so a copy never
    /// lands where it would be covered again.
    nonisolated static func areApart(_ a: URL, _ b: URL) -> Bool {
        let a = a.standardizedFileURL.path, b = b.standardizedFileURL.path
        return a != b && !a.hasPrefix(b + "/") && !b.hasPrefix(a + "/")
    }

    // MARK: Watching

    /// Watches, or stops, as Settings says. What was in the folder before
    /// stays as it is; only what lands from now on is covered.
    func restart() {
        stop()
        guard Self.isOn, let source = Self.source, let target = Self.target, Self.areApart(source, target) else { return }
        for folder in [source, target] where folder.startAccessingSecurityScopedResource() {
            opened.append(folder)
        }
        let watcher = ScreenshotWatcher(folder: source, anyImage: true, documents: true,
                                        onNew: { [weak self] url in self?.cover(url, into: target) },
                                        onChange: {})
        watcher.start()
        self.watcher = watcher
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        opened.forEach { $0.stopAccessingSecurityScopedResource() }
        opened = []
    }

    private func cover(_ url: URL, into folder: URL) {
        let chosen = PrivateDetails.details
        queue.async {
            let made = Self.waitUntilWritten(url) ? Self.coverCopy(of: url, chosen, into: folder) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.note(url, made?.report) }
            }
        }
    }

    /// A file still being written grows; it is covered once its size has
    /// held for half a second. False when it never does within ten.
    nonisolated static func waitUntilWritten(_ url: URL) -> Bool {
        var last: Int?
        for _ in 0..<20 {
            // Read fresh each time: a URL keeps what it read before.
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
            if let size, size > 0, size == last { return true }
            last = size
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// The covered copy saved in the folder under the file's name, a PDF as
    /// a PDF and a picture as a PNG, and what was covered in it. Nil when
    /// the file cannot be read.
    nonisolated static func coverCopy(of url: URL, _ chosen: Set<PrivateDetail>,
                                      into folder: URL) -> (url: URL, report: CoverReport)? {
        let name = url.deletingPathExtension().lastPathComponent
        let target = unique(name, ext: isDocument(url) ? "pdf" : "png", in: folder)
        return coverCopy(of: url, chosen, to: target).map { (target, $0) }
    }

    /// The covered copy written to `target`, a PDF as a PDF and a picture as
    /// a PNG, and what was covered in it. Nil, with nothing left behind,
    /// when the file cannot be read.
    nonisolated static func coverCopy(of url: URL, _ chosen: Set<PrivateDetail>, to target: URL) -> CoverReport? {
        if isDocument(url) {
            return DocumentCover.write(url, chosen, hand: [:], to: target)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = Cover.upright(source) else { return nil }
        guard let made = Finder.covered(image, chosen),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, made.image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return CoverReport(made.areas)
    }

    /// A name not taken in the folder: the file's, then with " 2", " 3"….
    nonisolated static func unique(_ name: String, ext: String, in folder: URL) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    // MARK: Saying so

    /// One note for a run of files, two seconds after the last one.
    private func note(_ url: URL, _ report: CoverReport?) {
        if let report {
            saved += 1
            if report.isEmpty { nothingFound.append(url.lastPathComponent) }
        } else {
            failed.append(url.lastPathComponent)
        }
        noting?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.speak() } }
        noting = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func speak() {
        var lines: [String] = []
        if saved > 0 { lines.append(String(format: L("Covered copies saved: %ld"), saved)) }
        if !nothingFound.isEmpty {
            lines.append(String(format: L("Nothing to cover in %@. Take a look."), Self.names(nothingFound)))
        }
        if !failed.isEmpty { lines.append(String(format: L("Could not cover %@."), Self.names(failed))) }
        saved = 0
        nothingFound = []
        failed = []
        guard !lines.isEmpty else { return }
        Notice.show(lines.joined(separator: " "))
    }

    /// Up to three names, then an ellipsis.
    nonisolated static func names(_ files: [String]) -> String {
        files.prefix(3).joined(separator: ", ") + (files.count > 3 ? " …" : "")
    }
}
