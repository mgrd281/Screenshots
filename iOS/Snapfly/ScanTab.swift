import SwiftUI
import VisionKit

/// The Scan tab: a letter, a form or a receipt scanned with the system's
/// document camera, straightened and cropped by it, then opened to cover its
/// private details like any screenshot. Scanned pages stay in memory while
/// the app runs, and are never saved unless the owner saves a covered copy.
struct ScanTab: View {
    @State private var scanning = false
    @State private var pages: [ScannedPage] = []
    @State private var path = NavigationPath()
    /// Each press of the scan button, for its haptic.
    @State private var presses = 0

    struct ScannedPage: Identifiable {
        let id = UUID()
        let image: CGImage
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScanCard(supported: VNDocumentCameraViewController.isSupported) {
                        presses += 1
                        scanning = true
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: presses)
                    if !pages.isEmpty { scanned }
                    steps
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(L("Scan"))
            .quickNotes()
            .navigationDestination(for: ProtectSession.Source.self) { source in ProtectView(source: source) }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                guard !images.isEmpty else { return }
                let new = images.map { ScannedPage(image: $0) }
                pages = new + pages
                // One page goes straight to covering; several wait here to be chosen.
                if new.count == 1 { open(new[0]) }
            }
            .ignoresSafeArea()
        }
    }

    /// The pages scanned while the app runs, newest first.
    private var scanned: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Scanned pages"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L("Clear")) {
                    withAnimation(.easeOut(duration: 0.2)) { pages = [] }
                }
                .font(.subheadline.weight(.medium))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button { open(page) } label: {
                        PageCard(image: page.image)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: L("Page %d"), pages.count - index))
                    .accessibilityHint(L("Cover Private Details"))
                }
            }
            Text(L("Pages stay on this iPhone only while Snapfly is open."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// How a scan goes, in three short steps.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("doc.viewfinder", L("Hold your iPhone over the page; it is found and taken by itself."))
            step("eye.slash", L("Names, numbers and other private details are covered as Settings says."))
            step("square.and.arrow.up", L("Check the places, then copy, share or save the covered page."))
        }
        .padding(.horizontal, 4)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SnapflyTokens.protect)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ page: ScannedPage) {
        path.append(ProtectSession.Source.picture(Imported.shared.keep(page.image)))
    }
}

/// The scan tab's first card: a page in a viewfinder on the soft green,
/// what scanning does, and the green button that opens the camera.
private struct ScanCard: View {
    let supported: Bool
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Viewfinder()
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(L("Scan a document"))
                    .font(.title2.weight(.bold))
                Text(L("Letters, forms and receipts, straight from the camera. Private details are covered on this iPhone before anything leaves it."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            Button(action: scan) {
                Label(L("Scan Document"), systemImage: "camera.viewfinder")
            }
            .buttonStyle(ProtectButtonStyle())
            .disabled(!supported)
            if !supported {
                Text(L("This iPhone cannot scan documents."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(SnapflyTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .padding(.top, 4)
    }
}

/// A page with a covered line in the corners of a viewfinder, drawn with
/// shapes, so it fits light and dark and shows no one's details.
private struct Viewfinder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SnapflyTokens.card)
                .frame(width: 74, height: 96)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color.primary.opacity(0.22)).frame(width: 30, height: 5)
                        Capsule().fill(Color.primary.opacity(0.85)).frame(width: 46, height: 5)
                        ForEach([CGFloat(50), 40, 48, 28], id: \.self) { width in
                            Capsule().fill(Color.primary.opacity(0.10)).frame(width: width, height: 5)
                        }
                    }
                    .padding(11)
                }
            Corners()
                .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    /// The four corners of a viewfinder.
    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let arm = rect.width * 0.2, inset: CGFloat = 2
            let r = rect.insetBy(dx: inset, dy: inset)
            var path = Path()
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1),
            ]
            for (corner, dx, dy) in corners {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }
            return path
        }
    }
}

/// A scanned page as a small square card, its top showing.
private struct PageCard: View {
    let image: CGImage

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

/// The system's document camera; `done` gets the pages, upright and
/// cropped, or none when it was cancelled or failed.
private struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([CGImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([CGImage]) -> Void

        init(done: @escaping ([CGImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            done([])
        }
    }
}
