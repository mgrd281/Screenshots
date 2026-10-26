import Photos
import SwiftUI
import UIKit

/// Covers several screenshots at once, as Settings says, one after another,
/// and saves each covered copy to Photos as a new picture beside it, or
/// shares them all; the screenshots themselves stay as they were. A copy is
/// kept only once it is covered, read again and checked (`CoveredCopy`); one
/// that cannot be is never saved, and stays chosen to try again. Covering
/// waits while Snapfly is away: iOS may keep Vision from reading in the
/// background, so a copy made while Snapfly went away, even for a moment,
/// is made again from a fresh reading once it is back.
@MainActor
final class BatchCover: ObservableObject {
    static let shared = BatchCover()

    /// How far a run is: covered so far, of how many; nil while none runs.
    @Published private(set) var progress: (done: Int, total: Int)?
    /// How the last run ended when it left screenshots chosen, shown in the
    /// bar over them.
    @Published var outcome: Outcome?
    @Published var sharing: SharedFiles?
    private var stopping = false
    /// Each time Snapfly stopped being in front, as for a call or another app.
    private var interruptions = 0

    enum Way { case photos, share }

    /// What became of a run that left screenshots chosen.
    struct Outcome: Equatable {
        let text: String
        /// Something went wrong, rather than the owner stopping it.
        let isProblem: Bool
    }

    /// One screenshot's covered copy, or why there is none.
    private enum Copy {
        case made(Data)
        case failed
        case stopped
    }

    var running: Bool { progress != nil }

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { BatchCover.shared.interruptions += 1 }
        }
    }

    /// Stops after the screenshot being covered; those done stay done.
    func stop() {
        stopping = true
    }

    /// Covers the screenshots in the order given and saves or shares them;
    /// gives back those that could not be, or were not reached, to stay
    /// chosen: all of them while another run is under way.
    func run(_ assets: [PHAsset], way: Way) async -> Set<String> {
        guard !running else { return Set(assets.map(\.localIdentifier)) }
        guard !assets.isEmpty else { return [] }
        stopping = false
        outcome = nil
        progress = (0, assets.count)
        // Preparing other photos waits, so these go faster.
        PhotoIndexer.shared.hold()
        defer {
            progress = nil
            PhotoIndexer.shared.release()
        }
        let chosen = Choice.details
        var failed: Set<String> = []
        var left: Set<String> = []
        var files: [URL] = []
        var saved = 0
        var refused = false
        for (index, asset) in assets.enumerated() {
            if stopping || refused {
                left.insert(asset.localIdentifier)
                continue
            }
            progress = (index, assets.count)
            let png: Data
            switch await copy(of: asset, chosen) {
            case .made(let made):
                png = made
            case .failed:
                failed.insert(asset.localIdentifier)
                continue
            case .stopped:
                left.insert(asset.localIdentifier)
                continue
            }
            switch way {
            case .photos:
                do {
                    try await Covering.save(png)
                    saved += 1
                } catch {
                    // Photos refused: the rest would be refused too.
                    refused = true
                    left.insert(asset.localIdentifier)
                    continue
                }
            case .share:
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(String(format: "Snapfly %d.png", files.count + 1))
                do {
                    try png.write(to: url, options: [.atomic, .completeFileProtection])
                    files.append(url)
                } catch {
                    failed.insert(asset.localIdentifier)
                    continue
                }
            }
            Recent.note(asset.localIdentifier)
            QuickCoverer.shared.didCover()
        }
        progress = (assets.count, assets.count)
        report(way: way, saved: saved, failed: failed.count, left: left.count, refused: refused)
        if way == .share, !files.isEmpty { sharing = SharedFiles(urls: files) }
        return failed.union(left)
    }

    /// A screenshot's covered copy, made while Snapfly is in front. One made
    /// while it went away is made again once it is back, and what was read
    /// meanwhile is forgotten, so nothing read then is trusted.
    private func copy(of asset: PHAsset, _ chosen: Set<PrivateDetail>) async -> Copy {
        while true {
            while UIApplication.shared.applicationState != .active, !stopping, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if stopping || Task.isCancelled { return .stopped }
            let before = interruptions
            let png = await Self.covered(asset, chosen)
            if interruptions == before, UIApplication.shared.applicationState == .active {
                return png.map(Copy.made) ?? .failed
            }
            Finder.forgetReadings()
        }
    }

    /// A screenshot covered as chosen, as PNG made off the main thread; nil
    /// when it could not be read, covered or checked.
    private static func covered(_ asset: PHAsset, _ chosen: Set<PrivateDetail>) async -> Data? {
        guard let image = await Library.image(of: asset), let made = await Covering.cover(image, chosen) else { return nil }
        return await Task.detached(priority: .userInitiated) { Covering.png(made.image) }.value
    }

    /// What became of the run: all well, in a note over the screen as the
    /// choosing ends; else in the bar, over those that stay chosen, with a
    /// warning when something went wrong.
    private func report(way: Way, saved: Int, failed: Int, left: Int, refused: Bool) {
        let done = way == .photos && saved > 0 ? (saved == 1 ? L("1 covered copy saved to Photos.")
                                                  : String(format: L("%d covered copies saved to Photos."), saved)) : nil
        let feedback = UINotificationFeedbackGenerator()
        guard failed > 0 || left > 0 else {
            if let done { QuickCoverer.shared.show(done, for: 3) }
            if way == .photos { feedback.notificationOccurred(.success) }
            return
        }
        var parts = [done].compactMap { $0 }
        if refused { parts.append(L("The picture could not be saved.")) }
        if failed > 0 {
            parts.append(failed == 1 ? L("1 could not be covered and stays selected.")
                         : String(format: L("%d could not be covered and stay selected."), failed))
        }
        // Stopped by the owner: what was not reached waits, chosen still.
        if left > 0, !refused { parts.append(L("The rest stay selected.")) }
        let problem = refused || failed > 0
        outcome = Outcome(text: parts.joined(separator: " "), isProblem: problem)
        if problem { feedback.notificationOccurred(.warning) }
    }
}

/// Files to share together, while the share sheet shows.
struct SharedFiles: Identifiable {
    let urls: [URL]
    var id: [URL] { urls }
}

/// The system's share sheet for several files; they are deleted once it
/// closes.
struct ShareFilesSheet: UIViewControllerRepresentable {
    let files: SharedFiles

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sheet = UIActivityViewController(activityItems: files.urls, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            for url in files.urls { try? FileManager.default.removeItem(at: url) }
        }
        return sheet
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Over the bottom while screenshots are being chosen: how many, Share, and
/// Save Covered Copies, the one green button; while they are covered, how
/// far it is, with Stop.
struct SelectionBar: View {
    @ObservedObject private var batch = BatchCover.shared
    let count: Int
    let save: () -> Void
    let share: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let progress = batch.progress {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: L("Covering %d of %d …"), min(progress.done + 1, progress.total), progress.total))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                            .tint(SnapflyTokens.protect)
                    }
                    Button(L("Stop")) { batch.stop() }
                        .font(.subheadline.weight(.semibold))
                }
                .animation(.snappy, value: progress.done)
            } else {
                HStack(spacing: 12) {
                    Button(action: share) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("Share Covered Copies"))
                    .disabled(count == 0)
                    Button(action: save) {
                        Label(count == 0 ? L("Select screenshots") : String(format: L("Save Covered Copies (%d)"), count),
                              systemImage: "shield.lefthalf.filled")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProtectButtonStyle())
                    .disabled(count == 0)
                    .animation(.snappy, value: count)
                }
                if let outcome = batch.outcome, outcome.isProblem {
                    Label(outcome.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.reviewOpen)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let outcome = batch.outcome {
                    // Stopped: said plainly, as nothing went wrong.
                    Text(outcome.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(count > 0 ? L("Covered as Settings says, each saved to Photos as a new picture. The screenshots stay as they are.")
                         : hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        // What went wrong goes with the choosing it belonged to.
        .onDisappear { batch.outcome = nil }
    }
}

/// Over the bottom while the Protected tab's screenshots are being chosen:
/// Merge into PDF, which puts them together in a new PDF project; and
/// Remove, which asks, as Photos does in an album, whether to take them off
/// this list, where they stay in Photos, or delete them from Photos.
struct RemoveBar: View {
    let count: Int
    var merge: (() -> Void)? = nil
    let remove: (Removing) -> Void
    @State private var asking = false

    var body: some View {
        VStack(spacing: 10) {
            if let merge {
                Button(action: merge) {
                    Label(L("Merge into PDF"), systemImage: "doc.on.doc")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(SnapflyTokens.protect)
                .disabled(count == 0)
                .accessibilityIdentifier("protected-merge")
            }
            Button(role: .destructive) {
                asking = true
            } label: {
                Label(count == 0 ? L("Select screenshots") : String(format: L("Remove (%d)"), count),
                      systemImage: "trash")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(count == 0)
            .animation(.snappy, value: count)
            .confirmationDialog(String(format: L("Remove (%d)"), count), isPresented: $asking, titleVisibility: .hidden) {
                Button(L("Remove from Protected")) { remove(.fromList) }
                Button(L("Delete from Photos"), role: .destructive) { remove(.fromPhotos) }
                Button(L("Cancel"), role: .cancel) {}
            }
            Text(count > 0 ? L("Removed from this list, they stay in Photos.") : hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// How to choose, as this iPhone allows.
private var hint: String {
    if #available(iOS 18, *) { return L("Tap screenshots, or draw a finger sideways across them.") }
    return L("Tap screenshots to choose them.")
}

/// On a chosen card: dimmed a little, drawn in a little, with Photos' mark
/// of a chosen picture, a white tick on the green, ringed in white.
struct ChosenMark: ViewModifier {
    let chosen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if chosen {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(SnapflyTokens.protect, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .padding(6)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .scaleEffect(chosen && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.72), value: chosen)
    }
}

/// A finger drawn sideways across the grid to choose a run of cards, as in
/// Photos; one drawn up or down still scrolls. While it lasts the page
/// holds still, so the finger can go on down the rows.
struct SweepToChoose: ViewModifier {
    /// Only while several are being chosen.
    let active: Bool
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    let ended: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(SweepGesture(active: active, began: began, changed: changed, ended: ended))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct SweepGesture: UIGestureRecognizerRepresentable {
    let active: Bool
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.isEnabled = active
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = active
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = context.converter.localLocation
        switch recognizer.state {
        case .began:
            // It begins once the finger has moved a little: from the card it came down on.
            let moved = recognizer.translation(in: recognizer.view)
            began(CGPoint(x: point.x - moved.x, y: point.y - moved.y))
            changed(point)
        case .changed: changed(point)
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a finger moving sideways at first chooses.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        /// The page's own scrolling isn't kept from starting; it is held
        /// still once this begins.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
