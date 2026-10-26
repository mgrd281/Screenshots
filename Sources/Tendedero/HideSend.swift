import AppKit
import SwiftUI

/// Where the covered copy of a photo or PDF from Finder goes, straight from
/// Hide Private Details: into a chat, an AI chat or a mailbox, onto the
/// clipboard, or through the Mac's own Share menu.
enum CopySend {
    case chat(ChatTarget), copy, share
}

/// The chats as the line shows them under a photo, each a click away, the
/// rest under ⋯, then Copy and Share.
struct SendBar: View {
    let busy: Bool
    let send: (CopySend) -> Void

    /// Those on for photos, or the usual six when none are.
    private var shown: [ChatTarget] {
        let on = ChatTarget.onPhotosNow
        return Array((on.isEmpty ? ChatTarget.allCases.filter(\.isStandard) : on).prefix(Self.most))
    }

    private var rest: [ChatTarget] {
        ChatTarget.ordered().filter { !shown.contains($0) }
    }

    private static let most = 6
    static let tile: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Send covered"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(shown) { chat in
                    SendTile(chat: chat) { send(.chat(chat)) }
                }
                if !rest.isEmpty {
                    Menu {
                        ForEach(rest) { chat in
                            Button(chat.name) { send(.chat(chat)) }
                        }
                    } label: {
                        MoreChatsIcon(size: Self.tile)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("More"))
                    .accessibilityLabel(L("More"))
                }
                Spacer(minLength: 4)
                tool("doc.on.doc", L("Copy")) { send(.copy) }
                tool("square.and.arrow.up", L("Share…")) { send(.share) }
            }
        }
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: Self.tile, height: Self.tile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A chat's icon that lifts a little under the pointer, as a photo's row
/// on the line does.
private struct SendTile: View {
    let chat: ChatTarget
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ChatIcon(chat: chat, size: SendBar.tile)
                .scaleEffect(hovering && !reduceMotion ? 1.1 : 1)
                .animation(Motion.spring(response: 0.25, damping: 0.7, reduced: reduceMotion), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(format: L("Send to %@"), chat.name))
        .accessibilityLabel(String(format: L("Send to %@"), chat.name))
    }
}

extension HideEditor {
    /// Where a copy to send is written: a folder of its own, under the
    /// original's name, so that is the name the chat shows, or “Image” or
    /// “Document” where the line's copies would be called so
    /// (`Cover.newCopy`). Copies from before last week go.
    static func sendFile(for url: URL, covering chosen: Set<PrivateDetail>) -> URL? {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("Snapfly Send", isDirectory: true)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        for folder in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            let made = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if made < weekAgo { try? fm.removeItem(at: folder) }
        }
        let folder = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        let own = url.deletingPathExtension().lastPathComponent
        let plain = Cover.plainNames || Cover.nameHolds(own, chosen)
        let name = (plain ? (isDocument(url) ? L("Document") : L("Image")) : own) + "." + SaveCopy.fileExtension(for: url)
        return folder.appendingPathComponent(name)
    }

    /// On the clipboard as the picture, for apps that paste pictures, and
    /// as the file, for those that take files, like a PDF.
    static func clip(_ file: URL) {
        let entry = NSPasteboardItem()
        switch file.pathExtension.lowercased() {
        case "png":
            if let data = try? Data(contentsOf: file) { entry.setData(data, forType: .png) }
        case "jpg", "jpeg":
            if let data = try? Data(contentsOf: file) {
                entry.setData(data, forType: NSPasteboard.PasteboardType("public.jpeg"))
            }
        default:
            break
        }
        entry.setString(file.absoluteString, forType: .fileURL)
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([entry])
    }
}
