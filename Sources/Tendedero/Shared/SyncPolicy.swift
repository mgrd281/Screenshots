import Foundation

/// What the owner chose for syncing, kept with the settings on each device.
/// Off until turned on; then only covered copies leave the device, unless
/// the owner also chooses the originals.
struct SyncSettings: Codable, Equatable, Sendable {
    var on = false
    /// Originals go too, not only covered copies.
    var originals = false
    /// When the originals were turned on: those taken before stay on the
    /// device, so turning it on never sends the old ones unasked.
    var originalsSince: Date?

    static let key = "syncSettings"
    private static let deviceKey = "syncDeviceID"

    mutating func setOriginals(_ on: Bool, now: Date = Date()) {
        originals = on
        originalsSince = on ? now : nil
    }

    static func load(from defaults: UserDefaults = .standard) -> SyncSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? SyncCoding.decoder.decode(SyncSettings.self, from: data) else { return SyncSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? SyncCoding.encoder.encode(self), forKey: Self.key)
    }

    /// This device's id among the owner's devices, made once. It names the
    /// device; it proves nothing, the iCloud account does.
    static func deviceID(in defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: deviceKey), !id.isEmpty { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceKey)
        return id
    }
}

/// What may leave the device, decided in one place and asked again just
/// before anything goes, so a setting changed meanwhile counts.
enum SyncPolicy {
    /// Larger pictures stay on the device.
    static let largestFile = 50 * 1024 * 1024

    static func allows(_ operation: SyncOperation, in ledger: SyncLedger, settings: SyncSettings) -> Bool {
        allows(operation.key, kind: operation.kind, in: ledger, settings: settings)
    }

    static func allows(_ key: SyncKey, kind: SyncOperation.Kind, in ledger: SyncLedger, settings: SyncSettings) -> Bool {
        guard settings.on else { return false }
        // Only what iCloud has can be taken out of it.
        if kind == .purge { return ledger.onServer.contains(key.recordName) }
        switch key.kind {
        case .device:
            return key.id == ledger.deviceID && ledger.devices[key.id] != nil
        case .project:
            return ledger.projects[key.id] != nil
        case .screenshot:
            guard let screenshot = ledger.screenshots[key.id] else { return false }
            // Once in iCloud, its changes follow: a move, a removal.
            if ledger.onServer.contains(key.recordName) { return true }
            // Otherwise only with a picture that may go, so a screenshot
            // that stays private is not even named in iCloud.
            return !ledger.isRemoved(screenshot)
                && ledger.revisions(of: key.id).contains { picture($0, in: ledger, settings: settings) }
        case .revision, .file:
            guard let revision = ledger.revisions[key.id] else { return false }
            return picture(revision, in: ledger, settings: settings)
        }
    }

    /// Whether a version's picture, and its preview, may leave the device:
    /// made here, not too large, in a project that syncs, and covered
    /// unless the owner chose originals too.
    static func picture(_ revision: SyncRevision, in ledger: SyncLedger, settings: SyncSettings) -> Bool {
        guard settings.on, revision.device == ledger.deviceID, revision.byteCount <= largestFile,
              let screenshot = ledger.screenshots[revision.screenshot], !ledger.isRemoved(screenshot),
              ledger.projects[ledger.project(of: screenshot)]?.syncs.value ?? true else { return false }
        switch revision.content {
        case .protected:
            return true
        case .original:
            guard settings.originals else { return false }
            return revision.stamp.date >= (settings.originalsSince ?? .distantPast)
        }
    }

    /// The changes waiting that may go, for the status.
    static func waiting(in ledger: SyncLedger, settings: SyncSettings) -> [SyncOperation] {
        ledger.journal.filter { $0.state != .stuck && allows($0, in: ledger, settings: settings) }
    }
}

// MARK: Status

/// Whether this device can reach the owner's iCloud.
enum SyncAccount: Equatable, Sendable {
    case available
    /// Not signed in to iCloud.
    case none
    /// Parental controls or a company profile keep iCloud closed.
    case restricted
    /// Not known yet.
    case unknown
}

/// Something only the owner can settle.
enum SyncProblem: String, Codable, Sendable {
    /// This build has no iCloud container.
    case notInThisBuild
    case noAccount
    case restricted
    /// A different iCloud account than before: syncing paused, asked again.
    case otherAccount
    /// Snapfly's data was removed in iCloud's settings.
    case removedFromICloud
    case iCloudFull
    /// Changes that failed too often.
    case stuck
    /// Another device has a newer Snapfly.
    case needsUpdate
    /// This device's sync file is from a newer Snapfly.
    case newerFile
    /// A Mac on another Apple account stopped sharing with this device, or
    /// this device left it.
    case disconnected
}

/// This device's syncing, as the owner sees it. Apart from it, each other
/// device has its own presence: a device can be away while everything it
/// had is already in iCloud.
enum SyncState: Equatable, Sendable {
    case off
    case unavailable(SyncProblem)
    case upToDate(Date?)
    case syncing(waiting: Int)
    case waitingForNetwork(waiting: Int)
    case attention(SyncProblem)

    /// - Parameters:
    ///   - problem: one already found, like another account.
    ///   - busy: sending or fetching right now.
    static func of(_ ledger: SyncLedger, settings: SyncSettings, account: SyncAccount, online: Bool,
                   busy: Bool, lastSync: Date?, problem: SyncProblem? = nil) -> SyncState {
        if problem == .notInThisBuild { return .unavailable(.notInThisBuild) }
        guard settings.on else { return .off }
        switch account {
        case .none: return .unavailable(.noAccount)
        case .restricted: return .unavailable(.restricted)
        case .available, .unknown: break
        }
        if let problem { return .attention(problem) }
        if ledger.journal.contains(where: { $0.state == .stuck && $0.needsRoom }) { return .attention(.iCloudFull) }
        if ledger.journal.contains(where: { $0.state == .stuck && allowsAny($0, ledger, settings) }) {
            return .attention(.stuck)
        }
        if !ledger.tooNew.isEmpty { return .attention(.needsUpdate) }
        let waiting = SyncPolicy.waiting(in: ledger, settings: settings).count
        if !online && waiting > 0 { return .waitingForNetwork(waiting: waiting) }
        if busy || waiting > 0 { return .syncing(waiting: waiting) }
        return .upToDate(lastSync)
    }

    private static func allowsAny(_ operation: SyncOperation, _ ledger: SyncLedger, _ settings: SyncSettings) -> Bool {
        SyncPolicy.allows(operation, in: ledger, settings: settings)
    }
}
