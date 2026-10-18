import AppKit

/// Download, the arrow on the tag: the photos picked, or all of them, saved
/// as they leave the line, covered, drawn on, cropped and stamped, into the
/// Downloads folder, each as a file of its own. They stay on the line, and
/// the files they came from stay as they are. The App Store edition asks
/// for the folder once, opening at Downloads, and keeps it as a bookmark.
@MainActor
enum Downloads {
    private static let folderKey = "downloadsFolder"

    /// Where downloads go: Downloads, or in the App Store edition the folder
    /// chosen for them; nil there until one is.
    static var folder: URL? {
        guard Edition.appStore else { return home }
        guard let mark = UserDefaults.standard.data(forKey: folderKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: mark, options: .withSecurityScope,
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private static var home: URL { Edition.home.appendingPathComponent("Downloads", isDirectory: true) }

    /// Asks for the folder, at Downloads; it, or nil when none was chosen.
    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = home
        panel.message = L("Choose the folder for downloads.")
        panel.prompt = L("Choose")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let mark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(mark, forKey: folderKey)
        return url
    }

    /// Saves each photo as it leaves the line, under the name it leaves
    /// with, and says where they went; a click shows them in Finder.
    static func save(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard !urls.contains(where: { PrivateDetails.stillCovering($0, PrivateDetails.details) }) else {
            Notice.show(L("Still covering the private details…"))
            return
        }
        guard let folder = folder ?? chooseFolder() else { return }
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        var saved: [URL] = []
        for url in urls {
            let made = PrivateDetails.shareable(url)
            let target = unique(made.lastPathComponent, in: folder)
            do {
                try FileManager.default.copyItem(at: made, to: target)
                saved.append(target)
            } catch {
                log.error("Could not download a photo: \(error.localizedDescription, privacy: .public)")
            }
        }
        switch saved.count {
        case 0:
            Notice.show(L("Could not save the copy."))
        case 1:
            Notice.savedCopy(saved[0])
        default:
            let place = Folders.placeName(folder)
            Notice.show(String(format: L("Saved %1$d photos in %2$@. Click to show them in Finder."), saved.count, place),
                        done: true, lasting: 6) {
                NSWorkspace.shared.activateFileViewerSelecting(saved)
            }
        }
    }

    /// The name in the folder, numbered after the first like Finder does,
    /// "Image 2.png", when one by that name is there already.
    nonisolated static func unique(_ name: String, in folder: URL,
                                   exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while exists(candidate) {
            let numbered = "\(base) \(n)"
            candidate = folder.appendingPathComponent(ext.isEmpty ? numbered : numbered + "." + ext)
            n += 1
        }
        return candidate
    }
}
