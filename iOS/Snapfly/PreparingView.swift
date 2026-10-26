import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Faster picture processing, in Settings: what it does and the owner's yes
/// first, then how far it is, with real numbers only, and the owner's
/// controls: Pause, Prepare Now, which photos, and Delete Local Index.
struct PreparingView: View {
    @ObservedObject private var indexer = PhotoIndexer.shared
    @State private var asking = false
    @State private var deleting = false
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        Form {
            if indexer.settings.isOn {
                status
                controls
                photos
            } else {
                Section {
                    explanation
                    Button(L("Turn On…")) { asking = true }
                }
            }
        }
        .navigationTitle(L("Faster picture processing"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $asking) { PreparingConsent() }
        .task { await indexer.refresh() }
        .confirmationDialog(L("Delete everything prepared on this iPhone?"), isPresented: $deleting,
                            titleVisibility: .visible) {
            Button(L("Delete Local Index"), role: .destructive) { Task { await indexer.deleteIndex() } }
        } message: {
            Text(L("Preparing waits until you go on. Your photos stay as they are."))
        }
        .onChange(of: picked) { _, items in
            let ids = items.compactMap(\.itemIdentifier)
            if !ids.isEmpty { indexer.pick(ids) }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Snapfly can prepare your pictures from the last 60 days on this iPhone, so private details are found faster later."))
            Text(L("Off until you turn it on. Nothing leaves this iPhone."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: How far

    private var status: some View {
        let progress = indexer.progress
        return Section {
            LabeledContent(L("Status"), value: state)
            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .accessibilityLabel(L("Prepared"))
                    .accessibilityValue(Text(progress.fraction, format: .percent.precision(.fractionLength(0))))
            }
            LabeledContent(L("Prepared"), value: String(format: L("%d of %d"), progress.ready, progress.total))
            LabeledContent(L("Still to prepare"), value: progress.remaining.formatted())
            if progress.inCloud > 0 {
                LabeledContent {
                    Text(progress.inCloud.formatted())
                } label: {
                    Text(L("Only in iCloud"))
                    Text(L("Not downloaded for this. Prepared once they are on this iPhone."))
                }
            }
            if progress.failed > 0 {
                LabeledContent(L("Could not be read"), value: progress.failed.formatted())
            }
            LabeledContent(L("Last update"), value: indexer.lastUpdate.map {
                $0.formatted(.relative(presentation: .named))
            } ?? L("Not yet"))
            LabeledContent(L("Room on this iPhone"),
                           value: ByteCountFormatter.string(fromByteCount: Int64(indexer.bytes), countStyle: .file))
        } footer: {
            Text(L("Snapfly prepares while it is open, and in the background while your iPhone is charging, when iOS allows. It waits in Low Power Mode and when your iPhone is warm."))
        }
    }

    private var state: String {
        if indexer.settings.paused { return L("Paused") }
        switch indexer.waiting {
        case .lowPower?: return L("Waiting for Low Power Mode to end")
        case .hot?: return L("Waiting for your iPhone to cool down")
        case .memory?: return L("Waiting for memory")
        case .busy?: return L("Waiting while you protect a picture")
        case .owner?: return L("Paused")
        case nil: break
        }
        if indexer.isRunning { return L("Preparing…") }
        if indexer.progress.remaining == 0 { return L("Up to date") }
        return L("Waiting for the next chance")
    }

    // MARK: The owner's controls

    private var controls: some View {
        Section {
            if indexer.settings.paused {
                Button(L("Resume")) { indexer.resume() }
            } else {
                Button(L("Pause")) { indexer.pause() }
                Button(L("Prepare Now")) { indexer.prepareNow() }
                    .disabled(indexer.isRunning || indexer.progress.remaining == 0)
            }
            Button(L("Delete Local Index"), role: .destructive) { deleting = true }
            Button(L("Turn Off"), role: .destructive) { Task { await indexer.turnOff() } }
        } footer: {
            Text(L("Turning it off deletes everything prepared."))
        }
    }

    private var photos: some View {
        Section {
            Picker(L("Photos"), selection: Binding(get: { indexer.settings.scope }, set: { indexer.choose($0) })) {
                ForEach(IndexSettings.Scope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            LabeledContent(L("Period"), value: indexer.settings.scope == .selected
                ? L("The photos you chose") : String(format: L("Last %d days"), indexer.settings.days))
            if indexer.settings.scope == .selected {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Text(indexer.settings.selected.isEmpty ? L("Choose Photos…")
                         : String(format: L("%d photos chosen"), indexer.settings.selected.count))
                }
            }
            if indexer.isLimited {
                Button(L("Change Allowed Photos…")) { Library.changeAllowedPhotos() }
            }
        } header: {
            Text(L("What is prepared"))
        } footer: {
            if indexer.isLimited {
                Text(L("Snapfly may see only some of your photos. Only those can be prepared."))
            }
        }
    }
}

/// What Faster picture processing does, said before it is turned on, with
/// which photos it may prepare. Nothing happens until the owner says yes.
struct PreparingConsent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope = IndexSettings.Scope.screenshots

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "bolt.badge.clock")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(L("Snapfly can prepare your pictures from the last 60 days on this iPhone, so private details are found faster later."))
                            .font(.body)
                    }
                    .padding(.vertical, 6)
                    point("iphone", L("Read on this iPhone only. Nothing is sent anywhere."))
                    point("lock", L("What is read is kept locked on this iPhone, never in backups, and deleted when you turn this off."))
                    point("battery.100.bolt", L("It works while Snapfly is open, and in the background while your iPhone is charging, when iOS allows."))
                    point("icloud.slash", L("Photos only in iCloud are not downloaded for this."))
                }
                Section {
                    Picker(L("Photos"), selection: $scope) {
                        ForEach(IndexSettings.Scope.allCases, id: \.self) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L("What may be prepared"))
                } footer: {
                    Text(L("Allowing Snapfly to see your photos is not a yes to this. You can pause it, or delete what was prepared, at any time."))
                }
            }
            .navigationTitle(L("Enable faster picture processing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Not Now")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Turn On")) {
                        PhotoIndexer.shared.turnOn(scope)
                        dismiss()
                    }
                }
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
    }
}

extension IndexSettings.Scope {
    var title: String {
        switch self {
        case .screenshots: L("Screenshots only")
        case .allowed: L("All allowed photos")
        case .selected: L("Only selected photos")
        }
    }
}
