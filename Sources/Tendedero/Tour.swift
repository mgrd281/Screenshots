import AppKit
import SwiftUI

/// The welcome tour: five cards on what Snapfly does and where to find it,
/// from the line to what stays private. It shows once on a Mac, at the
/// first launch of a version that has it; Welcome Tour in the menu bar
/// shows it again.
@MainActor
final class Tour: NSObject, NSWindowDelegate {
    static let shared = Tour()

    private static let shownKey = "tourShown"
    private var window: NSWindow?
    private var then: (() -> Void)?

    /// Whether it has shown once on this Mac.
    static var wasShown: Bool {
        get { UserDefaults.standard.bool(forKey: shownKey) }
        set { UserDefaults.standard.set(newValue, forKey: shownKey) }
    }

    /// One card: a symbol, a title and a few lines.
    struct Page: Equatable {
        let symbol: String
        let title: String
        let text: String
    }

    /// The cards, in order. The screenshot card names the shortcut chosen
    /// for it, or the menu bar's Take Screenshot without one; the others
    /// name the places in Settings as Settings names them.
    static func pages(capture: String?) -> [Page] {
        let still = capture.map {
            String(format: L("Press %@ and the screen holds still: drag over an area, click a window, or press Return for the whole screen."), $0)
        } ?? String(format: L("Choose %@ in the menu bar and the screen holds still: drag over an area, click a window, or press Return for the whole screen."),
                    L("Take Screenshot"))
        let icons = [L("Settings"), L("Line"), L("Icons under photos")].joined(separator: " › ")
        let privacy = [L("Settings"), L("Privacy")].joined(separator: " › ")
        return [
            Page(symbol: "menubar.rectangle", title: L("Your screenshots hang on a line"),
                 text: L("Rest the pointer in the menu bar and the line comes down, with every screenshot you took. Click one to copy it, or drag it into any app.")),
            Page(symbol: "viewfinder", title: L("Take just the part you need"), text: still),
            Page(symbol: "paperplane", title: L("Send in one click"),
                 text: String(format: L("Rest the pointer on a photo: the icons under it send it into ChatGPT, Claude, WhatsApp or your mail. Choose which show in %@."), icons)),
            Page(symbol: "contextualmenu.and.cursorarrow", title: L("More in a photo's menu"),
                 text: L("Right-click a photo to crop it, draw on it, hide a part, translate its words and more. ⌥-click crops it at once.")),
            Page(symbol: "hand.raised", title: L("Private details stay private"),
                 text: String(format: L("Names, addresses, bank details and more are covered in whatever leaves the line. Choose what in %@."), privacy)),
        ]
    }

    /// Shows the tour, calling back once it is closed.
    func show(then: (() -> Void)? = nil) {
        Self.wasShown = true
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.then = then
        let view = TourView(pages: Self.pages(capture: Shortcut.current(.capture)?.display)) { [weak self] in
            self?.window?.performClose(nil)
        }
        let window = TourWindow(contentViewController: NSHostingController(rootView: view))
        window.title = L("Welcome to Snapfly")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        // Snapfly lives in the menu bar, so it comes forward on purpose.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        let then = self.then
        self.then = nil
        // After the window, so what follows comes up on its own.
        DispatchQueue.main.async { MainActor.assumeIsolated { then?() } }
    }
}

/// Escape closes the tour wherever the keyboard is in it.
private final class TourWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// A card at a time, the dots saying which, and Skip, Back and Next.
private struct TourView: View {
    let pages: [Tour.Page]
    let close: () -> Void

    @State private var index = 0
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            card(pages[index])
                .id(index)
                .transition(transition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            dots
                .padding(.bottom, 20)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 440, height: 380)
    }

    private func card(_ page: Tour.Page) -> some View {
        VStack(spacing: 14) {
            Image(systemName: page.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(page.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }

    /// Which card, as dots: the accent for this one.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("Step %1$d of %2$d"), index + 1, pages.count))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isLast {
                Button(L("Skip"), action: close)
                    .buttonStyle(.link)
            }
            Spacer()
            if index > 0 {
                Button(L("Back")) { go(by: -1) }
                    .buttonStyle(.bordered)
            }
            Button {
                if isLast { close() } else { go(by: 1) }
            } label: {
                if isLast {
                    Label(L("Done"), systemImage: "checkmark")
                } else {
                    Label(L("Next"), systemImage: "arrow.forward")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(by step: Int) {
        forward = step > 0
        withAnimation(Motion.spring(response: 0.35, damping: 0.85, reduced: reduceMotion)) {
            index = min(max(0, index + step), pages.count - 1)
        }
    }

    /// The next card comes in from the reading direction's end and the one
    /// before leaves towards its start; with Reduce Motion they only fade.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let ahead: CGFloat = (forward ? 24 : -24) * (layoutDirection == .rightToLeft ? -1 : 1)
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: ahead)),
                           removal: .opacity.combined(with: .offset(x: -ahead)))
    }
}
