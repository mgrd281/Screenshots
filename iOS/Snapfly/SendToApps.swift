import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The apps a covered copy goes to, as from under a photo on the Mac: the
/// same apps, chosen and ordered in Settings. How it reaches each is
/// `Handoff`'s.
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

    /// The iPhone's apps in a new order; those it doesn't offer keep their
    /// place after them.
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

}

/// Hands covered pictures to another app the ways iOS gives an app, never
/// through a website: one picture straight to WhatsApp, as a file only it
/// opens (`ChatTarget.PhoneHandoff`); one to an AI chat by opening its app
/// with the picture on the clipboard, to paste there; anything else, or an
/// app that does not open, through the system's share sheet, where every
/// app that takes pictures shows and the owner taps it. With a question for
/// an AI chat, the share sheet too, the question going with the pictures.
/// Only the protected copy is ever handed over: the files are written for
/// it alone and deleted once it is done, and the clipboard keeps it ten
/// minutes at most. Nothing goes until the owner sends it in that app.
@MainActor
final class Handoff: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = Handoff()

    /// WhatsApp's menu while it shows, with its file and what to call.
    private var interaction: UIDocumentInteractionController?
    private var finished: ((Bool) -> Void)?
    private var handedOver = false

    /// Hands the pictures to an app, or, with none named, to whatever the
    /// owner picks in the share sheet; with a question for an AI chat, the
    /// share sheet, the question after the pictures. `opened` runs when an
    /// AI chat's app opened with the picture to paste, and `done` says
    /// whether they went. False when nothing could be shown.
    @discardableResult
    func send(_ pngs: [Data], to chat: ChatTarget?, named name: String, asking question: String? = nil,
              opened: @escaping () -> Void = {}, done: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !pngs.isEmpty, let host = Self.presenter() else { return false }
        #if DEBUG
        HandoffAudit.shared.handed(pngs)
        #endif
        if let question { return share(pngs, named: name, saying: question, from: host, done: done) }
        switch chat?.phoneHandoff(pictures: pngs.count) {
        case .direct?:
            if openInWhatsApp(pngs[0], named: name, from: host, done: done) { return true }
        case .openApp?:
            guard let chat else { break }
            Task {
                if await openApp(chat, with: pngs[0]) {
                    opened()
                    done(true)
                } else if let host = Self.presenter(), share(pngs, named: name, from: host, done: done) {
                    // Not on this iPhone: the share sheet, which offers what there is.
                } else {
                    done(false)
                }
            }
            return true
        case .shareSheet?, nil:
            break
        }
        // WhatsApp missing, or any other app: the share sheet, which offers what there is.
        return share(pngs, named: name, from: host, done: done)
    }

    /// The picture on the clipboard, for ten minutes, and the app opened by
    /// its own links, a website's only as the app's, never in a browser.
    /// False where none of them opens it.
    private func openApp(_ chat: ChatTarget, with png: Data) async -> Bool {
        UIPasteboard.general.setItems([[UTType.png.identifier: png]],
                                      options: [.expirationDate: Date.now.addingTimeInterval(600)])
        for link in chat.phoneAppLinks {
            let options: [UIApplication.OpenExternalURLOptionsKey: Any] = link.scheme == "https" ? [.universalLinksOnly: true] : [:]
            if await UIApplication.shared.open(link, options: options) { return true }
        }
        return false
    }

    /// The share sheet with the pictures as files, and the question after
    /// them where there is one.
    private func share(_ pngs: [Data], named name: String, saying question: String? = nil, from host: UIViewController,
                       done: @escaping (Bool) -> Void) -> Bool {
        guard let files = try? Self.write(pngs, named: name, as: "png") else { return false }
        var items: [Any] = files
        if let question { items.append(question) }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Nothing a protected picture has any use for.
        sheet.excludedActivityTypes = [.assignToContact, .addToReadingList]
        sheet.completionWithItemsHandler = { activity, completed, _, _ in
            // An app's own sheet cancelled leaves the share sheet up, for another.
            guard completed || activity == nil else { return }
            Self.remove(files)
            done(completed)
        }
        // On the iPhone the share sheet rises from the bottom, anchored to nothing.
        host.present(sheet, animated: true)
        return true
    }

    /// WhatsApp's own way in: the picture as a `.wai` file of the type only
    /// WhatsApp opens, so its menu offers WhatsApp, which then asks whom to
    /// send it to. False where WhatsApp isn't there to take it.
    private func openInWhatsApp(_ png: Data, named name: String, from host: UIViewController,
                                done: @escaping (Bool) -> Void) -> Bool {
        guard let file = try? Self.write([png], named: name, as: "wai").first else { return false }
        let menu = UIDocumentInteractionController(url: file)
        menu.uti = "net.whatsapp.image"
        menu.delegate = self
        let point = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        guard menu.presentOpenInMenu(from: point, in: host.view, animated: true) else {
            Self.remove([file])
            return false
        }
        // Kept until the next hand-over, so it lives as long as WhatsApp needs it.
        interaction = menu
        finished = done
        handedOver = false
        return true
    }

    func documentInteractionController(_ controller: UIDocumentInteractionController,
                                       willBeginSendingToApplication application: String?) {
        handedOver = true
    }

    func documentInteractionController(_ controller: UIDocumentInteractionController,
                                       didEndSendingToApplication application: String?) {
        handedOver = true
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        finished?(handedOver)
        finished = nil
        // Once WhatsApp has taken its copy of the file.
        if let file = controller.url {
            Task {
                try? await Task.sleep(for: .seconds(30))
                Self.remove([file])
            }
        }
    }

    /// The pictures as files of their own, in a folder of their own, named
    /// as the copy is; protected while the iPhone is locked.
    nonisolated private static func write(_ pngs: [Data], named name: String, as kind: String) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Handoff/\(UUID().uuidString)",
                                                                                  isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try pngs.enumerated().map { index, png in
            let file = folder.appendingPathComponent(pngs.count == 1 ? name : "\(name) \(index + 1)")
                .appendingPathExtension(kind)
            try png.write(to: file, options: [.atomic, .completeFileProtection])
            return file
        }
    }

    nonisolated private static func remove(_ files: [URL]) {
        for folder in Set(files.map { $0.deletingLastPathComponent() }) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// What shows on top, to show the share sheet or the menu over it.
    private static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
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
                    .accessibilityIdentifier("send-\(chat.rawValue)")
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

/// The ways a protected copy leaves, one above another beside the picture:
/// the apps chosen, as their own icons with nothing round them or under
/// them, then Photos, Files and the share sheet as plain tiles of the same
/// size; they scroll when they don't fit. A tap hands over the copy, with a
/// light haptic; one tapped before the copy is ready waits, with a spinner,
/// and goes once it is. Held, each offers the choice of apps. Turned off,
/// as after a failure, each is dimmed.
struct AppRail: View {
    @ObservedObject private var apps = SendApps.shared
    let pending: Leaving?
    let leave: (Leaving) -> Void
    @State private var choosing = false
    @State private var taps = 0

    /// The width it takes beside the picture.
    static let width: CGFloat = 44

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
            ScrollView(.vertical) { column }
                .scrollIndicators(.hidden)
        }
        .frame(width: Self.width)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sheet(isPresented: $choosing) { ChooseAppsSheet() }
    }

    private var column: some View {
        VStack(spacing: 8) {
            ForEach(apps.chosen) { chat in
                way(.app(chat), label: String(format: L("Send to %@"), chat.name)) {
                    AppIcon(chat: chat, size: RailTile.size)
                }
            }
            way(.photos, label: Leaving.photos.title) { RailTile(symbol: "photo.on.rectangle.angled") }
            way(.files, label: Leaving.files.title) { RailTile(symbol: "folder") }
            way(.share, label: Leaving.share.title) { RailTile(symbol: "square.and.arrow.up") }
        }
        .padding(.vertical, 4)
    }

    private func way(_ way: Leaving, label: String, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            taps += 1
            leave(way)
        } label: {
            icon()
                .overlay {
                    if pending == way {
                        RoundedRectangle(cornerRadius: RailTile.corner, style: .continuous).fill(.black.opacity(0.35))
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .frame(width: Self.width, height: Self.width)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailPress())
        .contextMenu {
            Button { choosing = true } label: { Label(L("Send to Apps"), systemImage: "slider.horizontal.3") }
        }
        .accessibilityLabel(label)
        .accessibilityHint(pending == way ? L("Goes as soon as the copy is ready.") : "")
    }
}

/// Photos, Files or the share sheet on the rail: a glyph on a plain tile
/// the size of an app's icon, with the same corners and hairline.
struct RailTile: View {
    let symbol: String

    static let size: CGFloat = 40
    static var corner: CGFloat { size * 12 / 52 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: Self.size, height: Self.size)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A rail icon pressed: a little smaller, back on a quick spring; with
/// Reduce Motion, a little dimmer instead. Off, as after a failure, it is
/// dimmed, so it doesn't look ready to tap.
private struct RailPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
                Text(L("A tap hands the protected copy to the app. WhatsApp opens with it; ChatGPT, Claude and the other AI chats open with it copied, to paste; the rest from the share sheet, where you tap the app. Nothing opens in a browser."))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("Send to Apps"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The choice of apps in a sheet of its own, from the row's More or the
/// editor's menu.
struct ChooseAppsSheet: View {
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
