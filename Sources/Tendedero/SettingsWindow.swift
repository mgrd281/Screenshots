import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers
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
        var setStyle: (Layout.Style) -> Void = { _ in }
        var addFolder: () -> Void = {}
        var foldersChanged: () -> Void = {}
        var changeShortcut: (Shortcut.Role) -> Void = { _ in }
        var fullScreenChanged: () -> Void = {}
        var setUpScreenshots: () -> Void = {}
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

    func setUpScreenshots() {
        actions.setUpScreenshots()
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

    var style: Layout.Style {
        get { Layout.style }
        set { change { actions.setStyle(newValue) } }
    }

    var keepOnLine: Int? {
        get { Line.keepOnLine }
        set { change { actions.setKeep(newValue) } }
    }

    var takesDownSent: Bool {
        get { Line.takesDownSent }
        set { change { Line.takesDownSent = newValue } }
    }

    var historyDays: Int? {
        get { History.days }
        set { change { History.days = newValue } }
    }

    var captureButton: Bool {
        get { CaptureButton.isEnabled }
        set { change { CaptureButton.isEnabled = newValue } }
    }

    var captureButtonClick: CaptureButton.Click {
        get { CaptureButton.click }
        set { change { CaptureButton.click = newValue } }
    }

    var captureButtonSymbol: CaptureButtonSymbol {
        get { CaptureButton.symbol }
        set { change { CaptureButton.symbol = newValue } }
    }

    var captureButtonTint: ChatButtonTint? {
        get { CaptureButton.tint }
        set { change { CaptureButton.tint = newValue } }
    }

    var chatButton: Bool {
        get { ChatButton.isEnabled }
        set { change { ChatButton.isEnabled = newValue } }
    }

    var chatButtonInApps: Bool {
        get { ChatButton.inApps }
        set { change { ChatButton.inApps = newValue } }
    }

    var chatApps: [ChatButton.ChatApp] {
        get { ChatButton.apps }
        set { change { ChatButton.apps = newValue } }
    }

    func chatAppOn(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { ChatButton.apps.first { $0.bundleID == bundleID }?.on ?? false },
            set: { on in
                self.chatApps = ChatButton.apps.map {
                    $0.bundleID == bundleID ? ChatButton.ChatApp(bundleID: bundleID, on: on) : $0
                }
            })
    }

    /// Asks for an app in the Applications folder and adds it to the chat apps.
    func addChatApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L("Add")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier,
              !chatApps.contains(where: { $0.bundleID == id }) else { return }
        chatApps.append(ChatButton.ChatApp(bundleID: id))
    }

    func removeChatApp(_ bundleID: String) {
        chatApps.removeAll { $0.bundleID == bundleID }
    }

    var chatSites: [ChatButton.Site] {
        get { ChatButton.sites }
        set { change { ChatButton.sites = newValue } }
    }

    func chatSiteOn(_ host: String) -> Binding<Bool> {
        Binding(
            get: { ChatButton.sites.first { $0.host == host }?.on ?? false },
            set: { on in
                self.chatSites = ChatButton.sites.map { $0.host == host ? ChatButton.Site(host: host, on: on) : $0 }
            })
    }

    /// Adds a website as typed. False when it isn't one, or is there already.
    func addChatSite(_ text: String) -> Bool {
        guard let host = ChatButton.host(from: text), !chatSites.contains(where: { $0.host == host }) else { return false }
        chatSites.append(ChatButton.Site(host: host))
        return true
    }

    func removeChatSite(_ host: String) {
        chatSites.removeAll { $0.host == host }
    }

    /// The button as it looks with these settings, for the preview.
    let chatButtonPreview = ChatButtonModel()

    var chatButtonPlacement: ChatButtonPlacement {
        get { ChatButton.placement }
        set { change { ChatButton.placement = newValue } }
    }

    var chatButtonLook: ChatButtonLook {
        get { ChatButton.look }
        set { change { ChatButton.look = newValue; chatButtonPreview.look = newValue } }
    }

    var chatButtonSymbol: ChatButtonSymbol {
        get { ChatButton.symbol }
        set { change { ChatButton.symbol = newValue; chatButtonPreview.symbol = newValue } }
    }

    var chatButtonTint: ChatButtonTint {
        get { ChatButton.tint }
        set { change { ChatButton.tint = newValue; chatButtonPreview.tint = newValue } }
    }

    /// The preview shows the photos hanging now, or a placeholder.
    func refreshChatButtonPreview() {
        let live = line.items.filter { !$0.falling }
        chatButtonPreview.thumbs = live.suffix(2).map(\.thumb)
        chatButtonPreview.count = max(1, live.count)
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
    var canPaste: Bool { Paste.isAllowed }

    /// Asks macOS to list Snapfly under Accessibility, and opens that list.
    func openAccessibility() {
        if !Paste.askToBeAllowed(),
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
                if Edition.appStore {
                    // The sandbox keeps Snapfly out of the screenshot
                    // settings, so this shows where to change them.
                    LabeledContent {
                        Button(L("Set Up…")) { prefs.setUpScreenshots() }
                    } label: {
                        Text(L("Handle screenshots"))
                        Text(L("Screenshots saved to Pictures › Snapfly hang on the line"))
                    }
                } else {
                    Toggle(isOn: $prefs.handlesScreenshots) {
                        Text(L("Handle screenshots"))
                        Text(L("Screenshots hang instantly and skip the Desktop"))
                    }
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
            Section(L("Line style")) {
                StylePicker(selection: $prefs.style)
            }
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
                Toggle(isOn: $prefs.takesDownSent) {
                    Text(L("Take photos down once sent"))
                    Text(L("Sent into a chat, they leave the line. Pinned ones stay."))
                }
                LabeledContent {
                    HStack {
                        Picker(L("Keep a history"), selection: $prefs.historyDays) {
                            Text(L("Off")).tag(Int?.none)
                            ForEach(History.dayChoices, id: \.self) { n in
                                Text(String(format: L("%d days"), n)).tag(Int?.some(n))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button(L("History…")) { HistoryWindow.shared.show() }
                            .disabled(prefs.historyDays == nil)
                    }
                } label: {
                    Text(L("Keep a history"))
                    Text(L("What leaves the line stays in the History, from the menu bar, to find and hang again."))
                }
            }
            ChatButtonSection(prefs: prefs)
            Section(L("Screenshot button")) {
                Toggle(isOn: $prefs.captureButton) {
                    Text(L("Show the screenshot button"))
                    Text(L("A small button at the edge of the screen takes a screenshot in one click. Drag it anywhere."))
                }
                Group {
                    Picker(L("A click"), selection: $prefs.captureButtonClick) {
                        Text(L("Chooses an area")).tag(CaptureButton.Click.choose)
                        Text(L("Takes the whole screen")).tag(CaptureButton.Click.screen)
                        Text(L("Takes the last area again")).tag(CaptureButton.Click.lastArea)
                    }
                    LabeledContent(L("Icon")) {
                        HStack(spacing: 8) {
                            ForEach(CaptureButtonSymbol.allCases) { symbol in
                                let chosen = prefs.captureButtonSymbol == symbol
                                Button { prefs.captureButtonSymbol = symbol } label: {
                                    Image(systemName: symbol.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(chosen ? Color.white : Color.primary)
                                        .frame(width: 28, height: 28)
                                        .background(chosen ? Color.accentColor : Color.primary.opacity(0.06), in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(symbol.name)
                                .accessibilityLabel(symbol.name)
                                .accessibilityAddTraits(chosen ? .isSelected : [])
                            }
                        }
                    }
                    LabeledContent(L("Color")) {
                        HStack(spacing: 4) {
                            tintButton(nil, name: L("Glass"))
                            ForEach(ChatButtonTint.allCases) { tint in
                                tintButton(tint, name: tint.name)
                            }
                        }
                    }
                    LabeledContent(L("Preview")) {
                        CaptureButtonFace(symbol: prefs.captureButtonSymbol, tint: prefs.captureButtonTint)
                            .padding(.vertical, 6)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(!prefs.captureButton)
            }
            Section {
                shortcutRow(L("Show or hide the line"), .toggle)
                shortcutRow(L("Send the newest photo"), .send)
                shortcutRow(L("Search screenshots"), .search)
                shortcutRow(L("Take a screenshot"), .capture)
                shortcutRow(L("Record the screen"), .record)
            }
        }
        .formStyle(.grouped)
    }

    /// A color for the screenshot button; nil is glass, shown frosted.
    private func tintButton(_ tint: ChatButtonTint?, name: String) -> some View {
        let chosen = prefs.captureButtonTint == tint
        return Button { prefs.captureButtonTint = tint } label: {
            Group {
                if let tint {
                    Circle().fill(tint.color)
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .padding(3)
            .overlay(Circle().strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
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

/// The send button over chats: whether it shows, where, and how it looks,
/// with a preview of the button itself.
private struct ChatButtonSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section(L("Send button over chats")) {
            Toggle(isOn: $prefs.chatButton) {
                Text(L("Show it while photos hang"))
                Text(L("While photos hang, a send button waits just above the chat's own. Drag it where you like it."))
            }
            Group {
                Toggle(isOn: $prefs.chatButtonInApps) {
                    Text(L("In chat apps"))
                    Text(L("ChatGPT, Claude, WhatsApp, Telegram, Messages and others."))
                }
                Picker(L("Position"), selection: $prefs.chatButtonPlacement) {
                    ForEach(ChatButtonPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                Picker(L("Style"), selection: $prefs.chatButtonLook) {
                    Text(L("Photo and count")).tag(ChatButtonLook.full)
                    Text(L("Icon only")).tag(ChatButtonLook.compact)
                }
                .pickerStyle(.segmented)
                LabeledContent(L("Icon")) {
                    HStack(spacing: 8) {
                        ForEach(ChatButtonSymbol.allCases) { symbol in
                            let chosen = prefs.chatButtonSymbol == symbol
                            Button { prefs.chatButtonSymbol = symbol } label: {
                                Image(systemName: symbol.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(chosen ? Color.white : Color.primary)
                                    .frame(width: 28, height: 28)
                                    .background(chosen ? Color.accentColor : Color.primary.opacity(0.06), in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(symbol.name)
                            .accessibilityLabel(symbol.name)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                LabeledContent(L("Color")) {
                    HStack(spacing: 4) {
                        ForEach(ChatButtonTint.allCases) { tint in
                            let chosen = prefs.chatButtonTint == tint
                            Button { prefs.chatButtonTint = tint } label: {
                                Circle()
                                    .fill(tint.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(tint.name)
                            .accessibilityLabel(tint.name)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                LabeledContent(L("Preview")) {
                    ChatButtonLabel(model: prefs.chatButtonPreview)
                        .padding(.vertical, 4)
                }
            }
            .disabled(!prefs.chatButton)
            .opacity(prefs.chatButton ? 1 : 0.5)
        }
        .onAppear { prefs.refreshChatButtonPreview() }

        ChatAppsSection(prefs: prefs)
        ChatSitesSection(prefs: prefs)
    }
}

/// The chat apps it shows over, by name and icon: those on this Mac from the
/// standard list, and any added. Each can be turned off or removed.
private struct ChatAppsSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section {
            ForEach(prefs.chatApps.filter { $0.url != nil }) { app in
                HStack(spacing: 8) {
                    if let url = app.url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    Toggle(isOn: prefs.chatAppOn(app.bundleID)) {
                        Text(verbatim: app.name)
                    }
                    Button { prefs.removeChatApp(app.bundleID) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remove"))
                    .accessibilityLabel(L("Remove"))
                }
            }
            Button(L("Add App…")) { prefs.addChatApp() }
        } header: {
            Text(L("Chat apps"))
        } footer: {
            Text(L("It shows over these apps while photos hang."))
                .foregroundStyle(.secondary)
        }
        .disabled(!prefs.chatButton || !prefs.chatButtonInApps)
    }
}

/// The chat websites where the button shows in a browser: each can be
/// turned off or removed, and any other can be added.
private struct ChatSitesSection: View {
    @ObservedObject var prefs: Preferences
    @State private var newSite = ""
    @State private var rejected = false

    var body: some View {
        Section {
            ForEach(prefs.chatSites) { site in
                HStack {
                    Toggle(isOn: prefs.chatSiteOn(site.host)) {
                        Text(verbatim: site.host)
                    }
                    Button { prefs.removeChatSite(site.host) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remove"))
                    .accessibilityLabel(L("Remove"))
                }
            }
            HStack {
                TextField(L("Add a website"), text: $newSite, prompt: Text(verbatim: "example.com"))
                    .onSubmit(add)
                    .onChange(of: newSite) { _, _ in rejected = false }
                Button(L("Add"), action: add)
                    .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if rejected {
                Text(L("That isn't a website, or it is in the list already."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Chat websites"))
        } footer: {
            Text(L("In Safari, Chrome and other browsers, it shows only on these websites. macOS asks once whether Snapfly may see which page is open."))
                .foregroundStyle(.secondary)
        }
        .disabled(!prefs.chatButton)
    }

    private func add() {
        if prefs.addChatSite(newSite) {
            newSite = ""
        } else {
            rejected = true
        }
    }
}

/// The four styles side by side, each as a little picture of the top of a
/// screen, to pick one by looking.
private struct StylePicker: View {
    @Binding var selection: Layout.Style

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Layout.Style.allCases) { style in
                tile(style)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ style: Layout.Style) -> some View {
        let chosen = style == selection
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selection = style
        } label: {
            VStack(spacing: 7) {
                StylePreview(style: style)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.12),
                                                lineWidth: chosen ? 2.5 : 1))
                    .shadow(color: .black.opacity(chosen ? 0.18 : 0.06), radius: chosen ? 6 : 2, y: 2)
                Text(style.title)
                    .font(.system(size: 11, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A style drawn small: a wallpaper, a menu bar and three screenshots on
/// what that style hangs them on.
private struct StylePreview: View {
    let style: Layout.Style

    private static let wallpaper = Gradient(colors: [
        Color(red: 0.17, green: 0.30, blue: 0.62),
        Color(red: 0.36, green: 0.52, blue: 0.86),
        Color(red: 0.93, green: 0.62, blue: 0.45),
    ])
    private static let accents: [Color] = [
        Color(red: 0.18, green: 0.62, blue: 0.36),
        Color(red: 0.48, green: 0.31, blue: 0.88),
        Color(red: 0.89, green: 0.51, blue: 0.17),
    ]

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Self.wallpaper, startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.08)), with: .color(.white.opacity(0.32)))
            let card = CGSize(width: w * 0.2, height: w * 0.15)
            switch style {
            case .clothesline:
                var rope = Path()
                rope.move(to: CGPoint(x: -2, y: h * 0.2))
                rope.addQuadCurve(to: CGPoint(x: w + 2, y: h * 0.2), control: CGPoint(x: w / 2, y: h * 0.4))
                context.stroke(rope, with: .color(Color(white: 0.25, opacity: 0.8)), lineWidth: 1)
                for (n, fx) in [0.22, 0.5, 0.78].enumerated() {
                    let x = w * fx
                    let y = h * 0.2 + 4 * (h * 0.1) * fx * (1 - fx)
                    Self.drawCard(in: &context, top: CGPoint(x: x, y: y + 2), size: card,
                                  angle: .degrees([-4, 2, 5][n]), accent: Self.accents[n], clip: true)
                }
            case .shelf:
                let pane = CGRect(x: w * 0.12, y: h * 0.15, width: w * 0.76, height: card.height + h * 0.12)
                let path = Path(roundedRect: pane, cornerRadius: h * 0.1, style: .continuous)
                context.fill(path, with: .color(.white.opacity(0.32)))
                context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
                for n in 0..<3 {
                    let x = pane.minX + pane.width * (0.2 + 0.28 * CGFloat(n))
                    Self.drawCard(in: &context, top: CGPoint(x: x, y: pane.minY + h * 0.06), size: card,
                                  angle: .zero, accent: Self.accents[n], clip: false)
                }
            case .island:
                let island = CGRect(x: w * 0.16, y: 0, width: w * 0.68, height: card.height + h * 0.24)
                context.fill(Path(roundedRect: island, cornerRadii: RectangleCornerRadii(
                    topLeading: 0, bottomLeading: h * 0.14, bottomTrailing: h * 0.14, topTrailing: 0)),
                             with: .color(.black))
                for n in 0..<3 {
                    let x = island.minX + island.width * (0.2 + 0.3 * CGFloat(n))
                    Self.drawCard(in: &context, top: CGPoint(x: x, y: h * 0.13), size: card,
                                  angle: .zero, accent: Self.accents[n], clip: false)
                }
            case .stack:
                let anchor = CGPoint(x: w * 0.74, y: h * 0.17)
                for (n, angle) in [-12.0, -6.0, 0].enumerated() {
                    Self.drawCard(in: &context, top: CGPoint(x: anchor.x - CGFloat(2 - n) * 4, y: anchor.y),
                                  size: card, angle: .degrees(angle), accent: Self.accents[n], clip: false)
                }
                let badge = CGRect(x: anchor.x + card.width / 2 - 5, y: anchor.y - 4, width: 9, height: 9)
                context.fill(Path(ellipseIn: badge), with: .color(.red))
            }
        }
    }

    /// One screenshot, hanging from the middle of its top edge.
    private static func drawCard(in context: inout GraphicsContext, top: CGPoint, size: CGSize,
                                 angle: Angle, accent: Color, clip: Bool) {
        var layer = context
        layer.translateBy(x: top.x, y: top.y)
        layer.rotate(by: angle)
        let rect = CGRect(x: -size.width / 2, y: 0, width: size.width, height: size.height)
        var shadow = layer
        shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 1))
        shadow.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white))
        layer.fill(Path(CGRect(x: rect.minX + size.width * 0.12, y: rect.minY + size.height * 0.16,
                               width: size.width * 0.5, height: max(1.5, size.height * 0.12))),
                   with: .color(accent))
        for row in 0..<2 {
            layer.fill(Path(CGRect(x: rect.minX + size.width * 0.12,
                                   y: rect.minY + size.height * (0.42 + 0.2 * CGFloat(row)),
                                   width: size.width * (row == 0 ? 0.72 : 0.5), height: max(1, size.height * 0.08))),
                       with: .color(Color(white: 0.86)))
        }
        if clip {
            layer.fill(Path(roundedRect: CGRect(x: -1.5, y: -4, width: 3, height: 6), cornerRadius: 1),
                       with: .color(Color(white: 0.75)))
        }
    }
}

private struct PrivacyPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var line: Line

    /// The newest photo, as it hangs: covered, once read, the way it will
    /// leave the line.
    private var newest: Pegged? {
        line.items.last { !$0.falling && $0.isImage }
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
            if !Edition.appStore {
                Button(L("Check for Updates…")) { prefs.checkForUpdates() }
                    .controlSize(.large)
                    .padding(.top, 12)
            }
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
