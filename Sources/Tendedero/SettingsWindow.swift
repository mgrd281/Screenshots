import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// What the settings window shows and changes. Each setting is read where
/// the app keeps it, and changing one runs what the app delegate does for
/// it, as the menu bar used to.
@MainActor
final class Preferences: ObservableObject {
    struct Actions {
        var setInbox: (Bool) -> Void = { _ in }
        var setClipboard: (Bool) -> Void = { _ in }
        var setKeep: (Int?) -> Void = { _ in }
        var setSize: (Layout.Size) -> Void = { _ in }
        var addFolder: () -> Void = {}
        var foldersChanged: () -> Void = {}
        var changeShortcut: (Shortcut.Role) -> Void = { _ in }
        var fullScreenChanged: () -> Void = {}
        var openScreenshotsFolder: () -> Void = {}
    }

    var actions = Actions()
    let line: Line

    init(line: Line) {
        self.line = line
    }

    /// Something changed outside the window, like a new shortcut.
    func refresh() {
        objectWillChange.send()
    }

    private func change(_ body: () -> Void) {
        objectWillChange.send()
        body()
    }

    // MARK: General

    var handlesScreenshots: Bool {
        get { Inbox.isEnabled }
        set { change { actions.setInbox(newValue) } }
    }

    var hangsCopiedImages: Bool {
        get { ClipboardWatcher.isEnabled }
        set { change { actions.setClipboard(newValue) } }
    }

    var sounds: Bool {
        get { line.soundOn }
        set { change { line.soundOn = newValue } }
    }

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { change { if newValue != opensAtLogin { AppDelegate.toggleLaunchAtLogin() } } }
    }

    var folders: [URL] { AppDelegate.extraFolders }

    func addFolder() {
        // The folder panel runs first; the window catches up after.
        actions.addFolder()
        refresh()
    }

    func stopWatching(_ folder: URL) {
        change {
            AppDelegate.extraFolders.removeAll { $0.standardizedFileURL == folder.standardizedFileURL }
            actions.foldersChanged()
        }
    }

    func openScreenshotsFolder() {
        actions.openScreenshotsFolder()
    }

    // MARK: Line

    var opensFromMenuBar: Bool {
        get { AppDelegate.opensFromMenuBar }
        set { change { AppDelegate.opensFromMenuBar = newValue } }
    }

    var peeksAtNew: Bool {
        get { AppDelegate.peeksAtNew }
        set { change { AppDelegate.peeksAtNew = newValue } }
    }

    var overFullScreen: Bool {
        get { FullScreen.showLineOver }
        set {
            change {
                FullScreen.showLineOver = newValue
                actions.fullScreenChanged()
            }
        }
    }

    var size: Layout.Size {
        get { Layout.size }
        set { change { actions.setSize(newValue) } }
    }

    var keepOnLine: Int? {
        get { Line.keepOnLine }
        set { change { actions.setKeep(newValue) } }
    }

    func shortcut(_ role: Shortcut.Role) -> String {
        Shortcut.current(role)?.display ?? L("None")
    }

    func changeShortcut(_ role: Shortcut.Role) {
        actions.changeShortcut(role)
    }

    // MARK: Privacy

    func hides(_ detail: PrivateDetail) -> Binding<Bool> {
        Binding(
            get: { PrivateDetails.details.contains(detail) },
            set: { [weak self] on in
                // SwiftUI sets it from the main thread.
                MainActor.assumeIsolated {
                    guard let self, on != PrivateDetails.details.contains(detail) else { return }
                    self.change {
                        PrivateDetails.toggle(detail)
                        self.line.readPrivateDetails()
                    }
                }
            })
    }

    /// Whether the send button may press ⌘V in the app in front.
    var canPaste: Bool { AXIsProcessTrusted() }

    /// Asks macOS to list Tendedero under Accessibility, and opens that list.
    func openAccessibility() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(prompt),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: About

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func checkForUpdates() {
        NSWorkspace.shared.open(AppDelegate.updatesURL)
    }
}

/// The settings window, laid out like System Settings: a sidebar with four
/// panes. Made once and kept, so it opens where it was left.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(_ preferences: Preferences) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(prefs: preferences, line: preferences.line))
            let window = NSWindow(contentViewController: host)
            window.title = L("Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 700, height: 500))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        preferences.refresh()
        // Tendedero lives in the menu bar, so it comes forward on purpose.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case general, line, privacy, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: L("General")
        case .line: L("Line")
        case .privacy: L("Privacy")
        case .about: L("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .line: "tshirt"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var line: Line
    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane ?? .general {
            case .general: GeneralPane(prefs: prefs)
            case .line: LinePane(prefs: prefs)
            case .privacy: PrivacyPane(prefs: prefs, line: line)
            case .about: AboutPane(prefs: prefs)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

private struct GeneralPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.handlesScreenshots) {
                    Text(L("Handle screenshots"))
                    Text(L("Screenshots hang instantly and skip the Desktop"))
                }
                Toggle(isOn: $prefs.hangsCopiedImages) {
                    Text(L("Hang copied images"))
                    Text(L("Images you copy hang on the line too"))
                }
            }
            Section {
                Toggle(L("Sounds"), isOn: $prefs.sounds)
                Toggle(L("Open at login"), isOn: $prefs.opensAtLogin)
            }
            Section(L("Also watch folders")) {
                ForEach(prefs.folders, id: \.self) { folder in
                    HStack {
                        Label(FileManager.default.displayName(atPath: folder.path), systemImage: "folder")
                        Spacer()
                        Button(L("Stop Watching")) { prefs.stopWatching(folder) }
                    }
                }
                Button(L("Add Folder…")) { prefs.addFolder() }
                    .disabled(prefs.folders.count >= AppDelegate.maxExtraFolders)
            }
            Section {
                Button(L("Open screenshots folder")) { prefs.openScreenshotsFolder() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LinePane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section(L("Bring the line down")) {
                Toggle(L("When the pointer rests in the menu bar"), isOn: $prefs.opensFromMenuBar)
                Toggle(L("When something new hangs"), isOn: $prefs.peeksAtNew)
                Toggle(L("Over full screen apps"), isOn: $prefs.overFullScreen)
            }
            Section {
                Picker(L("Size"), selection: $prefs.size) {
                    Text(L("Small")).tag(Layout.Size.small)
                    Text(L("Medium")).tag(Layout.Size.medium)
                    Text(L("Large")).tag(Layout.Size.large)
                }
                .pickerStyle(.segmented)
                Picker(L("Keep on line"), selection: $prefs.keepOnLine) {
                    Text(L("As many as fit")).tag(Int?.none)
                    ForEach(Line.keepChoices, id: \.self) { n in
                        Text(String(format: L("%d photos"), n)).tag(Int?.some(n))
                    }
                }
            }
            Section {
                shortcutRow(L("Show or hide the line"), .toggle)
                shortcutRow(L("Send the newest photo"), .send)
                shortcutRow(L("Search screenshots"), .search)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, _ role: Shortcut.Role) -> some View {
        LabeledContent(title) {
            HStack {
                Text(prefs.shortcut(role))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button(L("Change Shortcut…")) { prefs.changeShortcut(role) }
            }
        }
    }
}

private struct PrivacyPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var line: Line

    /// The newest photo, as it hangs: covered, once read, the way it will
    /// leave the line.
    private var newest: Pegged? {
        line.items.last { !$0.falling && !$0.isRecording }
    }

    var body: some View {
        Form {
            Section {
                ForEach(PrivateDetail.allCases, id: \.self) { detail in
                    Toggle(detail.title, isOn: prefs.hides(detail))
                }
            } header: {
                Text(L("Hide private details"))
            } footer: {
                Text(L("What is checked is covered in whatever leaves the line"))
                    .foregroundStyle(.secondary)
            }
            Section(L("Preview")) {
                if let photo = newest {
                    Image(nsImage: photo.thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(L("Take a screenshot to see it here"))
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Send button")) {
                HStack {
                    Label(prefs.canPaste ? L("Allowed") : L("Not allowed yet"),
                          systemImage: prefs.canPaste ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(prefs.canPaste ? Color.green : Color.orange)
                    Spacer()
                    if !prefs.canPaste {
                        Button(L("Open Accessibility Settings…")) { prefs.openAccessibility() }
                    }
                }
                Text(L("The send button presses ⌘V in the app in front, which needs the Accessibility permission."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Coming back from System Settings, the permission may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prefs.refresh()
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            Text(verbatim: "Snapfly")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .padding(.top, 14)
            Text(L("Screenshots, one click from any chat."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(String(format: L("Version %@"), prefs.version))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
            Divider()
                .frame(width: 240)
                .padding(.vertical, 18)
            Text(String(format: L("Made by %@"), AppDelegate.author))
                .font(.headline)
            Button(L("Check for Updates…")) { prefs.checkForUpdates() }
                .controlSize(.large)
                .padding(.top, 12)
            Spacer()
            // The MIT License asks for the original's credit to stay.
            Text(L("Based on Tendedero by Alejandro Buján, under the MIT License."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
