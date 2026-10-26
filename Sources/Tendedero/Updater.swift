import AppKit
import Security

/// Check for Updates…, in the menu bar. The download edition fetches the
/// newest build from the Releases page, makes sure it is signed by the same
/// developer as the Snapfly running, and after a question replaces itself and
/// opens again. Nothing is fetched until it is chosen. The App Store edition
/// updates through Apple: TestFlight for a test build, else the App Store.
@MainActor
enum Updater {
    /// The newest build from `main`.
    static let latestZip = URL(string: "https://github.com/mgrd281/Screenshots/releases/download/latest/Snapfly.zip")!

    private static var checking = false

    static func check() {
        if Edition.appStore {
            // A test build was installed by TestFlight, which updates it.
            let testFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            let url = URL(string: testFlight ? "itms-beta://" : "macappstore://showUpdatesPage")!
            if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(AppDelegate.updatesURL) }
            return
        }
        guard !checking else { return }
        // Only a build signed by its developer can be checked against the next.
        guard let team = teamIdentifier(of: Bundle.main.bundleURL) else {
            NSWorkspace.shared.open(AppDelegate.updatesURL)
            return
        }
        checking = true
        let note = Notice.show(L("Checking for updates…"), working: true)
        Task { @MainActor in
            defer { checking = false }
            let found = await download()
            Notice.end(note)
            guard let found else {
                Notice.show(L("Could not check for updates. Check the connection and try again."))
                return
            }
            let current = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            guard found.build > current else {
                try? FileManager.default.removeItem(at: found.folder)
                Notice.show(String(format: L("Snapfly %@ is up to date."), version), done: true)
                return
            }
            // Every file of it is checked, which takes a moment: off the main thread.
            let app = found.app
            let trusted = await Task.detached(priority: .userInitiated) {
                Updater.teamIdentifier(of: app) == team && Updater.isValid(app, team: team)
            }.value
            guard trusted else {
                try? FileManager.default.removeItem(at: found.folder)
                log.error("An update was not signed as Snapfly is; it was not installed")
                Notice.show(L("The update could not be checked, so it was not installed."))
                return
            }
            offer(found)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private struct Found {
        var app: URL
        var folder: URL
        var version: String
        var build: Int
    }

    /// The newest build, downloaded and unpacked in a folder of its own.
    private static func download() async -> Found? {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("Snapfly Update \(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let (file, response) = try await URLSession.shared.download(from: latestZip)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let zip = folder.appendingPathComponent("Snapfly.zip")
            try fm.moveItem(at: file, to: zip)
            let unpack = Process()
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unpack.arguments = ["-x", "-k", zip.path, folder.path]
            try unpack.run()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    unpack.waitUntilExit()
                    done.resume()
                }
            }
            guard unpack.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
            let app = folder.appendingPathComponent("Snapfly.app")
            guard let info = Bundle(url: app)?.infoDictionary,
                  let build = Int(info["CFBundleVersion"] as? String ?? "") else { throw CocoaError(.fileReadCorruptFile) }
            return Found(app: app, folder: folder, version: info["CFBundleShortVersionString"] as? String ?? "",
                         build: build)
        } catch {
            log.error("Could not download an update: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: folder)
            return nil
        }
    }

    /// Asks first, then puts the new build in place of this one and opens it.
    private static func offer(_ found: Found) {
        let alert = NSAlert()
        alert.messageText = String(format: L("Snapfly %@ is ready"), found.version)
        alert.informativeText = L("Snapfly closes, is replaced by the new version and opens again. Photos on the line stay.")
        alert.addButton(withTitle: L("Install and Reopen"))
        alert.addButton(withTitle: L("Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: found.folder)
            return
        }
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: found.app)
        } catch {
            log.error("Could not install an update: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: found.folder)
            Notice.show(L("Could not install the update here. The download page opens instead."))
            NSWorkspace.shared.open(AppDelegate.updatesURL)
            return
        }
        try? FileManager.default.removeItem(at: found.folder)
        reopen(current)
    }

    /// Quits, and opens the app at `app` again once this copy has gone, so
    /// two never run side by side: the one quitting would put back the
    /// screenshot settings the new one has just set, and hold its shortcuts.
    /// Quitting may wait some seconds for a recording under way to be saved;
    /// the new copy waits for it half a minute at most.
    static func reopen(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c",
                             "n=0; while kill -0 \"$1\" 2>/dev/null && [ $n -lt 150 ]; do sleep 0.2; n=$((n+1)); done; /usr/bin/open \"$0\"",
                             app.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: Signatures

    /// The developer team an app is signed by; nil for an app signed ad hoc.
    nonisolated static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Signed by Apple's chain for that team, every file of it unchanged.
    nonisolated static func isValid(_ app: URL, team: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
        guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
