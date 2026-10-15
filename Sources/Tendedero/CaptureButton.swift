import AppKit
import SwiftUI

/// One click, one screenshot: a small glass button that floats at the edge
/// of the screen, over every app. A click chooses an area, takes the whole
/// screen at once, or takes the last area again, as chosen in Settings.
/// While the screen is recorded it turns into the stop button. Drag it
/// anywhere; it remembers the spot. It is never in what it takes.
@MainActor
final class CaptureButton {
    static let shared = CaptureButton()

    /// What a click does.
    enum Click: String, CaseIterable {
        case choose, screen, lastArea
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "captureButton") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "captureButton")
            shared.update()
        }
    }

    static var click: Click {
        get { Click(rawValue: UserDefaults.standard.string(forKey: "captureButtonClick") ?? "") ?? .choose }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "captureButtonClick") }
    }

    var openSettings: () -> Void = {}

    private var panel: CaptureButtonPanel?
    private let model = CaptureButtonModel()
    private static let originKey = "captureButtonOrigin"

    func update() {
        if Self.isEnabled {
            show()
        } else {
            panel?.orderOut(nil)
            panel = nil
        }
    }

    func recordingChanged() {
        model.recording = Recording.shared.isRecording
        panel?.content.setAccessibilityLabel(model.recording ? L("Stop Recording") : L("Take Screenshot"))
        panel?.content.toolTip = model.recording ? L("Stop Recording") : L("Take Screenshot")
    }

    private func show() {
        if panel == nil {
            let panel = CaptureButtonPanel(model: model)
            panel.content.onClick = { [weak self] in self?.pressed() }
            panel.content.onDragEnd = { [weak self] in self?.remember() }
            panel.content.menu = makeMenu()
            panel.setFrameOrigin(savedOrigin(for: panel.frame.size) ?? defaultOrigin(for: panel.frame.size))
            self.panel = panel
        }
        recordingChanged()
        panel?.orderFrontRegardless()
    }

    private func pressed() {
        if Recording.shared.isRecording {
            Recording.shared.stop()
            return
        }
        switch Self.click {
        case .choose:
            Capture.shared.start()
        case .screen:
            guard let screen = screenOfButton else { return Capture.shared.start() }
            Capture.shared.takeNow(.screen(screen))
        case .lastArea:
            guard let region = Capture.shared.lastArea else { return Capture.shared.start() }
            Capture.shared.takeNow(region)
        }
    }

    private var screenOfButton: NSScreen? {
        guard let frame = panel?.frame else { return nil }
        return NSScreen.screens.first { NSMouseInRect(CGPoint(x: frame.midX, y: frame.midY), $0.frame, false) }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(L("Choose an area")) { Capture.shared.start(after: 0.2) })
        menu.addItem(ClosureMenuItem(L("Take the whole screen")) { [weak self] in
            guard let screen = self?.screenOfButton else { return }
            // Once the menu has faded, so it is not in the picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { Capture.shared.takeNow(.screen(screen)) }
            }
        })
        menu.addItem(ClosureMenuItem(L("Record Screen")) { Capture.shared.start(after: 0.2, mode: .record) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Hide Screenshot Button")) { CaptureButton.isEnabled = false })
        menu.addItem(ClosureMenuItem(L("Settings…")) { [weak self] in self?.openSettings() })
        return menu
    }

    // MARK: Where it sits

    private func remember() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: Self.originKey)
    }

    /// Where it was dragged, while that is still on a screen.
    private func savedOrigin(for size: CGSize) -> CGPoint? {
        guard let saved = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], saved.count == 2 else {
            return nil
        }
        let origin = CGPoint(x: saved[0], y: saved[1])
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return NSScreen.screens.contains { NSMouseInRect(center, $0.visibleFrame, false) } ? origin : nil
    }

    /// At first on the trailing edge of the main screen, a little above the
    /// middle, out of the way of windows' own controls.
    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let visible = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let x = rightToLeft ? visible.minX + 8 : visible.maxX - size.width - 8
        return CGPoint(x: x, y: visible.minY + visible.height * 0.6)
    }
}

@MainActor
final class CaptureButtonModel: ObservableObject {
    @Published var recording = false
}

/// The button's own window: never key, so the app in front keeps the
/// keyboard, and above other apps' windows.
private final class CaptureButtonPanel: NSPanel {
    /// Room around the circle for its shadow.
    static let margin: CGFloat = 12

    let content: CaptureButtonView

    init(model: CaptureButtonModel) {
        content = CaptureButtonView(model: model, margin: Self.margin)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = content
        content.layoutSubtreeIfNeeded()
        setContentSize(content.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the clicks and drags itself, as the chat button does: the panel
/// never becomes key, so only a view of its own takes the first click.
private final class CaptureButtonView: NSView {
    var onClick: () -> Void = {}
    var onDragEnd: () -> Void = {}

    private let host: NSHostingView<CaptureButtonLabel>
    private var downAt: CGPoint?
    private var startOrigin: CGPoint?
    private var isDragging = false

    init(model: CaptureButtonModel, margin: CGFloat) {
        host = NSHostingView(rootView: CaptureButtonLabel(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            host.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("Take Screenshot"))
        toolTip = L("Take Screenshot")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Only the circle takes the pointer; the shadow's margin lets it through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return host.frame.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt, let startOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - downAt.x, dy = now.y - downAt.y
        if !isDragging, hypot(dx, dy) < 4 { return }
        isDragging = true
        window.setFrameOrigin(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            downAt = nil
            startOrigin = nil
            isDragging = false
        }
        if isDragging {
            onDragEnd()
        } else if downAt != nil {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// A camera viewfinder on a glass circle; while recording, a white stop on
/// record red.
private struct CaptureButtonLabel: View {
    @ObservedObject var model: CaptureButtonModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        ZStack {
            if model.recording {
                Circle().fill(Color.red)
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .controlGlass(circle: true)
            }
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(hasLiquidGlass ? 0 : 0.18), radius: 6, y: 3)
        .scaleEffect(hovering && !reduceMotion ? 1.08 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.spring(response: 0.3, damping: 0.8, reduced: reduceMotion), value: hovering)
        .animation(.easeOut(duration: 0.15), value: model.recording)
        .accessibilityHidden(true)
    }
}
