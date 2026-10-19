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
    /// Each press of the green button, for its haptic.
    @State private var presses = 0
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// How many screenshots the home screen shows before See All.
    private let preview = 8

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
            PhoneSync.start()
            PhotoIndexer.shared.becameActive()
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
        .background(Color(.systemBackground))
        // The status bar stays readable over what scrolls under it.
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(.bar) }
        .phoneGuide(on: .library)
        .onAppear {
            if !library.shots.isEmpty { guide.offerIfDue() }
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
            protectButton
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
                protectButton
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 4) {
                PhotoHero(scale: 0.46)
                    .padding(.leading, -12)
                VStack(alignment: .leading, spacing: 12) {
                    words(center: false)
                    protectButton
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
    private var protectButton: some View {
        PhotosPicker(selection: $picked, matching: .images) {
            Label(L("Protect a Photo"), systemImage: "shield.lefthalf.filled")
        }
        .buttonStyle(ProtectButtonStyle())
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
                ScreenshotGrid(shots: Array(library.shots.prefix(preview)), protected: protected, place: .home, zoom: zoom,
                               quick: coverer.cover)
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

    /// A photo chosen in Photos, read the right way up and opened to protect.
    private func open(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = Covering.upright(data) else {
            coverer.show(L("The picture could not be read."))
            return
        }
        path.append(ProtectSession.Source.picture(Imported.shared.keep(image)))
    }

    // MARK: Before access

    /// The first launch: the whole picture, what Snapfly does, and access.
    private var welcome: some View {
        ScrollView {
            VStack(spacing: 20) {
                PhotoHero()
                    .padding(.top, 24)
                VStack(spacing: 8) {
                    Text(L("Allow Snapfly to see your screenshots"))
                        .font(.title2.weight(.bold))
                    Text(L("Snapfly covers names, addresses and other private details in your screenshots, right on this iPhone."))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Button(L("Allow Access")) {
                    presses += 1
                    library.ask()
                }
                .buttonStyle(ProtectButtonStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: presses)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
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
