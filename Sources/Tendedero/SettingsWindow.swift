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
        var screenshotsFolder: () -> URL? = { nil }
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

    /// Where the screenshots are saved, named under the button that opens it.
    var screenshotsFolder: URL? { actions.screenshotsFolder() }

    /// The capture screens, from Settings, to try them.
    func tryCapture() {
        Capture.shared.start(after: 0.3)
    }

    func setUpScreenshots() {
        actions.setUpScreenshots()
    }

    // MARK: Time stamp

    var stampsTime: Bool {
        get { TimeStamp.isOn }
        set { change { TimeStamp.isOn = newValue; line.readPrivateDetails() } }
    }

    var stampScope: TimeStamp.Scope {
        get { TimeStamp.scope }
        set { change { TimeStamp.scope = newValue; line.readPrivateDetails() } }
    }

    /// Kept as it is typed; the photos are stamped again once typing stops.
    var stampText: String {
        get { TimeStamp.text }
        set {
            change { TimeStamp.text = newValue }
            restamp?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.line.readPrivateDetails() }
            }
            restamp = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private var restamp: DispatchWorkItem?

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

    /// Every kind, the recommended ones, or none, from the buttons over the
    /// list.
    func hide(_ kinds: Set<PrivateDetail>) {
        guard kinds != PrivateDetails.details else { return }
        change {
            PrivateDetails.details = kinds
            line.readPrivateDetails()
        }
    }

    /// Copies made before keep their names; the photos hanging are read
    /// again, so what leaves next is named anew.
    var plainNames: Bool {
        get { Cover.plainNames }
        set { change { Cover.plainNames = newValue; line.readPrivateDetails() } }
    }

    /// Turned on, the photos hanging are read for AI chats at once, and the
    /// send button over one says so.
    var coversAllInAIChats: Bool {
        get { CoveringProfile.coversAllInAIChats }
        set {
            change {
                CoveringProfile.coversAllInAIChats = newValue
                line.readPrivateDetails()
                ChatButton.shared?.refresh()
            }
        }
    }

    /// The owner's own rules, edited in place. They are saved a moment
    /// after the typing stops, since each change reads every photo again.
    @Published var rules = OwnRules.all
    private var rulesSave: Task<Void, Never>?

    func addRule() {
        rules.append(OwnRule())
        saveRules()
    }

    func removeRule(_ rule: OwnRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    func rulesChanged() {
        rulesSave?.cancel()
        rulesSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveRules()
        }
    }

    // MARK: Bookkeeping

    /// The folder's name, once one is chosen.
    @Published var bookkeepingFolder = Bookkeeping.folder?.lastPathComponent
    @Published var bookkeepingAddress = Bookkeeping.address {
        didSet { Bookkeeping.address = bookkeepingAddress }
    }

    func chooseBookkeepingFolder() {
        if let url = Bookkeeping.chooseFolder() { bookkeepingFolder = url.lastPathComponent }
        refreshPackMonths()
    }

    /// The months the folder's table has receipts for, newest first, and
    /// the one chosen for a pack.
    @Published var packMonths: [String] = []
    @Published var packMonth = ""

    func refreshPackMonths() {
        packMonths = Bookkeeping.months()
        if !packMonths.contains(packMonth) { packMonth = packMonths.first ?? "" }
    }

    func makeReceiptsPack() {
        guard !packMonth.isEmpty else { return }
        Bookkeeping.makePack(month: packMonth)
    }

    // MARK: Shop header

    @Published var shopName = ShopHeader.name {
        didSet {
            ShopHeader.name = shopName
            refreshShopPreview()
        }
    }
    @Published private(set) var shopLogo: NSImage? = ShopHeader.hasLogo ? NSImage(contentsOf: ShopHeader.logoFile) : nil
    /// The band as a customer will see it, over nothing.
    @Published private(set) var shopPreview: NSImage?

    func chooseShopLogo() {
        guard ShopHeader.chooseLogo() else { return }
        shopLogo = NSImage(contentsOf: ShopHeader.logoFile)
        refreshShopPreview()
    }

    func removeShopLogo() {
        ShopHeader.removeLogo()
        shopLogo = nil
        refreshShopPreview()
    }

    func refreshShopPreview() {
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        // The band as it is on a wide screenshot, and of it the end with the
        // logo and the words, at twice the size, so they can be read.
        guard ShopHeader.isSet,
              let blank = CGContext(data: nil, width: 2080, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage(),
              let band = ShopHeader.render(blank, name: ShopHeader.name,
                                           logo: shopLogo?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                                           detail: ShopHeader.detail(order: "1024", day: Date()),
                                           rightToLeft: rightToLeft),
              let end = band.cropping(to: CGRect(x: rightToLeft ? band.width - 960 : 0, y: 0,
                                                 width: 960, height: band.height - 1))
        else {
            shopPreview = nil
            return
        }
        shopPreview = NSImage(cgImage: end, size: NSSize(width: end.width / 2, height: end.height / 2))
    }

    // MARK: Saved messages

    /// Messages kept ready for the message bar, edited in place and saved
    /// a moment after the typing stops.
    @Published var savedMessages = SavedMessages.all
    private var messagesSave: Task<Void, Never>?

    func addSavedMessage() {
        savedMessages.append(SavedMessage())
        saveSavedMessages()
    }

    func removeSavedMessage(_ message: SavedMessage) {
        savedMessages.removeAll { $0.id == message.id }
        saveSavedMessages()
    }

    func savedMessagesChanged() {
        messagesSave?.cancel()
        messagesSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveSavedMessages()
        }
    }

    func saveSavedMessages() {
        messagesSave?.cancel()
        SavedMessages.all = savedMessages
    }

    func saveRules() {
        rulesSave?.cancel()
        let before = OwnRules.fingerprint
        OwnRules.all = rules
        if OwnRules.fingerprint != before { line.readPrivateDetails() }
    }

    /// Set to bring the window up on Permissions.
    @Published var showsPermissions = false

    // MARK: About

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func checkForUpdates() {
        NSWorkspace.shared.open(AppDelegate.updatesURL)
    }
}

/// The settings window, laid out like System Settings: a sidebar with six
/// panes. It can be made larger or smaller by its edges and filled with the
/// green button, and opens at the size and place it was left.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(_ preferences: Preferences) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(prefs: preferences, line: preferences.line))
            // The window sets the size; the panes fill it.
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.title = L("Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.contentMinSize = NSSize(width: 640, height: 440)
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            // Where it was left, if it was moved or resized before.
            window.setFrameAutosaveName("SnapflySettings")
            self.window = window
        }
        preferences.refresh()
        // Tendedero lives in the menu bar, so it comes forward on purpose.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case general, line, privacy, permissions, support, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: L("General")
        case .line: L("Line")
        case .privacy: L("Privacy")
        case .permissions: L("Permissions")
        case .support: L("Support")
        case .about: L("About")
        }
    }

    /// Line shows Snapfly's own mark, the photo on the line, as the menu bar
    /// does.
    var icon: Image {
        switch self {
        case .general: Image(systemName: "gearshape")
        case .line: Image(nsImage: LineIcon.image(filled: false, description: title)).renderingMode(.template)
        case .privacy: Image(systemName: "hand.raised.fill")
        case .permissions: Image(systemName: "lock.shield.fill")
        case .support: Image(systemName: "lifepreserver.fill")
        case .about: Image(systemName: "info.circle.fill")
        }
    }

}

/// A sidebar row as System Settings draws them: the symbol on a small tile,
/// then the name. The tiles are all ink, the symbol knocked out of them, so
/// the sidebar stays quiet.
private struct PaneLabel: View {
    let pane: Pane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            Group {
                if pane == .line {
                    pane.icon.resizable().frame(width: 15, height: 15)
                } else {
                    pane.icon.font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(InkTile.glyph)
            .frame(width: 24, height: 24)
            .background(InkTile.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// A button at the trailing edge of a settings row. They all share one
/// width, so the column of buttons lines up down the pane; a longer label
/// still gets its room.
struct SettingsButton: View {
    static let width: CGFloat = 128

    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).frame(minWidth: Self.width)
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
                PaneLabel(pane: pane)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane ?? .general {
            case .general: GeneralPane(prefs: prefs)
            case .line: LinePane(prefs: prefs)
            case .privacy: PrivacyPane(prefs: prefs, line: line)
            case .permissions: PermissionsPane()
            case .support: SupportPane(prefs: prefs)
            case .about: AboutPane(prefs: prefs)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .onAppear(perform: showPermissionsIfAsked)
        .onChange(of: prefs.showsPermissions) { _, _ in showPermissionsIfAsked() }
    }

    private func showPermissionsIfAsked() {
        guard prefs.showsPermissions else { return }
        pane = .permissions
        prefs.showsPermissions = false
    }
}

private struct GeneralPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section(L("Screenshots")) {
                if Edition.appStore {
                    // Snapfly's own screenshots come first: they need
                    // nothing set up.
                    LabeledContent {
                        SettingsButton(L("Try It Now")) { prefs.tryCapture() }
                    } label: {
                        Text(L("Take screenshots with Snapfly"))
                        Text(String(format: L("Press %@ or click the screenshot button. Nothing to set up."),
                                    prefs.shortcut(.capture)))
                    }
                    // The sandbox keeps Snapfly out of the screenshot
                    // settings, so this shows where to change them.
                    LabeledContent {
                        SettingsButton(L("Set Up…")) { prefs.setUpScreenshots() }
                    } label: {
                        Text(L("Also from the Screenshot app"))
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
                Toggle(isOn: $prefs.stampsTime) {
                    Text(L("Stamp the date and time"))
                    Text(L("At the top, on the line and in a copy next to the screenshot"))
                }
                Picker(L("Which screenshots"), selection: $prefs.stampScope) {
                    Text(L("Screenshots of the whole screen")).tag(TimeStamp.Scope.wholeScreen)
                    Text(L("Every screenshot")).tag(TimeStamp.Scope.all)
                }
                .disabled(!prefs.stampsTime)
                TextField(L("Words before the date"), text: $prefs.stampText,
                          prompt: Text(L("Optional, like your shop’s name")))
                    .disabled(!prefs.stampsTime)
            } header: {
                Text(L("Time stamp"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("The screenshot itself stays as it was; the stamped copy is saved next to it."))
                    Text(L("The time comes from the PTB’s atomic clock in Germany, over the internet. Only the question for the time goes out; without a connection, the Mac’s clock is used."))
                }
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Sounds"), isOn: $prefs.sounds)
                Toggle(L("Open at login"), isOn: $prefs.opensAtLogin)
            }
            Section(L("Also watch folders")) {
                ForEach(prefs.folders, id: \.self) { folder in
                    HStack {
                        Label(Folders.placeName(folder), systemImage: "folder")
                        Spacer()
                        Button { prefs.stopWatching(folder) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("Stop Watching"))
                        .accessibilityLabel(L("Stop Watching"))
                    }
                }
                LabeledContent {
                    SettingsButton(L("Add Folder…")) { prefs.addFolder() }
                        .disabled(prefs.folders.count >= AppDelegate.maxExtraFolders)
                } label: {
                    Text(L("Watch another folder"))
                    Text(L("Pictures saved into it hang on the line too"))
                }
            }
            Section {
                LabeledContent {
                    SettingsButton(L("Show in Finder")) { prefs.openScreenshotsFolder() }
                } label: {
                    Text(L("Screenshots folder"))
                    if let folder = prefs.screenshotsFolder {
                        Text(Folders.placeName(folder))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Folders as the rows name them.
enum Folders {
    /// A folder as the Finder names it, from the home folder down, like
    /// "Pictures › Snapfly". Outside the home folder, from the top of the
    /// disk. The home folder is the user's own, even in the sandbox.
    static func placeName(_ url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        let home = Edition.home
        let top = home.standardizedFileURL.pathComponents
        var place = URL(fileURLWithPath: "/")
        var below = Array(parts.dropFirst())
        if parts.count >= top.count, Array(parts.prefix(top.count)) == top {
            place = home
            below = Array(parts.dropFirst(top.count))
        }
        var names: [String] = []
        for part in below {
            place.appendPathComponent(part)
            names.append(FileManager.default.displayName(atPath: place.path))
        }
        return names.isEmpty ? FileManager.default.displayName(atPath: url.path) : names.joined(separator: " › ")
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
                                Text(History.title(days: n)).tag(Int?.some(n))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        SettingsButton(L("History…")) { HistoryWindow.shared.show() }
                            .disabled(prefs.historyDays == nil)
                    }
                } label: {
                    Text(L("Keep a history"))
                    Text(L("What leaves the line stays in the History, from the menu bar, to find and hang again."))
                }
            }
            ChatButtonSection(prefs: prefs)
            SavedMessagesSection(prefs: prefs)
            BookkeepingSection(prefs: prefs)
            ShopHeaderSection(prefs: prefs)
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
                        // Two rows of six, so all of them fit beside the label.
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
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
                        .frame(width: 6 * 28 + 5 * 8)
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
                shortcutRow(L("Capture a whole page"), .page)
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
                SettingsButton(L("Change Shortcut…")) { prefs.changeShortcut(role) }
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
                    Text(L("ChatGPT, Claude, WhatsApp, Telegram, Messages, Mail, Outlook and others."))
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
            SettingsButton(L("Add App…")) { prefs.addChatApp() }
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

/// The styles four to a row, each as a little picture of the top of a
/// screen, to pick one by looking.
private struct StylePicker: View {
    @Binding var selection: Layout.Style

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4),
                  spacing: 14) {
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
            case .wire:
                var wire = Path()
                wire.move(to: CGPoint(x: -2, y: h * 0.2))
                wire.addLine(to: CGPoint(x: w + 2, y: h * 0.2))
                context.stroke(wire, with: .color(Color(white: 0.15, opacity: 0.85)), lineWidth: 0.8)
                for (n, fx) in [0.22, 0.5, 0.78].enumerated() {
                    Self.drawCard(in: &context, top: CGPoint(x: w * fx, y: h * 0.2 + 2), size: card,
                                  angle: .zero, accent: Self.accents[n], clip: true)
                }
            case .floating:
                for (n, fx) in [0.28, 0.5, 0.72].enumerated() {
                    Self.drawCard(in: &context, top: CGPoint(x: w * fx, y: h * 0.2), size: card,
                                  angle: .zero, accent: Self.accents[n], clip: false)
                }
            case .filmstrip:
                let strip = CGRect(x: w * 0.12, y: h * 0.13, width: w * 0.76, height: card.height + h * 0.18)
                context.fill(Path(roundedRect: strip, cornerRadius: h * 0.05, style: .continuous),
                             with: .color(Color(white: 0.09)))
                let holes = 9
                for i in 0..<holes {
                    let hx = strip.minX + strip.width * (CGFloat(i) + 0.5) / CGFloat(holes) - 1.5
                    for hy in [strip.minY + h * 0.025, strip.maxY - h * 0.025 - 2] {
                        context.fill(Path(roundedRect: CGRect(x: hx, y: hy, width: 3, height: 2), cornerRadius: 0.5),
                                     with: .color(Color(white: 0.85)))
                    }
                }
                for n in 0..<3 {
                    let x = strip.minX + strip.width * (0.2 + 0.28 * CGFloat(n))
                    Self.drawCard(in: &context, top: CGPoint(x: x, y: strip.minY + h * 0.09), size: card,
                                  angle: .zero, accent: Self.accents[n], clip: false)
                }
            case .fan:
                for (n, k) in [-1.0, 0.0, 1.0].enumerated() {
                    let x = w * 0.5 + CGFloat(k) * w * 0.22
                    let y = h * 0.18 + CGFloat(k * k) * h * 0.06
                    Self.drawCard(in: &context, top: CGPoint(x: x, y: y), size: card,
                                  angle: .degrees(-9 * k), accent: Self.accents[n], clip: false)
                }
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
                // Every kind at once, the recommended ones, or none. The
                // three share the row in equal parts.
                HStack(spacing: 8) {
                    choiceButton(L("Check All"), Set(PrivateDetail.allCases))
                    choiceButton(L("Recommended"), PrivateDetail.recommended)
                    choiceButton(L("Uncheck All"), [])
                }
                .controlSize(.small)
            } header: {
                Text(L("Hide private details"))
            } footer: {
                Text(L("What is checked is covered in whatever leaves the line"))
                    .foregroundStyle(.secondary)
            }
            ForEach(PrivateDetail.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(group.kinds, id: \.self) { detail in
                        Toggle(detail.title, isOn: prefs.hides(detail))
                    }
                }
            }
            Section {
                Toggle(L("Cover everything in AI chats"), isOn: $prefs.coversAllInAIChats)
            } footer: {
                Text(L("Whatever is sent or copied while ChatGPT, Claude, Gemini or another AI chat is in front has every kind above covered, checked or not."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Plain file names"), isOn: $prefs.plainNames)
            } footer: {
                Text(L("Pictures leave as fresh files, without notes on when, where or with what they were made. With plain file names they are called “Image” too, not after when they were taken."))
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach($prefs.rules) { $rule in
                    OwnRuleRow(rule: $rule) { prefs.removeRule(rule) }
                }
                Button(L("Add Rule")) { prefs.addRule() }
            } header: {
                Text(L("Also hide"))
            } footer: {
                Text(L("Words are covered wherever they appear. After a label, what follows it is covered: the rest of the line, or the line below."))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: prefs.rules) { _, _ in prefs.rulesChanged() }
            .onDisappear { prefs.saveRules() }
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
        }
        .formStyle(.grouped)
    }

    private func choiceButton(_ title: String, _ kinds: Set<PrivateDetail>) -> some View {
        Button { prefs.hide(kinds) } label: {
            Text(title).frame(maxWidth: .infinity)
        }
    }
}

/// Where receipts go for the books, and who keeps them.
private struct BookkeepingSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(prefs.bookkeepingFolder ?? L("Not chosen yet"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    SettingsButton(L("Choose…")) { prefs.chooseBookkeepingFolder() }
                }
            } label: {
                Text(L("Folder"))
                Text(L("Receipts saved for the books go here, each with a line in Snapfly.csv."))
            }
            TextField(L("Email"), text: $prefs.bookkeepingAddress, prompt: Text(L("Who keeps the books")))
            LabeledContent {
                HStack(spacing: 8) {
                    Picker(L("Month"), selection: $prefs.packMonth) {
                        ForEach(prefs.packMonths, id: \.self) { month in
                            Text(ReceiptsPack.title(month: month)).tag(month)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    SettingsButton(L("Make PDF")) { prefs.makeReceiptsPack() }
                }
                .disabled(prefs.packMonths.isEmpty)
            } label: {
                Text(L("Monthly pack"))
                Text(L("A month's receipts in one PDF, with a page listing them, to hand to your tax advisor."))
            }
        } header: {
            Text(L("Bookkeeping"))
        } footer: {
            Text(L("A photo's menu saves it here, or puts it in a new email, covered, named with its day, order and total."))
                .foregroundStyle(.secondary)
        }
        .onAppear { prefs.refreshPackMonths() }
    }
}

/// The shop's name and logo, for the band of Send with Shop Header.
private struct ShopHeaderSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section {
            TextField(L("Shop name"), text: $prefs.shopName, prompt: Text(L("Your shop's name")))
            LabeledContent {
                HStack(spacing: 8) {
                    if let logo = prefs.shopLogo {
                        Image(nsImage: logo)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .accessibilityHidden(true)
                        Button { prefs.removeShopLogo() } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove"))
                        .accessibilityLabel(L("Remove"))
                    }
                    SettingsButton(L("Choose…")) { prefs.chooseShopLogo() }
                }
            } label: {
                Text(L("Logo"))
                Text(L("A square picture works best."))
            }
            if let preview = prefs.shopPreview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: preview.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .accessibilityLabel(L("Preview"))
            }
        } header: {
            Text(L("Shop header"))
        } footer: {
            Text(L("Send with Shop Header, in a photo's menu, puts a band with your shop's name and logo, the order and the day above the covered screenshot."))
                .foregroundStyle(.secondary)
        }
        .onAppear { prefs.refreshShopPreview() }
    }
}

/// Messages kept ready above the message bar, with blanks the photo fills.
private struct SavedMessagesSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section {
            ForEach($prefs.savedMessages) { $message in
                HStack(spacing: 8) {
                    TextField(L("Message"), text: $message.text,
                              prompt: Text(L("Here is the invoice for your order {order}.")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button { prefs.removeSavedMessage(message) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remove"))
                    .accessibilityLabel(L("Remove"))
                }
            }
            Button(L("Add Message")) { prefs.addSavedMessage() }
        } header: {
            Text(L("Saved messages"))
        } footer: {
            Text(L("They wait above the message bar. {order}, {total}, {date}, {name} and {tracking} fill in from the photo; one of a kind you cover stays empty."))
                .foregroundStyle(.secondary)
        }
        .onChange(of: prefs.savedMessages) { _, _ in prefs.savedMessagesChanged() }
        .onDisappear { prefs.saveSavedMessages() }
    }
}

/// One rule of the owner's own: what kind it is, the text, and a way to
/// take it away. A pattern that cannot be read says so under the field.
private struct OwnRuleRow: View {
    @Binding var rule: OwnRule
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker(rule.kind.title, selection: $rule.kind) {
                    ForEach(OwnRule.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                TextField(rule.kind.title, text: $rule.text, prompt: Text(rule.kind.prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if !rule.isReadable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(L("Remove"))
                .accessibilityLabel(L("Remove"))
            }
            if !rule.isReadable {
                Text(L("This pattern cannot be read."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
            // Who made it, and whose it is.
            HStack(spacing: 5) {
                Text(L("Made by"))
                    .foregroundStyle(.secondary)
                Text(verbatim: AppDelegate.author)
                    .fontWeight(.semibold)
            }
            .padding(.top, 22)
            Text(verbatim: "© \(Calendar.current.component(.year, from: Date())) \(AppDelegate.author)")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            if !Edition.appStore {
                Button(L("Check for Updates…")) { prefs.checkForUpdates() }
                    .padding(.top, 18)
            }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
