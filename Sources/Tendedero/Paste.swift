import AppKit
import ApplicationServices
import Carbon

/// Pastes what is on the clipboard into the app in front, as if ⌘V were
/// pressed there. The line never takes focus, so the app in front is still
/// the one you were typing in, like the message box of a chat.
///
/// Pressing a key in another app needs the Accessibility permission, the
/// only thing in Tendedero that does, and it is asked for the first time
/// it is used. Until it is given, the photos are still on the clipboard,
/// for a ⌘V by hand.
@MainActor
enum Paste {
    /// The app a paste lands in, unless that is Tendedero itself.
    static var frontApp: NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
    }

    /// Whether a paste would happen now, without asking for anything.
    static var willPaste: Bool { frontApp != nil && AXIsProcessTrusted() }

    /// - Parameter delay: how long to wait first, so the paste lands with
    ///   the photos flying over.
    static func intoFrontApp(after delay: TimeInterval = 0) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard frontApp != nil, AXIsProcessTrustedWithOptions(prompt) else { return }
        // At least a moment for the app to see the new clipboard before reading it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + delay) { pressCommandV() }
    }

    /// ⌘V, once the keys of the send shortcut are let go, so the app in
    /// front never sees ⌃⌥ held with it. Waits a second at most.
    nonisolated private static func pressCommandV(tries: Int = 50) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        guard held.isEmpty || tries == 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { pressCommandV(tries: tries - 1) }
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Where a paste shows up on the given screen, in AppKit screen
    /// coordinates: the field being typed in, like a chat's message box,
    /// near its start; else the bottom of the app's window, where message
    /// boxes sit; else the bottom of the screen.
    static func landingPoint(on screen: NSScreen) -> CGPoint {
        let bottom = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 90)
        guard let app = frontApp else { return bottom }
        let system = AXUIElementCreateSystemWide()
        if let field = element(system, kAXFocusedUIElementAttribute), let frame = frame(of: field),
           frame.height < 200, screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            return CGPoint(x: frame.minX + min(70, frame.width / 2), y: frame.midY)
        }
        if let window = element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
           let frame = frame(of: window), screen.frame.contains(CGPoint(x: frame.midX, y: frame.minY + 90)) {
            return CGPoint(x: frame.midX, y: frame.minY + 90)
        }
        return bottom
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// An element's frame, which Accessibility gives from the top left of the
    /// main screen, turned into AppKit's, from the bottom left.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute),
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0,
              let main = NSScreen.screens.first else { return nil }
        return CGRect(x: position.x, y: main.frame.maxY - position.y - size.height, width: size.width, height: size.height)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
