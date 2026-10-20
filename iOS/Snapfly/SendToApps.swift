import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sending a covered copy to an app with one tap, as from under a photo on
/// the Mac: the same apps, chosen and ordered in Settings. A tap puts the
/// covered copy on the clipboard and opens the app, or its website without
/// it, to paste it there; an iPhone app can't put a picture into another
/// app's chat itself.
@MainActor
final class SendApps: ObservableObject {
    static let shared = SendApps()

    /// Those turned on, in their order.
    @Published private(set) var chosen = ChatTarget.onPhoneNow()
    /// Every app there is to choose on the iPhone, in their order.
    @Published private(set) var all = ChatTarget.phoneChoices()

    func set(_ chat: ChatTarget, on: Bool) {
        ChatTarget.setShows(on, chat)
        reload()
    }

    /// The iPhone's apps in a new order; the two editors keep their place
    /// after them.
    func move(from offsets: IndexSet, to offset: Int) {
        var order = all
        order.move(fromOffsets: offsets, toOffset: offset)
        ChatTarget.setOrder(order + ChatTarget.ordered().filter { !$0.onPhone })
        reload()
    }

    private func reload() {
        chosen = ChatTarget.onPhoneNow()
        all = ChatTarget.phoneChoices()
    }

    /// Puts the covered pictures on the clipboard, then opens the app, else
    /// its website; false when nothing could be opened.
    func send(_ pngs: [Data], to chat: ChatTarget) async -> Bool {
        guard !pngs.isEmpty else { return false }
        UIPasteboard.general.setItems(pngs.map { [UTType.png.identifier: $0] as [String: Any] })
        for link in chat.phoneLinks {
            if await UIApplication.shared.open(link) { return true }
        }
        return false
    }
}

extension ChatTarget {
    /// Its icon in the asset catalogue, drawn as its app's icon is: the logo
    /// to the edges, or the mark on white (`assets/chat-logos/README.md`).
    var phoneIcon: String? {
        switch self {
        case .chatGPT: "LogoChatGPT"
        case .claude: "ChatClaude"
        case .perplexity: "ChatPerplexity"
        case .grok: "ChatGrok"
        case .deepSeek: "ChatDeepSeek"
        case .qwen: "ChatQwen"
        case .whatsApp: "LogoWhatsApp"
        case .messenger: "ChatMessenger"
        case .instagram: "ChatInstagram"
        case .gmail: "ChatGmail"
        case .outlook: "ChatOutlook"
        case .yahoo: "ChatYahoo"
        case .gmx: "ChatGMX"
        case .webDe: "LogoWebDE"
        case .facebook: "ChatFacebook"
        case .airbnb: "ChatAirbnb"
        case .vsCode, .antigravity: nil
        }
    }
}

/// An app's icon: rounded as the Home Screen draws app icons, or round as
/// the Mac's under a photo, with a hairline so a white one keeps its edge.
struct AppIcon: View {
    let chat: ChatTarget
    var size: CGFloat = 52
    var round = false

    var body: some View {
        let shape = round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 12 / 52, style: .continuous))
        Group {
            if let name = chat.phoneIcon {
                Image(name)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text(verbatim: chat.mark)
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The apps chosen, side by side as in the share sheet, each its icon with
/// its name under it, scrolling sideways; a tap sends to it, and More, at
/// the end, chooses the apps. The one sending shows a spinner.
struct AppTiles: View {
    @ObservedObject private var apps = SendApps.shared
    let busy: ChatTarget?
    let send: (ChatTarget) -> Void
    @State private var choosing = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(apps.chosen) { chat in
                    Button { send(chat) } label: {
                        tile(name: chat.name) {
                            AppIcon(chat: chat)
                                .overlay {
                                    if busy == chat {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.black.opacity(0.35))
                                        ProgressView().tint(.white)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                    .accessibilityLabel(String(format: L("Send to %@"), chat.name))
                }
                Button { choosing = true } label: {
                    tile(name: L("More")) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: "ellipsis")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Send to Apps"))
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $choosing) { ChooseAppsSheet() }
    }

    private func tile(name: String, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 6) {
            icon()
            Text(verbatim: name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 64)
        .contentShape(Rectangle())
    }
}

/// The apps chosen, as round icons in a floating capsule over the picture,
/// like those under a photo on the Mac; ⋯ chooses them. One tapped before
/// the copy is ready waits, with a spinner, and goes once it is.
struct AppCircles: View {
    @ObservedObject private var apps = SendApps.shared
    let pending: Leaving?
    let leave: (Leaving) -> Void
    @State private var choosing = false

    var body: some View {
        // With none chosen, the row stays away; Settings chooses them.
        if !apps.chosen.isEmpty {
            ViewThatFits(in: .horizontal) {
                row.padding(.horizontal, 8).fixedSize()
                ScrollView(.horizontal) { row.padding(.horizontal, 8) }
                    .scrollIndicators(.hidden)
            }
            .padding(.vertical, 5)
            .editorGlass(in: Capsule())
            .padding(.horizontal, 16)
            .sheet(isPresented: $choosing) { ChooseAppsSheet() }
        }
    }

    private var row: some View {
        // Each 44 pt to the finger, so the circles stand 10 pt apart.
        HStack(spacing: 0) {
            ForEach(apps.chosen) { chat in
                Button { leave(.app(chat)) } label: {
                    AppIcon(chat: chat, size: 34, round: true)
                        .overlay {
                            if pending == .app(chat) {
                                Circle().fill(.black.opacity(0.35))
                                ProgressView().controlSize(.small).tint(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: L("Send to %@"), chat.name))
                .accessibilityHint(pending == .app(chat) ? L("Goes as soon as the copy is ready.") : "")
            }
            Button { choosing = true } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Send to Apps"))
        }
    }
}

/// Which apps show, and in which order: each with its switch, dragged by
/// its handle into place.
struct ChooseApps: View {
    @ObservedObject private var apps = SendApps.shared

    var body: some View {
        List {
            Section {
                ForEach(apps.all) { chat in
                    Toggle(isOn: Binding(get: { apps.chosen.contains(chat) }, set: { apps.set(chat, on: $0) })) {
                        HStack(spacing: 12) {
                            AppIcon(chat: chat, size: 29)
                            Text(verbatim: chat.name)
                        }
                    }
                }
                .onMove { apps.move(from: $0, to: $1) }
            } footer: {
                Text(L("A tap on an app copies the covered picture and opens the app. Hold in its message box and tap Paste. Without the app, its website opens."))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("Send to Apps"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The choice of apps in a sheet of its own, from the row's More.
private struct ChooseAppsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChooseApps()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
