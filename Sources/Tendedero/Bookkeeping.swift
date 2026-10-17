import AppKit

/// Handing receipts on for the books, from a photo's menu: a covered copy
/// whose name says what it is, saved in the bookkeeping folder with a line
/// in its table, or put in a new email to whoever keeps the books. What
/// goes is covered as anything that leaves the line, and the name leaves
/// out what is covered.
@MainActor
enum Bookkeeping {
    private static let folderKey = "bookkeepingFolder"
    private static let addressKey = "bookkeepingAddress"
    /// The table in the folder, a line a receipt.
    static let tableName = "Snapfly.csv"

    /// Whoever keeps the books, to write to.
    static var address: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: addressKey) }
    }

    /// The folder for the books; nil until one is chosen. The App Store
    /// edition keeps it as a bookmark, the only way back in after a relaunch.
    static var folder: URL? {
        get {
            if Edition.appStore {
                guard let mark = UserDefaults.standard.data(forKey: folderKey) else { return nil }
                var stale = false
                return try? URL(resolvingBookmarkData: mark, options: .withSecurityScope,
                                relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            return UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            if Edition.appStore {
                let mark = try? newValue?.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)
                UserDefaults.standard.set(mark, forKey: folderKey)
            } else {
                UserDefaults.standard.set(newValue?.path, forKey: folderKey)
            }
        }
    }

    /// Asks for the folder; it, or nil when none was chosen.
    @discardableResult
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = L("Choose the folder for receipts.")
        panel.prompt = L("Choose")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        folder = url
        return url
    }

    /// A receipt's name: its day, then the order number and the total when
    /// the photo shows them and they are not covered, like
    /// "2026-10-17 Order 1024 74,00 €". Nothing a file name cannot hold.
    nonisolated static func name(day: Date, fields: [OrderCard.Field], covering: Set<PrivateDetail>,
                                 timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd"
        func shown(_ part: OrderCard.Part) -> String? {
            covering.contains(SavedMessages.kind(of: part)) ? nil : fields.first { $0.part == part }?.value
        }
        var parts = [format.string(from: day)]
        if let order = shown(.order) { parts.append(L("Order") + " " + order) }
        if let total = shown(.total) { parts.append(total) }
        return parts.joined(separator: " ").map { "/:\\".contains($0) ? "-" : String($0) }.joined()
    }

    /// The table's headings, separated the way spreadsheets here expect.
    nonisolated static func headings(separator: Character = SendLog.listSeparator) -> String {
        [L("Date"), L("File"), L("Order"), L("Total")].map { SendLog.field($0, separator: separator) }
            .joined(separator: String(separator)) + "\r\n"
    }

    /// The table's line for a receipt: its day, its file, and the order
    /// number and total unless they are covered.
    nonisolated static func line(day: Date, file: String, fields: [OrderCard.Field], covering: Set<PrivateDetail>,
                                 separator: Character = SendLog.listSeparator,
                                 timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd"
        func shown(_ part: OrderCard.Part) -> String {
            covering.contains(SavedMessages.kind(of: part)) ? "" : fields.first { $0.part == part }?.value ?? ""
        }
        return [format.string(from: day), file, shown(.order), shown(.total)]
            .map { SendLog.field($0, separator: separator) }.joined(separator: String(separator)) + "\r\n"
    }

    /// Saves the photo, covered as it leaves the line, into the folder for
    /// the books under a name that says what it is, and notes it in the
    /// folder's table. The folder is asked for the first time.
    static func save(_ url: URL) {
        guard let folder = folder ?? chooseFolder() else { return }
        let copy = PrivateDetails.shareable(url)
        let covering = PrivateDetails.details
        Task {
            let fields = await Task.detached(priority: .userInitiated) { OrderCard.read(url) }.value
            let opened = folder.startAccessingSecurityScopedResource()
            defer { if opened { folder.stopAccessingSecurityScopedResource() } }
            let day = Date()
            let target = unique(name(day: day, fields: fields, covering: covering), ext: copy.pathExtension, in: folder)
            do {
                try FileManager.default.copyItem(at: copy, to: target)
                try note(line(day: day, file: target.lastPathComponent, fields: fields, covering: covering), in: folder)
                Notice.show(String(format: L("Saved for the books as %@."), target.lastPathComponent))
            } catch {
                log.error("Could not save for the books: \(error.localizedDescription, privacy: .public)")
                Notice.show(L("Could not save it for the books."))
            }
        }
    }

    /// The photo, covered, in a new email to whoever keeps the books, its
    /// subject saying what it is. Nothing goes until it is sent.
    static func mail(_ url: URL) {
        guard let service = NSSharingService(named: .composeEmail) else {
            Notice.show(L("No email app could be opened."))
            return
        }
        let copy = PrivateDetails.shareable(url)
        let covering = PrivateDetails.details
        Task {
            let fields = await Task.detached(priority: .userInitiated) { OrderCard.read(url) }.value
            if !address.isEmpty { service.recipients = [address] }
            service.subject = name(day: Date(), fields: fields, covering: covering)
            service.perform(withItems: [copy])
        }
    }

    /// A line added to the folder's table, which starts with its headings.
    private static func note(_ line: String, in folder: URL) throws {
        let table = folder.appendingPathComponent(tableName)
        guard let handle = try? FileHandle(forWritingTo: table) else {
            // A byte order mark first, so spreadsheets read the umlauts and Arabic right.
            try (Data("\u{FEFF}".utf8) + Data((headings() + line).utf8)).write(to: table, options: .atomic)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    private static func unique(_ name: String, ext: String, in folder: URL) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
