import Photos
import SwiftUI

/// The screenshots in Photos, newest first. A tap covers one.
struct ContentView: View {
    @StateObject private var library = Library()
    @ObservedObject private var guide = PhoneGuide.shared
    @State private var showsSettings = false
    /// The screenshot open, if one is.
    @State private var path: [String] = []
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.mayRead {
                    grid
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
            .navigationDestination(for: String.self) { id in CoveredView(assetID: id) }
        }
        .onAppear {
            library.load()
            guide.closeShot = { path.removeAll() }
            guide.openNewest = {
                guard let newest = library.shots.first?.localIdentifier else { return false }
                path.append(newest)
                return true
            }
        }
        .onChange(of: phase) { _, now in
            if now == .active { library.load() }
        }
        // The introduction, once, as the first screenshots show.
        .onChange(of: library.shots.isEmpty) { _, empty in
            if !empty { guide.offerIfDue() }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                ForEach(library.shots, id: \.localIdentifier) { asset in
                    NavigationLink(value: asset.localIdentifier) {
                        Thumbnail(asset: asset)
                    }
                    .accessibilityLabel(L("Cover Private Details"))
                    .phoneGuideTarget(.firstShot, on: asset.localIdentifier == library.shots.first?.localIdentifier)
                }
            }
            .padding(6)
        }
        .phoneGuide(on: .library)
        .onAppear { if !library.shots.isEmpty { guide.offerIfDue() } }
        .overlay {
            if library.shots.isEmpty {
                ContentUnavailableView(L("No screenshots yet"), systemImage: "camera.viewfinder",
                                       description: Text(L("Take a screenshot, then come back here.")))
            }
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
            Text(L("Snapfly covers names, addresses and other private details in your screenshots, right on this iPhone. Nothing is sent anywhere."))
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

/// One screenshot in the grid, in the shape of a phone's screen.
private struct Thumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(9 / 19.5, contentMode: .fit)
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
