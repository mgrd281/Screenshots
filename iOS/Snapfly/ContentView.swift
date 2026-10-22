import Photos
import PhotosUI
import SwiftUI

/// The Photos tab: Snapfly's picture of stacked photos with Protect a
/// Photo, what the Mac sent, and the newest screenshots, all of them behind
/// See All. The picture is full while there is nothing yet, and small beside
/// its words once there are screenshots. A tap opens a screenshot to
/// protect; its menu, or holding it down, covers it and copies, shares or
/// saves it at once.
struct PhotosTab: View {
    @ObservedObject var library: Library
    @ObservedObject private var guide = PhoneGuide.shared
    @ObservedObject private var sync = SyncCenter.shared
    @ObservedObject private var coverer = QuickCoverer.shared
    /// The pictures open: a screenshot from a card, or a photo chosen.
    @State private var path = NavigationPath()
    /// Where a screenshot grows out of as it opens.
    @Namespace private var zoom
    @State private var picked: PhotosPickerItem?
    /// Whether the page has scrolled under the status bar.
    @State private var scrolled = false
    /// Each press of the green button, for its haptic.
    @State private var presses = 0
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// How many to a row, as pinched; the home screen shows three rows of
    /// the newest before See All.
    @AppStorage(GridZoom.key) private var columns = GridZoom.standard
    /// The screenshots chosen, while several are being chosen.
    @State private var selection: GridSelection?
    /// A finger is drawn across the cards, so the page holds still.
    @State private var sweeping = false
    @ObservedObject private var batch = BatchCover.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.mayRead {
                    home
                } else if library.access == .notDetermined {
                    welcome
                } else {
                    denied
                }
            }
            .navigationTitle("Snapfly")
            .toolbar(.hidden, for: .navigationBar)
            .quickNotes()
            .navigationDestination(for: ProtectSession.Source.self) { source in ProtectView(source: source) }
            .navigationDestination(for: ShotLink.self) { link in
                ProtectView(source: link.source).zoomed(from: link, in: zoom)
            }
        }
        .onAppear {
            library.load()
            Choice.share()
            PhoneSync.start()
            PhotoIndexer.shared.becameActive()
            // For screenshots made in CI: the editor on a made-up invoice.
            if EditorSample.requested, path.isEmpty, let sample = EditorSample.picture() {
                path.append(ProtectSession.Source.picture(Imported.shared.keep(sample, info: Imported.Info(screenshot: true))))
            }
            // And on a made-up photo of a made-up invoice, offered to be cleaned.
            if DocumentPhotoDemo.requested, path.isEmpty, let photo = DocumentPhotoDemo.photo() {
                path.append(ProtectSession.Source.picture(Imported.shared.keep(photo.image, info: photo.info)))
            }
            guide.closeShot = { path.removeLast(path.count) }
            guide.openNewest = {
                guard let newest = library.shots.first?.localIdentifier else { return false }
                AppTabs.shared.selection = .photos
                path.append(ProtectSession.Source.asset(newest))
                return true
            }
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                library.load()
                PhotoIndexer.shared.becameActive()
            }
            // The share extension covers as Settings says, the look and rules too.
            if now != .active { Choice.share() }
            // Nothing read stays in memory while Snapfly is away.
            if now == .background {
                Finder.forgetReadings()
                PhotoIndexer.shared.wentAway()
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await open(item) }
        }
        // The introduction, once, as the first screenshots show.
        .onChange(of: library.shots.isEmpty) { _, empty in
            if !empty { guide.offerIfDue() }
            // Nothing left to choose: the choosing ends, and the tab bar comes back.
            if empty, !batch.running { selection = nil }
        }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if library.shots.isEmpty { fullHero } else { compactHero }
                // What the Mac sent, when syncing is on.
                FromMacRow(sync: sync)
                    .padding(.horizontal, -6)
                screenshots
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(sweeping)
        .onScrolledDown($scrolled)
        .background(Color(.systemBackground))
        // The page's own colour under the status bar; the bar's material only
        // once something scrolls under it, so it stays readable.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
                .background(scrolled ? AnyShapeStyle(.bar) : AnyShapeStyle(Color(.systemBackground)))
                .animation(.easeOut(duration: 0.15), value: scrolled)
        }
        .phoneGuide(on: .library)
        // While choosing, the tab bar steps aside for the choice's own bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection {
                SelectionBar(count: selection.count, save: { coverChosen(.photos) }, share: { coverChosen(.share) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(selection == nil ? .automatic : .hidden, for: .tabBar)
        .animation(.snappy, value: selection == nil)
        .onAppear {
            if !library.shots.isEmpty { guide.offerIfDue() }
        }
    }

    /// The screenshots chosen, covered as Settings says, one after another,
    /// in the grid's order; those that could not be stay chosen.
    private func coverChosen(_ way: BatchCover.Way) {
        guard let chosen = selection?.chosen, !chosen.isEmpty else { return }
        let assets = library.shots.filter { chosen.contains($0.localIdentifier) }
        Task {
            let failed = await batch.run(assets, way: way)
            withAnimation(.snappy) {
                if failed.isEmpty { selection = nil } else { selection?.keep(failed) }
            }
        }
    }

    /// Snapfly's name, large, and how syncing stands. Settings is the More tab.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Snapfly")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            syncChip
        }
        .frame(minHeight: 44)
        .padding(.top, 4)
    }

    /// The whole picture, while there are no screenshots yet.
    private var fullHero: some View {
        VStack(spacing: 20) {
            PhotoHero()
            words(center: true)
            protectButton(compact: false)
            VStack(spacing: 4) {
                Text(L("No screenshots yet"))
                    .font(.subheadline.weight(.semibold))
                Text(L("Take a screenshot, then come back here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// The picture made small, beside its words, so the screenshots come
    /// first; one under the other with the largest text sizes.
    @ViewBuilder private var compactHero: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 16) {
                PhotoHero(scale: 0.5)
                words(center: true)
                protectButton(compact: true)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 4) {
                PhotoHero(scale: 0.46)
                    .padding(.leading, -12)
                VStack(alignment: .leading, spacing: 12) {
                    words(center: false)
                    protectButton(compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func words(center: Bool) -> some View {
        VStack(alignment: center ? .center : .leading, spacing: 6) {
            Text(L("Your pictures. Your privacy."))
                .font(center ? Font.title2.weight(.bold) : Font.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Find private details and protect them, simply."))
                .font(center ? Font.body : Font.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(center ? .center : .leading)
    }

    /// Protect a Photo: the system's photo picker, any picture from Photos.
    private func protectButton(compact: Bool) -> some View {
        // From the library itself, so a screenshot is told from a photo.
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            Label(L("Protect a Photo"), systemImage: "shield.lefthalf.filled")
        }
        .buttonStyle(ProtectButtonStyle(compact: compact))
        .simultaneousGesture(TapGesture().onEnded { presses += 1 })
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
    }

    /// The newest screenshots, and all of them behind See All.
    @ViewBuilder private var screenshots: some View {
        if !library.shots.isEmpty {
            let protected = Set(Recent.ids)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Screenshots"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let selection {
                        let shown = Array(library.shots.prefix(GridZoom.preview(columns: columns))).map(\.localIdentifier)
                        Button(shown.allSatisfy(selection.contains) ? L("Deselect All") : L("Select All")) {
                            self.selection?.toggleAll(shown)
                        }
                        .font(.subheadline.weight(.medium))
                        .disabled(batch.running)
                        Button(L("Cancel")) {
                            withAnimation(.snappy) { self.selection = nil }
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(batch.running)
                    } else {
                        // Several at once: chosen, then covered with one tap.
                        Button(L("Select")) {
                            withAnimation(.snappy) { selection = GridSelection() }
                        }
                        .font(.subheadline.weight(.medium))
                        // Always there: it also finds screenshots by their words.
                        NavigationLink {
                            AllScreenshotsView(shots: library.shots, protected: protected, zoom: zoom, quick: coverer.cover)
                        } label: {
                            HStack(spacing: 3) {
                                Text(L("See All"))
                                Image(systemName: "chevron.forward")
                                    .font(.footnote.weight(.semibold))
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                }
                ScreenshotGrid(shots: Array(library.shots.prefix(GridZoom.preview(columns: columns))), protected: protected, place: .home, zoom: zoom,
                               quick: coverer.cover, selection: $selection, sweeping: $sweeping)
                    .disabled(batch.running)
            }
        }
    }

    /// How syncing with the Mac stands, when it is on; a tap opens the More tab.
    @ViewBuilder private var syncChip: some View {
        if sync.settings.on {
            Button {
                AppTabs.shared.selection = .more
            } label: {
                Label(sync.state.text, systemImage: sync.state.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.icloud")
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(sync.state.needsAttention ? Color.orange : Color.secondary)
        }
    }

    // MARK: Actions

    /// A photo chosen in Photos, read the right way up and opened to
    /// protect, with whether Photos calls it a screenshot and its lens, so
    /// a photographed document is told from a screenshot.
    private func open(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = Covering.upright(data) else {
            coverer.show(L("The picture could not be read."))
            return
        }
        let info = Imported.Info(screenshot: Library.isScreenshot(item.itemIdentifier, data: data),
                                 focal: ScanCleaner.focalLength(of: data, width: image.width, height: image.height))
        path.append(ProtectSession.Source.picture(Imported.shared.keep(image, info: info)))
    }

    // MARK: Before access

    /// Before access: Snapfly's picture of stacked photos, what it does,
    /// and Allow Access over the promise. The first run has shown it at
    /// work already; the tabs stay, so a document can be scanned first.
    private var welcome: some View {
        ScrollView {
            VStack(spacing: 20) {
                PhotoHero()
                VStack(spacing: 8) {
                    Text(L("Covered before you send"))
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(L("Snapfly covers names, addresses and other private details in your screenshots, right on this iPhone."))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 14) {
                    Button {
                        presses += 1
                        library.ask()
                    } label: {
                        Text(L("Allow Access"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(ProtectButtonStyle())
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(L("Your screenshots are read on this iPhone, and nothing leaves it unless you choose."))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 340)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
    }

    private var denied: some View {
        ContentUnavailableView {
            Label(L("Allow Snapfly to see your screenshots"), systemImage: "photo.badge.exclamationmark")
        } description: {
            Text(L("Snapfly may not see your screenshots. Allow it in Settings › Privacy & Security › Photos."))
        } actions: {
            Button(L("Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(ProtectButtonStyle())
        }
    }
}
