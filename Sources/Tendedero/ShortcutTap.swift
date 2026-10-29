import AppKit
import Carbon

/// While another app shows a menu, macOS holds back hot keys: the key goes
/// to the menu, which closes, and the shortcut does nothing. With
/// Accessibility, as pasting has it, this hears the screenshot and
/// recording shortcuts before any app does, keeps them from the menu and
/// does what they do, so a screenshot takes the menu still open. It hears
/// only these shortcuts; every other key goes on untouched. Used on the
/// main thread only, where its tap runs too.
final class ShortcutTap {
    static let shared = ShortcutTap()

    /// The shortcuts heard this way: those that take what is on screen.
    static let roles: [Shortcut.Role] = [.capture, .record]

    var onPress: (@MainActor (Shortcut.Role) -> Void)?

    private var shortcuts: [Shortcut.Role: Shortcut] = [:]
    private var tap: CFMachPort?
    /// The key of a shortcut kept from the app in front, whose release is kept too.
    private var keptKey: Int64?
    private var retry: Timer?

    /// Listens for these shortcuts, those of `roles` among them, or for
    /// none.
    func listen(for all: [Shortcut.Role: Shortcut]) {
        shortcuts = all.filter { Self.roles.contains($0.key) }
        if shortcuts.isEmpty { stop() } else { start() }
    }

    private func start() {
        guard tap == nil, !Edition.appStore else { return }
        guard AXIsProcessTrusted() else {
            // Allowed later, as for the first paste: it starts then.
            guard retry == nil else { return }
            retry = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.retry?.invalidate()
                self.retry = nil
                if !self.shortcuts.isEmpty { self.start() }
            }
            return
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: shortcutTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func stop() {
        retry?.invalidate()
        retry = nil
        keptKey = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS turns a slow tap off; it goes straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            guard key == keptKey else { return Unmanaged.passUnretained(event) }
            keptKey = nil
            return nil
        }
        guard type == .keyDown,
              let role = shortcuts.first(where: { Self.matches($0.value, key: key, flags: event.flags) })?.key else {
            return Unmanaged.passUnretained(event)
        }
        keptKey = key
        // Once, however long it is held.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let press = onPress
            DispatchQueue.main.async { MainActor.assumeIsolated { press?(role) } }
        }
        return nil
    }

    /// Whether a key press is the shortcut: its key, and exactly its
    /// Command, Control, Option and Shift.
    static func matches(_ shortcut: Shortcut, key: Int64, flags: CGEventFlags) -> Bool {
        guard key == Int64(shortcut.keyCode) else { return false }
        var wanted: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { wanted.insert(.maskCommand) }
        if shortcut.modifiers.contains(.control) { wanted.insert(.maskControl) }
        if shortcut.modifiers.contains(.option) { wanted.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.shift) { wanted.insert(.maskShift) }
        return flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]) == wanted
    }
}

/// The tap runs on the main run loop, where the shortcuts are kept.
private let shortcutTapCallback: CGEventTapCallBack = { _, type, event, info in
    guard let info else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ShortcutTap>.fromOpaque(info).takeUnretainedValue()
    return tap.handle(type, event)
}
