import CoreGraphics
import Foundation

/// What Snapfly prepared of a photo ahead of time, with the owner's consent,
/// kept on this device only: its lines of text and where they are, and the
/// kinds of private detail they hold. Covering the photo later starts from
/// these, without reading it again, whatever is chosen then. Pure, so it is
/// checked without a picture; the iPhone keeps it (`IndexStore`).
struct IndexedPhoto: Codable, Equatable {
    /// Raised when Snapfly reads pictures differently, so every photo
    /// prepared before is read again.
    static let version = 1

    enum Status: String, Codable {
        /// Read, its lines kept.
        case ready
        /// Could not be read; tried again with the next version.
        case failed
        /// Only in iCloud, not downloaded for this.
        case inCloud
    }

    /// The photo's identifier in Photos.
    let id: String
    /// The photo as it was read: its size and when it last changed.
    var stamp: String
    var created: Date?
    var width: Int
    var height: Int
    var version = Self.version
    var status: Status
    var lines: [Line] = []
    /// The kinds found in it with every kind chosen, as raw values.
    var kinds: [String] = []
    /// Whose names were found, as raw values.
    var roles: [String] = []
    /// How sure Snapfly is of the roles, from 0 to 1: the least sure.
    var confidence: Double?
    var read: Date

    /// A line of text, its box, and each word with its place in the line
    /// and in the picture: location and length, then x, y, width and height.
    struct Line: Codable, Equatable {
        var text: String
        var box: [Double]
        var words: [[Double]]
    }

    /// The stamp of a photo: a change to it, or another version of it,
    /// gives another.
    static func stamp(width: Int, height: Int, modified: Date?) -> String {
        "\(width)x\(height)@\(Int((modified?.timeIntervalSince1970 ?? 0).rounded()))"
    }

    /// Whether this is the photo as it is now, read by this Snapfly.
    func isCurrent(stamp: String) -> Bool {
        self.stamp == stamp && version == Self.version && status != .failed
    }

    /// A photo read now, with what its lines hold.
    init(id: String, stamp: String, created: Date?, width: Int, height: Int, lines: [Finder.TextLine], read: Date) {
        self.id = id
        self.stamp = stamp
        self.created = created
        self.width = width
        self.height = height
        self.status = .ready
        self.read = read
        self.lines = lines.map { line in
            Line(text: line.string, box: Self.numbers(line.box),
                 words: line.words.map { [Double($0.range.location), Double($0.range.length)] + Self.numbers($0.box) })
        }
        let strings = lines.map(\.string)
        let found = Finder.findings(strings, boxes: lines.map(\.box), part: { lines[$0].box(for: $1) },
                                    Set(PrivateDetail.allCases))
        kinds = Set(found.hits.compactMap(\.kind?.rawValue)).sorted()
        let named = found.hits.compactMap(\.role)
        roles = Set(named.map(\.role.rawValue)).sorted()
        confidence = named.map(\.confidence).min()
    }

    /// A photo that could not be read, or is only in iCloud.
    init(id: String, stamp: String, created: Date?, width: Int, height: Int, status: Status, read: Date) {
        self.id = id
        self.stamp = stamp
        self.created = created
        self.width = width
        self.height = height
        self.status = status
        self.read = read
    }

    /// The lines as Snapfly reads them, ready to cover the photo.
    var textLines: [Finder.TextLine] {
        lines.compactMap { line in
            guard let box = Self.rect(line.box) else { return nil }
            let words = line.words.compactMap { numbers -> Finder.TextLine.Word? in
                guard numbers.count == 6, let place = Self.rect(Array(numbers[2...])) else { return nil }
                return Finder.TextLine.Word(range: NSRange(location: Int(numbers[0]), length: Int(numbers[1])), box: place)
            }
            return Finder.TextLine(string: line.text, box: box, words: words)
        }
    }

    private static func numbers(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { (Double($0) * 100_000).rounded() / 100_000 }
    }

    private static func rect(_ numbers: [Double]) -> CGRect? {
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite) else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}

/// What the index holds, without the text: enough to know what is left to
/// read, and to show it, without opening a single photo's file.
struct IndexManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var stamp: String
        var version: Int
        var status: IndexedPhoto.Status
        var created: Date?
        /// How much room its file takes.
        var bytes: Int
        /// When it was read, or found only in iCloud.
        var checked: Date?
    }

    var entries: [String: Entry] = [:]
    var lastUpdate: Date?

    mutating func note(_ photo: IndexedPhoto, bytes: Int) {
        entries[photo.id] = Entry(stamp: photo.stamp, version: photo.version, status: photo.status,
                                  created: photo.created, bytes: bytes, checked: photo.read)
        lastUpdate = photo.read
    }

    var bytes: Int { entries.values.reduce(0) { $0 + $1.bytes } }
}

/// What the owner allowed to be prepared ahead of time, and whether it waits.
struct IndexSettings: Codable, Equatable {
    enum Scope: String, Codable, CaseIterable {
        /// The screenshots only.
        case screenshots
        /// Every photo Snapfly may see: all, or those chosen under limited access.
        case allowed
        /// Only the photos the owner picked for it.
        case selected
    }

    /// Turned on by the owner, after reading what it does.
    var isOn = false
    var scope = Scope.screenshots
    /// How far back, in days.
    var days = 60
    /// Stopped by the owner until they go on.
    var paused = false
    /// The photos picked, with `selected`.
    var selected: [String] = []

    static let key = "privacyIndex"

    static func load(from defaults: UserDefaults = .standard) -> IndexSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(IndexSettings.self, from: data) else { return IndexSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// The first day of the period, from now.
    func start(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }
}

/// What preparing photos ahead of time does next, worked out from the photos
/// in its period and what the index holds. Pure, so it is checked without
/// Photos.
enum IndexPlan {
    /// A photo in the period, as Photos lists it.
    struct Candidate: Equatable {
        let id: String
        let stamp: String
        let created: Date?
    }

    /// How the index stands, with real numbers only.
    struct Progress: Equatable {
        /// Photos in the period, as allowed.
        var total = 0
        /// Read, as they are now.
        var ready = 0
        /// Only in iCloud, so not read.
        var inCloud = 0
        /// Could not be read.
        var failed = 0
        /// Still to read.
        var remaining = 0

        /// From 0 to 1, of what can be read here.
        var fraction: Double {
            let readable = total - inCloud
            return readable > 0 ? Double(ready + failed) / Double(readable) : 1
        }
    }

    /// The photos still to read, newest first: not read yet, changed since,
    /// or read by an older Snapfly. After them, once a day, those only in
    /// iCloud before, which may be on the device now.
    static func pending(_ candidates: [Candidate], in manifest: IndexManifest, now: Date) -> [Candidate] {
        func newest(_ a: Candidate, _ b: Candidate) -> Bool { (a.created ?? .distantPast) > (b.created ?? .distantPast) }
        var first: [Candidate] = [], again: [Candidate] = []
        for candidate in candidates {
            guard let entry = manifest.entries[candidate.id], entry.stamp == candidate.stamp,
                  entry.version == IndexedPhoto.version else {
                first.append(candidate)
                continue
            }
            if entry.status == .inCloud, (entry.checked ?? .distantPast) < now.addingTimeInterval(-86_400) {
                again.append(candidate)
            }
        }
        return first.sorted(by: newest) + again.sorted(by: newest)
    }

    /// What the index holds that is no longer wanted: photos gone from
    /// Photos, from the period, or from what is allowed.
    static func stale(in manifest: IndexManifest, keeping candidates: [Candidate]) -> Set<String> {
        Set(manifest.entries.keys).subtracting(candidates.map(\.id))
    }

    static func progress(_ candidates: [Candidate], in manifest: IndexManifest) -> Progress {
        var progress = Progress(total: candidates.count)
        for candidate in candidates {
            guard let entry = manifest.entries[candidate.id], entry.stamp == candidate.stamp,
                  entry.version == IndexedPhoto.version else {
                progress.remaining += 1
                continue
            }
            switch entry.status {
            case .ready: progress.ready += 1
            case .inCloud: progress.inCloud += 1
            case .failed: progress.failed += 1
            }
        }
        return progress
    }

    /// Why preparing waits, if it does: what the device says matters more.
    enum Pause: Equatable {
        case owner
        case lowPower
        case hot
        case memory
        case busy
    }

    /// Whether to go on, given how the device is: never in Low Power Mode,
    /// when it is hot, short of memory, or while a photo is being covered.
    static func pause(settings: IndexSettings, lowPower: Bool, hot: Bool, lowMemory: Bool, busy: Bool) -> Pause? {
        if settings.paused { return .owner }
        if lowPower { return .lowPower }
        if hot { return .hot }
        if lowMemory { return .memory }
        if busy { return .busy }
        return nil
    }
}
