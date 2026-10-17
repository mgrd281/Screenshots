import SwiftUI

/// What to cover, and how to cover a screenshot with a double tap on the
/// back of the iPhone.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Choice.details

    var body: some View {
        NavigationStack {
            Form {
                ForEach(PrivateDetail.Group.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(group.kinds, id: \.self) { detail in
                            Toggle(detail.title, isOn: binding(for: detail))
                        }
                    }
                }

                Section {
                    step(1, L("Take a screenshot as usual."))
                    step(2, L("Double tap the back of your iPhone: the latest screenshot is covered and copied, ready to paste into a chat."))
                    step(3, String(format: L("To set it up once, open Settings › Accessibility › Touch › Back Tap › Double Tap, and choose %@."),
                                   L("Cover the Latest Screenshot")))
                } header: {
                    Text(L("Double tap the back of your iPhone"))
                } footer: {
                    Text(L("Everything happens on this iPhone. Nothing is sent anywhere."))
                }
            }
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func binding(for detail: PrivateDetail) -> Binding<Bool> {
        Binding {
            chosen.contains(detail)
        } set: { on in
            if on { chosen.insert(detail) } else { chosen.remove(detail) }
            Choice.details = chosen
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}
