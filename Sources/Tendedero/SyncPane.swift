import SwiftUI

/// Settings › Sync: this Mac and the owner's iPhone kept in step through
/// their own iCloud. Off until turned on; covered copies only, unless the
/// owner chooses originals too. An iPhone on another Apple account joins
/// with a code this Mac shows.
struct SyncPane: View {
    @ObservedObject var sync: SyncCenter
    @State private var pairing = false
    @State private var leaving: SyncDevice?
    @State private var problem: String?

    var body: some View {
        Form {
            if sync.isAvailable {
                choices
                status
                devices
                otherAccount
            } else {
                Section {
                    Label(SyncProblem.notInThisBuild.text, systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $pairing) { PairingSheet(sync: sync) }
        .confirmationDialog(String(format: L("Disconnect “%@”?"), leaving?.name ?? ""),
                            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })) {
            Button(L("Disconnect"), role: .destructive) {
                if let leaving { disconnect(leaving) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("It stops syncing with this Mac. What it sent stays here."))
        }
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
        let paired = Set(sync.pairedDevices.map(\.id))
        let own = sync.otherDevices.filter { !paired.contains($0.id) }
        return Section(L("Your devices")) {
            if own.isEmpty {
                Text(L("No other device yet. Turn syncing on in Snapfly on your iPhone, signed in to the same iCloud account."))
                    .foregroundStyle(.secondary)
            }
            ForEach(own) { device in
                DeviceRow(device: device)
            }
        }
    }

    /// An iPhone on another Apple account, joined with a code, and the way
    /// to connect one.
    private var otherAccount: some View {
        Section {
            ForEach(sync.pairedDevices) { device in
                HStack {
                    DeviceRow(device: device)
                    Spacer()
                    Button(L("Disconnect…")) { leaving = device }
                }
            }
            LabeledContent {
                SettingsButton(L("Show Code…")) { pairing = true }
                    .disabled(!sync.canShare)
            } label: {
                Text(L("Connect with a code"))
                Text(sync.canShare
                     ? L("For an iPhone signed in to another Apple account: it types the code this Mac shows.")
                     : L("Turn on syncing on this Mac first, then try again."))
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Another Apple account"))
        } footer: {
            Text(L("You choose on this Mac who joins. A device you connect sees what this Mac syncs, and what it sends hangs on your line."))
        }
    }

    private func disconnect(_ device: SyncDevice) {
        problem = nil
        Task {
            do {
                try await sync.disconnect(device)
            } catch {
                problem = L("Could not disconnect it. Check the connection and try again.")
            }
        }
    }
}

/// A device: its symbol, its name and when it was last there.
private struct DeviceRow: View {
    let device: SyncDevice

    var body: some View {
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

/// The code an iPhone on another Apple account types, a new one every 30
/// seconds, and the question when one did.
private struct PairingSheet: View {
    @ObservedObject var sync: SyncCenter
    @StateObject private var host = PairingHost(name: MacSync.device.name)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            content
                .frame(maxWidth: .infinity, minHeight: 190)
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { host.begin() }
        .onDisappear { host.end() }
    }

    @ViewBuilder private var content: some View {
        switch host.step {
        case .showing:
            code
        case .asking(let request):
            VStack(spacing: 10) {
                Image(systemName: request.device.symbol)
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(String(format: L("Connect “%@”?"), request.device.name))
                    .font(.headline)
                Text(L("It will see what this Mac syncs, and what it sends will hang on your line. Only say yes for a device of your own."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        case .sharing(let name):
            ProgressView(String(format: L("Connecting “%@”…"), name))
        case .joined(let name):
            outcome("checkmark.circle.fill", String(format: L("“%@” is connected."), name),
                    L("What it sends hangs on your line within a minute or two."))
        case .sameAccount(let name):
            outcome("checkmark.circle.fill", String(format: L("“%@” is connected."), name),
                    L("It uses the same Apple account as this Mac, so it syncs as one of your own devices."))
        case .failed(let message):
            outcome("exclamationmark.triangle.fill", L("Not connected"), message)
        }
    }

    private var code: some View {
        let current = host.schedule.current
        let left = current.secondsLeft(now: host.now)
        return VStack(spacing: 10) {
            Text(L("Connect an iPhone on another Apple account"))
                .font(.headline)
            // The way there in the iPhone's own words: More › Mac and iCloud.
            Text(String(format: L("In Snapfly on the iPhone, open %1$@, tap %2$@, and type:"),
                        [L("More"), L("Mac and iCloud")].joined(separator: " › "), L("Connect to a Mac with a Code")))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(current.spaced)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .textSelection(.enabled)
                .accessibilityLabel(current.value.map(String.init).joined(separator: " "))
            ProgressView(value: Double(left), total: PairingCode.period)
                .frame(width: 180)
                .accessibilityHidden(true)
            Text(String(format: L("A new code in %d seconds"), left))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func outcome(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch host.step {
        case .showing:
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        case .asking:
            Button(L("Don't Connect")) { host.decline() }
                .keyboardShortcut(.cancelAction)
            Button(L("Connect")) { host.accept() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .sharing:
            // Stops the attempt, should iCloud not answer.
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        case .joined, .sameAccount:
            // Escape closes it too, as Done does.
            Button { dismiss() } label: { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Button(L("Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .failed:
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L("Try Again")) { host.begin() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
