import AppKit

/// A transparent strip along the top of the screen that floats over every
/// app and every Space except full screen ones, never takes focus, and lets clicks pass through
/// everywhere except over the photos.
final class LinePanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // Every Space, full screen ones included. Whether the line comes down
        // over a full screen app is up to the user, see FullScreen.showLineOver.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = content
    }

    /// Two-finger swipes and the scroll wheel, for moving along a long line.
    var onScroll: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let onScroll {
            onScroll(event)
        } else {
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The line hangs on the screen you are using, which is the one with the
    /// pointer: that is where you just took the screenshot.
    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    func placeOnScreen(_ screen: NSScreen? = nil) {
        guard let visible = (screen ?? LinePanel.screenUnderPointer())?.visibleFrame else { return }
        // Moved down with its grip, the line still slides out from under the
        // menu bar, so the strip reaches up to it.
        let height = Layout.panelHeight + min(Layout.drop, Self.lowestDrop(in: visible))
        let target = NSRect(x: visible.minX, y: visible.maxY - height,
                            width: visible.width, height: height)
        if frame != target { setFrame(target, display: true) }
    }

    /// How far below the menu bar the line hangs on this screen.
    var drop: CGFloat { max(0, frame.height - Layout.panelHeight) }

    /// As low as the line goes: its photos stay above the bottom of the screen.
    private static func lowestDrop(in visible: NSRect) -> CGFloat {
        max(0, visible.height - Layout.panelHeight)
    }

    /// Dragging the grip on the line's tag moves it up or down. It hangs
    /// there from then on, on any screen with room for it.
    func moveLine(to drop: CGFloat) {
        guard let screen else { return }
        Layout.drop = min(max(0, drop), Self.lowestDrop(in: screen.visibleFrame))
        placeOnScreen(screen)
    }
}
