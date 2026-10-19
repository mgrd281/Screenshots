import Foundation

/// Keeping screenshots in step between the owner's Mac and iPhone, through
/// their own iCloud: the records that travel and the rules for merging them,
/// without a screen or a network, so both apps share them and tests check
/// them. `SyncLedger.swift` keeps them on the device, `SyncPolicy.swift`
/// decides what may leave it, and `CloudSync.swift` talks to iCloud. The plan
/// and its reasons are in SYNC.md.

/// The version of the records. A device that finds a newer one leaves it
/// alone and asks for an update instead of misreading it. Raise it when a
/// record gains a case or a field an older Snapfly could not do without.
enum SyncSchema {
    static let current = 1
}

// MARK: Order of changes

/// When a change was made, comparable across devices whose clocks disagree a
/// little (a hybrid logical clock): the time in milliseconds, a counter for
/// changes within one millisecond, and the device as the last tiebreak.
struct SyncStamp: Codable, Hashable, Comparable, Sendable {
    var millis: Int64
    var counter: Int
    var device: String

    static func < (a: SyncStamp, b: SyncStamp) -> Bool {
        (a.millis, a.counter, a.device) < (b.millis, b.counter, b.device)
    }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(millis) / 1000) }
}

/// Gives each change on this device a stamp later than every stamp it has
/// made or seen, so a change made after another one always wins over it,
/// even when this device's clock runs behind.
struct SyncClock: Codable, Equatable, Sendable {
    var device: String
    private(set) var last: SyncStamp?

    init(device: String) {
        self.device = device
    }

    mutating func tick(now: Date = Date()) -> SyncStamp {
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        let stamp = if let last, last.millis >= wall {
            SyncStamp(millis: last.millis, counter: last.counter + 1, device: device)
        } else {
            SyncStamp(millis: wall, counter: 0, device: device)
        }
        last = stamp
        return stamp
    }

    /// A stamp from another device, so the next change here comes after it.
    mutating func saw(_ stamp: SyncStamp) {
        guard last.map({ $0 < stamp }) ?? true else { return }
        last = SyncStamp(millis: stamp.millis, counter: stamp.counter, device: device)
    }
}

/// A value and when it was last changed. Of two, the later one stays, on
/// every device and in whatever order they arrive. Only for small facts
/// like a name or a project; pictures never merge this way.
struct SyncField<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var value: Value
    var stamp: SyncStamp

    func merged(with other: SyncField) -> SyncField {
        other.stamp > stamp ? other : self
    }
}

// MARK: Records

enum SyncPlatform: String, Codable, Sendable {
    case mac, iPhone, iPad
}

/// One Mac or iPhone of the owner's that syncs. Only that device writes its
/// record. It says who is there, not who may come in: being in this list
/// grants nothing, the iCloud account does.
struct SyncDevice: Codable, Equatable, Identifiable, Sendable {
    /// Made once on the device, kept with its settings.
    var id: String
    var name: String
    var platform: SyncPlatform
    /// The hardware, like "Mac15,3", for its symbol.
    var model: String
    var registered: Date
    /// When it last told iCloud it was there.
    var lastSeen: Date
    /// When it last sent and fetched everything it had.
    var lastSync: Date?
    var appVersion: String
    /// The newest records it understands.
    var schema: Int

    /// Seen within this long counts as there now.
    static let presentFor: TimeInterval = 15 * 60

    func isPresent(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSeen) < Self.presentFor
    }
}

/// A Workspace category, shared: its id is the category's, so the standard
/// ones ("orders", "unsorted") are the same project on every device.
struct SyncProject: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: SyncField<String>
    var order: SyncField<Int>
    /// Off: its screenshots stay on each device, on all of them.
    var syncs: SyncField<Bool>
    /// Taken out; its screenshots show under Unsorted.
    var removed: SyncField<Bool>

    static let unsortedID = WorkspaceCategory.unsortedID

    func merged(with other: SyncProject) -> SyncProject {
        var merged = self
        merged.name = name.merged(with: other.name)
        merged.order = order.merged(with: other.order)
        merged.syncs = syncs.merged(with: other.syncs)
        merged.removed = removed.merged(with: other.removed)
        return merged
    }
}

/// Whether a screenshot was removed, and how. It travels, so a device that
/// was away learns of it instead of bringing the screenshot back.
enum SyncRemoval: String, Codable, Sendable {
    case none
    /// Taken out of the synced screenshots on every device, kept in iCloud
    /// for 30 days in case it is wanted back. A version made later, on a
    /// device that had not heard yet, brings it back.
    case workspace
    /// Gone everywhere at once, and nothing brings it back.
    case permanent
}

extension SyncField where Value == SyncRemoval {
    /// Permanent stays permanent; otherwise the later change.
    func mergedRemoval(with other: SyncField) -> SyncField {
        if (value == .permanent) != (other.value == .permanent) { return value == .permanent ? self : other }
        return merged(with: other)
    }
}

/// A screenshot, whatever versions of it there are.
struct SyncScreenshot: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The device it was taken on or brought in from.
    var origin: String
    var created: Date
    var name: SyncField<String>
    var project: SyncField<String>
    /// Versions the owner chose against when two devices changed it at
    /// once. They stay, set aside, until the screenshot is removed.
    var setAside: [String: SyncStamp] = [:]
    var removal: SyncField<SyncRemoval>

    func merged(with other: SyncScreenshot) -> SyncScreenshot {
        var merged = self
        merged.name = name.merged(with: other.name)
        merged.project = project.merged(with: other.project)
        merged.setAside = setAside.merging(other.setAside) { min($0, $1) }
        merged.removal = removal.mergedRemoval(with: other.removal)
        return merged
    }
}

/// One version of a screenshot. Versions never change once made; a change
/// is a new version whose parent is the one it was made from, so two
/// devices changing the same screenshot make two versions, and both stay.
struct SyncRevision: Codable, Equatable, Identifiable, Sendable {
    enum Change: String, Codable, Sendable {
        /// The screenshot as it was taken or brought in.
        case captured
        /// Private details covered.
        case covered
        /// Drawn on, cropped or otherwise changed.
        case edited
    }

    /// What the picture holds, which decides whether it may leave the device.
    enum Content: String, Codable, Sendable {
        /// Everything that was on the screen.
        case original
        /// With its private details covered, burnt into the pixels.
        case protected
    }

    var id: String
    var screenshot: String
    /// The version this one replaces; nil for the first. Two versions with
    /// the same parent were made at once, on two devices.
    var parent: String?
    var device: String
    var stamp: SyncStamp
    var change: Change
    var content: Content
    /// What was covered, never the words that were.
    var redaction: SyncRedaction?
    /// The name it is saved and shared under.
    var fileName: String
    /// SHA-256 of the file, to know it again and to check what arrived.
    var contentHash: String
    var byteCount: Int
}

/// What a covered version covered: the kinds (`CoverReport` keys), how many
/// places and in which look.
struct SyncRedaction: Codable, Equatable, Sendable {
    var kinds: [String]
    var areas: Int
    var look: String?
}

// MARK: Travelling

/// The kinds of record, named as iCloud keeps them. A file is a version's
/// whole picture, kept apart from the version so it is fetched only when
/// opened.
enum SyncKind: String, Codable, CaseIterable, Sendable {
    case device = "Device"
    case project = "Project"
    case screenshot = "Screenshot"
    case revision = "Revision"
    case file = "File"

    /// Sent first: the small records, then the pictures.
    var order: Int {
        switch self {
        case .device: 0
        case .project: 1
        case .screenshot: 2
        case .revision: 3
        case .file: 4
        }
    }
}

/// Which record, by kind and id: "Screenshot.6F1C…" in iCloud.
struct SyncKey: Codable, Hashable, Comparable, Sendable {
    var kind: SyncKind
    var id: String

    var recordName: String { "\(kind.rawValue).\(id)" }

    init(_ kind: SyncKind, _ id: String) {
        self.kind = kind
        self.id = id
    }

    init?(recordName: String) {
        guard let dot = recordName.firstIndex(of: "."),
              let kind = SyncKind(rawValue: String(recordName[..<dot])) else { return nil }
        let id = String(recordName[recordName.index(after: dot)...])
        guard !id.isEmpty else { return nil }
        self.init(kind, id)
    }

    static func < (a: SyncKey, b: SyncKey) -> Bool {
        (a.kind.order, a.id) < (b.kind.order, b.id)
    }
}

/// A record as it travels, whatever carries it.
enum SyncRecord: Equatable, Sendable {
    case device(SyncDevice)
    case project(SyncProject)
    case screenshot(SyncScreenshot)
    case revision(SyncRevision)

    var key: SyncKey {
        switch self {
        case .device(let device): SyncKey(.device, device.id)
        case .project(let project): SyncKey(.project, project.id)
        case .screenshot(let screenshot): SyncKey(.screenshot, screenshot.id)
        case .revision(let revision): SyncKey(.revision, revision.id)
        }
    }

    /// What reading a record gave.
    enum Decoded: Equatable, Sendable {
        case record(SyncRecord)
        /// From a newer Snapfly; left alone until this one is updated.
        case tooNew(schema: Int)
        case unreadable
    }

    private struct Envelope: Codable {
        var schema: Int
        var body: Data
    }

    /// The record's contents, which iCloud keeps encrypted with the owner's
    /// keys; the version travels with them.
    func payload() throws -> Data {
        let body = switch self {
        case .device(let device): try SyncCoding.encoder.encode(device)
        case .project(let project): try SyncCoding.encoder.encode(project)
        case .screenshot(let screenshot): try SyncCoding.encoder.encode(screenshot)
        case .revision(let revision): try SyncCoding.encoder.encode(revision)
        }
        return try SyncCoding.encoder.encode(Envelope(schema: SyncSchema.current, body: body))
    }

    static func decode(_ kind: SyncKind, payload: Data) -> Decoded {
        guard let envelope = try? SyncCoding.decoder.decode(Envelope.self, from: payload) else { return .unreadable }
        guard envelope.schema <= SyncSchema.current else { return .tooNew(schema: envelope.schema) }
        let body = envelope.body
        let decoder = SyncCoding.decoder
        let record: SyncRecord? = switch kind {
        case .device: (try? decoder.decode(SyncDevice.self, from: body)).map(SyncRecord.device)
        case .project: (try? decoder.decode(SyncProject.self, from: body)).map(SyncRecord.project)
        case .screenshot: (try? decoder.decode(SyncScreenshot.self, from: body)).map(SyncRecord.screenshot)
        case .revision: (try? decoder.decode(SyncRevision.self, from: body)).map(SyncRecord.revision)
        case .file: nil
        }
        return record.map(Decoded.record) ?? .unreadable
    }
}

/// One way of writing records, on every device and in every version.
enum SyncCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

// MARK: Waiting to go

/// A change waiting to reach iCloud, kept on the device so nothing is lost
/// offline or when the app quits midway.
struct SyncOperation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Send the record as it is now.
        case save
        /// Take the record out of iCloud for good.
        case purge
    }

    enum State: String, Codable, Sendable {
        case waiting
        /// Handed to iCloud; back to waiting if the app quits before it answers.
        case sending
        /// Failed too often; waits for the owner to try again.
        case stuck
    }

    var id = UUID()
    var key: SyncKey
    var kind: Kind
    var created: Date
    var attempts = 0
    var lastError: String?
    /// Not before then, after a failure.
    var notBefore: Date?
    var state = State.waiting
    /// iCloud is full: no use trying until there is room.
    var needsRoom = false
    /// Changed again while it was being sent, so it goes once more.
    var again = false
}

/// Why a change did not reach iCloud.
enum SyncFailure: Equatable, Sendable {
    /// No connection, or iCloud not reachable just now; iCloud tries again
    /// by itself once it is, and this does not count as an attempt.
    case offline
    /// iCloud asked to wait, for this long if it said.
    case busy(retryAfter: TimeInterval?)
    /// Someone else changed it first; merged and sent again.
    case conflict
    /// The owner's iCloud storage is full.
    case iCloudFull
    /// The file to send is gone from the device.
    case missingFile
    case other(String)
}

/// How long to wait before trying again, and when to stop.
enum SyncRetry {
    static let first: TimeInterval = 30
    static let longest: TimeInterval = 60 * 60
    /// Then the change waits for the owner instead of trying forever.
    static let attempts = 8

    /// After the given number of failed attempts: 30 s, 1 min, 2 min, … up
    /// to an hour, or as long as iCloud asked.
    static func delay(after attempts: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(retryAfter, longest) }
        let doubled = first * pow(2, Double(max(0, attempts - 1)))
        return min(doubled, longest)
    }
}
