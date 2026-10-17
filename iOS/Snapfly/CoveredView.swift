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
                } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                }
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Snapfly", image: Image(uiImage: image))) {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
                Button {
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
            if let note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .transition(.opacity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(.easeOut(duration: 0.2), value: note)
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
