import AppKit
import AVFoundation
import CryptoKit

/// When a recording was made, in a form that holds up outside the Mac: a
/// time stamp from an independent authority (`TrustedTime`), qualified
/// under the EU's eIDAS regulation, on the recording's SHA-256 fingerprint.
/// The time is the authority's, never the Mac's clock, and only the
/// fingerprint goes out, never the recording.
///
/// It is off until turned on in Settings; then each new recording gets its
/// proof as it hangs, kept with the file wherever it goes on this Mac. Save
/// Proof of Time… in a recording's or a screenshot's menu puts the file, the
/// authority's signed answer and a page that says what it proves and how to
/// check it into one folder, ready to hand to a lawyer. A file with no proof,
/// or one changed since, gets one first.
enum TimeProof {
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "timeProof") }
        set { UserDefaults.standard.set(newValue, forKey: "timeProof") }
    }

    /// One file's proof, kept with the file.
    struct Record: Codable, Equatable, Sendable {
        /// SHA-256 of the file as it was proved.
        var fingerprint: String
        /// By the authority's clock, and signed by it.
        var signed: Date
        var accuracy: Double?
        var authority: String
        var qualified: Bool
        var serial: String
        /// The authority's whole answer, as it came: the proof itself.
        var response: Data
        /// When the recording began, by the atomic clock when `atomic`, by
        /// the Mac's clock otherwise. Snapfly's own reading, not signed.
        var began: Date?
        var atomic: Bool
        var duration: Double?
    }

    // MARK: New recordings

    /// When recordings Snapfly made began, by the Mac's clock, until their
    /// proof is made.
    @MainActor private static var beginnings: [String: Date] = [:]
    /// The recordings proved since Snapfly started, so a change Snapfly
    /// makes to one, as drawing its pointer in, gets a new proof.
    @MainActor private static var proved: Set<String> = []

    /// A recording Snapfly made began at this moment by the Mac's clock.
    @MainActor
    static func began(_ url: URL, at moment: Date) {
        beginnings[url.path] = moment
    }

    /// A new recording, as it hangs: it gets its proof now, while the
    /// moment is fresh. One hung again from the history keeps what it has.
    @MainActor
    static func arrive(_ url: URL) {
        let began = beginnings.removeValue(forKey: url.path)
        guard isOn, isRecording(url), let made = modified(url), Date().timeIntervalSince(made) < 120,
              record(of: url) == nil else { return }
        proved.insert(url.path)
        prove(url, began: began) { record in
            if record != nil {
                Notice.show(L("The recording has its proof of time. To hand it on, choose Save Proof of Time… in its menu."),
                            done: true, lasting: 6)
            } else {
                Notice.show(L("Could not get a proof of time for the recording. Choose Save Proof of Time… in its menu to try again."),
                            lasting: 8)
            }
        }
    }

    /// A recording Snapfly itself changed, as by drawing its pointer in: a
    /// proof made of it before is made again, of the file as it is now, and
    /// keeps when it began.
    @MainActor
    static func changed(_ url: URL) {
        guard isOn, proved.contains(url.path) else { return }
        prove(url, began: record(of: url)?.began, again: true) { _ in }
    }

    // MARK: Making a proof

    /// Who waits for a file's proof while it is being made.
    @MainActor private static var waiting: [String: [@MainActor (Record?) -> Void]] = [:]
    /// Files changed while their proof was being made, so it is made again.
    @MainActor private static var stale: Set<String> = []

    /// Asks for a proof of the file as it is now and keeps it with the
    /// file. Calls back on the main thread, with nil when no authority
    /// answered or the file could not be read.
    @MainActor
    static func prove(_ url: URL, began: Date? = nil, again: Bool = false,
                      then done: @escaping @MainActor (Record?) -> Void) {
        let path = url.path
        if waiting[path] != nil {
            waiting[path]?.append(done)
            if again { stale.insert(path) }
            return
        }
        waiting[path] = [done]
        AtomicTime.offset { offset in
            Task.detached(priority: .utility) {
                let made = await make(url, began: began, offset: offset)
                await MainActor.run { finished(url, began: began, made) }
            }
        }
    }

    @MainActor
    private static func finished(_ url: URL, began: Date?, _ made: Record?) {
        let path = url.path
        let callbacks = waiting.removeValue(forKey: path) ?? []
        if stale.remove(path) != nil {
            // Made of the file as it was before the change: once more.
            prove(url, began: began) { record in callbacks.forEach { $0(record) } }
            return
        }
        if let made { write(made, to: url) }
        callbacks.forEach { $0(made) }
    }

    nonisolated private static func make(_ url: URL, began: Date?, offset: TimeInterval?) async -> Record? {
        guard let digest = sha256(of: url) else { return nil }
        guard let (stamp, authority) = await TrustedTime.stamp(sha256: digest) else {
            log.error("No time stamping authority answered")
            return nil
        }
        let duration = isRecording(url) ? await length(of: url) : nil
        return Record(fingerprint: hex(digest), signed: stamp.time, accuracy: stamp.accuracy, authority: authority.name,
                      qualified: stamp.qualified, serial: stamp.serial, response: stamp.response,
                      began: began.map { $0.addingTimeInterval(offset ?? 0) }, atomic: began != nil && offset != nil,
                      duration: duration)
    }

    /// The file's SHA-256, read a little at a time, as a recording can be
    /// larger than the memory.
    nonisolated static func sha256(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                let more: Bool = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
                    hasher.update(data: chunk)
                    return true
                }
                if !more { break }
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize())
    }

    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func length(of url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration).seconds,
              duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    nonisolated private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Kept with the file

    private static let recordName = "com.snapfly.time-proof"

    static func record(of url: URL) -> Record? {
        url.withUnsafeFileSystemRepresentation { path -> Record? in
            guard let path else { return nil }
            let size = getxattr(path, recordName, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, recordName, $0.baseAddress, size, 0, 0) }
            guard read == size else { return nil }
            return try? JSONDecoder().decode(Record.self, from: data)
        }
    }

    private static func write(_ record: Record, to url: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes { setxattr(path, recordName, $0.baseAddress, data.count, 0, 0) }
        }
    }

    // MARK: Handing it on

    /// Save Proof of Time…: the proof kept with the file when it is still
    /// of the file as it is, else a new one; then the folder to put it in.
    @MainActor
    static func save(_ url: URL) {
        let note = Notice.show(L("Getting the proof of time…"), working: true)
        let kept = record(of: url)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = sha256(of: url).map(hex)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let kept, let now, kept.fingerprint == now {
                        Notice.end(note)
                        choosePlace(for: url, kept)
                        return
                    }
                    // Changed since, as by Trim: what it began at no longer holds.
                    prove(url) { record in
                        Notice.end(note)
                        guard let record else {
                            Notice.show(L("Could not get a proof of time. Check the internet connection and try again."),
                                        lasting: 6)
                            return
                        }
                        choosePlace(for: url, record)
                    }
                }
            }
        }
    }

    @MainActor
    private static func choosePlace(for url: URL, _ record: Record) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(format: L("%@ – proof of time"), url.deletingPathExtension().lastPathComponent)
        panel.message = L("A folder with the file, the signed time stamp and a page that explains it, for a lawyer or a court.")
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let text = page(record, file: url.lastPathComponent)
        let pageName = L("Proof of Time")
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let target = panel.url else { return }
                let note = Notice.show(L("Saving the proof of time…"), working: true)
                DispatchQueue.global(qos: .userInitiated).async {
                    let saved = write(url, record, page: text, named: pageName, into: target)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            Notice.end(note)
                            if saved {
                                Notice.savedCopy(target)
                            } else {
                                Notice.show(L("Could not save the proof of time."))
                            }
                        }
                    }
                }
            }
        }
    }

    /// The folder: the file exactly as it is, the authority's answer named
    /// after it (".tsr", as RFC 3161 tools expect), and the page.
    nonisolated private static func write(_ url: URL, _ record: Record, page: String, named pageName: String,
                                          into folder: URL) -> Bool {
        let fm = FileManager.default
        do {
            // The panel has already asked whether to replace it.
            if fm.fileExists(atPath: folder.path) { try fm.trashItem(at: folder, resultingItemURL: nil) }
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            try fm.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            try record.response.write(to: folder.appendingPathComponent(url.lastPathComponent + ".tsr"))
            try Data(page.utf8).write(to: folder.appendingPathComponent(pageName).appendingPathExtension("txt"))
            return true
        } catch {
            log.error("Could not save a proof of time: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    // MARK: The page

    /// What the proof says, what it proves and how to check it without
    /// Snapfly, in the Mac's language, with the time in UTC beside it.
    static func page(_ record: Record, file name: String, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let when = DateFormatter()
        when.locale = locale
        when.timeZone = timeZone
        when.dateStyle = .long
        when.timeStyle = .long
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"

        var lines = [L("Proof of Time"), ""]
        lines.append(String(format: L("File: %@"), name))
        lines.append(String(format: L("Fingerprint (SHA-256): %@"), record.fingerprint))
        lines.append("")
        lines.append(String(format: L("Signed time: %@"), when.string(from: record.signed) + " · " + utc.string(from: record.signed)))
        if let accuracy = record.accuracy {
            let number = NumberFormatter()
            number.locale = locale
            number.maximumFractionDigits = 3
            lines.append(String(format: L("Accuracy: ± %@ s"), number.string(from: NSNumber(value: accuracy)) ?? "\(accuracy)"))
        }
        lines.append(String(format: L("Time stamping authority: %@"), record.authority))
        lines.append(record.qualified
            ? L("A qualified electronic time stamp under the EU’s eIDAS regulation (Article 41).")
            : L("A time stamp under RFC 3161, though not a qualified one."))
        lines.append(String(format: L("Serial number: %@"), record.serial))
        if record.began != nil || record.duration != nil { lines.append("") }
        if let began = record.began {
            let format = record.atomic
                ? L("Recording began: %@, by the PTB’s atomic clock, as Snapfly read it (not signed).")
                : L("Recording began: %@, by the Mac’s clock (not signed).")
            lines.append(String(format: format, when.string(from: began)))
        }
        if let duration = record.duration {
            let length = DateComponentsFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            length.calendar = calendar
            length.unitsStyle = .full
            length.allowedUnits = [.hour, .minute, .second]
            lines.append(String(format: L("Length: %@"), length.string(from: duration.rounded()) ?? ""))
        }
        lines.append("")
        lines.append(L("What it proves: this very file, byte for byte, existed no later than the signed time. Changed in any way, even by one byte, it no longer matches. It does not prove who made it or what it shows."))
        lines.append("")
        let answer = name + ".tsr"
        lines.append(String(format: L("How to check it without Snapfly: “%@” is the authority’s signed answer (RFC 3161). Any program that reads RFC 3161 time stamps can check it against the file, OpenSSL for example:"), answer))
        lines.append("")
        lines.append("openssl ts -reply -in \"\(answer)\" -text")
        lines.append("openssl ts -verify -in \"\(answer)\" -data \"\(name)\" -CAfile \"root.pem\"")
        lines.append("")
        lines.append(L("“root.pem” stands for the authority’s root certificate, from its own website."))
        return lines.joined(separator: "\n") + "\n"
    }
}
