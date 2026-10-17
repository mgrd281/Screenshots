import AppKit
import SwiftUI

/// The history in a window: what left the line, newest first and grouped by
/// day, with a search through the words in each photo. A click hangs one
/// on the line again; Send Again sends it into the chat once more.
@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()

    /// Hangs a photo on the line, flying in as a new capture does.
    var onHang: (URL) -> Void = { _ in }
    /// Hangs a photo on the line and sends it into the app that was in
    /// front before the window.
    var onSendAgain: (URL) -> Void = { _ in }

    private var window: NSWindow?
    private let model = HistoryModel()

    func show() {
        History.purge()
        model.reload()
        if window == nil {
            let host = NSHostingController(rootView: HistoryView(model: model, hang: { [weak self] url in
                self?.onHang(url)
            }, sendAgain: { [weak self] url in
                self?.onSendAgain(url)
            }))
            // The search field and the clear button go in the window's toolbar.
            host.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: host)
            window.title = L("History")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 540))
            window.contentMinSize = NSSize(width: 480, height: 360)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("History")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.search = ""
    }
}

/// The entries the window shows, with their thumbnails, made off the main
/// thread as they are needed.
@MainActor
final class HistoryModel: ObservableObject {
    @Published var entries: [History.Entry] = []
    @Published var thumbs: [String: NSImage] = [:]
    @Published var search = ""
    /// Bumped when the words of a photo are known, so search sees them.
    @Published private var readCount = 0

    init() {
        History.onChange = { [weak self] in self?.reload() }
        let previous = TextIndex.onRead
        TextIndex.onRead = { [weak self] in
            previous?()
            self?.readCount += 1
        }
    }

    func reload() {
        entries = History.entries
        for entry in entries where thumbs[entry.path] == nil {
            let url = entry.url
            DispatchQueue.global(qos: .userInitiated).async {
                let image = makeThumbnail(url, maxPixels: 480)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.thumbs[url.path] = image ?? NSImage() }
                }
            }
            TextIndex.read(url)
        }
    }

    /// Every word typed must be in the photo's text or its name.
    var shown: [History.Entry] {
        _ = readCount
        let terms = TextIndex.fold(search).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            let words = (TextIndex.rows(for: entry.url) ?? []).map(\.folded).joined(separator: " ")
                + " " + TextIndex.fold(entry.url.lastPathComponent)
            return terms.allSatisfy { words.contains($0) }
        }
    }

    /// The shown entries by day, newest day first.
    var days: [(day: Date, entries: [History.Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.left) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.left > $1.left }) }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let hang: (URL) -> Void
    let sendAgain: (URL) -> Void
    @State private var confirmClear = false

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        // "Today" and "Yesterday", in the user's language.
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        Group {
            if model.entries.isEmpty {
                empty
            } else if model.shown.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else {
                grid
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .searchable(text: $model.search, placement: .toolbar, prompt: Text(L("Search…")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label(L("Clear History…"), systemImage: "trash")
                }
                .help(L("Clear History…"))
                .disabled(model.entries.isEmpty)
            }
        }
        .confirmationDialog(L("Clear the history?"), isPresented: $confirmClear) {
            Button(L("Clear History"), role: .destructive) { History.clear() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The photos kept in it go to the Trash."))
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(L("No history yet"), systemImage: "clock.arrow.circlepath")
        } description: {
            if let days = History.days {
                Text(String(format: L("Photos that leave the line stay here for %d days."), days))
            } else {
                Text(L("History is off. Turn it on in Settings, under Line."))
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(model.days, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.dayFormat.string(from: group.day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(group.entries) { entry in
                                HistoryCard(entry: entry, thumb: model.thumbs[entry.path], hang: hang, sendAgain: sendAgain)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

/// One photo: a click hangs it on the line again; its menu does the rest.
private struct HistoryCard: View {
    let entry: History.Entry
    let thumb: NSImage?
    let hang: (URL) -> Void
    let sendAgain: (URL) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let thumb, thumb.size.width > 0 {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 112)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.uturn.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                    .padding(8)
                    .opacity(hovering ? 1 : 0)
            }
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 10, y: 5)
            .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
            Text(Self.timeFormat.string(from: entry.left))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.spring(response: 0.25, damping: 0.85, reduced: reduceMotion), value: hovering)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(entry.url) }
        .onTapGesture { takeBack() }
        .help(L("Hang on the line"))
        .contextMenu {
            Button(L("Hang on the line")) { takeBack() }
            Button(L("Send Again")) { send() }
            Button(L("Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([entry.url as NSURL])
            }
            Button(L("Open")) { NSWorkspace.shared.open(entry.url) }
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Divider()
            Button(L("Remove from History"), role: .destructive) { History.remove(entry) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.url.deletingPathExtension().lastPathComponent)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { takeBack() }
    }

    private func takeBack() {
        guard let url = History.takeBack(entry) else { return }
        hang(url)
    }

    private func send() {
        guard let url = History.takeBack(entry) else { return }
        sendAgain(url)
    }
}
