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

/// An icon on the tool bar: a 44 pt target, the glyph 18 pt semibold, in
/// the green while it is the tool in hand.
struct DockIcon: View {
    let symbol: String
    var chosen = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(chosen ? AnyShapeStyle(SnapflyTokens.protectTint)
                             : enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The tools in one floating capsule: Select, Marker, Box, Lasso and
/// Eraser, then Undo and Redo. The tool in hand sits on a soft green circle,
/// which glides to the next one chosen. The marker's widths and the
/// eraser's sizes are a long press away, and the tool in hand chosen again
/// opens its options.
struct EditingDock: View {
    @Binding var tool: EditTool
    @Binding var markerWidth: CGFloat
    @Binding var eraserReach: CGFloat
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    let options: () -> Void
    @Namespace private var hand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditTool.allCases) { item in
                Button {
                    if tool == item, item != .select {
                        options()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) { tool = item }
                    }
                } label: {
                    DockIcon(symbol: item.symbol, chosen: tool == item)
                        .background {
                            if tool == item {
                                Circle()
                                    .fill(SnapflyTokens.protect.opacity(0.14))
                                    .frame(width: 36, height: 36)
                                    .matchedGeometryEffect(id: "hand", in: hand)
                            }
                        }
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
enum Leaving: Hashable, Identifiable {
    case copy, share, photos, files, mac
    /// Handed to the app, straight or through the share sheet (`Handoff`).
    case app(ChatTarget)
    var id: Self { self }

    var title: String {
        switch self {
        case .copy: L("Copy")
        case .share: L("Share")
        case .photos: L("Save to Photos")
        case .files: L("Save to Files")
        case .mac: L("Send to Mac")
        case .app(let chat): String(format: L("Send to %@"), chat.name)
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .share: "square.and.arrow.up"
        case .photos: "photo.on.rectangle"
        case .files: "folder"
        case .mac: "laptopcomputer.and.arrow.down"
        case .app: "paperplane"
        }
    }
}

// MARK: How the picture stands

/// How the picture stands, in a small floating capsule under the title,
/// as the engine has it, never ahead of it: while it is read, a spinner and
/// the step, with Don't Wait while Apple Intelligence reads; after a
/// failure, what went wrong and Try Again; then how many places are
/// covered, with the small green shield, and how many are still to check,
/// left visible by the categories chosen, or what is wrong with the picture
/// (`ReviewStatus`); that nothing private was found only when nothing is. A
/// tap opens Details, to see and change every place.
struct PrivacyStatus: View {
    let stage: ProtectSession.Stage
    let tally: ProtectionPlan.Tally
    /// What is wrong with the picture itself, as a scanned page's faults.
    var hints = 0
    /// On Review: what is open in orange, and a chevron, as a tap opens the list.
    var chip = false
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
                // What went wrong wraps onto as many lines as it needs, beside Try Again.
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Try Again"), action: retry)
                        .fontWeight(.semibold)
                        .fixedSize()
                        .touchTarget()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 34)
            case .ready:
                Button(action: open) { counts }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chip ? status.spoken : summary)
                    .accessibilityHint(chip ? "" : L("Details lists every place, to cover or uncover each one."))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("review-status")
            default:
                // The step wraps rather than being cut, at larger text sizes too.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                    if stage == .intelligence {
                        Button(L("Don't Wait"), action: dontWait)
                            .fontWeight(.semibold)
                            .fixedSize()
                            .touchTarget()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 34)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.footnote)
        .editorGlass(in: Capsule())
        // Each step gives way to the next in place, the capsule fitting its words.
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82), value: stage)
        .sensoryFeedback(trigger: stage) { _, now in now == .ready ? .success : nil }
    }

    private var status: ReviewStatus {
        ReviewStatus(covered: tally.covered, open: tally.toCheck, hints: hints, visible: tally.visible)
    }

    private var counts: some View {
        HStack(spacing: 6) {
            if status.state == .nothing {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(SnapflyTokens.protectTint)
                Text(L("Nothing private found"))
            } else {
                Image(systemName: status.covered > 0 ? "checkmark.shield.fill" : "checkmark.shield")
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .symbolEffect(.bounce.up, options: .nonRepeating, value: landed)
                    .onAppear { landed.toggle() }
                if let covering = status.covering {
                    Text(covering)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
                if let pending = status.pending {
                    if status.covering != nil { Text(verbatim: "·").foregroundStyle(.secondary) }
                    // Where the words don't fit, the sign that some are to check, or
                    // are left visible, and how many.
                    ViewThatFits(in: .horizontal) {
                        Text(pending)
                        Label {
                            Text(status.open > 0 ? status.open : status.visible > 0 ? status.visible : status.hints,
                                 format: .number)
                        } icon: {
                            Image(systemName: status.open > 0 && tally.exposed == 0 ? "circle.dashed"
                                : status.state == .visible ? "eye" : "exclamationmark.triangle.fill")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    // Orange words in the deeper orange, so they read on the glass.
                    .foregroundStyle(!chip && status.open > 0 && tally.exposed == 0 ? Color.accentColor
                                     : SnapflyTokens.reviewOpen)
                    .fontWeight(chip ? .semibold : nil)
                    .contentTransition(.numericText())
                }
            }
            if chip {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .contentShape(Capsule())
    }

    /// The whole of it in words, for VoiceOver.
    private var summary: String {
        guard tally.exposed > 0 else { return status.spoken }
        return status.spoken + " " + String(format: L("Not fully protected: %d places to check are not covered"), tally.exposed)
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
                Button(L("Try Again")) { retry(way) }
                    .fontWeight(.semibold)
                    .touchTarget()
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
/// Picture, Previous and Next. Then every place by whose it is, the
/// patient's, the doctors', other people's, and then by what it is, each
/// topic with a switch that covers or uncovers all of it at once, over its
/// places to turn on or off one by one; what Settings leaves visible is
/// listed too, to cover with a tap. What a place hides shows only here, on
/// this iPhone.
struct ReviewSheet: View {
    @ObservedObject var session: ProtectSession
    /// Closes the sheet and shows the place on the picture, selected.
    let show: (ProtectionPlan.Mark) -> Void
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = session.plan
        let doubtful = plan.doubtful
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
                ForEach(plan.topics) { listing in
                    topic(listing)
                }
            }
            .overlay {
                if plan.marks.isEmpty {
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
                    .foregroundStyle(SnapflyTokens.protectTint)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title(of: mark)).font(.headline)
                Spacer()
                Text(mark.covered ? L("Covered") : L("Not covered"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(mark.covered ? SnapflyTokens.protectTint : SnapflyTokens.reviewOpen)
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
                    Label(L("Previous"), systemImage: "chevron.backward").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L("Previous"))
                Spacer()
                Button(L("Show on Picture")) { show(mark) }
                Spacer()
                Button {
                    index = (index + 1) % doubtful.count
                } label: {
                    Label(L("Next"), systemImage: "chevron.forward").labelStyle(.iconOnly)
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

    // MARK: Who and what

    /// A topic: its sign, its name and how much of it is covered, with a
    /// switch for all of it, then its places, each with its own.
    private func topic(_ listing: ProtectionPlan.Listing) -> some View {
        let covered = listing.marks.filter(\.covered).count
        let all = covered == listing.marks.count
        return Section {
            Toggle(isOn: Binding(get: { all }, set: { session.set(Set(listing.marks.map(\.id)), covered: $0) })) {
                HStack(spacing: 12) {
                    TopicSign(symbol: Self.symbol(of: listing.topic), covered: covered, of: listing.marks.count)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.name(of: listing.topic))
                            .font(.headline)
                        Text(String(format: L("%d of %d covered"), covered, listing.marks.count))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
            .tint(SnapflyTokens.protect)
            .sensoryFeedback(.impact(weight: .light), trigger: all)
            ForEach(listing.marks) { mark in
                row(mark)
            }
        }
    }

    /// A place: what it hides, or what it is, and what kind it is, with a
    /// dashed circle while it waits to be checked; swiped, Show on Picture.
    private func row(_ mark: ProtectionPlan.Mark) -> some View {
        let words = mark.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = label(of: mark)
        return Toggle(isOn: Binding(get: { mark.covered }, set: { _ in session.toggle(mark.id) })) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(words.isEmpty ? kind : words)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !words.isEmpty {
                        Text(kind)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if session.plan.needsCheck(mark) {
                    Image(systemName: "circle.dashed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(L("To check"))
                }
            }
            // In line with the topic's name, past its sign.
            .padding(.leading, TopicSign.size + 12)
        }
        .tint(SnapflyTokens.protect)
        .swipeActions(edge: .leading) {
            Button {
                show(mark)
            } label: {
                Label(L("Show on Picture"), systemImage: "viewfinder")
            }
            .tint(SnapflyTokens.protect)
        }
        .contextMenu {
            Button {
                show(mark)
            } label: {
                Label(L("Show on Picture"), systemImage: "viewfinder")
            }
        }
    }

    /// What kind of place it is, in a word or two: the label a labelled
    /// cover shows, or the tool that hid it.
    private func label(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.label }
        switch mark.shape {
        case .stroke: return L("Marker")
        case .outline: return L("Lasso")
        case .box: return L("Box")
        case nil: return mark.origin == .hand ? L("Hidden by hand") : L("Your details and rules")
        }
    }

    static func name(of topic: ProtectionPlan.Topic) -> String {
        switch topic {
        case .patient: L("Patient")
        case .doctors: L("Doctors")
        case .otherPeople: L("Other people")
        case .group(let group): group.title
        case .hand: L("Hidden by hand")
        case .rules: L("Your details and rules")
        }
    }

    static func symbol(of topic: ProtectionPlan.Topic) -> String {
        switch topic {
        case .patient: "person.text.rectangle"
        case .doctors: "stethoscope"
        case .otherPeople: "person.2"
        case .group(.people): "person.crop.circle"
        case .group(.organizations): "building.2"
        case .group(.money): "creditcard"
        case .group(.health): "cross.case"
        case .group(.documents): "doc.text"
        case .group(.access): "key"
        case .hand: "hand.draw"
        case .rules: "text.badge.checkmark"
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
        return mark.origin == .hand ? L("Hidden by hand") : L("Your details and rules")
    }
}

/// A topic's sign in Details: its symbol in a circle, with a ring of how
/// much of it is covered in green, the circle filled once all of it is, and
/// faint while none is.
struct TopicSign: View {
    let symbol: String
    let covered: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 36

    init(symbol: String, covered: Int, of total: Int) {
        self.symbol = symbol
        self.covered = covered
        self.total = total
    }

    var body: some View {
        let share = total > 0 ? CGFloat(covered) / CGFloat(total) : 0
        let all = total > 0 && covered == total
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: share)
                .stroke(SnapflyTokens.protect, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .flipsForRightToLeftLayoutDirection(true)
            Circle()
                .fill(all ? SnapflyTokens.protect : covered > 0 ? SnapflyTokens.protect.opacity(0.12) : Color.primary.opacity(0.06))
                .padding(5)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(all ? Color.white : covered > 0 ? SnapflyTokens.protect : Color.secondary)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82),
                   value: covered)
        .accessibilityHidden(true)
    }
}
