import AppKit

/// What has left the line, kept for a while so it can be found and hung
/// again: a screenshot taken down by mistake, or sent and needed once more.
///
/// A file of Snapfly's own moves into the History folder instead of the
/// Trash. A file from anywhere else, like the Desktop, stays where it is
/// and is only remembered. Past its time, a kept file goes to the Trash.
/// Nothing leaves the Mac.
@MainActor
enum History {
    /// How many days photos stay, from Settings. Nil means no history.
    static var days: Int? {
        get {
            let saved = UserDefaults.standard.object(forKey: "historyDays") as? Int ?? 30
            return saved > 0 ? saved : nil
        }
        set {
            UserDefaults.standard.set(newValue ?? 0, forKey: "historyDays")
            if newValue == nil { clear() } else { purge() }
        }
    }

    /// Kept until removed: a hundred years.
    static let forever = 36_500

    static let dayChoices = [7, 30, 90, 365, forever]

    /// A choice as Settings names it: "30 days", "1 year" or "Forever".
    static func title(days: Int) -> String {
        switch days {
        case forever: L("Forever")
        case 365: L("1 year")
        default: String(format: L("%d days"), days)
        }
    }

    /// Always Snapfly's own folder, out of sight, so photos kept for a while
    /// never land in the Workspace.
    static let folder = Inbox.legacyFolder.appendingPathComponent("History", isDirectory: true)

    struct Entry: Codable, Identifiable, Hashable {
        var path: String
        /// When it left the line.
        var left: Date
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
    }

    /// Newest first.
    static private(set) var entries: [Entry] = load() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: entriesKey)
            onChange?()
        }
    }

    /// The history window listens, to show what changed.
    static var onChange: (() -> Void)?

    private static let entriesKey = "historyEntries"

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return saved
    }

    /// The files it holds, so their words stay known for search.
    static var paths: Set<String> { Set(entries.map(\.path)) }

    /// A photo leaving the line. Returns true when a file of Snapfly's own
    /// was kept, so it must not go to the Trash.
    @discardableResult
    static func keep(_ url: URL, owned: Bool) -> Bool {
        guard days != nil, FileManager.default.fileExists(atPath: url.path) else { return false }
        var kept = url
        if owned {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                kept = unique(url.lastPathComponent, in: folder)
                try fm.moveItem(at: url, to: kept)
            } catch {
                log.error("Could not keep \(url.lastPathComponent, privacy: .public) in the history: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        entries.removeAll { $0.path == kept.path }
        entries.insert(Entry(path: kept.path, left: Date()), at: 0)
        return owned
    }

    /// Back on the line: a kept file returns to Snapfly's folder, and leaves
    /// the history. Returns where it is now.
    static func takeBack(_ entry: Entry) -> URL? {
        entries.removeAll { $0.path == entry.path }
        guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
        guard isKept(entry.url) else { return entry.url }
        let back = unique(entry.url.lastPathComponent, in: Inbox.folder)
        do {
            try FileManager.default.moveItem(at: entry.url, to: back)
            return back
        } catch {
            return entry.url
        }
    }

    /// Out of the history for good: a kept file goes to the Trash.
    static func remove(_ entry: Entry) {
        entries.removeAll { $0.path == entry.path }
        if isKept(entry.url) {
            try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        }
    }

    static func clear() {
        for entry in entries where isKept(entry.url) {
            try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        }
        entries = []
        SendLog.clear()
    }

    /// What has had its days, or whose file is gone, leaves. Runs at launch
    /// and when the history window opens.
    static func purge() {
        guard let days else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let fm = FileManager.default
        var stay: [Entry] = []
        for entry in entries {
            if entry.left < cutoff {
                if isKept(entry.url) { try? fm.trashItem(at: entry.url, resultingItemURL: nil) }
            } else if fm.fileExists(atPath: entry.path) {
                stay.append(entry)
            }
        }
        if stay != entries { entries = stay }
        SendLog.purge(before: cutoff)
    }

    private static func isKept(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    private static func unique(_ name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var url = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
