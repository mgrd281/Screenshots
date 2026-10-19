import Foundation

/// How syncing stands, in the owner's words, on the Mac and the iPhone.
extension SyncState {
    var text: String {
        switch self {
        case .off: L("Off")
        case .unavailable(let problem), .attention(let problem): problem.text
        case .upToDate: L("Up to date")
        case .syncing(let waiting):
            waiting > 0 ? String(format: L("Syncing, %d waiting"), waiting) : L("Syncing…")
        case .waitingForNetwork(let waiting):
            String(format: L("Waiting for a connection, %d waiting"), waiting)
        }
    }

    /// Something only the owner can settle.
    var needsAttention: Bool {
        if case .attention = self { return true }
        return false
    }
}

extension SyncProblem {
    var text: String {
        switch self {
        case .notInThisBuild: L("This build of Snapfly cannot sync.")
        case .noAccount: L("Sign in to iCloud to sync.")
        case .restricted: L("iCloud is restricted on this device.")
        case .otherAccount: L("Another iCloud account is signed in. Turn syncing on again to sync with it.")
        case .removedFromICloud: L("Snapfly's data was removed from iCloud. Turn syncing on again to start anew.")
        case .iCloudFull: L("Your iCloud storage is full.")
        case .stuck: L("Some changes could not be sent. Try Sync Now.")
        case .needsUpdate, .newerFile: L("Another device has a newer Snapfly. Update Snapfly here.")
        case .disconnected: L("No longer connected.")
        }
    }
}

extension SyncDevice {
    /// The SF Symbol for the device.
    var symbol: String {
        switch platform {
        case .mac: model.hasPrefix("iMac") || model.hasPrefix("Macmini") || model.hasPrefix("MacPro")
            ? "desktopcomputer" : "laptopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }

    /// There now, or when it was last.
    func presence(now: Date = Date()) -> String {
        guard !isPresent(now: now) else { return L("Here now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(format: L("Last here %@"), formatter.localizedString(for: lastSeen, relativeTo: now))
    }
}
