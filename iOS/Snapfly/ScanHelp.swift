import SwiftUI
import UIKit
#if DEBUG
import CryptoKit
#endif

/// Over a photo chosen in Photos that looks like a photographed paper
/// document (`DocumentPhoto`): the offer to straighten and brighten it as a
/// scan is, while that is done, and once done what was done, with Undo.
/// Never shown for a screenshot, and nothing changes until it is tapped.
struct DocumentOfferBanner: View {
    @ObservedObject var session: ProtectSession
    @State private var dismissed = false

    var body: some View {
        Group {
            if session.cleaned {
                card(symbol: "checkmark.seal", tint: SnapflyTokens.protectTint,
                     text: L("Straightened and brightened. Its covers were found again on the cleaned page.")) {
                    Button(L("Revert")) { session.undoCleaning() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("photo-clean-undo")
                }
                .accessibilityIdentifier("photo-cleaned")
            } else if session.cleaning {
                card(symbol: nil, tint: .secondary, text: L("Straightening and brightening…")) { EmptyView() }
            } else if let note = session.cleaningNote {
                card(symbol: "exclamationmark.triangle", tint: SnapflyTokens.scanWarnText, text: note) {
                    close { session.cleaningNote = nil }
                }
            } else if session.documentPage != nil, !dismissed {
                card(symbol: "doc.viewfinder", tint: SnapflyTokens.protectTint,
                     text: L("Looks like a photographed document. Straighten and brighten it?")) {
                    Button(L("Clean Up")) { session.clean() }
                        .buttonStyle(.borderedProminent)
                        .tint(SnapflyTokens.protect)
                        .disabled(!session.found)
                        .accessibilityIdentifier("photo-clean")
                    close { dismissed = true }
                }
                .accessibilityIdentifier("photo-clean-offer")
            }
        }
        .controlSize(.small)
    }

    /// The words beside what can be done, on the editor's glass.
    private func card(symbol: String?, tint: Color, text: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(tint)
                } else {
                    ProgressView()
                }
            }
            .font(.body.weight(.semibold))
            .frame(width: 24)
            .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .editorGlass(in: RoundedRectangle(cornerRadius: SnapflyTokens.scanCardRadius, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    private func close(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Not Now"))
    }
}

/// A tap on an AI chat for scanned pages: what goes to it, the covered
/// copy and never the original, and what to ask with it; then the pages
/// are handed to the owner's own app, where nothing is sent until they
/// send it. Snapfly holds no key and sends nothing itself.
struct ScanAssistantSheet: View {
    let chat: ChatTarget
    /// What was chosen: a question, or nil to hand the pages over alone.
    let choose: (ScanAsk?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AppIcon(chat: chat, size: 44)
                        Text(String(format: L("The covered copy is handed over to %@."), chat.name))
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("scan-ask-what")
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(String(format: L("Never the original. Nothing is sent until you send it in %@."), chat.name))
                }
                Section {
                    ForEach(ScanAsk.allCases) { ask in
                        Button { pick(ask) } label: {
                            Label(ask.title, systemImage: ask.symbol)
                        }
                        .accessibilityIdentifier("scan-ask-\(ask.rawValue)")
                    }
                } header: {
                    Text(L("Ask with It"))
                } footer: {
                    Text(String(format: L("With a question, the share sheet opens: tap %@ there, then send."), chat.name))
                }
                Section {
                    Button { pick(nil) } label: {
                        Label(L("Hand Over Only"), systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("scan-ask-none")
                }
            }
            .navigationTitle(String(format: L("Hand Over to %@"), chat.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if DEBUG
        .overlay(alignment: .topLeading) { HandoffAuditMarks() }
        #endif
    }

    private func pick(_ ask: ScanAsk?) {
        choose(ask)
        dismiss()
    }
}

/// An AI chat chosen for scanned pages, while its sheet shows, and what was
/// asked there, handed over once the sheet has gone.
struct AssistantChoice: Identifiable {
    let chat: ChatTarget
    var id: ChatTarget { chat }
}

/// What a scanned document is, beside its pages, as its first page's words
/// say (`ScanNaming`).
struct PaperKindLabel: View {
    let kind: PaperKind

    var body: some View {
        Text(kind.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(SnapflyTokens.hideAccentSoft, in: Capsule())
            .accessibilityLabel(String(format: L("Kind: %@"), kind.title))
            .accessibilityIdentifier("scan-kind")
    }
}

#if DEBUG
/// For the UI tests only: the SHA-256 of the pictures last handed to an app
/// and of the covered pictures last made by Save and Share, so a test can
/// see they are the same bytes and that nothing went before a tap.
@MainActor
final class HandoffAudit: ObservableObject {
    static let shared = HandoffAudit()
    @Published private(set) var handedDigest = "none"
    @Published private(set) var exportedDigest = "none"

    func handed(_ pngs: [Data]) { handedDigest = Self.digest(pngs) }
    func exported(_ pngs: [Data]) { exportedDigest = Self.digest(pngs) }

    private static func digest(_ pngs: [Data]) -> String {
        pngs.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }.joined(separator: " ")
    }
}

/// The digests as invisible words the UI tests read, with the made-up scans only.
struct HandoffAuditMarks: View {
    @ObservedObject private var audit = HandoffAudit.shared

    var body: some View {
        if ScanDemo.requested {
            VStack {
                Text(verbatim: audit.handedDigest).accessibilityIdentifier("audit-handed")
                Text(verbatim: audit.exportedDigest).accessibilityIdentifier("audit-exported")
            }
            .font(.system(size: 2))
            .foregroundStyle(.clear)
            .frame(width: 2, height: 2)
            .allowsHitTesting(false)
        }
    }
}
#endif
