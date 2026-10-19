import Photos
import SwiftUI

/// One screenshot with its private details covered, and the ways to send
/// it: copy, share, or save to Photos. The screenshot itself stays as it was.
struct CoveredView: View {
    let assetID: String
    @State private var covered: UIImage?
    @State private var png: Data?
    @State private var report = CoverReport()
    @State private var working = true
    @State private var note: String?
    @ObservedObject private var sync = SyncCenter.shared
    /// Sent to the Mac already, so it goes once.
    @State private var sent = false

    var body: some View {
        ScrollView {
            if let covered {
                Image(uiImage: covered)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding()
            } else if working {
                ProgressView(L("Covering private details…"))
                    .padding(.top, 120)
            } else {
                ContentUnavailableView(L("The picture could not be read."), systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(L("Cover Private Details"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let covered, let png { actions(covered, png) }
        }
        .phoneGuide(on: .shot)
        .onAppear {
            PhoneGuide.shared.screen = .shot
            PhoneGuide.shared.happened(.openedShot)
        }
        .onDisappear { PhoneGuide.shared.screen = .library }
        .task { await cover() }
    }

    private func actions(_ image: UIImage, _ png: Data) -> some View {
        VStack(spacing: 10) {
            Text(report.sentence ?? L("Nothing private found"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    Covering.copy(png)
                    note = L("Copied")
                    PhoneGuide.shared.happened(.used)
                } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                }
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Snapfly", image: Image(uiImage: image))) {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded { PhoneGuide.shared.happened(.used) })
                Button {
                    PhoneGuide.shared.happened(.used)
                    Task {
                        do {
                            try await Covering.save(png)
                            note = L("Saved to Photos")
                        } catch {
                            note = L("The picture could not be saved.")
                        }
                    }
                } label: {
                    Label(L("Save"), systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            // With syncing on, the covered copy hangs on the Mac's line.
            if sync.canSend {
                Button {
                    send(png)
                } label: {
                    Label(L("Send to Mac"), systemImage: "laptopcomputer.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(sent)
            }
            if let note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .transition(.opacity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
        .phoneGuideTarget(.actions)
        .animation(.easeOut(duration: 0.2), value: note)
    }

    private func send(_ png: Data) {
        sent = true
        let redaction = SyncRedaction(kinds: report.keys, areas: report.total, look: CoverStyle.current.rawValue)
        // Named by when it was taken, as the Mac names screenshots.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let taken = Library.asset(assetID)?.creationDate ?? Date()
        let name = "Snapfly \(formatter.string(from: taken)).png"
        Task {
            if await sync.send(covered: png, name: name, redaction: redaction) {
                note = L("On its way to your Mac")
            } else {
                sent = false
                note = L("Could not send it. Try again.")
            }
        }
    }

    private func cover() async {
        guard covered == nil else { return }
        guard let asset = Library.asset(assetID), let image = await Library.image(of: asset) else {
            working = false
            return
        }
        let chosen = Choice.details
        let result = await Covering.cover(image, chosen)
        png = Covering.png(result.image)
        covered = UIImage(cgImage: result.image)
        report = result.report
        working = false
    }
}
