import Foundation

/// What this device knows of the synced screenshots: every record, where the
/// pictures are on this device, the changes still to send, and what iCloud
/// already has. A value, changed only through these functions, so every
/// rule is checked in tests; `SyncLedgerFile` keeps it in Application
/// Support, and `CloudSync` carries its changes to iCloud and back.
struct SyncLedger: Codable, Equatable, Sendable {
    /// The version of this file. Raise it with a step in `SyncLedgerFile.migrate`.
    static let version = 1

    var version = SyncLedger.version
    var clock: SyncClock
    var devices: [String: SyncDevice] = [:]
    var projects: [String: SyncProject] = [:]
    var screenshots: [String: SyncScreenshot] = [:]
    var revisions: [String: SyncRevision] = [:]
    /// This device's copies of each version. Never sent.
    var local: [String: SyncLocal] = [:]
    var journal: [SyncOperation] = []
    /// The records iCloud has, by record name.
    var onServer: Set<String> = []
    /// Records from a newer Snapfly, left alone until this one is updated.
    var tooNew: Set<String> = []
    /// iCloud's bookkeeping for each record, by record name, kept for the
    /// next save. Only `CloudSync` reads it.
    var systemFields: [String: Data] = [:]
    /// The sync engine's own state, likewise.
    var engineState: Data?
    /// The iCloud account synced with, as iCloud names it, so another one
    /// is noticed and asked about before anything goes to it.
    var account: String?

    var deviceID: String { clock.device }

    init(device: String) {
        clock = SyncClock(device: device)
    }

    /// Fields added later must be read with a default, so an older file
    /// still opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        clock = try container.decode(SyncClock.self, forKey: .clock)
        devices = try container.decodeIfPresent([String: SyncDevice].self, forKey: .devices) ?? [:]
        projects = try container.decodeIfPresent([String: SyncProject].self, forKey: .projects) ?? [:]
        screenshots = try container.decodeIfPresent([String: SyncScreenshot].self, forKey: .screenshots) ?? [:]
        revisions = try container.decodeIfPresent([String: SyncRevision].self, forKey: .revisions) ?? [:]
        local = try container.decodeIfPresent([String: SyncLocal].self, forKey: .local) ?? [:]
        journal = try container.decodeIfPresent([SyncOperation].self, forKey: .journal) ?? []
        onServer = try container.decodeIfPresent(Set<String>.self, forKey: .onServer) ?? []
        tooNew = try container.decodeIfPresent(Set<String>.self, forKey: .tooNew) ?? []
        systemFields = try container.decodeIfPresent([String: Data].self, forKey: .systemFields) ?? [:]
        engineState = try container.decodeIfPresent(Data.self, forKey: .engineState)
        account = try container.decodeIfPresent(String.self, forKey: .account)
    }

    // MARK: Reading

    /// The versions of a screenshot known here, oldest first.
    func revisions(of screenshot: String) -> [SyncRevision] {
        revisions.values.filter { $0.screenshot == screenshot }.sorted { $0.stamp < $1.stamp }
    }

    /// Removed, unless a version made after a removal from the workspace
    /// brought it back.
    func isRemoved(_ screenshot: SyncScreenshot) -> Bool {
        switch screenshot.removal.value {
        case .none: false
        case .permanent: true
        case .workspace: !revisions.values.contains { $0.screenshot == screenshot.id && $0.stamp > screenshot.removal.stamp }
        }
    }

    /// The screenshots to show, newest first.
    var visible: [SyncScreenshot] {
        screenshots.values.filter { !isRemoved($0) }.sorted { ($0.created, $0.id) > ($1.created, $1.id) }
    }

    /// The latest versions: those no other version replaced, less those set
    /// aside. More than one means two devices changed it at once.
    func heads(of screenshot: String) -> [SyncRevision] {
        let versions = revisions(of: screenshot)
        let replaced = Set(versions.compactMap(\.parent))
        let setAside = screenshots[screenshot]?.setAside ?? [:]
        return versions.filter { !replaced.contains($0.id) && setAside[$0.id] == nil }
    }

    /// The version to show, or nil while the owner has to choose.
    func current(of screenshot: String) -> SyncRevision? {
        let heads = heads(of: screenshot)
        return heads.count == 1 ? heads[0] : nil
    }

    /// Screenshots changed on two devices at once, waiting for a choice.
    var conflicts: [SyncScreenshot] {
        visible.filter { heads(of: $0.id).count > 1 }
    }

    /// A record as it goes now. A file's is its version, whose picture it carries.
    func record(for key: SyncKey) -> SyncRecord? {
        switch key.kind {
        case .device: devices[key.id].map(SyncRecord.device)
        case .project: projects[key.id].map(SyncRecord.project)
        case .screenshot: screenshots[key.id].map(SyncRecord.screenshot)
        case .revision, .file: revisions[key.id].map(SyncRecord.revision)
        }
    }

    /// The project a screenshot shows under: Unsorted when its own is gone.
    func project(of screenshot: SyncScreenshot) -> String {
        let id = screenshot.project.value
        guard let project = projects[id] else { return id }
        return project.removed.value ? SyncProject.unsortedID : id
    }

    // MARK: Changes made here

    /// A screenshot new on this device, with its first version, or the one
    /// already known by a version with this content, so the same picture
    /// brought in twice stays one screenshot.
    @discardableResult
    mutating func add(name: String, file: String, hash: String, bytes: Int, content: SyncRevision.Content,
                      change: SyncRevision.Change = .captured, redaction: SyncRedaction? = nil,
                      created: Date, project: String = SyncProject.unsortedID,
                      now: Date = Date()) -> (screenshot: String, isNew: Bool) {
        if let known = revisions.values.first(where: { $0.contentHash == hash }),
           let screenshot = screenshots[known.screenshot], !isRemoved(screenshot) {
            return (screenshot.id, false)
        }
        let stamp = clock.tick(now: now)
        let id = UUID().uuidString
        screenshots[id] = SyncScreenshot(id: id, origin: deviceID, created: created,
                                         name: SyncField(value: name, stamp: stamp),
                                         project: SyncField(value: project, stamp: stamp),
                                         removal: SyncField(value: .none, stamp: stamp))
        let revision = SyncRevision(id: UUID().uuidString, screenshot: id, parent: nil, device: deviceID,
                                    stamp: stamp, change: change, content: content, redaction: redaction,
                                    fileName: name, contentHash: hash, byteCount: bytes)
        revisions[revision.id] = revision
        local[revision.id] = SyncLocal(file: file)
        enqueue(.save, SyncKey(.screenshot, id), now: now)
        enqueueVersion(revision.id, now: now)
        return (id, true)
    }

    /// A version made here, like a covered copy. It replaces the version
    /// shown now. Nil for a screenshot that is not there; the known one
    /// when a version of it already has this content.
    @discardableResult
    mutating func addRevision(to screenshot: String, change: SyncRevision.Change, content: SyncRevision.Content,
                              redaction: SyncRedaction? = nil, fileName: String, file: String, hash: String,
                              bytes: Int, now: Date = Date()) -> String? {
        guard let shot = screenshots[screenshot], !isRemoved(shot) else { return nil }
        if let same = revisions.values.first(where: { $0.screenshot == screenshot && $0.contentHash == hash }) {
            return same.id
        }
        let heads = heads(of: screenshot)
        let revision = SyncRevision(id: UUID().uuidString, screenshot: screenshot,
                                    parent: heads.max { $0.stamp < $1.stamp }?.id, device: deviceID,
                                    stamp: clock.tick(now: now), change: change, content: content,
                                    redaction: redaction, fileName: fileName, contentHash: hash, byteCount: bytes)
        revisions[revision.id] = revision
        local[revision.id] = SyncLocal(file: file)
        enqueueVersion(revision.id, now: now)
        return revision.id
    }

    mutating func move(_ screenshot: String, to project: String, now: Date = Date()) {
        guard var shot = screenshots[screenshot], shot.project.value != project else { return }
        shot.project = SyncField(value: project, stamp: clock.tick(now: now))
        screenshots[screenshot] = shot
        enqueue(.save, SyncKey(.screenshot, screenshot), now: now)
    }

    mutating func rename(_ screenshot: String, to name: String, now: Date = Date()) {
        guard var shot = screenshots[screenshot], shot.name.value != name else { return }
        shot.name = SyncField(value: name, stamp: clock.tick(now: now))
        screenshots[screenshot] = shot
        enqueue(.save, SyncKey(.screenshot, screenshot), now: now)
    }

    /// Removes a screenshot on every device. A permanent removal takes its
    /// pictures out of iCloud at once. Returns the versions whose files on
    /// this device the caller removes.
    @discardableResult
    mutating func remove(_ screenshot: String, _ how: SyncRemoval, now: Date = Date()) -> [String] {
        guard how != .none, var shot = screenshots[screenshot] else { return [] }
        shot.removal = shot.removal.mergedRemoval(with: SyncField(value: how, stamp: clock.tick(now: now)))
        screenshots[screenshot] = shot
        enqueue(.save, SyncKey(.screenshot, screenshot), now: now)
        let versions = revisions(of: screenshot).map(\.id)
        if how == .permanent {
            for version in versions {
                enqueue(.purge, SyncKey(.file, version), now: now)
                enqueue(.purge, SyncKey(.revision, version), now: now)
            }
        }
        return versions.filter { local[$0] != nil }
    }

    /// Brings back a screenshot removed from the workspace, within its 30 days.
    mutating func restore(_ screenshot: String, now: Date = Date()) {
        guard var shot = screenshots[screenshot], shot.removal.value == .workspace else { return }
        shot.removal = SyncField(value: .none, stamp: clock.tick(now: now))
        screenshots[screenshot] = shot
        enqueue(.save, SyncKey(.screenshot, screenshot), now: now)
    }

    /// Takes this device's copy of a version away, nothing else: it stays in
    /// iCloud and on the other devices, and can be fetched again.
    mutating func removeLocalCopy(_ revision: String) {
        local[revision] = nil
    }

    /// Keeps one of the versions two devices made at once. The others stay,
    /// set aside; one changed again later asks once more.
    mutating func choose(_ revision: String, now: Date = Date()) {
        guard let chosen = revisions[revision], var shot = screenshots[chosen.screenshot] else { return }
        let others = heads(of: chosen.screenshot).filter { $0.id != revision }
        guard !others.isEmpty else { return }
        let stamp = clock.tick(now: now)
        for other in others { shot.setAside[other.id] = stamp }
        screenshots[chosen.screenshot] = shot
        enqueue(.save, SyncKey(.screenshot, shot.id), now: now)
    }

    /// A project as the Workspace has it now; sent when something changed.
    mutating func setProject(_ id: String, name: String, order: Int, syncs: Bool = true, now: Date = Date()) {
        let stamp = clock.tick(now: now)
        guard var project = projects[id] else {
            projects[id] = SyncProject(id: id, name: SyncField(value: name, stamp: stamp),
                                       order: SyncField(value: order, stamp: stamp),
                                       syncs: SyncField(value: syncs, stamp: stamp),
                                       removed: SyncField(value: false, stamp: stamp))
            enqueue(.save, SyncKey(.project, id), now: now)
            return
        }
        let before = project
        if project.name.value != name { project.name = SyncField(value: name, stamp: stamp) }
        if project.order.value != order { project.order = SyncField(value: order, stamp: stamp) }
        if project.syncs.value != syncs { project.syncs = SyncField(value: syncs, stamp: stamp) }
        if project.removed.value { project.removed = SyncField(value: false, stamp: stamp) }
        guard project != before else { return }
        projects[id] = project
        enqueue(.save, SyncKey(.project, id), now: now)
    }

    /// Takes a project out; its screenshots move to Unsorted. Unsorted stays.
    mutating func removeProject(_ id: String, now: Date = Date()) {
        guard id != SyncProject.unsortedID, var project = projects[id], !project.removed.value else { return }
        project.removed = SyncField(value: true, stamp: clock.tick(now: now))
        projects[id] = project
        enqueue(.save, SyncKey(.project, id), now: now)
        for screenshot in screenshots.values where screenshot.project.value == id {
            move(screenshot.id, to: SyncProject.unsortedID, now: now)
        }
    }

    /// This device, as the others see it: sent when it changed, and at most
    /// hourly just to say it is there.
    mutating func register(_ device: SyncDevice, now: Date = Date()) {
        guard device.id == deviceID else { return }
        var device = device
        if let previous = devices[deviceID] {
            let same = previous.name == device.name && previous.model == device.model
                && previous.appVersion == device.appVersion && previous.schema == device.schema
            if same && now.timeIntervalSince(previous.lastSeen) < 60 * 60 {
                device.lastSeen = previous.lastSeen
                devices[deviceID] = device
                return
            }
        }
        device.lastSeen = now
        devices[deviceID] = device
        enqueue(.save, SyncKey(.device, deviceID), now: now)
    }

    // MARK: Changes from iCloud

    /// What applying a record from iCloud asks of the device.
    enum Effect: Equatable, Sendable {
        /// The files of these versions go from this device.
        case removeFiles([String])
        /// Two devices changed this screenshot at once; the owner chooses.
        case conflict(String)
    }

    /// Merges a record from iCloud. The same record twice changes nothing.
    /// When this device knows something newer, the merged record waits to
    /// be sent back, so every device ends up the same.
    @discardableResult
    mutating func apply(_ record: SyncRecord, now: Date = Date()) -> [Effect] {
        let key = record.key
        onServer.insert(key.recordName)
        tooNew.remove(key.recordName)
        switch record {
        case .device(let device):
            // This device writes its own record and no other.
            guard device.id != deviceID else { return [] }
            devices[device.id] = device
            return []

        case .project(let remote):
            for stamp in [remote.name.stamp, remote.order.stamp, remote.syncs.stamp, remote.removed.stamp] {
                clock.saw(stamp)
            }
            let merged = projects[remote.id].map { $0.merged(with: remote) } ?? remote
            projects[remote.id] = merged
            if merged != remote { enqueue(.save, key, now: now) }
            return []

        case .screenshot(let remote):
            for stamp in [remote.name.stamp, remote.project.stamp, remote.removal.stamp] + remote.setAside.values {
                clock.saw(stamp)
            }
            let known = screenshots[remote.id]
            let wasShown = known.map { !isRemoved($0) } ?? false
            let hadConflict = heads(of: remote.id).count > 1
            let merged = known.map { $0.merged(with: remote) } ?? remote
            screenshots[remote.id] = merged
            if merged != remote { enqueue(.save, key, now: now) }
            var effects: [Effect] = []
            if wasShown && isRemoved(merged) {
                let here = revisions(of: remote.id).map(\.id).filter { local[$0] != nil }
                if !here.isEmpty { effects.append(.removeFiles(here)) }
            }
            if !hadConflict && !isRemoved(merged) && heads(of: remote.id).count > 1 {
                effects.append(.conflict(remote.id))
            }
            return effects

        case .revision(let remote):
            clock.saw(remote.stamp)
            // Versions never change: one known already is the same one.
            guard revisions[remote.id] == nil else { return [] }
            let hadConflict = heads(of: remote.screenshot).count > 1
            revisions[remote.id] = remote
            if !hadConflict, let shot = screenshots[remote.screenshot], !isRemoved(shot),
               heads(of: remote.screenshot).count > 1 {
                return [.conflict(remote.screenshot)]
            }
            return []
        }
    }

    /// iCloud no longer has a record: another device took it out for good.
    @discardableResult
    mutating func applyDeletion(_ key: SyncKey) -> [Effect] {
        onServer.remove(key.recordName)
        systemFields[key.recordName] = nil
        tooNew.remove(key.recordName)
        journal.removeAll { $0.key == key }
        return forget(key)
    }

    /// A record from a newer Snapfly.
    mutating func noteTooNew(_ key: SyncKey) {
        onServer.insert(key.recordName)
        tooNew.insert(key.recordName)
    }

    /// Takes a record out of this device's knowledge, and its files.
    private mutating func forget(_ key: SyncKey) -> [Effect] {
        switch key.kind {
        case .device:
            devices[key.id] = nil
        case .project:
            projects[key.id] = nil
        case .screenshot:
            screenshots[key.id] = nil
            let versions = revisions.values.filter { $0.screenshot == key.id }.map(\.id)
            let here = versions.filter { local[$0] != nil }
            for version in versions {
                revisions[version] = nil
                local[version] = nil
            }
            return here.isEmpty ? [] : [.removeFiles(here)]
        case .revision:
            revisions[key.id] = nil
            if local.removeValue(forKey: key.id) != nil { return [.removeFiles([key.id])] }
        case .file:
            // The picture left iCloud; a copy here stays this device's.
            break
        }
        return []
    }

    // MARK: Waiting to go

    /// Notes a change to send. One change per record waits: a newer one
    /// takes its place, and taking a record out for good wins over saving it.
    mutating func enqueue(_ kind: SyncOperation.Kind, _ key: SyncKey, now: Date = Date()) {
        guard let index = journal.firstIndex(where: { $0.key == key }) else {
            journal.append(SyncOperation(key: key, kind: kind, created: now))
            return
        }
        if journal[index].kind == .purge && kind == .save { return }
        if journal[index].state == .sending {
            journal[index].again = true
            journal[index].kind = kind
            return
        }
        journal[index] = SyncOperation(key: key, kind: kind, created: journal[index].created)
    }

    /// A version's record, with its small preview, and its whole picture.
    private mutating func enqueueVersion(_ revision: String, now: Date) {
        enqueue(.save, SyncKey(.revision, revision), now: now)
        enqueue(.save, SyncKey(.file, revision), now: now)
    }

    /// The changes due now, the small records first.
    func due(now: Date = Date()) -> [SyncOperation] {
        journal.filter { $0.state == .waiting && ($0.notBefore ?? .distantPast) <= now }.sorted { $0.key < $1.key }
    }

    mutating func markSending(_ key: SyncKey) {
        guard let index = journal.firstIndex(where: { $0.key == key }) else { return }
        journal[index].state = .sending
    }

    /// iCloud has it. A change made meanwhile goes once more.
    mutating func markDone(_ key: SyncKey) {
        guard let index = journal.firstIndex(where: { $0.key == key }) else { return }
        let operation = journal[index]
        if operation.again {
            journal[index] = SyncOperation(key: key, kind: operation.kind, created: operation.created)
        } else {
            journal.remove(at: index)
        }
        switch operation.kind {
        case .save:
            onServer.insert(key.recordName)
        case .purge:
            onServer.remove(key.recordName)
            systemFields[key.recordName] = nil
            if key.kind != .file && !operation.again { _ = forget(key) }
        }
    }

    /// It did not go: tried again later, unless it failed too often or
    /// cannot go until something changes; then it waits for the owner.
    mutating func markFailed(_ key: SyncKey, _ failure: SyncFailure, now: Date = Date()) {
        guard let index = journal.firstIndex(where: { $0.key == key }) else { return }
        var operation = journal[index]
        operation.state = .waiting
        operation.again = false
        switch failure {
        case .offline:
            operation.lastError = "offline"
        case .conflict:
            operation.attempts += 1
            operation.lastError = "conflict"
        case .busy(let retryAfter):
            operation.attempts += 1
            operation.lastError = "busy"
            operation.notBefore = now.addingTimeInterval(SyncRetry.delay(after: operation.attempts, retryAfter: retryAfter))
        case .iCloudFull:
            operation.state = .stuck
            operation.needsRoom = true
            operation.lastError = "iCloud full"
        case .missingFile:
            operation.state = .stuck
            operation.lastError = "file missing"
        case .other(let reason):
            operation.attempts += 1
            operation.lastError = reason
            operation.notBefore = now.addingTimeInterval(SyncRetry.delay(after: operation.attempts))
        }
        if operation.attempts >= SyncRetry.attempts { operation.state = .stuck }
        journal[index] = operation
    }

    /// Sync Now: what was stuck tries once more.
    mutating func retryStuck() {
        for index in journal.indices where journal[index].state == .stuck {
            journal[index] = SyncOperation(key: journal[index].key, kind: journal[index].kind,
                                           created: journal[index].created)
        }
    }

    /// After a launch: what was being sent when the app quit waits again.
    mutating func resume() {
        for index in journal.indices where journal[index].state == .sending {
            journal[index].state = .waiting
            journal[index].again = false
        }
    }

    /// Everything this device made that iCloud does not have yet, to send
    /// when syncing is turned on. What may go is decided as it goes.
    mutating func queueUnsent(now: Date = Date()) {
        if devices[deviceID] != nil { enqueue(.save, SyncKey(.device, deviceID), now: now) }
        for project in projects.values where !onServer.contains(SyncKey(.project, project.id).recordName) {
            enqueue(.save, SyncKey(.project, project.id), now: now)
        }
        for screenshot in screenshots.values where screenshot.origin == deviceID
            && !onServer.contains(SyncKey(.screenshot, screenshot.id).recordName) {
            enqueue(.save, SyncKey(.screenshot, screenshot.id), now: now)
        }
        for revision in revisions.values where revision.device == deviceID {
            for kind in [SyncKind.revision, .file] where !onServer.contains(SyncKey(kind, revision.id).recordName) {
                enqueue(.save, SyncKey(kind, revision.id), now: now)
            }
        }
    }

    /// How long a removed screenshot stays in iCloud, for every device to hear of it.
    static let keepRemoved: TimeInterval = 30 * 24 * 60 * 60

    /// Removed screenshots kept long enough: out of iCloud for good, and
    /// those iCloud never had, out of this device's knowledge.
    mutating func purgeOld(now: Date = Date()) {
        for screenshot in screenshots.values where screenshot.removal.value != .none && isRemoved(screenshot)
            && now.timeIntervalSince(screenshot.removal.stamp.date) > Self.keepRemoved {
            let key = SyncKey(.screenshot, screenshot.id)
            guard onServer.contains(key.recordName) else {
                journal.removeAll { $0.key == key }
                _ = forget(key)
                continue
            }
            for version in revisions(of: screenshot.id) {
                for kind in [SyncKind.file, .revision] where onServer.contains(SyncKey(kind, version.id).recordName) {
                    enqueue(.purge, SyncKey(kind, version.id), now: now)
                }
            }
            enqueue(.purge, key, now: now)
        }
    }

    /// Signed out of iCloud, or into another account: what came from it
    /// goes from this device, what was made here stays, and waits to be
    /// sent again once syncing is turned on. Returns the versions whose
    /// files the caller removes.
    mutating func forgetAccount() -> [String] {
        let theirs = revisions.values.filter { revision in
            revision.device != deviceID || screenshots[revision.screenshot]?.origin != deviceID
        }.map(\.id)
        let gone = theirs.filter { local[$0] != nil }
        for id in theirs {
            revisions[id] = nil
            local[id] = nil
        }
        screenshots = screenshots.filter { $0.value.origin == deviceID }
        devices = devices.filter { $0.key == deviceID }
        journal = []
        onServer = []
        tooNew = []
        systemFields = [:]
        engineState = nil
        return gone
    }
}

/// Where a version is on this device.
struct SyncLocal: Codable, Equatable, Sendable {
    /// The whole picture; nil until it is fetched.
    var file: String?
    /// Its small preview.
    var preview: String?
}

// MARK: Kept on the device

/// The ledger as a file in Application Support, written whole and at once,
/// so a quit midway leaves the last good one.
enum SyncLedgerFile {
    enum Outcome: Equatable, Sendable {
        /// None yet.
        case fresh
        case loaded
        /// Written by a newer Snapfly: left as it is, and syncing waits for
        /// an update.
        case newer(Int)
        /// Could not be read; set aside under this name, and started anew.
        case unreadable(String?)
    }

    private struct Head: Decodable {
        var version: Int
    }

    static func load(_ url: URL, device: String) -> (ledger: SyncLedger, outcome: Outcome) {
        guard let data = try? Data(contentsOf: url) else { return (SyncLedger(device: device), .fresh) }
        guard let head = try? SyncCoding.decoder.decode(Head.self, from: data) else {
            return (SyncLedger(device: device), .unreadable(setAside(url)))
        }
        guard head.version <= SyncLedger.version else { return (SyncLedger(device: device), .newer(head.version)) }
        guard let migrated = migrate(data, from: head.version),
              var ledger = try? SyncCoding.decoder.decode(SyncLedger.self, from: migrated) else {
            return (SyncLedger(device: device), .unreadable(setAside(url)))
        }
        ledger.version = SyncLedger.version
        ledger.resume()
        return (ledger, .loaded)
    }

    static func save(_ ledger: SyncLedger, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder.encode(ledger).write(to: url, options: .atomic)
    }

    /// Brings an older file up to this version, one step at a time. There
    /// is one version so far; a new one adds its step here, with a test.
    static func migrate(_ data: Data, from version: Int) -> Data? {
        version >= 1 ? data : nil
    }

    /// Moves an unreadable file aside, so nothing is overwritten unseen.
    private static func setAside(_ url: URL) -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        guard (try? FileManager.default.moveItem(at: url, to: aside)) != nil else { return nil }
        return aside.lastPathComponent
    }
}
