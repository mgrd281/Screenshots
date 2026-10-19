import Photos
import SwiftUI

/// The four places of the app, in the tab bar.
enum AppTab: Hashable {
    case photos, scan, protected, more
}

/// Which tab shows, so a chip, the introduction or Settings can move to another.
@MainActor
final class AppTabs: ObservableObject {
    static let shared = AppTabs()
    @Published var selection = AppTab.photos
}

/// Snapfly on the iPhone: the screenshots in Photos, a document scanned with
/// the camera, the screenshots protected lately, and More with Settings and
/// help, each a tab of the system's tab bar, in Liquid Glass from iOS 26 on.
struct ContentView: View {
    @StateObject private var library = Library()
    @ObservedObject private var tabs = AppTabs.shared
    @ObservedObject private var coverer = QuickCoverer.shared

    var body: some View {
        TabView(selection: $tabs.selection) {
            PhotosTab(library: library)
                .tabItem { Label(L("Photos"), systemImage: "photo.on.rectangle.angled") }
                .tag(AppTab.photos)
            ScanTab()
                .tabItem { Label(L("Scan"), systemImage: "doc.viewfinder") }
                .tag(AppTab.scan)
            ProtectedTab(library: library)
                .tabItem { Label(L("Protected"), systemImage: "checkmark.shield") }
                .tag(AppTab.protected)
            SettingsView(inTab: true)
                .tabItem { Label(L("More"), systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .tabBarShrinksOnScroll()
        .sensoryFeedback(.selection, trigger: tabs.selection)
        // One share sheet for the whole app, whichever tab asked for it.
        .sheet(item: $coverer.sharing) { file in
            ShareSheet(url: file.url) { _ in try? FileManager.default.removeItem(at: file.url) }
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// From iOS 26, the tab bar shrinks to its chosen tab while a page
    /// scrolls down, and comes back as it scrolls up.
    @ViewBuilder func tabBarShrinksOnScroll() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Whether a scroll view has moved its content up, from iOS 18 on;
    /// before, it stays false.
    @ViewBuilder func onScrolledDown(_ scrolled: Binding<Bool>) -> some View {
        if #available(iOS 18, *) {
            onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 4
            } action: { _, now in
                scrolled.wrappedValue = now
            }
        } else {
            self
        }
    }

    /// The note a quick cover leaves, floating over the bottom of the tab.
    func quickNotes() -> some View {
        modifier(QuickNotes())
    }
}

private struct QuickNotes: ViewModifier {
    @ObservedObject private var coverer = QuickCoverer.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let note = coverer.note {
                    Text(note)
                        .floatingPill()
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: coverer.note)
    }
}

/// Covers a screenshot as Settings says, checks it and copies, shares or
/// saves it, without opening it, from any tab.
@MainActor
final class QuickCoverer: ObservableObject {
    static let shared = QuickCoverer()
    @Published var note: String?
    @Published var sharing: SharedFile?
    /// How many screenshots were covered here, so the lists of them update.
    @Published private(set) var covered = 0

    func cover(_ asset: PHAsset, _ way: QuickCover) {
        show(L("Covering private details…"), for: 60)
        Task {
            guard let image = await Library.image(of: asset) else {
                show(L("The picture could not be read."))
                return
            }
            guard let made = await Covering.cover(image, Choice.details), let png = Covering.png(made.image) else {
                show(L("The copy could not be made."))
                return
            }
            switch way {
            case .copy:
                Covering.copy(png)
                show(L("Covered and copied, ready to paste."))
            case .save:
                do {
                    try await Covering.save(png)
                    show(L("Saved to Photos"))
                } catch {
                    show(L("The picture could not be saved."))
                    return
                }
            case .share:
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Snapfly.png")
                do {
                    try png.write(to: url, options: [.atomic, .completeFileProtection])
                } catch {
                    show(L("The copy could not be made."))
                    return
                }
                note = nil
                sharing = SharedFile(url: url)
            }
            Recent.note(asset.localIdentifier)
            covered += 1
            PhoneGuide.shared.happened(.used)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// A short note over the bottom of the screen, gone after a while.
    func show(_ text: String, for seconds: Double = 2.5) {
        note = text
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if note == text { note = nil }
        }
    }
}

/// The Protected tab: the screenshots protected here lately, newest first,
/// in the same grid as the Photos tab, each opened again or covered from
/// its menu.
struct ProtectedTab: View {
    @ObservedObject var library: Library
    @ObservedObject private var coverer = QuickCoverer.shared
    @State private var shots: [PHAsset] = []
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            Group {
                if shots.isEmpty {
                    ContentUnavailableView {
                        Label(L("Nothing protected yet"), systemImage: "checkmark.shield")
                    } description: {
                        Text(L("The screenshots you protect show up here."))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ScreenshotGrid(shots: shots, protected: Set(shots.map(\.localIdentifier)), place: .recent,
                                           zoom: zoom, quick: coverer.cover)
                            Text(L("The last twelve, kept on this iPhone by their place in Photos alone."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(L("Protected"))
            .quickNotes()
            .navigationDestination(for: ShotLink.self) { link in
                ProtectView(source: link.source).zoomed(from: link, in: zoom)
            }
            .onAppear(perform: reload)
        }
        .onChange(of: coverer.covered) { reload() }
        .onChange(of: library.mayRead) { reload() }
    }

    private func reload() {
        shots = library.mayRead ? Library.assets(Recent.ids) : []
    }
}
