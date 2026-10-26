import AppKit

/// Syncing on the Mac: what hangs on the line goes to the iPhone as it
/// leaves the line, covered, once Settings › Sync is on; what the iPhone
/// sends hangs on the line. `SyncCenter` does the rest, as on the iPhone.
@MainActor
enum MacSync {
    static func start(line: Line) {
        let center = SyncCenter.shared
        center.onArrival = { versions in hang(versions, on: line) }
        center.start(as: device)
    }

    /// This Mac, as the iPhone lists it.
    static var device: SyncDevice {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return SyncDevice(id: SyncSettings.deviceID(), name: Host.current().localizedName ?? "Mac", platform: .mac,
                          model: model, registered: SyncCenter.registered, lastSeen: Date(), lastSync: nil,
                          appVersion: version, schema: SyncSchema.current)
    }

    /// The hardware, like "Mac15,3".
    private static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }

    /// A photo just hung: kept as the original, which stays on this Mac
    /// unless originals were chosen.
    static func hung(_ url: URL) {
        SyncCenter.shared.offer(original: url, covered: nil, redaction: nil)
    }

    /// Its private details read: the copy that leaves the line goes, covered
    /// as Settings › Privacy says. With covering turned off, nothing is
    /// covered, so nothing goes but the original, if chosen.
    static func read(_ url: URL) {
        let chosen = PrivateDetails.details
        guard SyncCenter.shared.settings.on, !chosen.isEmpty, SyncCenter.isPicture(url) else { return }
        // Only a reading of it as it is now that went well: a picture Vision
        // could not read goes nowhere, not even covered whole, which is no
        // covered copy of it, and it is not read again here on its way.
        guard PrivateDetails.shown(url) != nil else { return }
        let copy = PrivateDetails.shareable(url)
        guard copy != url else { return }
        let redaction = SyncRedaction(kinds: PrivateDetails.coveredKeys(url, covering: chosen),
                                      areas: PrivateDetails.report(for: url)?.total ?? 0,
                                      look: CoverStyle.current.rawValue)
        SyncCenter.shared.offer(original: url, covered: copy, redaction: redaction)
    }

    /// What the iPhone sent since syncing was turned on hangs on the line.
    private static func hang(_ versions: [SyncRevision], on line: Line) {
        let since = SyncCenter.shared.since
        for version in versions where version.stamp.date >= since {
            Task { @MainActor in
                do {
                    let picture = try await SyncCenter.shared.picture(version.id)
                    line.hang(picture)
                } catch {
                    log.error("A picture from another device could not be fetched: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
