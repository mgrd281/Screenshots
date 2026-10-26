import AppKit
import Carbon
import SwiftUI

/// Every permission Snapfly asks macOS for, in one place: what each is for,
/// whether it is given, and one button that asks for it or opens the right
/// page of System Settings. Each is asked for only when what needs it is
/// first used, so none is needed to start.
@MainActor
enum Permissions {
    enum Status: Equatable {
        case allowed
        /// Asked, and not given, or turned off since.
        case denied
        case notAsked
        /// A browser that is not open, so macOS cannot say.
        case notRunning
    }

    struct Browser: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
        var status: Status
    }

    // MARK: Screen recording

    /// Screenshots and recordings taken by Snapfly itself.
    static var screen: Status {
        if CGPreflightScreenCaptureAccess() { return .allowed }
        return Capture.wasAsked ? .denied : .notAsked
    }

    /// macOS asks once, in its own words; after that, only System Settings
    /// can turn it on.
    static func askForScreen() {
        if !Capture.wasAsked {
            Capture.wasAsked = true
            CGRequestScreenCaptureAccess()
        } else {
            open("Privacy_ScreenCapture")
        }
    }

    // MARK: Pressing ⌘V

    private static let keysAskedKey = "keysAsked"

    /// The send button pressing ⌘V in the app in front.
    static var keys: Status {
        if Paste.isAllowed { return .allowed }
        return UserDefaults.standard.bool(forKey: keysAskedKey) ? .denied : .notAsked
    }

    static func noteKeysAsked() {
        UserDefaults.standard.set(true, forKey: keysAskedKey)
    }

    static func askForKeys() {
        let first = keys == .notAsked
        noteKeysAsked()
        // The first time, macOS shows its own prompt, which leads there.
        if !Paste.askToBeAllowed(), !first { open("Privacy_Accessibility") }
    }

    // MARK: Browsers

    /// The browsers on this Mac that the chat button can ask for the page
    /// in front, with what macOS last said about each.
    static func installedBrowsers() -> [Browser] {
        ChatButton.browserIDs.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return Browser(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), status: .notRunning)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What macOS says about Snapfly asking a browser for its page. With
    /// `ask`, macOS asks the user if it has not yet, and this waits for the
    /// answer, so it never runs on the main thread.
    nonisolated static func automation(_ id: String, ask: Bool) -> Status {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: id).aeDesc else { return .notRunning }
        // Any event, '****': the question is whether Snapfly may send one at all.
        let any = AEEventClass(0x2A2A_2A2A)
        switch AEDeterminePermissionToAutomateTarget(desc, any, any, ask) {
        case 0: return .allowed
        case -1743: return .denied // errAEEventNotPermitted
        case -1744: return .notAsked // errAEEventWouldRequireUserConsent
        default: return .notRunning // procNotFound
        }
    }

    /// Opens the browser if it is not open, then asks; once said no, only
    /// System Settings can change it.
    static func askForBrowser(_ browser: Browser, then done: @escaping () -> Void) {
        switch browser.status {
        case .allowed:
            return
        case .denied:
            open("Privacy_Automation")
            return
        case .notAsked:
            ask(browser.id, after: 0, then: done)
        case .notRunning:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            // Give it a moment to start before asking it anything.
            ask(browser.id, after: 1.5, then: done)
        }
    }

    private static func ask(_ id: String, after delay: TimeInterval, then done: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            _ = automation(id, ask: true)
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    // MARK: All of them

    /// Something was asked for and not given. The menu bar then offers the
    /// way to fix it; nothing is said about what was never needed.
    static var somethingDenied: Bool {
        screen == .denied || keys == .denied
    }

    static func open(_ page: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(page)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Quits and opens again: macOS applies Screen Recording only to a
    /// fresh start.
    static func reopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// What the Permissions pane shows, read again every second while it is
/// open, so a switch turned in System Settings shows at once.
@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var screen = Permissions.Status.notAsked
    @Published private(set) var keys = Permissions.Status.notAsked
    @Published private(set) var browsers: [Permissions.Browser] = []
    private var timer: Timer?

    func start() {
        browsers = Permissions.installedBrowsers()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        screen = Permissions.screen
        keys = Permissions.keys
        let ids = browsers.map(\.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let statuses = ids.map { Permissions.automation($0, ask: false) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (id, status) in zip(ids, statuses) {
                        if let i = self.browsers.firstIndex(where: { $0.id == id }), self.browsers[i].status != status {
                            self.browsers[i].status = status
                        }
                    }
                }
            }
        }
    }

    /// How many of what this Mac uses are given.
    var allowedCount: Int { [screen, keys].filter { $0 == .allowed }.count }
}

/// Settings › Permissions: each permission with what it is for, where it
/// stands and one button to give it.
struct PermissionsPane: View {
    @StateObject private var model = PermissionsModel()

    var body: some View {
        Form {
            Section {
                Label {
                    Text(model.allowedCount == 2 ? L("Snapfly has what it needs.")
                         : L("Snapfly asks for each permission only when you use what needs it."))
                    Text(L("Everything stays on your Mac. You can change these any time in System Settings."))
                } icon: {
                    Image(systemName: model.allowedCount == 2 ? "checkmark.shield.fill" : "lock.shield")
                        .foregroundStyle(model.allowedCount == 2 ? Color.green : Color.secondary)
                }
            }

            Section {
                PermissionRow(symbol: "rectangle.dashed.badge.record", title: L("Screen Recording"),
                              detail: L("To take screenshots and recordings with Snapfly: ⌃⌥S, the screenshot button and Record Screen."),
                              status: model.screen) {
                    Permissions.askForScreen()
                    model.refresh()
                }
                if model.screen == .denied {
                    LabeledContent {
                        SettingsButton(L("Reopen Snapfly")) { Permissions.reopen() }
                    } label: {
                        Text(L("Turned it on and it still says not allowed?"))
                        Text(L("macOS applies it once Snapfly opens again."))
                    }
                }
            }

            Section {
                PermissionRow(symbol: "keyboard", title: L("Accessibility"),
                              detail: L("For the send buttons: they press ⌘V in the chat in front, so the photos land where you type."),
                              status: model.keys) {
                    Permissions.askForKeys()
                    model.refresh()
                }
                if model.keys == .denied {
                    Text(L("Snapfly not in the list? Click + under it and choose Snapfly in Applications."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.browsers.isEmpty {
                Section {
                    ForEach(model.browsers) { browser in
                        PermissionRow(icon: browser.icon, title: browser.name, detail: nil, status: browser.status) {
                            Permissions.askForBrowser(browser) { model.refresh() }
                        }
                    }
                } header: {
                    Text(L("Browsers"))
                } footer: {
                    Text(L("So the send button shows only on chat websites, Snapfly asks the browser which page is open. Nothing else is read."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

/// One permission: what it is, what it is for, where it stands, and the
/// one button that moves it on.
private struct PermissionRow: View {
    var symbol: String?
    var icon: NSImage?
    let title: String
    let detail: String?
    let status: Permissions.Status
    let act: () -> Void

    init(symbol: String, title: String, detail: String?, status: Permissions.Status, act: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.status = status
        self.act = act
    }

    init(icon: NSImage, title: String, detail: String?, status: Permissions.Status, act: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.status = status
        self.act = act
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            PermissionStatus(status: status)
            if status != .allowed {
                SettingsButton(buttonTitle, action: act)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttonTitle: String {
        switch status {
        case .allowed, .notAsked: L("Allow…")
        case .denied: L("Open System Settings…")
        case .notRunning: L("Open and Allow…")
        }
    }
}

/// Allowed with a green symbol, not allowed with an orange one, not asked
/// yet in grey. The colour is on the symbol alone: system green and orange
/// are too light for words on a light ground.
private struct PermissionStatus: View {
    let status: Permissions.Status

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(words)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.callout.weight(.medium))
        .labelStyle(.titleAndIcon)
        .fixedSize()
    }

    private var text: String {
        switch status {
        case .allowed: L("Allowed")
        case .denied: L("Not allowed yet")
        case .notAsked: L("Not asked yet")
        case .notRunning: L("Not open")
        }
    }

    private var symbol: String {
        switch status {
        case .allowed: "checkmark.circle.fill"
        case .denied: "exclamationmark.circle.fill"
        case .notAsked, .notRunning: "circle.dashed"
        }
    }

    private var color: Color {
        switch status {
        case .allowed: .green
        case .denied: .orange
        case .notAsked, .notRunning: .secondary
        }
    }

    private var words: Color {
        switch status {
        case .allowed, .denied: .primary
        case .notAsked, .notRunning: .secondary
        }
    }
}
