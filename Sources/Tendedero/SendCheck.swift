import AppKit
import SwiftUI

/// Check Before Sending, from Settings › Privacy: before photos go into an
/// AI chat, or an app or website Snapfly doesn't know as a chat, a card
/// shows them as they will go and what is covered in them. Return sends
/// them, Escape keeps them on the line. Like the message bar, the card takes
/// the keyboard without bringing Snapfly to the front, so the chat stays the
/// app in front and gets the paste.
@MainActor
final class SendCheck: NSObject, NSWindowDelegate {
    static let shared = SendCheck()

    enum When: String, CaseIterable, Identifiable {
        case aiAndUnknown, always, never

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aiAndUnknown: L("In AI chats and unknown apps")
            case .always: L("Every time")
            case .never: L("Never")
            }
        }
    }

    /// Why the card shows.
    enum Reason: Equatable {
        case aiChat, unknownPlace, everySend
    }

    /// Never unless changed: a click on a chat sends at once, and the card is
    /// for whoever turns it on.
    nonisolated static var when: When {
        get { UserDefaults.standard.string(forKey: "checkBeforeSending").flatMap(When.init(rawValue:)) ?? .never }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "checkBeforeSending") }
    }

    /// Why photos going to an app, or a website open in a browser, get the
    /// card first; nil when they go at once. A chat app counts as known even
    /// with the send button turned off for it, and a browser whose page
    /// can't be read is an unknown place.
    nonisolated static func reason(_ when: When, app: String?, host: String?, inBrowser: Bool,
                                   chatApps: Set<String>, chatSites: [String]) -> Reason? {
        guard when != .never else { return nil }
        if CoveringProfile.isAIChat(app: app, host: host) { return .aiChat }
        let known: Bool
        if inBrowser {
            let host = host?.lowercased() ?? ""
            known = !host.isEmpty && chatSites.contains { host == $0 || host.hasSuffix("." + $0) }
        } else {
            known = app.map { chatApps.contains($0) } ?? false
        }
        if !known { return .unknownPlace }
        return when == .always ? .everySend : nil
    }

    /// Why photos sent now get the card first, for the app in front.
    static var reasonNow: Reason? {
        let when = Self.when
        guard when != .never, let app = Paste.frontApp?.bundleIdentifier else { return nil }
        let inBrowser = ChatButton.browserIDs.contains(app)
        // Asking a browser for its page takes a moment: only in a browser.
        let host = inBrowser ? ChatButton.shared?.siteInFront ?? ChatButton.pageInFront()?.host : nil
        return reason(when, app: app, host: host, inBrowser: inBrowser,
                      chatApps: Set(ChatButton.apps.map(\.bundleID)), chatSites: ChatButton.sites.map(\.host))
    }

    // MARK: The card

    static let width: CGFloat = 380
    /// Room around the card for its shadow.
    static let margin: CGFloat = 28

    private var panel: SendCheckPanel?
    private var send: (() -> Void)?

    var isOpen: Bool { panel != nil }

    /// - Parameters:
    ///   - files: the copies that will go, covered, one a photo.
    ///   - sentBefore: sends of photos like these, newest first.
    ///   - anchor: the send button over the chat, to sit just above it; else
    ///     the card sits under the line.
    ///   - send: sends them, once Return or Send is pressed.
    func show(_ files: [URL], to destination: String, reason: Reason, covered: CoverReport, hides: Bool,
              sentBefore: [SendLog.Sent], above anchor: CGRect?, send: @escaping () -> Void) {
        close()
        self.send = send
        let thumbs = files.prefix(4).compactMap { makeThumbnail($0, maxPixels: 240) }
        let sentLine: String? = switch sentBefore.count {
        case 0: nil
        case _ where files.count == 1: SendLog.sentence(sentBefore[0])
        default: String(format: L("Sent before: %1$d of %2$d"), sentBefore.count, files.count)
        }
        let view = SendCheckView(destination: destination, thumbs: thumbs, more: max(0, files.count - thumbs.count),
                                 covered: hides ? covered.sentence ?? L("Nothing private found") : L("Hide private details is off."),
                                 sent: sentLine, reason: reason,
                                 send: { [weak self] in self?.confirm() }, cancel: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = SendCheckPanel()
        panel.contentView = host
        panel.delegate = self
        panel.onReturn = { [weak self] in self?.confirm() }
        panel.onEscape = { [weak self] in self?.close() }
        panel.setFrame(CGRect(origin: origin(for: size, above: anchor), size: size), display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// Above the send button over the chat, its trailing edge on the
    /// button's, as the message bar sits; else under the line, at the top of
    /// the screen with the pointer. Always on the screen.
    private func origin(for size: CGSize, above anchor: CGRect?) -> CGPoint {
        let pointer = NSEvent.mouseLocation
        let screen = anchor.flatMap { button in NSScreen.screens.first { $0.frame.intersects(button) } }
            ?? NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin: CGPoint
        if let anchor {
            origin = CGPoint(x: anchor.maxX + Self.margin - size.width, y: anchor.maxY + 6 - Self.margin)
        } else {
            // Below the strip the line hangs in.
            let line = Layout.photoMaxHeight + 106
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - line - size.height + Self.margin)
        }
        origin.x = min(max(origin.x, visible.minX - Self.margin + 8), visible.maxX - size.width + Self.margin - 8)
        origin.y = min(max(origin.y, visible.minY - Self.margin + 8), visible.maxY - size.height + Self.margin - 8)
        return origin
    }

    /// The keyboard goes back to the chat before anything is pasted.
    private func confirm() {
        guard let send else { return }
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { send() }
    }

    /// Put away without sending: the photos stay on the line.
    func close() {
        send = nil
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// A click in another app puts it away, unsent, as it does the message bar.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Takes the keyboard without bringing Snapfly forward, and hears Return
/// and Escape even when no button has the focus.
private final class SendCheckPanel: NSPanel {
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}

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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn()
        case 53: onEscape()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}

/// A floating card in the text card's look: what goes, what is covered in
/// it, and Send.
private struct SendCheckView: View {
    let destination: String
    let thumbs: [NSImage]
    /// Photos going beyond those shown.
    let more: Int
    let covered: String
    let sent: String?
    let reason: SendCheck.Reason
    let send: () -> Void
    let cancel: () -> Void

    private var note: String? {
        switch reason {
        case .aiChat: L("AI chats can keep what they are sent.")
        case .unknownPlace: L("Snapfly doesn't know this app or website as a chat.")
        case .everySend: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(16)
        .frame(width: SendCheck.width, alignment: .leading)
        .background(card)
        .padding(SendCheck.margin)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(String(format: L("Send to %@?"), destination))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L("Close"))
            .accessibilityLabel(L("Close"))
        }
    }

    /// The copies as they will go, then what is covered in them and when
    /// photos like them went before.
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(thumbs.enumerated()), id: \.offset) { _, thumb in
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 76, maxHeight: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
                if more > 0 {
                    Text(verbatim: "+\(more)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .accessibilityHidden(true)
            row("lock.fill", covered)
            if let sent { row("paperplane.fill", sent) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(L("Don't Send"), action: cancel)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            Button(action: send) {
                Label(L("Send"), systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}
