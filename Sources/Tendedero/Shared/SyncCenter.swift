#if canImport(CloudKit)
import Combine
import Foundation

/// Syncing as the apps see it: the owner's choices, how it stands, the
/// devices and the screenshots it knows, and the ways in, the same on the
/// Mac and the iPhone. `CloudSync` does the work with iCloud; each app tells
/// this what it made and is told what arrived (`MacSync`, `PhoneSync`).
///
/// Besides the owner's own iCloud, a device paired with a code syncs with
/// each Mac on another Apple account that shares with it, a space of its own
/// with its own ledger (SYNC.md, "Pairing with a code").
@MainActor
final class SyncCenter: ObservableObject {
    static let shared = SyncCenter()

    @Published private(set) var settings = SyncSettings.load()
    /// How syncing through the owner's own iCloud stands.
    @Published private(set) var state: SyncState
    /// Everything synced through the owner's own iCloud, as of the last
    /// change; nil until syncing starts.
    @Published private(set) var ledger: SyncLedger?
    /// The Macs on another Apple account this device joined with a code.
    @Published private(set) var connections: [Connection] = []

    /// A Mac on another Apple account that shares with this device.
    struct Connection: Identifiable, Equatable {
        /// That Mac's account, as CloudKit names it in Snapfly's container.
        var owner: String
        /// The Mac's name when they were paired.
        var name: String
        var ledger: SyncLedger?
        var state: SyncState

        var id: String { owner }
    }

    /// Versions from the owner's other devices, as they arrive, oldest first.
    var onArrival: (([SyncRevision]) -> Void)?

    private var cloud: CloudSync?
    private var sharedClouds: [String: CloudSync] = [:]
    /// The versions known at the last change in each space, so what arrives
    /// stands out.
    private var known: [SyncSpace: Set<String>] = [:]
    private var device: SyncDevice?

    private static let sinceKey = "syncHangSince"
    private static let registeredKey = "syncRegistered"
    private static let connectionsKey = "syncConnections"

    /// Only in a build that names the owner's iCloud container.
    var isAvailable: Bool { CloudSetup.container != nil }

    init() {
        state = CloudSetup.container == nil ? .unavailable(.notInThisBuild) : .off
    }

    /// Snapfly's own folder for syncing: the ledger, previews, pictures
    /// fetched and copies waiting to go. Spaces shared by other accounts
    /// have folders inside it.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapfly", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
    }

    /// On the iPhone, the folder is left out of its backups: what it holds
    /// (previews, covered copies, pictures fetched) is in iCloud already,
    /// and a backup would keep another copy of it.
    private static func keepOutOfBackups() {
        #if os(iOS)
        var root = folder
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        #endif
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

    /// Begins, in a build that can sync; nothing leaves until it is turned
    /// on, or until this device joins a Mac with a code.
    func start(as device: SyncDevice) {
        guard cloud == nil, isAvailable else { return }
        self.device = device
        Self.keepOutOfBackups()
        cloud = CloudSync(settings: settings, folder: Self.folder, device: device) { snapshot in
            Task { @MainActor in SyncCenter.shared.take(snapshot, in: .own) }
        }
        if let cloud { Task { await cloud.start() } }
        for saved in Self.savedConnections() { open(saved) }
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
        for cloud in clouds { Task { await cloud.syncNow() } }
    }

    private func apply(_ new: SyncSettings) {
        settings = new
        new.save()
        if let cloud { Task { await cloud.update(new) } }
        let shared = sharedSettings
        for cloud in sharedClouds.values { Task { await cloud.update(shared) } }
    }

    /// A space shared by a Mac syncs while it is connected, with the
    /// owner's choices about originals.
    private var sharedSettings: SyncSettings {
        var shared = settings
        shared.on = true
        return shared
    }

    /// Every space that is syncing now.
    private var clouds: [CloudSync] {
        (settings.on ? [cloud].compactMap { $0 } : []) + Array(sharedClouds.values)
    }

    /// Whether anything made here goes anywhere, like Send to Mac.
    var canSend: Bool { !clouds.isEmpty }

    // MARK: Going

    /// A screenshot made here, as it was taken, and its covered copy once
    /// there is one. The original stays unless the owner chose originals;
    /// the covered copy goes. Files in the sync folder came from the other
    /// devices and are not offered again.
    func offer(original: URL, covered: URL?, redaction: SyncRedaction?) {
        let targets = clouds
        guard !targets.isEmpty, Self.isPicture(original),
              !original.standardizedFileURL.path.hasPrefix(Self.folder.standardizedFileURL.path) else { return }
        let created = (try? original.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let outbox = Self.folder.appendingPathComponent("Outbox", isDirectory: true)
        Task.detached(priority: .utility) {
            guard let hash = CloudSync.hash(of: original), let bytes = Self.size(of: original) else { return }
            let copy = covered.flatMap { Self.keep($0, in: outbox) }
            let name = original.lastPathComponent
            for cloud in targets {
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
    }

    /// A covered picture sent from here on purpose, like Send to Mac on the
    /// iPhone: a screenshot of its own, covered from the start.
    func send(covered data: Data, name: String, redaction: SyncRedaction?) async -> Bool {
        let targets = clouds
        guard !targets.isEmpty else { return false }
        let outbox = Self.folder.appendingPathComponent("Outbox", isDirectory: true)
        let made: (path: String, hash: String, bytes: Int)? = await Task.detached(priority: .userInitiated) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            guard (try? data.write(to: file)) != nil else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            return Self.keep(file, in: outbox)
        }.value
        guard let made else { return false }
        let created = Date()
        for cloud in targets {
            await cloud.change { ledger in
                _ = ledger.add(name: name, file: made.path, hash: made.hash, bytes: made.bytes, content: .protected,
                               change: .covered, redaction: redaction, created: created)
            }
        }
        return true
    }

    // MARK: Coming

    /// Every ledger this device syncs, its own iCloud's first.
    private var ledgers: [SyncLedger] {
        [ledger].compactMap { $0 } + connections.compactMap(\.ledger)
    }

    /// A version's whole picture, fetched the first time it is wanted, from
    /// the space it came with.
    func picture(_ revision: String) async throws -> URL {
        if ledger?.revisions[revision] != nil, let cloud { return try await cloud.picture(revision) }
        for connection in connections where connection.ledger?.revisions[revision] != nil {
            if let cloud = sharedClouds[connection.owner] { return try await cloud.picture(revision) }
        }
        guard let cloud else { throw CocoaError(.featureUnsupported) }
        return try await cloud.picture(revision)
    }

    /// The screenshots that came from the owner's other devices, newest
    /// first, each with the version to show.
    var received: [(screenshot: SyncScreenshot, version: SyncRevision)] {
        var seen = Set<String>()
        var out: [(screenshot: SyncScreenshot, version: SyncRevision)] = []
        for ledger in ledgers {
            for screenshot in ledger.visible {
                guard let version = ledger.current(of: screenshot.id) ?? ledger.heads(of: screenshot.id).last,
                      version.device != ledger.deviceID, seen.insert(version.id).inserted else { continue }
                out.append((screenshot, version))
            }
        }
        return out.sorted { $0.version.stamp > $1.version.stamp }
    }

    /// Where a version's small preview is on this device, once it came.
    func preview(of revision: String) -> URL? {
        for ledger in ledgers {
            if let path = ledger.local[revision]?.preview { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// The other devices syncing through the owner's own iCloud, the ones
    /// seen lately first. A Mac joined with a code is a connection instead.
    var otherDevices: [SyncDevice] {
        guard let ledger else { return [] }
        return ledger.devices.values.filter { $0.id != ledger.deviceID }.sorted { $0.lastSeen > $1.lastSeen }
    }

    // MARK: Another Apple account

    /// This device's iCloud account, as CloudKit names it in Snapfly's
    /// container, once syncing has started.
    var account: String? { ledger?.account }

    /// Whether this Mac can share with a device on another Apple account:
    /// syncing is on and iCloud answered.
    var canShare: Bool {
        guard settings.on, account != nil else { return false }
        switch state {
        case .upToDate, .syncing, .waitingForNetwork: return true
        case .off, .unavailable, .attention: return false
        }
    }

    /// The devices on another Apple account that this Mac shares with.
    var pairedDevices: [SyncDevice] {
        guard let ledger, let account = ledger.account else { return [] }
        return otherDevices.filter { $0.account != nil && $0.account != account && ledger.devices[$0.id] != nil }
    }

    /// Shares this Mac's zones with the account of a device paired with a code.
    func invite(_ user: String) async throws -> [URL] {
        guard let cloud else { throw CocoaError(.featureUnsupported) }
        return try await cloud.invite(user)
    }

    /// Stops sharing with a device's account; it and the account's other
    /// devices stop syncing with this Mac.
    func disconnect(_ device: SyncDevice) async throws {
        guard let cloud, let user = device.account else { return }
        try await cloud.removeAccess(user)
    }

    /// Whether this Mac shares its zones with that account already, as
    /// after an earlier pairing.
    func shares(with user: String) async -> Bool {
        guard let cloud else { return false }
        return await cloud.shares(with: user)
    }

    /// Takes an account off this Mac's zones again, as when its pairing was
    /// cancelled while it was being let in.
    func removeAccess(_ user: String) async {
        guard let cloud else { return }
        do {
            try await cloud.removeAccess(user)
        } catch {
            log.error("An account let in by a cancelled pairing could not be taken off: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Joins a Mac on another Apple account, once its shares were accepted.
    func connect(owner: String, name: String) {
        let entry = Saved(owner: owner, name: name)
        Self.save(Self.savedConnections().filter { $0.owner != owner } + [entry])
        open(entry)
    }

    /// Leaves a Mac on another Apple account: what came from it goes from
    /// this device, and nothing more is sent to it.
    func leave(_ owner: String) async {
        if let cloud = sharedClouds[owner] { await cloud.leave() }
        close(owner)
    }

    private struct Saved: Codable {
        var owner: String
        var name: String
    }

    private static func savedConnections() -> [Saved] {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey),
              let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return [] }
        return saved
    }

    private static func save(_ saved: [Saved]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: connectionsKey)
    }

    private func open(_ saved: Saved) {
        guard let device, sharedClouds[saved.owner] == nil else { return }
        let space = SyncSpace.shared(owner: saved.owner)
        let cloud = CloudSync(settings: sharedSettings, folder: space.folder(in: Self.folder), device: device,
                              space: space) { snapshot in
            Task { @MainActor in SyncCenter.shared.take(snapshot, in: space) }
        }
        guard let cloud else { return }
        sharedClouds[saved.owner] = cloud
        if !connections.contains(where: { $0.owner == saved.owner }) {
            connections.append(Connection(owner: saved.owner, name: saved.name, ledger: nil, state: .syncing(waiting: 0)))
        }
        Task { await cloud.start() }
    }

    /// Takes a shared space off this device, with its folder.
    private func close(_ owner: String) {
        sharedClouds[owner] = nil
        connections.removeAll { $0.owner == owner }
        known[.shared(owner: owner)] = nil
        Self.save(Self.savedConnections().filter { $0.owner != owner })
        try? FileManager.default.removeItem(at: SyncSpace.shared(owner: owner).folder(in: Self.folder))
    }

    // MARK: Changes

    private func take(_ snapshot: CloudSync.Snapshot, in space: SyncSpace) {
        let folder = space.folder(in: Self.folder)
        switch space {
        case .own:
            ledger = snapshot.ledger
            state = snapshot.state
            // Syncing may have stopped by itself, as for another iCloud account.
            settings = SyncSettings.load()
        case .shared(let owner):
            guard sharedClouds[owner] != nil else { return }
            if snapshot.state == .attention(.disconnected) { return close(owner) }
            if let index = connections.firstIndex(where: { $0.owner == owner }) {
                connections[index].ledger = snapshot.ledger
                connections[index].state = snapshot.state
            }
        }
        for effect in snapshot.effects {
            if case .removeFiles(let versions) = effect { Self.removeOwnFiles(versions, in: folder) }
        }
        let before = known[space]
        known[space] = Set(snapshot.ledger.revisions.keys)
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
    private static func removeOwnFiles(_ versions: [String], in folder: URL) {
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
