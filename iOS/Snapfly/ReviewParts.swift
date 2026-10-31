import Combine
import SwiftUI
import UIKit
import VisionKit

// Review, for a scanned document's pages: one job, checking the covers.
// Its own bar along the top, the status chip under it, the page as large
// as it can be, the pages small under it and one bar of tools, Covers or
// Page. Everything else is a tap away: the list of places to check, the
// menu, and Save and Share after Next.

// MARK: The bar along the top

/// Review's bar: the round back button, the title with the page under it
/// ("Seite 1 von 3"), the menu, and Next, the one filled button. The title
/// stands in the middle of the screen, at least 12 points clear of the
/// buttons on either side, and only where it would not be, between them.
struct ReviewHeader<More: View>: View {
    let page: Int
    let pages: Int
    let canGoOn: Bool
    let back: () -> Void
    let next: () -> Void
    @ViewBuilder let menu: () -> More

    var body: some View {
        ReviewHeaderLayout(gap: 12) {
            Button(action: back) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                    .editorGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Back"))
            .accessibilityIdentifier("review-back")
            VStack(spacing: 1) {
                Text(L("Review"))
                    .font(.headline)
                if pages > 0 {
                    Text(String(format: L("Page %d of %d"), page, pages))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("review-title")
            HStack(spacing: 8) {
                menu()
                Button(action: next) {
                    Text(L("Next"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(minHeight: SnapflyTokens.touch)
                        .background(SnapflyTokens.protect, in: Capsule())
                        .opacity(canGoOn ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canGoOn)
                .accessibilityIdentifier("scan-next")
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Lays out Review's bar: the first view at the leading edge, the last at
/// the trailing edge, and the one between them in the middle of the bar,
/// `gap` points clear of both; where the middle leaves less room than
/// that, the title sits in the room there is between them.
struct ReviewHeaderLayout: Layout {
    var gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified), trailing = subviews[2].sizeThatFits(.unspecified)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(leading))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(trailing))
        // The room between the buttons, and the room the middle leaves.
        let left = bounds.minX + leading.width + gap, right = bounds.maxX - trailing.width - gap
        let room = max(0, right - left)
        let side = max(leading.width, trailing.width) + gap
        let centred = max(0, bounds.width - 2 * side)
        let ideal = subviews[1].sizeThatFits(.unspecified).width
        if ideal <= centred {
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(width: centred, height: bounds.height))
        } else {
            let width = min(ideal, room)
            let x = min(max(bounds.midX, left + width / 2), right - width / 2)
            subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

/// The menu's round button on Review's bar.
struct ReviewMenuLabel: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
            .editorGlass(in: Circle())
    }
}

// MARK: The bar of tools

/// What Review's bar of tools holds: the tools that cover, or the page's own.
enum ReviewMode: Hashable {
    case cover, page
}

/// One floating bar of glass along the bottom: a switch between Covers and
/// Page on top, the switch sliding on a spring and the row under it
/// crossfading. Covers holds Undo, then Select, Rectangle, Lasso, Brush and
/// Eraser, the tool in hand on a mint pill that glides to the next, then
/// Redo. Page holds Crop, Turn, the colours (named as they are: Farbe,
/// Graustufen, Schwarzweiß), Before and After, and last, apart and in red,
/// Delete. Each is its icon over a short label, Undo and Redo their icons
/// alone; at the accessibility text sizes every icon alone, VoiceOver
/// still saying its name.
struct ReviewToolbar: View {
    @Binding var mode: ReviewMode
    @Binding var tool: EditTool
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    /// The tool in hand chosen again: its options.
    let options: () -> Void
    let comparing: Bool
    let colour: ScanColor
    /// The page is made and shown, so it can be compared.
    let ready: Bool
    let canTurn: Bool
    let compare: () -> Void
    let crop: () -> Void
    let turn: () -> Void
    let choose: (ScanColor) -> Void
    let delete: () -> Void
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The tools that cover, in the order the bar shows them.
    private static let tools: [EditTool] = [.select, .box, .lasso, .marker, .eraser]

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.84)
    }

    var body: some View {
        VStack(spacing: 6) {
            switcher
            ZStack {
                if mode == .cover {
                    coverRow.transition(.opacity)
                } else {
                    pageRow.transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.2), value: mode)
        }
        .padding(8)
        .editorGlass(in: RoundedRectangle(cornerRadius: SnapflyTokens.reviewBarRadius, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: The switch

    private var switcher: some View {
        HStack(spacing: 0) {
            segment(L("Cover Up"), .cover, id: "review-mode-cover")
            segment(L("Page"), .page, id: "review-mode-page")
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func segment(_ title: String, _ value: ReviewMode, id: String) -> some View {
        Button {
            guard mode != value else { return }
            withAnimation(spring) { mode = value }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == value ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if mode == value {
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "segment", in: space)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(id)
    }

    // MARK: Covers

    private var coverRow: some View {
        HStack(spacing: 0) {
            Button(action: undo) { edge("arrow.uturn.backward") }
                .disabled(!canUndo)
                .accessibilityLabel(L("Undo"))
            divider
            ForEach(Self.tools) { item in
                Button {
                    if tool == item, item != .select {
                        options()
                    } else {
                        withAnimation(spring) { tool = item }
                    }
                } label: {
                    self.item(item.title, item.symbol, chosen: tool == item)
                }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tool == item ? [.isSelected, .isButton] : .isButton)
                .accessibilityHint(tool == item && item != .select ? L("Tap again for its options.") : "")
                .accessibilityIdentifier("review-tool-\(item.rawValue)")
            }
            divider
            Button(action: redo) { edge("arrow.uturn.forward") }
                .disabled(!canRedo)
                .accessibilityLabel(L("Redo"))
        }
        .buttonStyle(.plain)
    }

    // MARK: Page

    private var pageRow: some View {
        HStack(spacing: 0) {
            Button(action: crop) { item(L("Crop"), "crop") }
                .accessibilityLabel(L("Crop"))
                .accessibilityIdentifier("scan-crop")
            Button(action: turn) { item(L("Turn"), "rotate.right") }
                .disabled(!canTurn)
                .accessibilityLabel(L("Turn"))
                .accessibilityIdentifier("scan-turn")
            Menu {
                ForEach(ScanColor.allCases) { option in
                    Button { choose(option) } label: {
                        Text(option.title)
                        if let detail = option.detail { Text(detail) }
                        if option == colour { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                item(colour.title, "circle.lefthalf.filled")
            }
            .accessibilityLabel(L("Color"))
            .accessibilityValue(colour.title)
            .accessibilityIdentifier("scan-color")
            Button(action: compare) { item(L("Before"), "square.split.2x1", chosen: comparing) }
                .disabled(!ready)
                .accessibilityLabel(L("Compare"))
                .accessibilityAddTraits(comparing ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("scan-compare")
            divider
            Button(action: delete) { item(L("Delete"), "trash", tint: .red) }
                .accessibilityLabel(L("Delete Page"))
                .accessibilityIdentifier("scan-delete")
        }
        .buttonStyle(.plain)
    }

    // MARK: Its parts

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 2)
    }

    /// Undo or Redo at the bar's ends: the glyph alone, in a 36 point wide,
    /// 44 point high target, so the tools between have room for their names.
    private func edge(_ symbol: String) -> some View {
        ReviewToolItem(title: "", symbol: symbol, chosen: false, tint: nil, labelled: false, space: space)
            .frame(width: 36)
    }

    /// A tool: its icon over its short label, a 44 pt target, on the mint
    /// pill while it is in hand.
    private func item(_ title: String, _ symbol: String, chosen: Bool = false, tint: Color? = nil) -> some View {
        ReviewToolItem(title: title, symbol: symbol, chosen: chosen, tint: tint,
                       labelled: !typeSize.isAccessibilitySize, space: space)
    }
}

/// One tool on Review's bar.
private struct ReviewToolItem: View {
    let title: String
    let symbol: String
    let chosen: Bool
    let tint: Color?
    let labelled: Bool
    let space: Namespace.ID
    @Environment(\.isEnabled) private var enabled

    private var colour: AnyShapeStyle {
        if !enabled { return AnyShapeStyle(.tertiary) }
        if chosen { return AnyShapeStyle(SnapflyTokens.reviewChosenText) }
        if let tint { return AnyShapeStyle(tint) }
        return AnyShapeStyle(.primary)
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(height: 22)
            if labelled {
                Text(title)
                    .font(.caption2.weight(chosen ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    // At least 6 points between two labels, on the smallest iPhone too.
                    .padding(.horizontal, 3)
            }
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
        .background {
            if chosen {
                Capsule()
                    .fill(SnapflyTokens.reviewChosen)
                    .matchedGeometryEffect(id: "tool", in: space)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: The pages

/// The document's pages under the page, small and centred: each 32 by 44
/// points, the open one ringed in green and a little larger, one with
/// something still open marked with a small orange dot, one being made with
/// a spinner, one whose corners wait with the crop glyph; then a dashed
/// plus to add pages. A tap opens a page; dragged onto another it takes
/// that one's place; held, it offers Turn, Crop and Delete.
struct ReviewPages: View {
    @ObservedObject var store: ScannedPages
    let current: UUID
    /// Whether a page has something still open: a place to check or a fault.
    let open: (ScannedPages.Page) -> Bool
    let show: (UUID) -> Void
    let add: (ScanAdding) -> Void
    let turn: (UUID) -> Void
    let crop: (UUID) -> Void
    let delete: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Centred while they fit, scrolling once they no longer do.
        ViewThatFits(in: .horizontal) {
            row
            ScrollViewReader { reader in
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.hidden)
                    .onAppear { reader.scrollTo(current, anchor: .center) }
                    .onChange(of: current) { _, page in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
                            reader.scrollTo(page, anchor: .center)
                        }
                    }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                thumb(page, index: index)
                    .id(page.id)
            }
            plus
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var plus: some View {
        Menu {
            if VNDocumentCameraViewController.isSupported {
                Button { add(.camera(replacing: nil)) } label: { Label(L("Scan Pages"), systemImage: "camera.viewfinder") }
            }
            Button { add(.photos(replacing: nil)) } label: {
                Label(L("Choose from Photos"), systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: SnapflyTokens.reviewThumb.width, height: SnapflyTokens.reviewThumb.height)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: SnapflyTokens.touch, height: 56)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("Add Pages"))
        .accessibilityIdentifier("scan-add")
    }

    private func thumb(_ page: ScannedPages.Page, index: Int) -> some View {
        let chosen = page.id == current
        let base = Button { show(page.id) } label: {
            card(page, chosen: chosen)
        }
        .buttonStyle(.plain)
        .draggable(page.id.uuidString) {
            Image(uiImage: page.thumbnail ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(width: SnapflyTokens.reviewThumb.width, height: SnapflyTokens.reviewThumb.height)
                .clipShape(RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first.flatMap(UUID.init(uuidString:)), moved != page.id,
                  let place = store.index(of: page.id) else { return false }
            withAnimation(reduceMotion || ScanDemo.still ? nil : .snappy) { store.move(moved, to: place) }
            UISelectionFeedbackGenerator().selectionChanged()
            return true
        }
        .contextMenu {
            Button { turn(page.id) } label: { Label(L("Turn"), systemImage: "rotate.right") }
                .disabled(page.way == nil)
            Button { crop(page.id) } label: { Label(L("Crop"), systemImage: "crop") }
            Button(role: .destructive) { delete(page.id) } label: { Label(L("Delete Page"), systemImage: "trash") }
        }
        let named = base
            .accessibilityLabel(label(page, index: index))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("scan-thumb-\(index + 1)")
        return named
            .accessibilityAction(named: L("Move Earlier")) {
                if index > 0 { store.move(page.id, to: index - 1) }
            }
            .accessibilityAction(named: L("Move Later")) {
                if index < store.pages.count - 1 { store.move(page.id, to: index + 1) }
            }
            .accessibilityAction(named: L("Delete Page")) { delete(page.id) }
    }

    /// A page small: a little larger and ringed in green while it is open.
    private func card(_ page: ScannedPages.Page, chosen: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous)
        let grow: CGFloat = chosen ? 1.12 : 1
        return Color(.secondarySystemBackground)
            .overlay {
                if let thumbnail = page.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                }
            }
            .overlay {
                if page.state == .needsCorners {
                    Image(systemName: "crop")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SnapflyTokens.scanWarnText)
                } else if page.state == .waiting || page.state == .improving {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: SnapflyTokens.reviewThumb.width * grow, height: SnapflyTokens.reviewThumb.height * grow)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(chosen ? SnapflyTokens.protectTint : Color.primary.opacity(0.12),
                                   lineWidth: chosen ? 2 : 0.5)
                    .padding(chosen ? -3 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if open(page) {
                    Circle()
                        .fill(SnapflyTokens.reviewOpen)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: SnapflyTokens.touch, height: 56)
            .contentShape(Rectangle())
    }

    /// "Seite 2 von 3, zu prüfen", and that it is being made.
    private func label(_ page: ScannedPages.Page, index: Int) -> String {
        var words = [String(format: L("Page %d of %d"), index + 1, store.pages.count)]
        if open(page) { words.append(L("To check")) }
        if page.state == .needsCorners { words.append(L("corners to set")) }
        if page.state == .waiting || page.state == .improving { words.append(L("being brightened")) }
        return words.joined(separator: ", ")
    }
}

// MARK: The list of places to check

/// Every page's protection, watched together, so the list changes as any
/// page's places are decided.
@MainActor
final class ReviewWatch: ObservableObject {
    private var watched: [ObjectIdentifier: AnyCancellable] = [:]

    /// Follows the protections of the document's pages opened so far.
    func follow(_ sessions: [ProtectSession]) {
        for session in sessions where watched[ObjectIdentifier(session)] == nil {
            watched[ObjectIdentifier(session)] = session.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

/// One place on one page, as the list shows it.
struct ReviewPlace: Identifiable {
    let page: UUID
    let number: Int
    let mark: ProtectionPlan.Mark
    var id: String { "\(page.uuidString)-\(mark.id)" }
}

/// The list of places to check, as tall as what it holds: "2 Stellen zu
/// prüfen" (or "Alles geprüft") and that nothing leaves the iPhone, and,
/// where a page was read as a paper Snapfly knows, which it is
/// ("Arbeitsunfähigkeitsbescheinigung erkannt"); then each place still open,
/// on any page, with what it is, whose it is where Snapfly is sure, its
/// first words and its page, and Leave or Cover, with Cover All over them;
/// the private details the categories chosen leave visible, each with
/// Cover, and a word where no name of the owner's is kept in Always Hide on
/// this iPhone; the page's faults, with Look, which opens that page's own
/// tools; and what is covered, in one line that opens into the list of it.
/// Each decision is one change to undo, and the mark on the page turns
/// with it.
struct ReviewListSheet: View {
    @ObservedObject var store: ScannedPages
    let current: UUID
    /// A place to show first, tapped on the page.
    let focus: Int?
    /// A page's own tools, for a fault: the page opened in Page.
    let look: (UUID) -> Void
    /// A page taken again, for small print that reads unsurely: with the
    /// camera, or as it was taken.
    let retake: (UUID) -> Void
    @StateObject private var watch = ReviewWatch()
    @State private var height: CGFloat = 420
    @State private var coveredOpen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sessions: [(page: ScannedPages.Page, number: Int, session: ProtectSession)] {
        store.pages.enumerated().compactMap { index, page in
            store.opened(page.id).map { (page: page, number: index + 1, session: $0) }
        }
    }

    private var open: [ReviewPlace] {
        sessions.flatMap { page, number, session in
            session.plan.marks.filter(session.plan.needsCheck).map { ReviewPlace(page: page.id, number: number, mark: $0) }
        }
    }

    private var covered: [ReviewPlace] {
        sessions.flatMap { page, number, session in
            session.plan.marks.filter { $0.covered && !session.plan.needsCheck($0) }
                .map { ReviewPlace(page: page.id, number: number, mark: $0) }
        }
    }

    /// What the categories chosen leave visible, never covered: a name
    /// where Names is off.
    private var visible: [ReviewPlace] {
        sessions.flatMap { page, number, session in
            session.plan.marks.filter { $0.origin == .spared && !$0.covered }
                .map { ReviewPlace(page: page.id, number: number, mark: $0) }
        }
    }

    /// The papers the opened pages were read as, like a sick note, each
    /// once, in page order.
    private var papers: [DocumentPaper] {
        var seen = Set<DocumentPaper>()
        return sessions.compactMap { $0.session.paper }.filter { seen.insert($0).inserted }
    }

    private var faults: [(page: ScannedPages.Page, number: Int, issue: ScanIssue)] {
        store.pages.enumerated().flatMap { index, page in page.issues.map { (page: page, number: index + 1, issue: $0) } }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    if !open.isEmpty { openSection }
                    if !visible.isEmpty { visibleSection }
                    if !faults.isEmpty { faultSection }
                    if !covered.isEmpty { coveredSection }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .measuredHeight($height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                watch.follow(sessions.map(\.session))
                if let focus, let place = open.first(where: { $0.page == current && $0.mark.id == focus }) {
                    reader.scrollTo(place.id, anchor: .center)
                }
            }
        }
        .background(SnapflyTokens.hideGround)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(min(height + 16, 640)), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SnapflyTokens.hideSheetRadius)
        .animation(motion, value: open.map(\.id))
        .animation(motion, value: visible.map(\.id))
        .animation(motion, value: coveredOpen)
    }

    // MARK: Its title

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.isHeader)
                Text(L("Decide what is covered. Nothing leaves your iPhone."))
                    .font(.subheadline)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                // What the page was read as, so the owner knows why each
                // detail is what the list says.
                if !papers.isEmpty {
                    Label(String(format: L("%@ recognized"), ListFormatter.localizedString(byJoining: papers.map(\.title))),
                          systemImage: "doc.text.magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("review-paper")
                }
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .frame(width: 30, height: 30)
                    .background(SnapflyTokens.hideButtonOff, in: Circle())
                    .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Close"))
        }
    }

    private var title: String {
        switch open.count {
        case 0: L("Everything checked")
        case 1: L("1 place to check")
        default: String(format: L("%d places to check"), open.count)
        }
    }

    // MARK: Open

    private var openSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(L("Still open"))
                Spacer()
                Button(L("Cover All")) { decideAll() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(SnapflyTokens.hideAccentSoft, in: Capsule())
                    .buttonStyle(.plain)
                    .frame(minHeight: SnapflyTokens.touch)
                    .accessibilityIdentifier("review-cover-all")
            }
            card {
                ForEach(Array(open.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { Divider().padding(.leading, 60) }
                    openRow(place)
                        .id(place.id)
                        // A row decided slides away, or only fades with Reduce Motion.
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
    }

    private func openRow(_ place: ReviewPlace) -> some View {
        row(stacked: typeSize.isAccessibilitySize) {
            sign(place.mark)
            words(place)
        } actions: {
            decisions(place)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(place, L("To check")))
        .accessibilityAction(named: L("Cover")) { decide(place, covered: true) }
        .accessibilityAction(named: L("Leave")) { decide(place, covered: false) }
    }

    /// A row of the list: its sign and words, then its buttons, which keep
    /// their size while the words give way, cut short with "…"; at the
    /// accessibility text sizes the buttons go under the words.
    private func row<Lead: View, Actions: View>(stacked: Bool, @ViewBuilder _ lead: () -> Lead,
                                                @ViewBuilder actions: () -> Actions) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) { lead() }
                .frame(maxWidth: .infinity, alignment: .leading)
            actions()
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private func decisions(_ place: ReviewPlace) -> some View {
        HStack(spacing: 6) {
            Button(L("Leave")) { decide(place, covered: false) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
            Button(L("Cover")) { decide(place, covered: true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(Color.primary, in: Capsule())
                .frame(minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Left visible

    private var visibleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("\(L("Left visible")) · \(visible.count)")
                Spacer()
                Button(L("Cover All")) { coverVisible() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.hideAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(SnapflyTokens.hideAccentSoft, in: Capsule())
                    .buttonStyle(.plain)
                    .frame(minHeight: SnapflyTokens.touch)
                    .accessibilityLabel(L("Cover All Left Visible"))
                    .accessibilityIdentifier("review-cover-visible")
            }
            Text(visibleNote)
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("review-visible-note")
            card {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { Divider().padding(.leading, 60) }
                    row(stacked: typeSize.isAccessibilitySize) {
                        sign(place.mark, muted: true)
                        words(place)
                    } actions: {
                        Button(L("Cover")) { decide(place, covered: true) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(Color.primary, in: Capsule())
                            .frame(minHeight: SnapflyTokens.touch)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .id(place.id)
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Self.spoken(place, L("Left visible")))
                    .accessibilityAction(named: L("Cover")) { decide(place, covered: true) }
                }
            }
        }
    }

    /// Why these show: the categories chosen; and, where a name is among
    /// them and none of the owner's is kept in Always Hide on this iPhone,
    /// that too, as Always Hide is kept on each device alone.
    private var visibleNote: String {
        let note = L("Your categories leave these visible.")
        let names = visible.contains { $0.mark.kind.map(PrivateDetail.allNames.contains) == true }
        let ownName = OwnRules.all.contains { $0.kind == .name && $0.isActive }
        guard names, !ownName else { return note }
        return note + " " + L("No name of yours is kept in Always Hide on this iPhone.")
    }

    private func coverVisible() {
        withAnimation(motion) {
            for (_, _, session) in sessions {
                let ids = Set(session.plan.marks.filter { $0.origin == .spared && !$0.covered }.map(\.id))
                if !ids.isEmpty { session.set(ids, covered: true) }
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Faults

    private var faultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("Hint"))
            card {
                ForEach(Array(faults.enumerated()), id: \.offset) { index, fault in
                    if index > 0 { Divider().padding(.leading, 60) }
                    row(stacked: typeSize.isAccessibilitySize) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SnapflyTokens.reviewOpen)
                            .frame(width: 36, height: 36)
                            .background(SnapflyTokens.reviewOpenFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fault.issue.message(in: store.mode))
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(String(format: L("Page %d"), fault.number))
                                .font(.footnote)
                                .foregroundStyle(SnapflyTokens.hideSecondary)
                        }
                    } actions: {
                        Button(action(for: fault)) {
                            dismiss()
                            if fault.issue.kind == .smallPrint { retake(fault.page.id) } else { look(fault.page.id) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(SnapflyTokens.hideButtonOff, in: Capsule())
                        .frame(minHeight: SnapflyTokens.touch)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    /// What a fault's button does: small print is taken again, closer with
    /// the camera or again for a photo; anything else is looked at.
    private func action(for fault: (page: ScannedPages.Page, number: Int, issue: ScanIssue)) -> String {
        guard fault.issue.kind == .smallPrint else { return L("Look") }
        return fault.page.origin == .camera ? L("Take Closer") : L("Retake for Small Print")
    }

    // MARK: Covered

    private var coveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("\(L("Covered")) · \(covered.count)")
            card {
                Button {
                    coveredOpen.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SnapflyTokens.hideAccent)
                            .frame(width: 36, height: 36)
                            .background(SnapflyTokens.hideAccentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coveredKinds)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(coveredFrom)
                                .font(.footnote)
                                .foregroundStyle(SnapflyTokens.hideSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        // Pointing on in the reading direction, and down once open, in Arabic too.
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(coveredOpen ? 90 : 0))
                            .flipsForRightToLeftLayoutDirection(true)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(coveredOpen ? L("Expanded") : L("Collapsed"))
                if coveredOpen {
                    ForEach(covered) { place in
                        Divider().padding(.leading, 60)
                        row(stacked: typeSize.isAccessibilitySize) {
                            sign(place.mark)
                            words(place)
                        } actions: {
                            Button(L("Uncover")) { decide(place, covered: false) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SnapflyTokens.hideSecondary)
                                .frame(minHeight: SnapflyTokens.touch)
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    /// "Name, Adresse, IBAN": what is covered, each kind once.
    private var coveredKinds: String {
        var seen = Set<String>()
        let names = covered.map { Self.name(of: $0.mark) }.filter { seen.insert($0).inserted }
        return ListFormatter.localizedString(byJoining: Array(names.prefix(4))) + (names.count > 4 ? " …" : "")
    }

    /// Where what is covered comes from: the owner's details, the kinds
    /// chosen, what was covered by hand.
    private var coveredFrom: String {
        let own = covered.contains { $0.mark.kind == nil && $0.mark.origin != .hand }
        let hand = covered.contains { $0.mark.origin == .hand }
        let kinds = covered.contains { $0.mark.kind != nil }
        var said = own && kinds ? L("Your details from Always Hide, the rest from your categories.")
            : own ? L("Your details from Always Hide.") : kinds ? L("From your categories.") : ""
        if hand { said += (said.isEmpty ? "" : " ") + L("Some covered by hand.") }
        return said
    }

    // MARK: Its parts

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SnapflyTokens.hideSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(SnapflyTokens.hideCard, in: RoundedRectangle(cornerRadius: SnapflyTokens.hideCardRadius, style: .continuous))
    }

    /// A place's sign: in orange while it is open, quiet where the
    /// categories leave it visible.
    private func sign(_ mark: ProtectionPlan.Mark, muted: Bool = false) -> some View {
        Image(systemName: Self.symbol(of: mark))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(muted ? SnapflyTokens.hideSecondary : SnapflyTokens.reviewOpen)
            .frame(width: 36, height: 36)
            .background(muted ? SnapflyTokens.hideButtonOff : SnapflyTokens.reviewOpenFill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private func words(_ place: ReviewPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.name(of: place.mark))
                .font(.subheadline.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
            Text(Self.detail(of: place))
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// A row's second line: whose it is first, where Snapfly is sure, then
    /// its first words and its page, "Patient · Beispielyan · Seite 1". Not
    /// on the first line, which the kind's name fills beside the buttons.
    private static func detail(of place: ReviewPlace) -> String {
        [ProtectionPlan.whose(of: place.mark), excerpt(of: place.mark), String(format: L("Page %d"), place.number)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// What VoiceOver says for a row: what the place is, whose it is where
    /// Snapfly is sure, how it stands, and its page.
    private static func spoken(_ place: ReviewPlace, _ state: String) -> String {
        [name(of: place.mark), ProtectionPlan.whose(of: place.mark), state, String(format: L("Page %d"), place.number)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// What a place is: its kind, the owner's details, or covered by hand.
    static func name(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.title }
        return mark.origin == .hand ? L("Hidden by hand") : L("Your details and rules")
    }

    static func symbol(of mark: ProtectionPlan.Mark) -> String {
        if let kind = mark.kind { return kind.symbol }
        return mark.origin == .hand ? "hand.draw" : "person.text.rectangle"
    }

    /// Its first words, as far as a short line shows: "Rechnung Nr. …".
    static func excerpt(of mark: ProtectionPlan.Mark) -> String {
        let text = (mark.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return L("Hidden by hand") }
        guard text.count > 14 else { return text }
        return String(text.prefix(12)).trimmingCharacters(in: .whitespaces) + " …"
    }

    // MARK: Deciding

    private func decide(_ place: ReviewPlace, covered: Bool) {
        guard let session = store.opened(place.page) else { return }
        withAnimation(motion) { session.set([place.mark.id], covered: covered) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func decideAll() {
        withAnimation(motion) {
            for (_, _, session) in sessions {
                let ids = Set(session.plan.marks.filter(session.plan.needsCheck).map(\.id))
                if !ids.isEmpty { session.set(ids, covered: true) }
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: Faults on the page

extension ScanIssue.Kind {
    /// The short name on a fault's outline on the page.
    var tag: String {
        switch self {
        case .blurred: L("Blurred")
        case .glare: L("Reflection")
        case .lessText: L("Hard to read")
        case .smudge: L("Smudged lens")
        case .small: L("Too small")
        case .smallPrint: L("Small print")
        }
    }
}
