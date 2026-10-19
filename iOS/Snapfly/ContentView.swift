import Photos
import PhotosUI
import SwiftUI

/// The start: a photo to protect from Photos, what the Mac sent, the
/// screenshots protected lately, and every screenshot, newest first. A tap
/// opens one to protect; holding one down covers and copies it at once.
struct ContentView: View {
    @StateObject private var library = Library()
    @ObservedObject private var guide = PhoneGuide.shared
    @ObservedObject private var sync = SyncCenter.shared
    @State private var showsSettings = false
    /// The picture open, if one is.
    @State private var path: [ProtectSession.Source] = []
    @State private var picked: PhotosPickerItem?
    @State private var recent: [PHAsset] = []
    @State private var note: String?
    @Environment(\.scenePhase) private var phase

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L("Settings"))
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .navigationDestination(for: ProtectSession.Source.self) { source in ProtectView(source: source) }
        }
        .overlay(alignment: .bottom) {
            if let note {
                Text(note)
                    .floatingPill()
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: note)
        .onAppear {
            library.load()
            PhoneSync.start()
            PhotoIndexer.shared.becameActive()
            guide.closeShot = { path.removeAll() }
            guide.openNewest = {
                guard let newest = library.shots.first?.localIdentifier else { return false }
                path.append(.asset(newest))
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
        .onChange(of: path) { _, now in
            if now.isEmpty { recent = Library.assets(Recent.ids) }
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

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(L("Protect a Photo"), systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                    syncChip
                }
                .padding(.horizontal, 6)
                // What the Mac sent, when syncing is on.
                FromMacRow(sync: sync)
                if !recent.isEmpty {
                    row(L("Protected lately"), recent)
                }
                if !library.shots.isEmpty {
                    Text(L("Screenshots"))
                        .font(.headline)
                        .padding(.horizontal, 6)
                }
                grid
            }
            .padding(.vertical, 6)
        }
        .phoneGuide(on: .library)
        .onAppear {
            recent = Library.assets(Recent.ids)
            if !library.shots.isEmpty { guide.offerIfDue() }
        }
        .overlay {
            if library.shots.isEmpty {
                ContentUnavailableView(L("No screenshots yet"), systemImage: "camera.viewfinder",
                                       description: Text(L("Take a screenshot, then come back here.")))
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
            ForEach(library.shots, id: \.localIdentifier) { asset in
                NavigationLink(value: ProtectSession.Source.asset(asset.localIdentifier)) {
                    Thumbnail(asset: asset)
                }
                .accessibilityLabel(L("Cover Private Details"))
                .contextMenu {
                    Button {
                        quickProtect(asset)
                    } label: {
                        Label(L("Cover and Copy"), systemImage: "doc.on.doc")
                    }
                }
                .phoneGuideTarget(.firstShot, on: asset.localIdentifier == library.shots.first?.localIdentifier)
            }
        }
        .padding(.horizontal, 6)
    }

    /// A row that scrolls sideways, as From your Mac is.
    private func row(_ title: String, _ assets: [PHAsset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        NavigationLink(value: ProtectSession.Source.asset(asset.localIdentifier)) {
                            Thumbnail(asset: asset, aspect: 3 / 4)
                                .frame(width: 104)
                        }
                        .accessibilityLabel(L("Cover Private Details"))
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    /// How syncing with the Mac stands, when it is on; a tap opens Settings.
    @ViewBuilder private var syncChip: some View {
        if sync.settings.on {
            Button {
                showsSettings = true
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

    /// A photo chosen in Photos, read the right way up and opened to protect.
    private func open(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = Covering.upright(data) else {
            show(L("The picture could not be read."))
            return
        }
        path.append(.picture(Imported.shared.keep(image)))
    }

    /// Covers a screenshot as Settings says, checks it and copies it, without
    /// opening it.
    private func quickProtect(_ asset: PHAsset) {
        show(L("Covering private details…"), for: 60)
        Task {
            guard let image = await Library.image(of: asset) else {
                show(L("The picture could not be read."))
                return
            }
            guard let covered = await Covering.cover(image, Choice.details), let png = Covering.png(covered.image) else {
                show(L("The copy could not be made."))
                return
            }
            Covering.copy(png)
            Recent.note(asset.localIdentifier)
            recent = Library.assets(Recent.ids)
            PhoneGuide.shared.happened(.used)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show(L("Covered and copied, ready to paste."))
        }
    }

    /// A short note over the bottom of the screen, gone after a while.
    private func show(_ text: String, for seconds: Double = 2.5) {
        note = text
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if note == text { note = nil }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text(L("Allow Snapfly to see your screenshots"))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(L("Snapfly covers names, addresses and other private details in your screenshots, right on this iPhone."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("Allow Access")) { library.ask() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
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
            .buttonStyle(.borderedProminent)
        }
    }
}

/// One screenshot, in the shape of a phone's screen, or of From your Mac's
/// previews in a row.
private struct Thumbnail: View {
    let asset: PHAsset
    var aspect: CGFloat = 9 / 19.5
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task { image = await Library.thumbnail(of: asset, width: 320) }
    }
}
