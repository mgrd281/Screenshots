import SwiftUI

/// Settings › Sync: this Mac and the owner's iPhone kept in step through
/// their own iCloud. Off until turned on; covered copies only, unless the
/// owner chooses originals too.
struct SyncPane: View {
    @ObservedObject var sync: SyncCenter

    var body: some View {
        Form {
            if sync.isAvailable {
                choices
                status
                devices
            } else {
                Section {
                    Label(SyncProblem.notInThisBuild.text, systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var choices: some View {
        Section {
            Toggle(isOn: Binding(get: { sync.settings.on }, set: { sync.setOn($0) })) {
                Text(L("Sync with your iPhone"))
                Text(L("What hangs on the line goes to Snapfly on your iPhone with its private details covered, and what you send from the iPhone hangs on the line."))
            }
            Toggle(isOn: Binding(get: { sync.settings.originals }, set: { sync.setOriginals($0) })) {
                Text(L("Originals too"))
                Text(L("Screenshots also go as they were taken, with nothing covered. Only those taken from now on."))
            }
            .disabled(!sync.settings.on)
        } footer: {
            Text(L("It goes through your own iCloud, to your devices signed in to it. Nothing goes through a server of Snapfly's."))
        }
    }

    private var status: some View {
        Section {
            LabeledContent {
                SettingsButton(L("Sync Now")) { sync.syncNow() }
                    .disabled(!sync.settings.on)
            } label: {
                Text(L("This Mac"))
                if sync.state.needsAttention {
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(sync.state.text)")
                } else {
                    Text(sync.state.text)
                }
            }
        }
    }

    private var devices: some View {
        Section(L("Your devices")) {
            if sync.otherDevices.isEmpty {
                Text(L("No other device yet. Turn syncing on in Snapfly on your iPhone, signed in to the same iCloud account."))
                    .foregroundStyle(.secondary)
            }
            ForEach(sync.otherDevices) { device in
                HStack(spacing: 12) {
                    Image(systemName: device.symbol)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(device.presence())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
