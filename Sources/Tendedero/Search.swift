import AppKit
import SwiftUI

/// The words in every photo on the line, read once in the background, so
/// Search finds them as you type. Read on this Mac, kept in memory only,
/// and forgotten when a photo leaves the line.
@MainActor
enum TextIndex {
    struct Row: Sendable {
        /// The line's text, as read.
        let text: String
        /// The same, folded so case and accents do not matter.
        let folded: String
        /// Where it sits, from 0 to 1 from the bottom left.
        let box: CGRect
    }

    private static var rows: [String: [Row]] = [:]
    private static var reading: Set<String> = []
    private static let queue = DispatchQueue(label: "de.ghazarian.Snapfly.search", qos: .utility)

    /// Called each time a photo has been read.
    static var onRead: (() -> Void)?

    /// Rechnung, rechnung and RECHNUNG are one word, and so are café and cafe.
    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func rows(for url: URL) -> [Row]? {
        key(for: url).flatMap { rows[$0] }
    }

    /// Reads a photo's words, unless they are already known. A photo edited
    /// in Markup is read again.
    static func read(_ url: URL) {
        guard isImage(url), let key = key(for: url), rows[key] == nil, !reading.contains(key) else { return }
        reading.insert(key)
        queue.async {
            let found = Finder.lines(of: url).map { Row(text: $0.text, folded: fold($0.text), box: $0.box) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    reading.remove(key)
                    rows[key] = found
                    onRead?()
                }
            }
        }
    }

    static func keep(only paths: Set<String>) {
        rows = rows.filter { paths.contains(path(of: $0.key)) }
    }

    private static func key(for url: URL) -> String? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return nil }
        return "\(url.path)|\(date.timeIntervalSinceReferenceDate)"
    }

    private static func path(of key: String) -> String {
        key.components(separatedBy: "|").dropLast().joined(separator: "|")
    }
}

// MARK: - The search bar

/// A bar under the line to type into. It takes the keyboard without
/// bringing Snapfly to the front, so the app you were in stays in front for
/// sending what you find. Return picks what was found, Escape closes.
@MainActor
final class SearchBar: NSObject, NSWindowDelegate {
    static let shared = SearchBar()

    static let width: CGFloat = 440

    private var panel: SearchPanel?
    private weak var line: Line?

    var isOpen: Bool { panel != nil }

    /// - Parameter top: the middle of the bar's top edge, in screen coordinates.
    func show(for line: Line, at top: CGPoint) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        self.line = line
        line.beginSearch()
        let view = SearchBarView(line: line) { [weak self] in self?.close() }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = SearchPanel()
        panel.contentView = host
        panel.delegate = self
        panel.setFrame(NSRect(x: top.x - size.width / 2, y: top.y - size.height, width: size.width, height: size.height),
                       display: false)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        line?.endSearch()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    /// A click in another app puts the search away.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

private final class SearchPanel: NSPanel {
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

private struct SearchBarView: View {
    @ObservedObject var line: Line
    let close: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var count: Int { line.found?.count ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(L("Search screenshots"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit {
                        guard count > 0 else { return NSSound.beep() }
                        line.pickFound()
                        close()
                    }
                    .onExitCommand(perform: close)
                    .onChange(of: text) { _, now in line.search(now) }
                status
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("Close"))
                .accessibilityLabel(L("Close"))
            }
            .padding(.horizontal, 16)
            .frame(width: SearchBar.width, height: 50)
            .background(bar)

            Text(L("Return picks them, ready to send."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .controlGlass(capsule: true)
                .opacity(count > 0 ? 1 : 0)
        }
        .padding(24)
        .animation(.easeOut(duration: 0.15), value: count)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    @ViewBuilder
    private var status: some View {
        if line.found != nil {
            Text(count > 0 ? String(format: L("%d found"), count) : L("No matches"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((count > 0 ? Color.accentColor : Color.primary).opacity(0.1), in: Capsule())
                .fixedSize()
        }
        if line.stillReading > 0 {
            ProgressView().controlSize(.small)
        }
    }

    /// Like Spotlight: Liquid Glass on macOS 26, lifted a little off the
    /// desktop; frosted glass before it.
    @ViewBuilder
    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }
}
