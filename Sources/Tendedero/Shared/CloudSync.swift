#if canImport(CloudKit)
import CloudKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The owner's iCloud container, which builds write into Info.plist once
/// their Apple account has it, together with the entitlement (SYNC.md).
/// Without it syncing stays out of the app: opening a container the app is
/// not entitled to would stop it.
enum CloudSetup {
    static var container: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "SnapflyCloudContainer") as? String,
              id.hasPrefix("iCloud.") else { return nil }
        return id
    }
}

/// Syncing through the owner's own iCloud, in its private database: Apple's
/// sync engine carries the ledger's changes there and back, sending when
/// there is a connection and fetching when iCloud says something changed.
/// Each record's contents are encrypted with the owner's iCloud keys. A
/// version's small preview rides on its record; its whole picture is a
/// record of its own in a second zone, fetched only when it is opened.
///
/// A device paired with a code from another Apple account syncs the same
/// way with the zones the Mac shares with it, through its shared database:
/// one of these for each such Mac, with a ledger of its own.
actor CloudSync {
    static let zoneName = "Snapfly"
    static let filesZoneName = "SnapflyFiles"

    /// What the app shows after each change: the ledger, how syncing
    /// stands, and what applying iCloud's changes asks of the device.
    struct Snapshot: Sendable {
        var ledger: SyncLedger
        var state: SyncState
        var effects: [SyncLedger.Effect]
    }

    let space: SyncSpace
    private let container: CKContainer
    private let database: CKDatabase
    private let zone: CKRecordZone.ID
    private let filesZone: CKRecordZone.ID
    private let folder: URL
    private let device: SyncDevice
    private let report: @Sendable (Snapshot) -> Void
    private var ledger: SyncLedger
    private var settings: SyncSettings
    private var engine: CKSyncEngine?
    private var account = SyncAccount.unknown
    private var problem: SyncProblem?
    private var busy = false
    private var online = true
    private var lastSync: Date?
    private var effects: [SyncLedger.Effect] = []
    /// False while the ledger file is from a newer Snapfly: it stays as it is.
    private var canSave = true
    private var retry: Task<Void, Never>?

    private var ledgerFile: URL { folder.appendingPathComponent("Ledger.json") }

    /// - Parameters:
    ///   - folder: this space's folder in Application Support.
    ///   - device: this device, as the others will see it.
    ///   - space: the owner's own iCloud, or a Mac's shared with this device.
    ///   - report: called after every change, from this actor.
    init?(settings: SyncSettings, folder: URL, device: SyncDevice, space: SyncSpace = .own,
          report: @escaping @Sendable (Snapshot) -> Void) {
        guard let identifier = CloudSetup.container else { return nil }
        container = CKContainer(identifier: identifier)
        self.space = space
        database = space == .own ? container.privateCloudDatabase : container.sharedCloudDatabase
        let owner = space.owner ?? CKCurrentUserDefaultName
        zone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner)
        filesZone = CKRecordZone.ID(zoneName: Self.filesZoneName, ownerName: owner)
        self.folder = folder
        self.device = device
        self.settings = settings
        self.report = report
        let (ledger, outcome) = SyncLedgerFile.load(folder.appendingPathComponent("Ledger.json"), device: device.id)
        self.ledger = ledger
        switch outcome {
        case .newer:
            canSave = false
            problem = .newerFile
        case .unreadable(let aside):
            log.error("The sync ledger could not be read and was set aside as \(aside ?? "nothing", privacy: .public)")
        case .fresh, .loaded:
            break
        }
    }

    // MARK: Turning it on and off

    /// Starts when syncing is on and iCloud is there: this device says it is
    /// there, and what it made that iCloud lacks waits to go.
    func start() async {
        guard settings.on, canSave else { return publish() }
        account = await accountStatus()
        guard account == .available else { return publish() }
        guard await sameAccount() else { return publish() }
        if engine == nil {
            let made = makeEngine()
            engine = made
            if space == .own {
                saveZones()
            } else {
                // A shared space's zones are the Mac's; only it makes them.
                // Just joined, what it holds comes down at once.
                Task { try? await made.fetchChanges() }
            }
        }
        var me = device
        me.account = ledger.account
        ledger.register(me)
        ledger.purgeOld()
        ledger.queueUnsent()
        hand()
        save()
        publish()
    }

    /// The owner's choices. Turning syncing on after another account was
    /// found means syncing with the account now signed in.
    func update(_ new: SyncSettings) async {
        let turnedOn = new.on && !settings.on
        settings = new
        keepSettings()
        if turnedOn && problem == .otherAccount {
            problem = nil
            ledger.account = nil
        }
        if new.on { await start() } else { publish() }
    }

    /// A change made on this device, sent when it may go.
    func change(_ body: @Sendable (inout SyncLedger) -> Void) {
        body(&ledger)
        hand()
        save()
        publish()
    }

    /// Sync Now: what was stuck tries again, then everything is sent and fetched.
    func syncNow() async {
        ledger.retryStuck()
        hand()
        publish()
        guard let engine else { return await start() }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            log.error("Sync Now did not finish: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Pictures

    /// A version's whole picture, fetched the first time it is opened, kept
    /// in the sync folder and checked against the version's hash.
    func picture(_ revision: String) async throws -> URL {
        if let path = ledger.local[revision]?.file, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let version = ledger.revisions[revision] else { throw CKError(.unknownItem) }
        let record = try await database.record(for: recordID(SyncKey(.file, revision)))
        guard let asset = (record["file"] as? CKAsset)?.fileURL else { throw CKError(.unknownItem) }
        let name = URL(fileURLWithPath: version.fileName).lastPathComponent
        let out = folder.appendingPathComponent("Files", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true).appendingPathComponent(name.isEmpty ? revision : name)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.copyItem(at: asset, to: out)
        guard Self.hash(of: out) == version.contentHash else {
            try? FileManager.default.removeItem(at: out)
            throw CKError(.assetFileModified)
        }
        ledger.local[revision, default: SyncLocal()].file = out.path
        save()
        publish()
        return out
    }

    // MARK: Another Apple account

    /// Lets the account of a device paired with a code into this Mac's
    /// zones: each is shared with that account alone, to read and write,
    /// never with anyone who has the link. Returns the links it joins with.
    func invite(_ user: String) async throws -> [URL] {
        guard space == .own, engine != nil else { throw CKError(.notAuthenticated) }
        var links: [URL] = []
        for zoneID in [zone, filesZone] {
            let share = try await zoneShare(zoneID) ?? CKShare(recordZoneID: zoneID)
            share.publicPermission = .none
            if !share.participants.contains(where: { $0.userIdentity.userRecordID?.recordName == user }) {
                let participant = try await container.shareParticipant(forUserRecordID: CKRecord.ID(recordName: user))
                participant.permission = .readWrite
                share.addParticipant(participant)
            }
            let saved = try await saveShare(share)
            guard let link = saved.url else { throw CKError(.internalError) }
            links.append(link)
        }
        return links
    }

    /// Takes a device's account off this Mac's zones, and its devices off
    /// the list. What it sent stays.
    func removeAccess(_ user: String) async throws {
        guard space == .own else { return }
        for zoneID in [zone, filesZone] {
            guard let share = try await zoneShare(zoneID) else { continue }
            let theirs = share.participants.filter {
                $0.role != .owner && $0.userIdentity.userRecordID?.recordName == user
            }
            for participant in theirs { share.removeParticipant(participant) }
            if share.participants.allSatisfy({ $0.role == .owner }) {
                // Nobody else left: the zone is not shared any more.
                _ = try await database.modifyRecords(saving: [], deleting: [share.recordID],
                                                     savePolicy: .ifServerRecordUnchanged, atomically: true)
            } else {
                _ = try await saveShare(share)
            }
        }
        ledger.forgetDevices(of: user)
        hand()
        save()
        publish()
    }

    /// Leaves the zones a Mac shared with this device; what came from them
    /// is taken off with the space.
    func leave() async {
        guard space != .own else { return }
        engine = nil
        let shares = [zone, filesZone].map { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: $0) }
        do {
            _ = try await database.modifyRecords(saving: [], deleting: shares,
                                                 savePolicy: .ifServerRecordUnchanged, atomically: false)
        } catch {
            log.error("Leaving a shared Mac did not reach iCloud: \(error.localizedDescription, privacy: .public)")
        }
        disconnected()
        publish()
    }

    private func zoneShare(_ zoneID: CKRecordZone.ID) async throws -> CKShare? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func saveShare(_ share: CKShare) async throws -> CKShare {
        let (saved, _) = try await database.modifyRecords(saving: [share], deleting: [],
                                                          savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let result = saved[share.recordID], let record = try result.get() as? CKShare else {
            throw CKError(.internalError)
        }
        return record
    }

    // MARK: Inside

    private func accountStatus() async -> SyncAccount {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .none
            case .restricted: return .restricted
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    /// Whether the account signed in is the one synced with before; the
    /// first one is remembered. Another one pauses syncing until the owner
    /// turns it on again, and what came from the old one goes.
    private func sameAccount() async -> Bool {
        // Not known just now, offline say: an account synced with before
        // goes on, as the engine reports a change of account by itself.
        guard let user = try? await container.userRecordID().recordName else { return ledger.account != nil }
        if ledger.account == nil { ledger.account = user }
        guard ledger.account != user else { return true }
        otherAccount()
        return false
    }

    private func otherAccount() {
        effects.append(.removeFiles(ledger.forgetAccount()))
        engine = nil
        if space == .own {
            settings.on = false
            keepSettings()
            problem = .otherAccount
        } else {
            // What a Mac shared, it shared with the account that was here.
            disconnected()
        }
        save()
    }

    /// The owner's choices are kept for their own iCloud only; a shared
    /// space follows them and syncs while it is connected.
    private func keepSettings() {
        if space == .own { settings.save() }
    }

    private func saveZones() {
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone)),
                                                   .saveZone(CKRecordZone(zoneID: filesZone))])
    }

    /// The Mac stopped sharing, or this device left: nothing more goes, and
    /// the space is taken off this device.
    private func disconnected() {
        ledger.journal = []
        engine = nil
        problem = .disconnected
    }

    private func makeEngine() -> CKSyncEngine {
        let state = ledger.engineState.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let configuration = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self)
        return CKSyncEngine(configuration)
    }

    private func recordID(_ key: SyncKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.recordName, zoneID: key.kind == .file ? filesZone : zone)
    }

    /// Hands the engine the changes that may go now; the others wait in the
    /// ledger, and those waiting out a failure are handed when it is time.
    private func hand() {
        guard let engine, settings.on else { return }
        let ready = ledger.due().filter { SyncPolicy.allows($0, in: ledger, settings: settings) }
        if !ready.isEmpty {
            engine.state.add(pendingRecordZoneChanges: ready.map { operation -> CKSyncEngine.PendingRecordZoneChange in
                let id = recordID(operation.key)
                return operation.kind == .save ? .saveRecord(id) : .deleteRecord(id)
            })
        }
        retry?.cancel()
        let now = Date()
        guard let next = ledger.journal.filter({ $0.state == .waiting }).compactMap(\.notBefore)
            .filter({ $0 > now }).min() else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, next.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.handAgain()
        }
    }

    private func handAgain() {
        hand()
        publish()
    }

    /// The record to send, built now so it is current and still allowed;
    /// nil takes it off the engine's list, and it waits in the ledger.
    private func outgoing(_ id: CKRecord.ID) -> CKRecord? {
        guard let key = SyncKey(recordName: id.recordName),
              let operation = ledger.journal.first(where: { $0.key == key }),
              operation.kind == .save, operation.state != .stuck,
              SyncPolicy.allows(operation, in: ledger, settings: settings),
              let record = build(key, id) else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        ledger.markSending(key)
        return record
    }

    private func build(_ key: SyncKey, _ id: CKRecord.ID) -> CKRecord? {
        let record = ledger.systemFields[key.recordName].flatMap(Self.unarchive)
            ?? CKRecord(recordType: key.kind.rawValue, recordID: id)
        if key.kind == .file {
            guard let version = ledger.revisions[key.id], let path = ledger.local[key.id]?.file,
                  Self.hash(of: URL(fileURLWithPath: path)) == version.contentHash else {
                // Gone, or changed since: not the version it says it is.
                ledger.markFailed(key, .missingFile)
                return nil
            }
            record["file"] = CKAsset(fileURL: URL(fileURLWithPath: path))
            return record
        }
        guard let contents = ledger.record(for: key), let payload = try? contents.payload() else { return nil }
        record.encryptedValues["payload"] = payload as NSData
        if case .revision(let version) = contents, let small = preview(of: version) {
            record["preview"] = CKAsset(fileURL: small)
        }
        return record
    }

    /// A small JPEG made from the version itself, so a covered copy's
    /// preview shows nothing it covers, and without the picture's metadata.
    private func preview(of version: SyncRevision) -> URL? {
        if let path = ledger.local[version.id]?.preview, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let path = ledger.local[version.id]?.file,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = previewURL(version.id)
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        ledger.local[version.id, default: SyncLocal()].preview = out.path
        return out
    }

    private func previewURL(_ revision: String) -> URL {
        folder.appendingPathComponent("Previews", isDirectory: true).appendingPathComponent("\(revision).jpg")
    }

    /// A record from iCloud, merged into the ledger.
    private func received(_ record: CKRecord) {
        guard let key = SyncKey(recordName: record.recordID.recordName), key.kind != .file else { return }
        ledger.systemFields[key.recordName] = Self.archive(record)
        guard let payload = record.encryptedValues["payload"] as? NSData else { return }
        switch SyncRecord.decode(key.kind, payload: payload as Data) {
        case .record(let contents):
            effects += ledger.apply(contents)
            if case .revision(let version) = contents, ledger.local[version.id]?.preview == nil,
               let asset = (record["preview"] as? CKAsset)?.fileURL {
                let out = previewURL(version.id)
                try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: out)
                if (try? FileManager.default.copyItem(at: asset, to: out)) != nil {
                    ledger.local[version.id, default: SyncLocal()].preview = out.path
                }
            }
        case .tooNew:
            ledger.noteTooNew(key)
        case .unreadable:
            log.error("A synced \(key.kind.rawValue, privacy: .public) could not be read")
        }
    }

    private func sent(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in changes.savedRecords {
            guard let key = SyncKey(recordName: record.recordID.recordName) else { continue }
            ledger.systemFields[key.recordName] = Self.archive(record)
            ledger.markDone(key)
        }
        for id in changes.deletedRecordIDs {
            if let key = SyncKey(recordName: id.recordName) { ledger.markDone(key) }
        }
        for failure in changes.failedRecordSaves {
            guard let key = SyncKey(recordName: failure.record.recordID.recordName) else { continue }
            let error = failure.error
            switch error.code {
            case .serverRecordChanged:
                // Changed elsewhere first: merged, and the merge goes again.
                if let server = error.serverRecord { received(server) }
                ledger.markFailed(key, .conflict)
            case .zoneNotFound, .userDeletedZone:
                guard space == .own else { return disconnected() }
                saveZones()
                ledger.systemFields[key.recordName] = nil
                ledger.markFailed(key, .conflict)
            case .unknownItem:
                // iCloud no longer knows it: sent again as new.
                ledger.systemFields[key.recordName] = nil
                ledger.markFailed(key, .conflict)
            case .quotaExceeded:
                ledger.markFailed(key, .iCloudFull)
            case .assetFileNotFound, .assetFileModified:
                ledger.markFailed(key, .missingFile)
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .accountTemporarilyUnavailable:
                // The engine sends it again by itself once it can.
                online = false
                ledger.markFailed(key, .offline)
            case .zoneBusy, .requestRateLimited:
                ledger.markFailed(key, .busy(retryAfter: error.retryAfterSeconds))
            default:
                ledger.markFailed(key, .other("CKError \(error.code.rawValue)"))
            }
        }
        for (id, error) in changes.failedRecordDeletes {
            guard let key = SyncKey(recordName: id.recordName) else { continue }
            switch error.code {
            case .unknownItem: ledger.markDone(key)
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .accountTemporarilyUnavailable:
                online = false
                ledger.markFailed(key, .offline)
            default: ledger.markFailed(key, .other("CKError \(error.code.rawValue)"))
            }
        }
        hand()
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn(let user):
            account = .available
            if ledger.account == nil { ledger.account = user.recordName }
            if ledger.account == user.recordName {
                ledger.queueUnsent()
                hand()
            } else {
                otherAccount()
            }
        case .signOut:
            account = .none
            effects.append(.removeFiles(ledger.forgetAccount()))
            engine = nil
        case .switchAccounts:
            otherAccount()
        @unknown default:
            break
        }
    }

    private func zoneDeleted(_ deletion: CKDatabase.DatabaseChange.Deletion) {
        guard deletion.zoneID == zone else { return }
        ledger.onServer = []
        ledger.systemFields = [:]
        guard space == .own else { return disconnected() }
        switch deletion.reason {
        case .encryptedDataReset:
            // iCloud's keys were reset: everything made here goes again.
            saveZones()
            ledger.queueUnsent()
            hand()
        default:
            // The owner removed Snapfly's data in iCloud's settings: syncing
            // stops here too, and nothing is sent back unasked.
            ledger.journal = []
            settings.on = false
            keepSettings()
            problem = .removedFromICloud
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            try SyncLedgerFile.save(ledger, to: ledgerFile)
        } catch {
            log.error("Could not keep the sync ledger: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publish() {
        let state = SyncState.of(ledger, settings: settings, account: account, online: online, busy: busy,
                                 lastSync: lastSync, problem: problem)
        report(Snapshot(ledger: ledger, state: state, effects: effects))
        effects = []
    }

    private static func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// SHA-256 of a file, as `SyncRevision.contentHash` holds it.
    static func hash(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            ledger.engineState = try? JSONEncoder().encode(update.stateSerialization)
        case .accountChange(let change):
            accountChanged(change)
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions { zoneDeleted(deletion) }
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications { received(modification.record) }
            for deletion in changes.deletions {
                if let key = SyncKey(recordName: deletion.recordID.recordName) { effects += ledger.applyDeletion(key) }
            }
        case .sentRecordZoneChanges(let changes):
            sent(changes)
        case .willFetchChanges, .willSendChanges:
            busy = true
        case .didFetchChanges, .didSendChanges:
            busy = false
            online = true
            lastSync = Date()
        default:
            break
        }
        save()
        publish()
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.outgoing(id)
        }
    }

    /// Whole pictures are not fetched with the rest: each is fetched when
    /// opened. A shared space fetches only its Mac's zone.
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                 syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        if case .all = options.scope {
            options.scope = space == .own ? .allExcluding([filesZone]) : .zoneIDs([zone])
        }
        return options
    }
}
#endif
