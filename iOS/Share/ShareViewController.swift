import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Snapfly in the share sheet of any app: a picture shared to it is covered
/// as the owner chose in the app (`SharedChoice`), read again and checked,
/// then copied, shared on or saved, without opening Snapfly. Nothing of the
/// picture is kept once the sheet closes.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private lazy var model = ShareModel(context: extensionContext)

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareScreen(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.start()
    }
}

/// The picture shared, as it is covered.
@MainActor
final class ShareModel: ObservableObject {
    @Published private(set) var covered: CGImage?
    @Published private(set) var count = 0
    @Published private(set) var failure: String?
    @Published var note: String?
    @Published var sharing: URL?
    private weak var context: NSExtensionContext?
    private var png: Data?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var ready: Bool { png != nil }

    func start() {
        Task { await cover() }
    }

    private func cover() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let data = await Self.data(of: provider),
              let image = CoveredCopy.upright(data) else {
            failure = L("The picture could not be read.")
            return
        }
        // As chosen in the app; the recommended kinds before it was first opened.
        let choice = SharedChoice.kept
        guard let made = await CoveredCopy.make(image, choice?.details ?? PrivateDetail.recommended,
                                                rules: choice?.rules ?? [], style: choice?.look ?? .ink,
                                                intelligence: false),
              let png = CoveredCopy.png(made.image) else {
            failure = L("The copy could not be made.")
            return
        }
        self.png = png
        covered = made.image
        count = made.report.total
    }

    private static func data(of provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { done in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                done.resume(returning: data)
            }
        }
    }

    func copy() {
        guard let png else { return }
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        show(L("Covered and copied, ready to paste."))
    }

    func save() {
        guard let png else { return }
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
                }
                show(L("Saved to Photos"))
            } catch {
                show(L("The picture could not be saved."))
            }
        }
    }

    func share() {
        guard let png else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Snapfly.png")
        do {
            try png.write(to: url, options: [.atomic, .completeFileProtection])
            sharing = url
        } catch {
            show(L("The copy could not be made."))
        }
    }

    func finish() {
        if let sharing { try? FileManager.default.removeItem(at: sharing) }
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func show(_ text: String) {
        note = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if note == text { note = nil }
        }
    }
}

/// The sheet: the covered picture, how it stands, and Copy, Share and Save.
struct ShareScreen: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                picture
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                status
                HStack(spacing: 10) {
                    way(L("Copy"), "doc.on.doc", model.copy)
                    way(L("Share"), "square.and.arrow.up", model.share)
                    way(L("Save"), "arrow.down.to.line", model.save)
                }
                .disabled(!model.ready)
                Text(L("Covered as chosen in Snapfly."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snapfly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel"), action: model.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done"), action: model.finish)
                        .fontWeight(.semibold)
                }
            }
            .overlay(alignment: .bottom) {
                if let note = model.note {
                    Text(note)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .padding(.bottom, 96)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.note)
            .sheet(item: Binding(get: { model.sharing.map(SharedURL.init) }, set: { if $0 == nil { model.sharing = nil } })) { file in
                ActivitySheet(url: file.url).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private var picture: some View {
        if let image = model.covered {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .accessibilityLabel(L("Cover Private Details"))
        } else if model.failure == nil {
            ProgressView()
                .controlSize(.large)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var status: some View {
        Group {
            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if model.ready {
                Label(model.count == 0 ? L("Nothing private found") : String(format: L("%d places covered"), model.count),
                      systemImage: "checkmark.shield.fill")
                    .foregroundStyle(Color(red: 7 / 255, green: 135 / 255, blue: 92 / 255))
            } else {
                Label {
                    Text(L("Covering private details…"))
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: Capsule())
    }

    private func way(_ title: String, _ symbol: String, _ action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(Color(red: 7 / 255, green: 135 / 255, blue: 92 / 255))
    }
}

/// The copy's file while the share sheet shows.
private struct SharedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system's share sheet for the covered copy.
private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
