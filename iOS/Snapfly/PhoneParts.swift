import SwiftUI

/// How far the protection is, floating over the picture while it is under
/// way: a capsule of glass with a spinner and the step, Don't Wait while
/// Apple Intelligence reads, Try Again after a failure. Gone once ready.
struct StatusPill: View {
    let stage: ProtectSession.Stage
    let onDontWait: @MainActor () -> Void
    let onRetry: @MainActor () -> Void

    var body: some View {
        switch stage {
        case .ready:
            EmptyView()
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Button(L("Try Again"), action: onRetry)
                    .fontWeight(.semibold)
            }
            .floatingPill()
        default:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                if stage == .intelligence {
                    Button(L("Don't Wait"), action: onDontWait)
                        .fontWeight(.semibold)
                }
            }
            .floatingPill()
            .accessibilityElement(children: .combine)
        }
    }

    private var title: String {
        switch stage {
        case .opening: L("Opening…")
        case .finding: L("Finding private details…")
        case .checking: L("Checking the copy…")
        case .intelligence:
            Finder.asksAssistant ? String(format: L("Asking %@…"), AIAccount.provider.name)
                : L("Apple Intelligence is reading…")
        case .ready, .failed: ""
        }
    }
}

extension View {
    /// A capsule of glass floating over the picture, as the iPhone's
    /// floating controls are.
    func floatingPill() -> some View {
        font(.footnote)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .padding(.horizontal, 16)
    }
}

/// A kind and how many places of it are covered, as a quiet chip; in the
/// accent for what is to be checked.
struct KindChip: View {
    let title: String
    let count: Int
    var accent = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(count, format: .number)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.footnote)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(accent ? Color.accentColor : Color.primary)
        .background(accent ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A round floating tool over the picture, 44 pt to touch: glass, or the
/// accent while it is on.
struct ToolButton: View {
    let symbol: String
    var active = false

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Material.regularMaterial), in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .contentShape(Circle())
    }
}

/// Every place on the picture, to turn on or off one by one: those to
/// check first, then what is covered, then what is not. What a place
/// hides shows under its kind, only here, on this iPhone.
struct DetailsSheet: View {
    @ObservedObject var session: ProtectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let marks = session.plan.marks.sorted { $0.rect.maxY > $1.rect.maxY }
        let check = marks.filter { $0.check && !session.plan.isDecided($0.id) && ($0.covered || $0.origin == .possible) }
        let rest = marks.filter { mark in !check.contains { $0.id == mark.id } }
        NavigationStack {
            List {
                if !check.isEmpty {
                    Section {
                        rows(check)
                    } header: {
                        Text(L("To check"))
                    } footer: {
                        Text(L("Snapfly is not sure about these: check each, and turn it on or off."))
                    }
                }
                let covered = rest.filter(\.covered), left = rest.filter { !$0.covered }
                if !covered.isEmpty {
                    Section(L("Covered")) { rows(covered) }
                }
                if !left.isEmpty {
                    Section(L("Not covered")) { rows(left) }
                }
            }
            .overlay {
                if marks.isEmpty {
                    ContentUnavailableView(L("Nothing private found"), systemImage: "checkmark.shield")
                }
            }
            .navigationTitle(L("Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func rows(_ marks: [ProtectionPlan.Mark]) -> some View {
        ForEach(marks) { mark in
            Toggle(isOn: Binding(get: { mark.covered }, set: { _ in session.toggle(mark.id) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: mark))
                    if let text = mark.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func title(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.title }
        return mark.origin == .hand ? L("Hidden by hand") : L("Your own rules")
    }
}
