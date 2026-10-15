import AppKit
import Carbon

/// A global shortcut through the Carbon hot key API. Unlike a global key
/// monitor, it needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    /// What each shortcut does, by the role it plays.
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    /// Nil when the combination cannot be registered, for example because
    /// another app, or the other shortcut, already took it.
    init?(_ shortcut: Shortcut, for role: Shortcut.Role, action: @escaping () -> Void) {
        HotKey.actions[role.rawValue] = action
        // One handler for the app, however many times the shortcuts change.
        if !HotKey.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let role = pressed.id
                DispatchQueue.main.async { HotKey.actions[role]?() }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5445_4E44), id: role.rawValue) // "TEND"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}

/// A global shortcut: one that shows and hides the line, ⌃⌥T unless
/// changed, one that sends the newest photo, ⌃⌥V, one that searches, ⌃⌥F,
/// one that takes a screenshot, ⌃⌥S, and one that starts and stops a screen
/// recording, ⌃⌥R. Each can be none.
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags
    /// The key as typed, for the menu: "t", " ", "1".
    var key: String

    enum Role: UInt32, CaseIterable {
        /// Shows and hides the line.
        case toggle = 1
        /// Pastes the photos picked, or the newest one, into the app in front.
        case send = 2
        /// Brings the line down with the search bar under it.
        case search = 3
        /// Takes a screenshot from Snapfly itself.
        case capture = 4
        /// Starts a screen recording from Snapfly itself, or stops it.
        case record = 5

        var standard: Shortcut {
            switch self {
            case .toggle: Shortcut(keyCode: kVK_ANSI_T, modifiers: [.control, .option], key: "t")
            case .send: Shortcut(keyCode: kVK_ANSI_V, modifiers: [.control, .option], key: "v")
            case .search: Shortcut(keyCode: kVK_ANSI_F, modifiers: [.control, .option], key: "f")
            case .capture: Shortcut(keyCode: kVK_ANSI_S, modifiers: [.control, .option], key: "s")
            case .record: Shortcut(keyCode: kVK_ANSI_R, modifiers: [.control, .option], key: "r")
            }
        }

        fileprivate var defaultsKey: String {
            switch self {
            case .toggle: "shortcut"
            case .send: "sendShortcut"
            case .search: "searchShortcut"
            case .capture: "captureShortcut"
            case .record: "recordShortcut"
            }
        }
    }

    /// The user's choice. Nil means no shortcut at all.
    static func current(_ role: Role) -> Shortcut? {
        guard let saved = UserDefaults.standard.dictionary(forKey: role.defaultsKey) else { return role.standard }
        guard let code = saved["keyCode"] as? Int, let flags = saved["modifiers"] as? UInt,
              let key = saved["key"] as? String else { return nil }
        return Shortcut(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags), key: key)
    }

    static func save(_ shortcut: Shortcut?, for role: Role) {
        UserDefaults.standard.set(shortcut.map {
            ["keyCode": $0.keyCode, "modifiers": $0.modifiers.rawValue, "key": $0.key] as [String: Any]
        } ?? [:], forKey: role.defaultsKey)
    }

    /// From a key press, if it makes a usable global shortcut: it needs
    /// Command, Control or Option, so typing alone never triggers it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: flags, key: key)
    }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    var carbonModifiers: Int {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return carbon
    }

    /// As macOS writes it in menus: ⌃⌥⇧⌘ and the key.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (key == " " ? L("Space") : key.uppercased())
    }
}

/// Asks for a new shortcut in a small window: the next key press with
/// Command, Control or Option becomes it. Escape cancels and Delete leaves
/// the line without a shortcut.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    static let shared = ShortcutRecorder()

    private var window: NSWindow?
    private var monitor: Any?
    private var done: ((Shortcut??) -> Void)?

    /// Calls back with the new shortcut, `.some(nil)` for none, or nil if
    /// cancelled.
    func record(_ done: @escaping (Shortcut??) -> Void) {
        finish(nil)
        self.done = done

        let title = NSTextField(labelWithString: L("Press the new shortcut"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(labelWithString: L("Escape cancels. Delete removes the shortcut."))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Change Shortcut")
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if event.keyCode == UInt16(kVK_Escape) && plain {
                self.finish(nil)
            } else if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) && plain {
                self.finish(.some(nil))
            } else if let shortcut = Shortcut(event: event) {
                self.finish(.some(shortcut))
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        finish(nil)
    }

    private func finish(_ result: Shortcut??) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let done = self.done
        self.done = nil
        window?.close()
        window = nil
        done?(result)
    }
}
