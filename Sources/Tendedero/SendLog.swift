import AppKit
import UniformTypeIdentifiers

/// What was sent into a chat: when, which photo, where to and what was
/// covered in it, so a send can be looked up later or handed on as a table.
/// It keeps only these facts, no pictures, for as long as the History keeps
/// photos, and it stays on the Mac.
@MainActor
enum SendLog {
    struct Sent: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        /// The photo's name, as the chat shows it.
        var name: String
        /// The chat it went into: the website in a browser, else the app.
        var to: String
        /// What was covered in it, as `CoverReport.keys`.
        var covered: [String]
        /// The message sent after the photos, if any.
        var message: String?
    }

    /// Newest first.
    static private(set) var entries: [Sent] = load() {
        didSet {
            save()
            onChange?()
        }
    }

    /// The History window listens, to show what changed.
    static var onChange: (() -> Void)?

    /// In Snapfly's own Application Support folder, inside the sandbox for
    /// the App Store edition.
    private static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snapfly", isDirectory: true)
        .appendingPathComponent("Sent.json")

    private static func load() -> [Sent] {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([Sent].self, from: data) else { return [] }
        return saved
    }

    private static func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            log.error("Could not keep the send log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Where a paste lands now: the chat website the send button sits over
    /// in a browser, else the app in front. Nil with no app to paste into.
    static var destination: String? {
        guard let app = Paste.frontApp else { return nil }
        return ChatButton.shared?.siteInFront ?? app.localizedName
    }

    /// Photos just sent into a chat, noted while the History is on.
    /// - Parameter chosen: the kinds covered in what went, more than Settings
    ///   checks in an AI chat with Cover Everything on.
    static func note(_ urls: [URL], to destination: String, message: String?,
                     covering chosen: Set<PrivateDetail> = PrivateDetails.details) {
        guard History.days != nil, !urls.isEmpty else { return }
        let now = Date()
        let sent = urls.map { url in
            Sent(date: now, name: url.lastPathComponent, to: destination,
                 covered: PrivateDetails.coveredKeys(url, covering: chosen), message: message)
        }
        entries.insert(contentsOf: sent, at: 0)
    }

    static func remove(_ sent: Sent) {
        entries.removeAll { $0.id == sent.id }
    }

    static func clear() {
        entries = []
    }

    /// What is older than the History keeps photos leaves.
    static func purge(before cutoff: Date) {
        let stay = entries.filter { $0.date >= cutoff }
        if stay.count != entries.count { entries = stay }
    }

    // MARK: As a table

    /// The sends as a table for a spreadsheet: a row of headings, then one
    /// row a photo. Fields are quoted where they need it, and one that a
    /// spreadsheet would take for a formula starts with an apostrophe.
    /// - Parameter separator: a semicolon where numbers use a decimal comma,
    ///   as spreadsheets there expect, else a comma.
    nonisolated static func table(_ entries: [Sent], separator: Character = listSeparator,
                                  timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var rows = [[L("Date"), L("Photo"), L("Sent to"), L("Covered"), L("Message")]]
        for sent in entries {
            rows.append([format.string(from: sent.date), sent.name, sent.to,
                         CoverReport.titles(of: sent.covered).joined(separator: ", "), sent.message ?? ""])
        }
        return rows.map { row in row.map { field($0, separator: separator) }.joined(separator: String(separator)) }
            .joined(separator: "\r\n") + "\r\n"
    }

    nonisolated static var listSeparator: Character {
        Locale.current.decimalSeparator == "," ? ";" : ","
    }

    nonisolated static func field(_ text: String, separator: Character) -> String {
        var text = text
        if let first = text.first, "=+-@".contains(first) { text = "'" + text }
        guard text.contains(where: { $0 == separator || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Asks where to save the table, as a CSV file a spreadsheet opens.
    static func export(_ entries: [Sent], from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = L("Sent with Snapfly") + ".csv"
        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            // A byte order mark, so spreadsheets read the umlauts and Arabic right.
            let data = Data("\u{FEFF}".utf8) + Data(table(entries).utf8)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Notice.show(L("Could not save the table."))
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }
}
