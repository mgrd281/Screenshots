import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: Glass

extension View {
    /// Floating glass, as the iPhone's own floating controls are: Liquid
    /// Glass from iOS 26, else a material with a hairline and a soft shadow.
    @ViewBuilder func editorGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    /// The height this view takes, kept in a binding as it changes.
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: MeasuredHeight.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(MeasuredHeight.self) { height.wrappedValue = $0 }
    }
}

private struct MeasuredHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: Icons on the docks

/// An icon on a floating dock: a 44 pt target, the glyph 18 pt semibold, on
/// a green circle in white while it is the tool in hand.
struct DockIcon: View {
    let symbol: String
    var chosen = false
    /// A way out waiting for the copy: a small spinner in its place.
    var waiting = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack {
            if chosen {
                Circle().fill(SnapflyTokens.protect).frame(width: 38, height: 38)
            }
            if waiting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chosen ? AnyShapeStyle(Color.white)
                                     : enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

/// The tools in a floating capsule: Select, Marker, Box, Lasso and Eraser,
/// then Undo and Redo. The marker's widths and the eraser's sizes are a
/// long press away, and the tool in hand chosen again opens its options.
struct EditingDock: View {
    @Binding var tool: EditTool
    @Binding var markerWidth: CGFloat
    @Binding var eraserReach: CGFloat
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    let options: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditTool.allCases) { item in
                Button {
                    if tool == item, item != .select { options() } else { tool = item }
                } label: {
                    DockIcon(symbol: item.symbol, chosen: tool == item)
                }
                .buttonStyle(.plain)
                .contextMenu { sizes(for: item) }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
                .accessibilityHint(tool == item && item != .select ? L("Tap again for its options.") : "")
            }
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 4)
            Button(action: undo) { DockIcon(symbol: "arrow.uturn.backward") }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .accessibilityLabel(L("Undo"))
            Button(action: redo) { DockIcon(symbol: "arrow.uturn.forward") }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .accessibilityLabel(L("Redo"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .editorGlass(in: Capsule())
    }

    @ViewBuilder private func sizes(for item: EditTool) -> some View {
        switch item {
        case .marker:
            ForEach(HandShape.widths.indices, id: \.self) { i in
                choice(widthNames[i], chosen: markerWidth == HandShape.widths[i]) {
                    markerWidth = HandShape.widths[i]
                    tool = .marker
                }
            }
        case .eraser:
            ForEach(eraserSizes.indices, id: \.self) { i in
                choice(eraserNames[i], chosen: eraserReach == eraserSizes[i]) {
                    eraserReach = eraserSizes[i]
                    tool = .eraser
                }
            }
        default:
            Button { tool = item } label: { Label(item.title, systemImage: item.symbol) }
        }
    }

    private func choice(_ title: String, chosen: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if chosen { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

/// The marker's widths, by name, as `HandShape.widths` orders them.
let widthNames = [L("Thin"), L("Medium"), L("Thick")]

/// The eraser's sizes, a share of the picture's width, and their names.
let eraserSizes: [CGFloat] = [0.015, 0.03, 0.06]
let eraserNames = [L("Small"), L("Medium"), L("Large")]

/// The ways a covered copy leaves.
enum Leaving: Identifiable {
    case copy, share, photos, files, mac
    var id: Self { self }

    var title: String {
        switch self {
        case .copy: L("Copy")
        case .share: L("Share")
        case .photos: L("Save to Photos")
        case .files: L("Save to Files")
        case .mac: L("Send to Mac")
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .share: "square.and.arrow.up"
        case .photos: "photo.on.rectangle"
        case .files: "folder"
        case .mac: "laptopcomputer.and.arrow.down"
        }
    }
}

/// Copy, Share and Save in a floating capsule, and Send to Mac while a
/// Mac is there to send to. Save puts the copy in Photos; held, it offers
/// Files too. Held, each says what it does. A way tapped before the copy is
/// ready waits, with a spinner, and goes once it is.
struct ExportDock: View {
    let pending: Leaving?
    let canSend: Bool
    let sent: Bool
    let leave: (Leaving) -> Void

    var body: some View {
        HStack(spacing: 0) {
            way(.copy, symbol: "doc.on.doc")
            way(.share, symbol: "square.and.arrow.up")
            Menu {
                Button { leave(.photos) } label: { Label(Leaving.photos.title, systemImage: Leaving.photos.symbol) }
                Button { leave(.files) } label: { Label(Leaving.files.title, systemImage: Leaving.files.symbol) }
            } label: {
                DockIcon(symbol: "arrow.down.to.line", waiting: pending == .photos || pending == .files)
            } primaryAction: {
                leave(.photos)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .tint(Color.primary)
            .accessibilityLabel(L("Save to Photos"))
            .accessibilityHint(pending == .photos ? L("Goes as soon as the copy is ready.") : "")
            .accessibilityAction(named: L("Save to Files")) { leave(.files) }
            if canSend {
                way(.mac, symbol: "laptopcomputer.and.arrow.down")
                    .disabled(sent)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .editorGlass(in: Capsule())
    }

    private func way(_ way: Leaving, symbol: String) -> some View {
        Button { leave(way) } label: {
            DockIcon(symbol: symbol, waiting: pending == way)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { leave(way) } label: { Label(way.title, systemImage: way.symbol) }
        }
        .accessibilityLabel(way.title)
        .accessibilityHint(pending == way ? L("Goes as soon as the copy is ready.") : "")
    }
}

// MARK: How the picture stands

/// How the picture stands, in a small floating capsule under the title:
/// while it is protected, a spinner and the step, with Don't Wait while
/// Apple Intelligence reads; after a failure, what went wrong and Try
/// Again; then the places covered and those to check, a place only offered
/// never counted as covered. A tap opens the places, to check them.
struct PrivacyStatus: View {
    let stage: ProtectSession.Stage
    let tally: ProtectionPlan.Tally
    let nothingFound: Bool
    let open: @MainActor () -> Void
    let dontWait: @MainActor () -> Void
    let retry: @MainActor () -> Void
    /// Turns each time the copy is ready, so the shield bounces once.
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch stage {
            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).lineLimit(2)
                    Button(L("Try Again"), action: retry).fontWeight(.semibold)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
            case .ready:
                Button(action: open) { counts }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    .accessibilityHint(L("Details lists every place, to cover or uncover each one."))
                    .accessibilityAddTraits(.isButton)
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(step).lineLimit(1)
                    if stage == .intelligence {
                        Button(L("Don't Wait"), action: dontWait).fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.footnote)
        .editorGlass(in: Capsule())
        .padding(.horizontal, 16)
        // Each step gives way to the next in place, the capsule fitting its words.
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82), value: stage)
        .sensoryFeedback(trigger: stage) { _, now in now == .ready ? .success : nil }
    }

    private var counts: some View {
        HStack(spacing: 6) {
            if nothingFound {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(SnapflyTokens.protect)
                Text(L("Nothing private found"))
            } else {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(SnapflyTokens.protect)
                    .symbolEffect(.bounce.up, options: .nonRepeating, value: landed)
                    .onAppear { landed.toggle() }
                Text(tally.covered, format: .number)
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                if tally.toCheck > 0 {
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Image(systemName: tally.exposed > 0 ? "exclamationmark.triangle.fill" : "circle.dashed")
                        .foregroundStyle(tally.exposed > 0 ? Color.orange : Color.accentColor)
                    Text(tally.toCheck, format: .number)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                    Text(L("To check"))
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .contentShape(Capsule())
    }

    /// The whole of it in words, for VoiceOver.
    private var summary: String {
        if nothingFound { return L("Nothing private found") }
        let state = tally.exposed > 0
            ? String(format: L("Not fully protected: %d places to check are not covered"), tally.exposed)
            : tally.toCheck > 0 ? L("Covered. Check the marked places before sharing.") : L("Everything found is covered")
        return "\(state). \(L("Protected")) \(tally.covered), \(L("To check")) \(tally.toCheck), "
            + "\(L("Not protected")) \(tally.left)"
    }

    private var step: String {
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

// MARK: Notes

/// A short note floating over the docks: done, or what went wrong with a
/// way to try again.
struct EditorNote: Equatable {
    let text: String
    var failed = false
    var retry: Leaving?
}

struct EditorNoteView: View {
    let note: EditorNote
    let retry: (Leaving) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: note.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(note.failed ? Color.orange : SnapflyTokens.protect)
            Text(note.text).lineLimit(2)
            if let way = note.retry {
                Button(L("Try Again")) { retry(way) }.fontWeight(.semibold)
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .editorGlass(in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Save to Files

/// The covered copy as a PNG file, for the system's file exporter.
struct PNGFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: Checking the places

/// Every place on the picture. First, those Snapfly was not sure about, one
/// at a time from the top down, with how many are checked: the place as it
/// is on the picture, what it hides, and Cover or Leave Visible, Show on
/// Picture, Previous and Next. Then every other place, to turn on or off
/// one by one. What a place hides shows only here, on this iPhone.
struct ReviewSheet: View {
    @ObservedObject var session: ProtectSession
    /// Closes the sheet and shows the place on the picture, selected.
    let show: (ProtectionPlan.Mark) -> Void
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = session.plan
        let doubtful = plan.doubtful
        let marks = plan.marks.sorted { $0.rect.maxY > $1.rect.maxY }
        // The places not waiting to be checked, decided ones too.
        let rest = marks.filter { !plan.needsCheck($0) }
        NavigationStack {
            List {
                if !doubtful.isEmpty {
                    Section {
                        card(doubtful[min(index, doubtful.count - 1)], of: doubtful)
                    } header: {
                        progress(plan.checked, of: doubtful.count)
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
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear {
            // The first place still to check, else the first.
            index = doubtful.firstIndex(where: session.plan.needsCheck) ?? 0
        }
    }

    private func progress(_ checked: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("To check"))
                Spacer()
                Text(String(format: L("%d of %d checked"), checked, total))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(checked), total: Double(max(total, 1)))
                .tint(SnapflyTokens.protect)
                .accessibilityHidden(true)
        }
        .textCase(nil)
    }

    @ViewBuilder private func card(_ mark: ProtectionPlan.Mark, of doubtful: [ProtectionPlan.Mark]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.plan.toCheck == 0 {
                Label(L("Everything is checked."), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.protect)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title(of: mark)).font(.headline)
                Spacer()
                Text(mark.covered ? L("Covered") : L("Not covered"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(mark.covered ? SnapflyTokens.protect : Color.orange)
            }
            if let crop = crop(of: mark) {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            if let text = mark.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    if mark.covered { session.toggle(mark.id) } else { session.decide([mark.id]) }
                    advance(from: mark)
                } label: {
                    Text(L("Leave Visible")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    if mark.covered { session.decide([mark.id]) } else { session.toggle(mark.id) }
                    advance(from: mark)
                } label: {
                    Text(mark.covered ? L("Keep Covered") : L("Cover")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SnapflyTokens.protect)
            }
            .controlSize(.large)
            HStack {
                Button {
                    index = (index - 1 + doubtful.count) % doubtful.count
                } label: {
                    Label(L("Previous"), systemImage: "chevron.left").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L("Previous"))
                Spacer()
                Button(L("Show on Picture")) { show(mark) }
                Spacer()
                Button {
                    index = (index + 1) % doubtful.count
                } label: {
                    Label(L("Next"), systemImage: "chevron.right").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L("Next"))
            }
            .buttonStyle(.borderless)
            .disabled(doubtful.count < 1)
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.2), value: index)
    }

    /// On to the next place still to check after this one, if any.
    private func advance(from mark: ProtectionPlan.Mark) {
        let doubtful = session.plan.doubtful
        guard let here = doubtful.firstIndex(where: { $0.id == mark.id }) else { return }
        let order = doubtful.indices.map { (here + 1 + $0) % doubtful.count }
        if let next = order.first(where: { session.plan.needsCheck(doubtful[$0]) }) { index = next }
        UISelectionFeedbackGenerator().selectionChanged()
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
            .tint(SnapflyTokens.protect)
        }
    }

    /// The place on the original picture, with a little room round it.
    private func crop(of mark: ProtectionPlan.Mark) -> UIImage? {
        guard let image = session.original?.cgImage else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let rect = mark.rect.insetBy(dx: -0.02, dy: -0.01)
        let pixels = CGRect(x: rect.minX * width, y: (1 - rect.maxY) * height,
                            width: rect.width * width, height: rect.height * height)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard pixels.width >= 1, pixels.height >= 1, let part = image.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: part)
    }

    private func title(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.title }
        return mark.origin == .hand ? L("Hidden by hand") : L("Your own rules")
    }
}
