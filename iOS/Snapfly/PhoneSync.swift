import SwiftUI
import UIKit

/// Syncing on the iPhone: what the Mac sends shows under "From your Mac",
/// and Send to Mac sends a covered screenshot to the Mac's line, through the
/// owner's own iCloud. `SyncCenter` does the rest, as on the Mac.
@MainActor
enum PhoneSync {
    static func start() {
        SyncCenter.shared.start(as: device)
    }

    /// This iPhone, as the Mac lists it.
    static var device: SyncDevice {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return SyncDevice(id: SyncSettings.deviceID(), name: UIDevice.current.name,
                          platform: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone,
                          model: model, registered: SyncCenter.registered, lastSeen: Date(), lastSync: nil,
                          appVersion: version, schema: SyncSchema.current)
    }

    /// The hardware, like "iPhone16,1".
    private static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// What the Mac sent, newest first, in a row above the screenshots.
struct FromMacRow: View {
    @ObservedObject var sync: SyncCenter
    @State private var open: SyncRevision?

    var body: some View {
        let received = sync.received
        if !received.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("From your Mac"))
                    .font(.headline)
                    .padding(.horizontal, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(received, id: \.version.id) { item in
                            Button {
                                open = item.version
                            } label: {
                                ReceivedThumbnail(preview: sync.preview(of: item.version.id))
                            }
                            .accessibilityLabel(item.screenshot.name.value)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.top, 6)
            .sheet(item: $open) { version in ReceivedView(version: version) }
        }
    }
}

/// One picture from the Mac, by its preview, in the shape of the grid's.
private struct ReceivedThumbnail: View {
    let preview: URL?

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(width: 104)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let preview, let image = UIImage(contentsOfFile: preview.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A picture from the Mac, fetched whole when opened, ready to copy, share
/// or save, as a covered screenshot is.
struct ReceivedView: View {
    let version: SyncRevision
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var data: Data?
    @State private var failed = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()
                } else if failed {
                    ContentUnavailableView(L("The picture could not be fetched. Check the connection and try again."),
                                           systemImage: "icloud.slash")
                } else {
                    ProgressView(L("Fetching from iCloud…"))
                        .padding(.top, 120)
                }
            }
            .navigationTitle(L("From your Mac"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let image, let data { actions(image, data) }
            }
            .task { await fetch() }
        }
    }

    private func actions(_ image: UIImage, _ data: Data) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Covering.copy(image.pngData() ?? data)
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
                            try await Covering.save(data)
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

    private func fetch() async {
        guard image == nil else { return }
        do {
            let url = try await SyncCenter.shared.picture(version.id)
            let loaded = try Data(contentsOf: url)
            guard let picture = UIImage(data: loaded) else { throw CocoaError(.fileReadCorruptFile) }
            data = loaded
            image = picture
        } catch {
            failed = true
        }
    }
}

/// Syncing in Settings: on or off, how it stands, and the owner's devices.
struct SyncSection: View {
    @ObservedObject var sync: SyncCenter

    var body: some View {
        if sync.isAvailable {
            Section {
                Toggle(isOn: Binding(get: { sync.settings.on }, set: { sync.setOn($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sync with your Mac"))
                        Text(L("What the Mac's line holds shows here with its private details covered, and Send to Mac hangs a covered screenshot on the Mac's line."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("This iPhone")) {
                    if sync.state.needsAttention {
                        Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(sync.state.text)")
                            .foregroundStyle(.orange)
                    } else {
                        Text(sync.state.text)
                    }
                }
                if sync.settings.on {
                    Button(L("Sync Now")) { sync.syncNow() }
                }
                ForEach(sync.otherDevices) { device in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text(device.presence())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: device.symbol)
                    }
                }
            } header: {
                Text(L("Sync"))
            } footer: {
                Text(L("It goes through your own iCloud, to your devices signed in to it. Nothing goes through a server of Snapfly's."))
            }
            OtherAccountSection(sync: sync)
        }
    }
}

/// Macs on another Apple account, joined with the code they show.
private struct OtherAccountSection: View {
    @ObservedObject var sync: SyncCenter
    @State private var joining = false
    @State private var leaving: SyncCenter.Connection?

    var body: some View {
        Section {
            ForEach(sync.connections) { connection in
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                            Text(connection.state.text)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "laptopcomputer")
                    }
                    Spacer()
                    Button(L("Disconnect…"), role: .destructive) { leaving = connection }
                        .buttonStyle(.borderless)
                }
            }
            Button {
                joining = true
            } label: {
                Label(L("Connect to a Mac with a Code"), systemImage: "number")
            }
        } header: {
            Text(L("Another Apple account"))
        } footer: {
            Text(L("For a Mac signed in to another Apple account. On the Mac, open Snapfly's Settings, then Sync, and click Show Code."))
        }
        .sheet(isPresented: $joining) { PairingJoinView(sync: sync) }
        .confirmationDialog(String(format: L("Disconnect “%@”?"), leaving?.name ?? ""),
                            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                            titleVisibility: .visible) {
            Button(L("Disconnect"), role: .destructive) {
                if let leaving { Task { await sync.leave(leaving.owner) } }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This iPhone stops syncing with that Mac, and what came from it goes from here."))
        }
    }
}

/// Typing the code a Mac on another Apple account shows; the person at
/// the Mac then says yes.
struct PairingJoinView: View {
    @ObservedObject var sync: SyncCenter
    @StateObject private var guest = PairingGuest()
    @State private var code = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch guest.step {
                case .typing, .failed:
                    typing
                case .looking:
                    working(L("Looking for the Mac…"))
                case .waiting(let name):
                    working(String(format: L("Say yes on “%@” to connect."), name))
                case .joining(let name):
                    working(String(format: L("Connecting to “%@”…"), name))
                case .joined(let name):
                    done(String(format: L("Connected to “%@”. What it sends shows under From your Mac."), name))
                case .sameAccount(let name):
                    done(String(format: L("“%@” uses the same Apple account, so Sync with your Mac is now on."), name))
                }
            }
            .navigationTitle(L("Connect to a Mac"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !finished {
                        Button(L("Cancel")) {
                            guest.cancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if finished {
                        Button(L("Done")) { dismiss() }
                    } else if isTyping {
                        Button(L("Connect")) { join() }
                            .disabled(PairingCode.normalize(code) == nil)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private var isTyping: Bool {
        switch guest.step {
        case .typing, .failed: true
        default: false
        }
    }

    private var finished: Bool {
        switch guest.step {
        case .joined, .sameAccount: true
        default: false
        }
    }

    private var typing: some View {
        Section {
            TextField("000 000", text: $code)
                .keyboardType(.numberPad)
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focused)
                .accessibilityLabel(L("Code"))
                .onChange(of: code) { _, now in
                    if PairingCode.normalize(now) != nil { join() }
                }
        } footer: {
            if case .failed(let message) = guest.step {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text(L("On the Mac, open Snapfly's Settings, then Sync, and click Show Code. A new code shows every 30 seconds."))
            }
        }
    }

    private func working(_ text: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(text)
            }
        }
    }

    private func done(_ text: String) -> some View {
        Section {
            Label(text, systemImage: "checkmark.circle.fill")
        }
    }

    private func join() {
        focused = false
        guest.join(code, as: PhoneSync.device)
    }
}
