import Photos
import SwiftUI
import UIKit

/// Covers several screenshots at once, as Settings says, one after another,
/// and saves each covered copy to Photos as a new picture beside it, or
/// shares them all; the screenshots themselves stay as they were. A copy is
/// kept only once it is covered, read again and checked (`CoveredCopy`); one
/// that cannot be is never saved, and stays chosen to try again.
@MainActor
final class BatchCover: ObservableObject {
    static let shared = BatchCover()

    /// How far a run is: covered so far, of how many; nil while none runs.
    @Published private(set) var progress: (done: Int, total: Int)?
    /// What went wrong in the last run, shown in the bar while the
    /// screenshots it leaves stay chosen.
    @Published var outcome: String?
    @Published var sharing: SharedFiles?
    private var stopping = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    enum Way { case photos, share }

    var running: Bool { progress != nil }

    /// Stops after the screenshot being covered; those done stay done.
    func stop() {
        stopping = true
    }

    /// Covers the screenshots in the order given and saves or shares them;
    /// gives back those that could not be, or were not reached, to stay
    /// chosen.
    func run(_ assets: [PHAsset], way: Way) async -> Set<String> {
        guard !running, !assets.isEmpty else { return [] }
        stopping = false
        outcome = nil
        progress = (0, assets.count)
        // Leaving the app for a moment doesn't stop it halfway; if iOS ends
        // the time it gives, the run stops after the one it is covering.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Cover screenshots") { [weak self] in
            MainActor.assumeIsolated {
                self?.stopping = true
                self?.endBackground()
            }
        }
        // Preparing other photos waits, so these go faster.
        PhotoIndexer.shared.hold()
        defer {
            progress = nil
            endBackground()
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
            guard let image = await Library.image(of: asset),
                  let made = await Covering.cover(image, chosen),
                  let png = await Self.png(made.image) else {
                failed.insert(asset.localIdentifier)
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

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// What became of the run: all well, in a note over the screen as the
    /// choosing ends; else in the bar, over those that stay chosen.
    private func report(way: Way, saved: Int, failed: Int, left: Int, refused: Bool) {
        let done = way == .photos && saved > 0 ? (saved == 1 ? L("1 covered copy saved to Photos.")
                                                  : String(format: L("%d covered copies saved to Photos."), saved)) : nil
        var problems: [String] = []
        if refused { problems.append(L("The picture could not be saved.")) }
        if failed > 0 {
            problems.append(failed == 1 ? L("1 could not be covered and stays selected.")
                            : String(format: L("%d could not be covered and stay selected."), failed))
        }
        if left > 0, !refused { problems.append(L("The rest stay selected.")) }
        let feedback = UINotificationFeedbackGenerator()
        if problems.isEmpty {
            if let done { QuickCoverer.shared.show(done, for: 3) }
            if way == .photos { feedback.notificationOccurred(.success) }
        } else {
            outcome = ([done].compactMap { $0 } + problems).joined(separator: " ")
            feedback.notificationOccurred(.warning)
        }
    }

    /// The covered copy as PNG, made off the main thread.
    private static func png(_ image: CGImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { Covering.png(image) }.value
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
                if let outcome = batch.outcome {
                    Label(outcome, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
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
        case .began: began(point)
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
