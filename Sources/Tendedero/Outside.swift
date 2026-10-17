import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Photos and PDFs brought onto the line from anywhere on the Mac: dropped
/// on the line or on the menu bar icon, sent from Finder's menu, opened
/// with Snapfly, or added from the menu bar. They hang like screenshots, and
/// what leaves the line is a protected copy. The file itself stays where it
/// is, untouched.
enum Outside {
    /// More at once would push every screenshot off the line.
    static let maxAtOnce = 20

    /// What can hang: a picture the Mac can open, or a PDF. A recording
    /// cannot be covered, and other documents are saved as PDFs first.
    static func accepts(_ url: URL) -> Bool {
        // Photos from a phone often say HEIC or JPG in capitals.
        guard !url.hasDirectoryPath, let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        if type.conforms(to: .pdf) { return true }
        guard type.conforms(to: .image) else { return false }
        return readableImageTypes.contains { type.conforms(to: $0) }
    }

    /// The kinds of picture macOS can read, from JPEG and HEIC to RAW.
    private static let readableImageTypes: [UTType] = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.compactMap(UTType.init)
    }()

    /// The files sorted into what can hang, what cannot, and PDFs that
    /// cannot be read without their password or are too long to read.
    struct Sorted {
        var accepted: [URL] = []
        var refused: [URL] = []
        var locked: [URL] = []
        var tooLong: [URL] = []
    }

    static func sort(_ urls: [URL]) -> Sorted {
        var sorted = Sorted()
        var seen = Set<String>()
        for url in urls where seen.insert(url.standardizedFileURL.path).inserted {
            if !accepts(url) {
                sorted.refused.append(url)
            } else if isDocument(url), DocumentCover.isLocked(url) {
                sorted.locked.append(url)
            } else if isDocument(url), DocumentCover.pageCount(url) > DocumentCover.maxPages {
                sorted.tooLong.append(url)
            } else {
                sorted.accepted.append(url)
            }
        }
        return sorted
    }

    // MARK: Brought from outside

    private static let broughtKey = "broughtFiles"

    /// Files brought onto the line this way, as opposed to screenshots: the
    /// time stamp, which says when a screenshot was taken, leaves them alone.
    static func isBrought(_ url: URL) -> Bool {
        (UserDefaults.standard.stringArray(forKey: broughtKey) ?? []).contains(url.standardizedFileURL.path)
    }

    /// Remembers a file brought in, and in the App Store edition how to
    /// open it again after a relaunch, which the sandbox only allows
    /// through a bookmark.
    static func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        var brought = UserDefaults.standard.stringArray(forKey: broughtKey) ?? []
        brought.removeAll { $0 == path }
        brought.append(path)
        UserDefaults.standard.set(Array(brought.suffix(200)), forKey: broughtKey)
        guard Edition.appStore,
              let mark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var marks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        marks[path] = mark
        // The oldest go once there are many; their files are long off the line.
        if marks.count > 200, let oldest = brought.first(where: { marks[$0] != nil && $0 != path }) {
            marks[oldest] = nil
        }
        UserDefaults.standard.set(marks, forKey: bookmarksKey)
    }

    private static let bookmarksKey = "broughtBookmarks"

    /// At launch, in the App Store edition: the files brought in before can
    /// be read again, on the line and in the history.
    static func reopen() {
        guard Edition.appStore else { return }
        let marks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        for mark in marks.values {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: mark, options: .withSecurityScope,
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
        }
    }
}

/// Finder's menu offers "Send Safely with Snapfly" for photos and PDFs, as a
/// service (Info.plist, NSServices). What it sends hangs on the line.
final class ServiceProvider: NSObject {
    /// Finder's "Send Safely with Snapfly".
    var onFiles: (([URL]) -> Void)?
    /// Finder's "Hide Private Details with Snapfly".
    var onHide: (([URL]) -> Void)?

    @objc func sendSafely(_ pasteboard: NSPasteboard, userData: String?,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        deliver(pasteboard, error: error, to: onFiles)
    }

    @objc func hideDetails(_ pasteboard: NSPasteboard, userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        deliver(pasteboard, error: error, to: onHide)
    }

    private func deliver(_ pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>,
                         to handle: (([URL]) -> Void)?) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files" as NSString
            return
        }
        // Services are called on the main thread.
        handle?(urls)
    }
}

/// Files dragged from Finder, or any other app, towards the top of the
/// screen. The line comes down to take them, the way the Dock opens a
/// folder you drag onto. Watching where the pointer goes needs no
/// permission; nothing is read until a drag carries files.
@MainActor
final class FileDragWatcher {
    /// Where the pointer is, while files are being dragged.
    var onMove: ((CGPoint) -> Void)?
    /// The drag is over: dropped somewhere, or let go.
    var onEnd: (() -> Void)?

    private var monitors: [Any] = []
    /// The drag pasteboard as it was when the button went down. A drag that
    /// starts writes to it; moving a window or selecting text does not.
    private var restCount = NSPasteboard(name: .drag).changeCount
    private var active = false
    private var lastLook = Date.distantPast

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.restCount = NSPasteboard(name: .drag).changeCount }
        }) {
            monitors.append(down)
        }
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }) {
            monitors.append(moved)
        }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }) {
            monitors.append(up)
        }
    }

    private func dragged() {
        if !active {
            // A few looks a second are plenty to notice a drag beginning.
            let now = Date()
            guard now.timeIntervalSince(lastLook) > 0.15 else { return }
            lastLook = now
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != restCount,
                  pasteboard.availableType(from: [.fileURL]) != nil else { return }
            active = true
        }
        onMove?(NSEvent.mouseLocation)
    }

    private func ended() {
        restCount = NSPasteboard(name: .drag).changeCount
        guard active else { return }
        active = false
        onEnd?()
    }
}

/// The line's strip takes files dropped on it. It holds the line view, and
/// only answers drags that carry files from another app: a photo dragged
/// along the line is the line's own business.
final class DropView: NSView {
    /// Files are over the line, or have left it.
    var onTarget: ((Bool) -> Void)?
    /// Dropped, with where they were let go on the screen.
    var onDrop: (([URL], CGPoint) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func files(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { answer(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { answer(sender) }

    private func answer(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil, files(sender).contains(where: Outside.accepts) else {
            onTarget?(false)
            return []
        }
        onTarget?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTarget?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTarget?(false)
        guard sender.draggingSource == nil else { return false }
        let point = window?.convertPoint(toScreen: sender.draggingLocation) ?? NSEvent.mouseLocation
        return onDrop?(files(sender), point) ?? false
    }
}

/// The menu bar icon takes files too, for when the line stays up there.
@MainActor
final class StatusDrop: NSObject, NSWindowDelegate, NSDraggingDestination {
    weak var button: NSStatusBarButton?
    var onDrop: (([URL], CGPoint) -> Void)?

    private func files(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard files(sender).contains(where: Outside.accepts) else { return [] }
        button?.highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(sender).contains(where: Outside.accepts) ? .copy : []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        let urls = files(sender)
        guard urls.contains(where: Outside.accepts) else { return false }
        let point = button?.window.map { $0.convertPoint(toScreen: sender.draggingLocation) } ?? NSEvent.mouseLocation
        onDrop?(urls, point)
        return true
    }
}
