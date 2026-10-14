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

    static func intoFrontApp() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard frontApp != nil, AXIsProcessTrustedWithOptions(prompt) else { return }
        // A moment for the app to see the new clipboard before reading it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
