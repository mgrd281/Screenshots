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
    /// Photos first; More where screenshots made in CI and the UI tests ask for it or Always Hide, and
    /// Scan for made-up scans.
    @Published var selection = ScanDemo.requested || ProjectDemo.showsTab ? AppTab.scan
        : AlwaysHideSample.requested || MoreSample.requested ? AppTab.more : AppTab.photos
    /// The first run's Try It Now: the Scan tab opens the camera as it shows.
    @Published var scanRequested = false
    /// Pages of More asked for from another tab, like Faster picture
    /// processing from See All: More opens them as it shows, then empties this.
    @Published var morePages: [MorePage] = []
}

/// Snapfly on the iPhone: the screenshots in Photos, a document scanned with
/// the camera, the screenshots protected lately, and More with Settings and
/// help, each a tab of the system's tab bar, in Liquid Glass from iOS 26 on.
/// The first run shows over all of it, from the first frame. A PDF project
/// shows over the tabs, as it is started, opened again, or a PDF or a picture
/// is opened in Snapfly from Files, Mail or Safari.
struct ContentView: View {
    @StateObject private var library = Library()
    @ObservedObject private var tabs = AppTabs.shared
    @ObservedObject private var projects = ProjectStore.shared
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var coverer = QuickCoverer.shared
    @ObservedObject private var batch = BatchCover.shared
    @ObservedObject private var firstRun = FirstRunCoordinator.shared
    /// The tabs are made once the first run that opens Snapfly is over, so
    /// reading Photos and starting sync never hold up its first seconds.
    @State private var appReady = !FirstRunCoordinator.shared.showing

    var body: some View {
        ZStack {
            if appReady {
                tabView
                    .accessibilityHidden(firstRun.showing)
            }
            if firstRun.showing {
                SnapflyFirstRunExperience()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onChange(of: firstRun.showing) { _, showing in
            if !showing { appReady = true }
        }
        // "Open in Snapfly": the file becomes a new PDF project.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            ProjectStore.shared.start(.files([url]))
        }
        // A project is written at once as Snapfly goes away.
        .onChange(of: phase) { _, now in
            if now != .active { ProjectStore.shared.flush() }
        }
    }

    private var tabView: some View {
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
        // On More the tab bar stays whole, so its shrunk button never sits over a row.
        .tabBarShrinksOnScroll(tabs.selection != .more)
        .sensoryFeedback(.selection, trigger: tabs.selection)
        // One share sheet for the whole app, whichever tab asked for it.
        .sheet(item: $coverer.sharing) { file in
            ShareSheet(url: file.url) { _ in try? FileManager.default.removeItem(at: file.url) }
                .ignoresSafeArea()
        }
        // And one for the covered copies of several screenshots, shared at once.
        .sheet(item: $batch.sharing) { files in
            ShareFilesSheet(files: files)
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $projects.shown) { _ in ProjectCover() }
    }
}

extension View {
    /// From iOS 26, the tab bar shrinks to its chosen tab while a page
    /// scrolls down, and comes back as it scrolls up; or, not shrinking, it
    /// stays whole.
    @ViewBuilder func tabBarShrinksOnScroll(_ shrinks: Bool = true) -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(shrinks ? .onScrollDown : .never)
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
            // Said as it is: a copy with nothing covered is no covered copy.
            let none = made.report.isEmpty
            switch way {
            case .copy:
                Covering.copy(png)
                show(none ? L("Nothing to cover was found. Copied as it is, ready to paste.") : L("Covered and copied, ready to paste."))
            case .save:
                do {
                    try await Covering.save(png)
                    show(none ? L("Nothing to cover was found. Saved to Photos as it is.") : L("Saved to Photos"))
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

    /// Another screenshot covered elsewhere, like several at once, so the
    /// lists of them update.
    func didCover() {
        covered += 1
    }

    /// Screenshots taken off the list of those protected lately, or put
    /// back, so the lists of them update too.
    func protectedChanged() {
        covered += 1
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
/// its menu. Holding one, or choosing several with Select, takes them off
/// the list, where they stay in Photos and Undo puts them back, or deletes
/// them from Photos, as iOS asks first; several chosen are merged into a
/// PDF project, in the order they show.
struct ProtectedTab: View {
    @ObservedObject var library: Library
    @ObservedObject private var coverer = QuickCoverer.shared
    @State private var shots: [PHAsset] = []
    @Namespace private var zoom
    /// The screenshots chosen, while several are being chosen.
    @State private var selection: GridSelection?
    /// A finger is drawn across the cards, so the page holds still.
    @State private var sweeping = false
    /// What was taken off the list last, while Undo can put it back.
    @State private var removed: ProtectedList.Removal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if !library.mayRead, library.access != .notDetermined {
                    // Photos refused: the screenshots protected stay listed, but can't show.
                    PhotosAccessDenied()
                } else if shots.isEmpty {
                    ContentUnavailableView {
                        Label(L("Nothing protected yet"), systemImage: "checkmark.shield")
                    } description: {
                        Text(L("The screenshots you protect show up here."))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ScreenshotGrid(shots: shots, protected: Set(shots.map(\.localIdentifier)), place: .recent,
                                           zoom: zoom, quick: coverer.cover, selection: $selection,
                                           sweeping: $sweeping, remove: remove)
                            Text(L("The last twelve, kept on this iPhone by their place in Photos alone."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .scrollDisabled(sweeping)
                }
            }
            .navigationTitle(L("Protected"))
            .toolbar { toolbar }
            // While choosing, the tab bar steps aside for the choice's own bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selection {
                    RemoveBar(count: selection.count, merge: { merge(selection) }) { way in
                        remove(shots.filter { selection.contains($0.localIdentifier) }, way)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(selection == nil ? .automatic : .hidden, for: .tabBar)
            .animation(choosing, value: selection == nil)
            .overlay(alignment: .bottom) {
                if let removed {
                    HStack(spacing: 12) {
                        Text(removed.count == 1 ? L("Removed from Protected")
                             : String(format: L("%d removed from Protected"), removed.count))
                        Button(L("Undo")) { undo(removed) }
                            .fontWeight(.semibold)
                            .contentShape(Rectangle().inset(by: -10))
                    }
                    .floatingPill()
                    .padding(.bottom, 24)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy, value: removed)
            // Undo waits a few seconds, then the list is as it is.
            .task(id: removed) {
                guard removed != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { removed = nil }
            }
            .quickNotes()
            .navigationDestination(for: ShotLink.self) { link in
                ProtectView(source: link.source).zoomed(from: link, in: zoom)
            }
            .onAppear(perform: reload)
        }
        .onChange(of: coverer.covered) { reload() }
        .onChange(of: library.mayRead) { reload() }
        // Nothing left to choose: the choosing ends, and the tab bar comes back.
        .onChange(of: shots.isEmpty) { _, empty in
            if empty { selection = nil }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if selection != nil {
            ToolbarItem(placement: .topBarLeading) {
                let ids = shots.map(\.localIdentifier)
                let all = selection.map { chosen in ids.allSatisfy(chosen.contains) } ?? false
                Button(all ? L("Deselect All") : L("Select All")) {
                    selection?.toggleAll(ids)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Cancel")) {
                    withAnimation(choosing) { selection = nil }
                }
                .fontWeight(.semibold)
            }
        }
        if selection == nil, !shots.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Select")) {
                    withAnimation(choosing) { selection = GridSelection() }
                }
            }
        }
    }

    /// How choosing starts and ends, and its bar comes and goes: on
    /// `.snappy`, or a short fade with Reduce Motion.
    private var choosing: Animation {
        reduceMotion ? SnapflyMotion.calm : .snappy
    }

    private func reload() {
        shots = library.mayRead ? Library.assets(Recent.ids) : []
    }

    /// The screenshots chosen, in the order they show, as the pages of a new PDF project.
    private func merge(_ chosen: GridSelection) {
        let ids = shots.map(\.localIdentifier).filter(chosen.contains)
        guard !ids.isEmpty else { return }
        withAnimation(choosing) { selection = nil }
        ProjectStore.shared.start(.screenshots(ids))
    }

    /// Takes screenshots off the list at once, with Undo; or deletes them
    /// from Photos once iOS has asked, and takes them off the list then.
    private func remove(_ assets: [PHAsset], _ way: Removing) {
        let gone = Set(assets.map(\.localIdentifier))
        guard !gone.isEmpty else { return }
        switch way {
        case .fromList:
            let removal = Recent.remove(gone)
            coverer.note = nil
            withAnimation(leaving) {
                shots.removeAll { gone.contains($0.localIdentifier) }
                selection = nil
                removed = removal
            }
            coverer.protectedChanged()
        case .fromPhotos:
            let ids = Array(gone)
            Task {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
                    }
                } catch {
                    // Don't Allow, in iOS's own question, leaves everything as it was.
                    if (error as NSError).code != PHPhotosError.Code.userCancelled.rawValue {
                        coverer.show(L("The screenshots could not be deleted."))
                    }
                    return
                }
                _ = Recent.remove(gone)
                withAnimation(leaving) {
                    shots.removeAll { gone.contains($0.localIdentifier) }
                    selection = nil
                    removed = nil
                }
                library.load()
                coverer.protectedChanged()
                coverer.show(L("Deleted. Photos can still bring them back for 30 days."), for: 3)
            }
        }
    }

    /// Those taken off, back in their places.
    private func undo(_ removal: ProtectedList.Removal) {
        Recent.restore(removal)
        withAnimation(leaving) {
            removed = nil
            reload()
        }
        coverer.protectedChanged()
    }

    /// How cards leave and come back: on a spring, or a fade with Reduce Motion.
    private var leaving: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.86)
    }
}
