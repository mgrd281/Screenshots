import AppKit
import CoreMedia
import CryptoKit

/// A recording's Studio work: its zooms, the marks drawn over it and when
/// each shows, and whether clicks show. Kept with the recording while it is
/// on the line or in the history, so Studio opens again as it was left. The
/// recording itself is never changed; Save Video makes a new one.
struct StudioProject: Codable, Equatable, Sendable {
    /// A mark drawn over the recording, and from when to when it shows.
    struct Mark: Codable, Equatable, Identifiable, Sendable {
        var mark: Drawing.Mark
        var start: Double
        var end: Double

        var id: UUID { mark.id }
    }

    var zooms: [StudioZoom] = []
    var marks: [Mark] = []
    /// Zooms made from the clicks and typing. Turned off, those go and the
    /// ones made by hand stay.
    var autoZoom = true
    /// How close the automatic zooms come; nil for what suits the area.
    var autoScale: Double?
    /// A ring where each click landed.
    var showsClicks = true

    /// The steps' numbers, in the order they show.
    var numbers: [UUID: Int] {
        StudioTimeline.numbers(of: marks.filter { $0.mark.kind == .step }.map { (id: $0.id, start: $0.start) })
    }

    /// A first project for a recording: zoomed in on what was done.
    static func first(events: StudioEvents?, duration: Double) -> StudioProject {
        var project = StudioProject()
        if let events { project.zooms = StudioAutoZoom.zooms(for: events, duration: duration) }
        return project
    }

    /// The same after the recording's first `offset` seconds were trimmed
    /// off and `duration` kept: everything moves to the new start, and what
    /// fell outside goes.
    func trimmed(from offset: Double, keeping duration: Double) -> StudioProject {
        var trimmed = self
        trimmed.zooms = zooms.compactMap { zoom in
            var zoom = zoom
            zoom.start = max(0, zoom.start - offset)
            zoom.end = min(duration, zoom.end - offset)
            return zoom.duration >= StudioZoom.shortest ? zoom : nil
        }
        trimmed.marks = marks.compactMap { mark in
            var mark = mark
            mark.start = max(0, mark.start - offset)
            mark.end = min(duration, mark.end - offset)
            return mark.end - mark.start >= StudioFade.shortest ? mark : nil
        }
        return trimmed
    }
}

/// Where Studio keeps what it knows about each recording, under its path,
/// in Snapfly's own folder (inside the sandbox for the App Store edition):
/// what was done while recording and the work done on it since. Nothing of
/// it leaves the Mac.
enum StudioStore {
    static let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snapfly", isDirectory: true)
        .appendingPathComponent("Studio", isDirectory: true)

    /// A name for the recording's files that says nothing about it.
    static func key(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func file(_ url: URL, _ kind: String) -> URL {
        folder.appendingPathComponent("\(key(url)).\(kind).json")
    }

    static func events(for url: URL) -> StudioEvents? {
        read(StudioEvents.self, from: file(url, "events"))
    }

    static func setEvents(_ events: StudioEvents, for url: URL) {
        write(events, to: file(url, "events"))
    }

    static func project(for url: URL) -> StudioProject? {
        read(StudioProject.self, from: file(url, "project"))
    }

    static func setProject(_ project: StudioProject, for url: URL) {
        write(project, to: file(url, "project"))
    }

    /// A recording moved, as Workspace moves files: what Studio knows goes
    /// with it.
    static func move(from old: URL, to new: URL) {
        let fm = FileManager.default
        for kind in ["events", "project"] {
            let from = file(old, kind), to = file(new, kind)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: to)
            try? fm.moveItem(at: from, to: to)
        }
    }

    /// A recording trimmed in place: its events and project move to the
    /// new start.
    static func trimmed(_ url: URL, from offset: Double, keeping duration: Double) {
        if let events = events(for: url) {
            setEvents(events.trimmed(from: offset, keeping: duration), for: url)
        }
        if let project = project(for: url) {
            setProject(project.trimmed(from: offset, keeping: duration), for: url)
        }
    }

    /// Forgets the recordings that have left the line and the history.
    static func keep(only paths: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let kept = Set(paths.map { key(URL(fileURLWithPath: $0)) })
        for file in files {
            let name = file.lastPathComponent
            guard let dot = name.firstIndex(of: "."), !kept.contains(String(name[..<dot])) else { continue }
            try? fm.removeItem(at: file)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to file: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            log.error("Could not keep Studio's work: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Studio's one setting, in Settings › General under Screen recordings.
enum Studio {
    private static let afterRecordingKey = "studioAfterRecording"

    /// Whether Studio opens on each recording once it hangs. On until
    /// turned off.
    static var opensAfterRecording: Bool {
        get { UserDefaults.standard.object(forKey: afterRecordingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: afterRecordingKey) }
    }
}

/// Notes what is done while the screen is recorded, for Studio: where the
/// pointer goes, about thirty times a second while it moves, where it
/// clicks, and when a key goes down. Which key is never noted. Keys are
/// only seen where Snapfly may use Accessibility; without it, typing is
/// simply not zoomed in on.
@MainActor
final class StudioCapture {
    /// The recorded area, in the screen's points.
    private let frame: CGRect
    private var pointer: [(t: Double, point: CGPoint)] = []
    private var clicks: [(t: Double, point: CGPoint, right: Bool)] = []
    private var keys: [Double] = []
    private var timer: Timer?
    private var monitors: [Any] = []
    private var last: CGPoint?

    init(frame: CGRect) {
        self.frame = frame
    }

    /// The host clock the screen's frames are timed by.
    nonisolated static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Also while a menu is open, which is often what is shown.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let right = event.type == .rightMouseDown
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.clicked(at: point, right: right) }
        }) {
            monitors.append(clicks)
        }
        if let typing = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard !event.isARepeat else { return }
            let now = StudioCapture.now
            MainActor.assumeIsolated { self?.typed(at: now) }
        }) {
            monitors.append(typing)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func sample() {
        let point = NSEvent.mouseLocation
        guard point != last else { return }
        last = point
        pointer.append((Self.now, point))
    }

    private func clicked(at point: CGPoint, right: Bool) {
        clicks.append((Self.now, point, right))
    }

    private func typed(at time: Double) {
        keys.append(time)
    }

    /// What was noted, timed from the recording's first picture and placed
    /// on the recorded area.
    func events(since start: Double) -> StudioEvents {
        let w = max(frame.width, 1), h = max(frame.height, 1)
        let x = { (p: CGPoint) in Double((p.x - self.frame.minX) / w) }
        let y = { (p: CGPoint) in Double((p.y - self.frame.minY) / h) }
        var events = StudioEvents(width: Double(frame.width), height: Double(frame.height))
        // Where the pointer was as the recording began, then where it went.
        let before = pointer.last { $0.t <= start }
        if let before { events.pointer.append(StudioEvents.Point(t: 0, x: x(before.point), y: y(before.point))) }
        events.pointer += pointer.filter { $0.t > start }.map {
            StudioEvents.Point(t: $0.t - start, x: x($0.point), y: y($0.point))
        }
        events.clicks = clicks.filter { $0.t >= start }.map {
            StudioEvents.Click(t: $0.t - start, x: x($0.point), y: y($0.point), right: $0.right)
        }
        events.keys = keys.filter { $0 >= start }.map { $0 - start }
        return events
    }
}
