import AppKit
import ApplicationServices
import Carbon
import QuartzCore
import SwiftUI

/// Another app's file dialog, its Open window, as a website shows it to
/// attach a file. While one is in front the line comes down with an arrow
/// from the newest photo to it, and a photo sent goes into the dialog,
/// chosen there, rather than pasted.
///
/// Finding the dialog needs Accessibility, as pasting does, so the store
/// edition, which may only press keys, pastes as before.
@MainActor
enum OpenPanel {
    /// Where the Open window in front is, in AppKit screen coordinates, or
    /// nil when there is none or Accessibility may not say.
    static func frontFrame() -> CGRect? {
        guard !Edition.appStore, AXIsProcessTrusted(), let app = Paste.frontApp else { return nil }
        if let frame = openPanel(in: app.processIdentifier) { return frame }
        // A sandboxed app's dialog belongs to macOS's own service.
        for pid in serviceProcesses() {
            if let frame = openPanel(in: pid) { return frame }
        }
        return nil
    }

    static var isInFront: Bool { frontFrame() != nil }

    /// The photos' copies, chosen in the Open window in front, after the
    /// flight there. Stops at once should the window have gone, so no key
    /// ever lands in another app.
    static func choose(_ files: [URL], after delay: TimeInterval) {
        guard !files.isEmpty, Paste.askToBeAllowed(), let placed = place(files) else { return }
        let steps = OpenPanelPlan.steps(for: placed.files.map(\.path), in: placed.folder.path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + delay) {
            // Not before the send shortcut's keys are let go, a second at most.
            MainActor.assumeIsolated { whenKeysReleased(tries: 50) { run(steps[...]) } }
        }
    }

    // MARK: Finding it

    /// An NSOpenPanel says what it is to Accessibility: "open-panel".
    private static let identifier = "open-panel"

    private static func openPanel(in pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        // A busy app must not hold up the main thread.
        AXUIElementSetMessagingTimeout(app, 0.15)
        for window in elements(app, kAXWindowsAttribute) {
            if string(window, "AXIdentifier") == identifier { return frame(of: window) }
            // A sheet on a window, as Safari and Mail show it.
            for child in elements(window, kAXChildrenAttribute)
            where string(child, kAXRoleAttribute) == kAXSheetRole && string(child, "AXIdentifier") == identifier {
                return frame(of: child)
            }
        }
        return nil
    }

    /// The processes showing a sandboxed app's file dialog on screen.
    private static func serviceProcesses() -> [pid_t] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let owners = Set(list.compactMap { $0[kCGWindowOwnerPID as String] as? Int }.map { pid_t($0) })
        return owners.filter { pid in
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?
                .hasPrefix("com.apple.appkit.xpc.openAndSavePanelService") == true
        }
    }

    private static func elements(_ parent: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// An element's frame, which Accessibility gives from the top left of the
    /// main screen, turned into AppKit's, from the bottom left.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue, let main = NSScreen.screens.first else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(x: position.x, y: main.frame.maxY - position.y - size.height, width: size.width, height: size.height)
    }

    // MARK: Choosing the photos

    /// The copies in a folder of their own, each under its own name, for
    /// the dialog to go to.
    private static func place(_ files: [URL]) -> (folder: URL, files: [URL])? {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Snapfly Upload", isDirectory: true)
        // Those from before have done their work.
        try? manager.removeItem(at: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        var placed: [URL] = []
        for (file, name) in zip(files, OpenPanelPlan.names(files.map(\.lastPathComponent))) {
            let target = folder.appendingPathComponent(name)
            guard (try? manager.copyItem(at: file, to: target)) != nil else { return nil }
            placed.append(target)
        }
        return (folder, placed)
    }

    /// - Parameter confirmed: whether Return was pressed already, after
    ///   which a window gone has opened the photo.
    private static func run(_ steps: ArraySlice<OpenPanelPlan.Step>, confirmed: Bool = false) {
        guard let step = steps.first else { return }
        // The dialog went meanwhile: what is left would land elsewhere.
        guard isInFront else {
            if !confirmed { Notice.show(L("The file window closed before the photo could go into it.")) }
            return
        }
        let rest = steps.dropFirst()
        if case .wait(let seconds) = step {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { run(rest, confirmed: confirmed) }
            }
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        switch step {
        case .goTo: press(kVK_ANSI_G, [.maskCommand, .maskShift], source)
        case .selectAll: press(kVK_ANSI_A, .maskCommand, source)
        case .confirm: press(kVK_Return, [], source)
        case .type(let text):
            for chunk in OpenPanelPlan.chunks(of: text) {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.flags = []
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event?.post(tap: .cghidEventTap)
                }
            }
        case .wait: break
        }
        run(rest, confirmed: confirmed || step == .confirm)
    }

    /// Goes on once no modifier is held, as after the send shortcut, or
    /// after the tries.
    private static func whenKeysReleased(tries: Int, then go: @escaping @MainActor () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        guard !held.isEmpty, tries > 0 else { return go() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            MainActor.assumeIsolated { whenKeysReleased(tries: tries - 1, then: go) }
        }
    }

    private static func press(_ key: Int, _ flags: CGEventFlags, _ source: CGEventSource?) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Looks out for an Open window in front while photos hang, and says when
/// one comes and when it goes.
@MainActor
final class OpenPanelWatch {
    static let shared = OpenPanelWatch()

    var onAppear: ((CGRect) -> Void)?
    var onDisappear: (() -> Void)?

    private var timer: Timer?
    private(set) var frame: CGRect?

    /// Watches while there are photos to send, and rests otherwise.
    func watch(_ on: Bool) {
        let on = on && !Edition.appStore
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        } else if !on, let timer {
            timer.invalidate()
            self.timer = nil
            if frame != nil {
                frame = nil
                onDisappear?()
            }
        }
    }

    private func check() {
        let now = OpenPanel.frontFrame()
        defer { frame = now }
        if let now, frame == nil {
            onAppear?(now)
        } else if now == nil, frame != nil {
            onDisappear?()
        }
    }
}

/// The arrow from the newest photo to an Open window: a round chip in the
/// tag's look, its arrow turned toward the window, that travels there once
/// and rests at its edge until the window goes.
@MainActor
final class OpenPanelArrow {
    static let shared = OpenPanelArrow()

    /// The chip's side, and the room round it for its shadow.
    static let side: CGFloat = 28
    private static let room: CGFloat = 12

    private var window: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(from start: CGPoint, to end: CGPoint) {
        hide(now: true)
        // It has said its piece: it goes after a while, should the window stay.
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        let angle = Angle(radians: -atan2(end.y - start.y, end.x - start.x))
        let size = Self.side + Self.room * 2
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ArrowChip(angle: angle))
        func frame(at point: CGPoint) -> CGRect {
            CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        }
        window = panel
        panel.alphaValue = 0
        if Motion.reduced {
            // Only a short fade, where it rests.
            panel.setFrame(frame(at: end), display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
            return
        }
        panel.setFrame(frame(at: start), display: false)
        panel.orderFrontRegardless()
        // Fades in as it leaves, then travels once on ease.out.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame(at: end), display: true)
        }
    }

    /// Fades out over 0.2 s, or at once.
    func hide(now: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        guard let panel = window else { return }
        window = nil
        if now {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

/// The chip: an arrow on the glass of the tag and the other floating controls.
private struct ArrowChip: View {
    let angle: Angle

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .rotationEffect(angle)
            .frame(width: OpenPanelArrow.side, height: OpenPanelArrow.side)
            .controlGlass(circle: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
