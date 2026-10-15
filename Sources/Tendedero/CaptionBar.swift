import AppKit
import SwiftUI

/// A line to write a message in, just above the chat button: a press and
/// hold on the button opens it, Return sends the photos with the message
/// after them, as one message in the chat, and Escape closes it. Like the
/// search bar, it takes the keyboard without bringing Snapfly to the front,
/// so the chat stays the app in front and gets the paste.
@MainActor
final class CaptionBar: NSObject, NSWindowDelegate {
    static let shared = CaptionBar()

    static let width: CGFloat = 340
    /// Room around the bar for its shadow.
    static let margin: CGFloat = 20

    private var panel: CaptionPanel?

    var isOpen: Bool { panel != nil }

    /// - Parameter anchor: the chat button's capsule, in screen coordinates;
    ///   the bar's trailing edge lines up with it, just above.
    func show(above anchor: CGRect, count: Int, send: @escaping (String) -> Void) {
        close()
        let view = CaptionBarView(count: count, send: { [weak self] text in
            // The keyboard goes back to the chat before anything is pasted.
            self?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { send(text) }
        }, close: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = CaptionPanel()
        panel.contentView = host
        panel.delegate = self
        var origin = CGPoint(x: anchor.maxX + Self.margin - size.width, y: anchor.maxY + 6 - Self.margin)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX - Self.margin), visible.maxX - size.width + Self.margin)
            origin.y = min(origin.y, visible.maxY - size.height + Self.margin)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// A click in another app puts it away, as it does the search bar.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

private final class CaptionPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    // Typing needs a key window; a non-activating panel can be one without
    // bringing the app forward.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The field and the send button, in the chat button's own glyph and color.
private struct CaptionBarView: View {
    let count: Int
    let send: (String) -> Void
    let close: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("Add a message…"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: close)
            Text(count, format: .number)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .help(String(format: L("%d photos"), count))
                .accessibilityLabel(String(format: L("%d photos"), count))
            Button(action: submit) {
                Image(systemName: ChatButton.symbol.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ChatButton.tint.glyph)
                    .frame(width: 30, height: 30)
                    .background(ChatButton.tint.color, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("Send"))
            .accessibilityLabel(L("Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .frame(width: CaptionBar.width, height: 44)
        .background(bar)
        .padding(CaptionBar.margin)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    private func submit() {
        send(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The search bar's glass, in a capsule.
    @ViewBuilder
    private var bar: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }
}
