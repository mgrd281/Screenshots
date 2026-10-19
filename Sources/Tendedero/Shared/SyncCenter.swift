#if canImport(CloudKit)
import Combine
import Foundation

/// Syncing as the apps see it: the owner's choices, how it stands, the
/// devices and the screenshots it knows, and the ways in, the same on the
/// Mac and the iPhone. `CloudSync` does the work with iCloud; each app tells
/// this what it made and is told what arrived (`MacSync`, `PhoneSync`).
@MainActor
final class SyncCenter: ObservableObject {
    static let shared = SyncCenter()

    @Published private(set) var settings = SyncSettings.load()
    @Published private(set) var state: SyncState
    /// Everything synced, as of the last change; nil until syncing starts.
    @Published private(set) var ledger: SyncLedger?

    /// Versions from the owner's other devices, as they arrive, oldest first.
    var onArrival: (([SyncRevision]) -> Void)?

    private var cloud: CloudSync?
    /// The versions known at the last change, so what arrives stands out.
    private var known: Set<String>?

    private static let sinceKey = "syncHangSince"
    private static let registeredKey = "syncRegistered"

    /// Only in a build that names the owner's iCloud container.
    var isAvailable: Bool { CloudSetup.container != nil }

    init() {
        state = CloudSetup.container == nil ? .unavailable(.notInThisBuild) : .off
    }

    /// Snapfly's own folder for syncing: the ledger, previews, pictures
    /// fetched and copies waiting to go.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapfly", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
    }

    /// When syncing was last turned on: what the other devices made before
    /// then is listed, not brought up in front of the owner.
    var since: Date {
        UserDefaults.standard.object(forKey: Self.sinceKey) as? Date ?? .distantPast
    }

    /// When this device first joined, for the list of devices.
    static var registered: Date {
        if let date = UserDefaults.standard.object(forKey: registeredKey) as? Date { return date }
        let now = Date()
        UserDefaults.standard.set(now, forKey: registeredKey)
        return now
    }

    /// Begins, in a build that can sync; nothing leaves until it is turned on.
    func start(as device: SyncDevice) {
        guard cloud == nil, isAvailable else { return }
        cloud = CloudSync(settings: settings, folder: Self.folder, device: device) { snapshot in
            Task { @MainActor in SyncCenter.shared.take(snapshot) }
        }
        guard let cloud else { return }
        Task { await cloud.start() }
    }

    func setOn(_ on: Bool) {
        var new = settings
        new.on = on
        if on && !settings.on { UserDefaults.standard.set(Date(), forKey: Self.sinceKey) }
        apply(new)
    }

    func setOriginals(_ on: Bool) {
        var new = settings
        new.setOriginals(on)
        apply(new)
    }

    func syncNow() {
        guard let cloud else { return }
        Task { await cloud.syncNow() }
    }

    private func apply(_ new: SyncSettings) {
        settings = new
        new.save()
        guard let cloud else { return }
        Task { await cloud.update(new) }
    }

    // MARK: Going

    /// A screenshot made here, as it was taken, and its covered copy once
    /// there is one. The original stays unless the owner chose originals;
    /// the covered copy goes. Files in the sync folder came from the other
    /// devices and are not offered again.
    func offer(original: URL, covered: URL?, redaction: SyncRedaction?) {
        guard settings.on, let cloud, Self.isPicture(original),
              !original.standardizedFileURL.path.hasPrefix(Self.folder.standardizedFileURL.path) else { return }
        let created = (try? original.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let outbox = Self.folder.appendingPathComponent("Outbox", isDirectory: true)
        Task.detached(priority: .utility) {
            guard let hash = CloudSync.hash(of: original), let bytes = Self.size(of: original) else { return }
            let copy = covered.flatMap { Self.keep($0, in: outbox) }
            let name = original.lastPathComponent
            await cloud.change { ledger in
                let (id, _) = ledger.add(name: name, file: original.path, hash: hash, bytes: bytes,
                                         content: .original, created: created)
                if let copy {
                    ledger.addRevision(to: id, change: .covered, content: .protected, redaction: redaction,
                                       fileName: name, file: copy.path, hash: copy.hash, bytes: copy.bytes)
                }
            }
        }
    }

    /// A covered picture sent from here on purpose, like Send to Mac on the
    /// iPhone: a screenshot of its own, covered from the start.
    func send(covered data: Data, name: String, redaction: SyncRedaction?) async -> Bool {
        guard settings.on, let cloud else { return false }
        let outbox = Self.folder.appendingPathComponent("Outbox", isDirectory: true)
        let made: (path: String, hash: String, bytes: Int)? = await Task.detached(priority: .userInitiated) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            guard (try? data.write(to: file)) != nil else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            return Self.keep(file, in: outbox)
        }.value
        guard let made else { return false }
        await cloud.change { ledger in
            _ = ledger.add(name: name, file: made.path, hash: made.hash, bytes: made.bytes, content: .protected,
                       change: .covered, redaction: redaction, created: Date())
        }
        return true
    }

    // MARK: Coming

    /// A version's whole picture, fetched the first time it is wanted.
    func picture(_ revision: String) async throws -> URL {
        guard let cloud else { throw CocoaError(.featureUnsupported) }
        return try await cloud.picture(revision)
    }

    /// The screenshots that came from the owner's other devices, newest
    /// first, each with the version to show.
    var received: [(screenshot: SyncScreenshot, version: SyncRevision)] {
        guard let ledger else { return [] }
        return ledger.visible.compactMap { screenshot in
            guard let version = ledger.current(of: screenshot.id) ?? ledger.heads(of: screenshot.id).last,
                  version.device != ledger.deviceID else { return nil }
            return (screenshot, version)
        }
    }

    /// Where a version's small preview is on this device, once it came.
    func preview(of revision: String) -> URL? {
        ledger?.local[revision]?.preview.map { URL(fileURLWithPath: $0) }
    }

    /// The owner's other devices, the ones seen lately first.
    var otherDevices: [SyncDevice] {
        guard let ledger else { return [] }
        return ledger.devices.values.filter { $0.id != ledger.deviceID }.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func take(_ snapshot: CloudSync.Snapshot) {
        let before = known
        ledger = snapshot.ledger
        state = snapshot.state
        // Syncing may have stopped by itself, as for another iCloud account.
        settings = SyncSettings.load()
        known = Set(snapshot.ledger.revisions.keys)
        for effect in snapshot.effects {
            if case .removeFiles(let versions) = effect { Self.removeOwnFiles(versions) }
        }
        guard let before else { return }
        let arrived = snapshot.ledger.revisions.values
            .filter { !before.contains($0.id) && $0.device != snapshot.ledger.deviceID }
            .sorted { $0.stamp < $1.stamp }
        if !arrived.isEmpty { onArrival?(arrived) }
    }

    // MARK: Files

    nonisolated static func isPicture(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "gif"].contains(url.pathExtension.lowercased())
    }

    nonisolated private static func size(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// A copy kept in the sync folder under its hash, so it is still there
    /// when it goes, whatever happens to the file it came from.
    nonisolated private static func keep(_ file: URL, in folder: URL) -> (path: String, hash: String, bytes: Int)? {
        guard let hash = CloudSync.hash(of: file), let bytes = size(of: file) else { return nil }
        let ending = file.pathExtension.isEmpty ? "png" : file.pathExtension.lowercased()
        let kept = folder.appendingPathComponent("\(hash).\(ending)")
        let manager = FileManager.default
        if !manager.fileExists(atPath: kept.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? manager.copyItem(at: file, to: kept)) != nil else { return nil }
        }
        return (kept.path, hash, bytes)
    }

    /// The previews and pictures of these versions that came from iCloud.
    /// Only Snapfly's own folder is touched, never a file of the owner's.
    private static func removeOwnFiles(_ versions: [String]) {
        let manager = FileManager.default
        for version in versions {
            try? manager.removeItem(at: folder.appendingPathComponent("Files", isDirectory: true)
                .appendingPathComponent(version, isDirectory: true))
            try? manager.removeItem(at: folder.appendingPathComponent("Previews", isDirectory: true)
                .appendingPathComponent("\(version).jpg"))
        }
    }
}
#endif
