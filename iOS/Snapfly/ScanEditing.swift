import SwiftUI
import UIKit

// MARK: The editor's pages

/// A scanned page in the editor: which page it is, and the way to another
/// page of the document.
struct ScanContext {
    let page: UUID
    let open: (UUID) -> Void
}

/// The editor for a document's scanned pages, one page at a time, its strip
/// switching between them. A page's editor starts afresh when its shape
/// changes: turned, cut again or taken again. When the page open is taken
/// away, the page in its place opens, or the one before it; with none
/// left, the Scan tab shows again.
struct ScanEditor: View {
    @ObservedObject private var store = ScannedPages.shared
    @State private var current: UUID
    @Environment(\.dismiss) private var dismiss

    init(page: UUID) {
        _current = State(initialValue: page)
    }

    var body: some View {
        ProtectView(source: .scanned(current), scan: ScanContext(page: current, open: { current = $0 }))
            .id("\(current.uuidString)-\(store.page(current)?.revision ?? 0)")
            .onChange(of: store.pages.map(\.id)) { before, ids in
                guard !ids.contains(current) else { return }
                guard let place = before.firstIndex(of: current), !ids.isEmpty else { return dismiss() }
                current = ids[min(place, ids.count - 1)]
            }
    }
}

/// Adding pages to the document, or taking one again: from the camera or
/// from photos.
enum ScanAdding: Equatable {
    case camera(replacing: UUID?)
    case photos(replacing: UUID?)
}

/// A page, by its id, for a sheet that shows it.
struct ScanPageRef: Identifiable, Equatable {
    let id: UUID
}

/// A page to turn or to cut again, while it is asked whether what was
/// covered by hand on it may go.
enum ScanReshape: Equatable {
    case turn(UUID), crop(UUID)

    var page: UUID {
        switch self {
        case .turn(let page), .crop(let page): page
        }
    }

    /// The button that does it.
    var title: String {
        switch self {
        case .turn: L("Turn")
        case .crop: L("Crop")
        }
    }
}

// MARK: How the page stands

/// While a scanned page is made ready, in the status capsule's glass: a
/// spinner and what is happening; or that it could not be read, with Take
/// Again.
struct ScanWorking: View {
    let state: ScannedPages.Page.State
    let retake: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if state == .failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(L("The page could not be read."))
                Button(L("Take Again"), action: retake).fontWeight(.semibold)
            } else {
                ProgressView().controlSize(.small)
                Text(L("Straightening and brightening…"))
            }
        }
        .font(.footnote)
        .lineLimit(2)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .editorGlass(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan-working")
    }
}

/// Over a scanned page once its copy is checked. Green: what was done to
/// the page and what was covered ("Straightened and brightened, text
/// unchanged. 3 private details covered."), and a tap opens Details. Amber,
/// with its edge: what is wrong and where, with Take Again, or Compare when
/// cleaning read less. A warning is said to VoiceOver once.
struct ScanStatusCard: View {
    let page: ScannedPages.Page
    let mode: ScanColor
    let covered: Int
    let toCheck: Int
    let open: () -> Void
    let retake: () -> Void
    let compare: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SnapflyTokens.scanCardRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if let issue = page.issues.first {
                warning(issue)
            } else {
                good
            }
        }
        .frame(maxWidth: 520)
        .onAppear(perform: say)
        .onChange(of: page.issues) { _, _ in say() }
    }

    private var good: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .accessibilityHidden(true)
                Text(goodWords)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(SnapflyTokens.scanGoodText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(SnapflyTokens.scanGood, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("Details lists every place, to cover or uncover each one."))
        .accessibilityIdentifier("scan-status-good")
    }

    /// What was done, and what was covered.
    private var goodWords: String {
        var words = [page.textKept == true ? L("Straightened and brightened, text unchanged.") : L("Straightened and brightened.")]
        switch covered {
        case 0: words.append(L("No private details found."))
        case 1: words.append(L("1 private detail covered."))
        default: words.append(String(format: L("%d private details covered."), covered))
        }
        if toCheck == 1 {
            words.append(L("Check 1 place."))
        } else if toCheck > 1 {
            words.append(String(format: L("Check %d places."), toCheck))
        }
        return words.joined(separator: " ")
    }

    private func warning(_ issue: ScanIssue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(issue.message(in: mode))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: issue.asksForRetake ? retake : compare) {
                Text(issue.asksForRetake ? L("Take Again") : L("Compare"))
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(SnapflyTokens.scanWarnEdge, in: Capsule())
                    .frame(minWidth: SnapflyTokens.touch, minHeight: SnapflyTokens.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scan-status-action")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(SnapflyTokens.scanWarnText)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .background(SnapflyTokens.scanWarn, in: shape)
        .overlay(shape.strokeBorder(SnapflyTokens.scanWarnEdge, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan-status-warning")
    }

    /// The warning, once for each page, to VoiceOver.
    private func say() {
        guard let issue = page.issues.first, ScannedPages.shared.sayOnce(page.id) else { return }
        UIAccessibility.post(notification: .announcement, argument: issue.message(in: mode))
    }
}

// MARK: The pages

/// The document's pages under the page open, in a strip of glass: each
/// small, in order, the one open ringed in green, one with something wrong
/// marked in orange, one still being made with a spinner. A tap opens a
/// page; dragged onto another it takes that one's place; held, it offers
/// Turn, Crop and Delete. The plus adds pages, from the camera or photos.
struct ScanPageStrip: View {
    @ObservedObject var store: ScannedPages
    let current: UUID
    let canScan: Bool
    let open: (UUID) -> Void
    let add: (ScanAdding) -> Void
    let turn: (UUID) -> Void
    let crop: (UUID) -> Void
    let delete: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            // As wide as the pages, and scrolling once they no longer fit.
            ViewThatFits(in: .horizontal) {
                thumbs
                ScrollViewReader { reader in
                    ScrollView(.horizontal) { thumbs }
                        .scrollIndicators(.hidden)
                        .onAppear { reader.scrollTo(current, anchor: .center) }
                }
            }
            Menu {
                if canScan {
                    Button { add(.camera(replacing: nil)) } label: { Label(L("Scan Pages"), systemImage: "camera.viewfinder") }
                }
                Button { add(.photos(replacing: nil)) } label: {
                    Label(L("Choose from Photos"), systemImage: "photo.on.rectangle.angled")
                }
            } label: {
                DockIcon(symbol: "plus")
            }
            .accessibilityLabel(L("Add Pages"))
            .accessibilityIdentifier("scan-add")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .editorGlass(in: RoundedRectangle(cornerRadius: SnapflyTokens.scanStripRadius, style: .continuous))
    }

    private var thumbs: some View {
        HStack(spacing: 6) {
            ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                thumb(page, index: index)
                    .id(page.id)
            }
        }
        .padding(.horizontal, 6)
    }

    private func thumb(_ page: ScannedPages.Page, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous)
        return Button { open(page.id) } label: {
            card(page, chosen: page.id == current)
        }
        .buttonStyle(.plain)
        .draggable(page.id.uuidString) {
            Image(uiImage: page.thumbnail ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 46)
                .clipShape(shape)
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
            Button { crop(page.id) } label: { Label(L("Crop"), systemImage: "crop") }
            Button(role: .destructive) { delete(page.id) } label: { Label(L("Delete Page"), systemImage: "trash") }
        }
        .accessibilityLabel(label(page, index: index))
        .accessibilityAddTraits(page.id == current ? .isSelected : [])
        .accessibilityIdentifier("scan-thumb-\(index + 1)")
        .accessibilityAction(named: L("Move Earlier")) {
            if index > 0 { store.move(page.id, to: index - 1) }
        }
        .accessibilityAction(named: L("Move Later")) {
            if index < store.pages.count - 1 { store.move(page.id, to: index + 1) }
        }
        .accessibilityAction(named: L("Delete Page")) { delete(page.id) }
    }

    /// A page small, as the strip shows it.
    private func card(_ page: ScannedPages.Page, chosen: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.scanThumbRadius, style: .continuous)
        let working = page.state == .waiting || page.state == .improving || page.state == .needsCorners
        return Color(.secondarySystemBackground)
            .overlay {
                if let thumbnail = page.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                }
            }
            .overlay {
                if working { ProgressView().controlSize(.small) }
            }
            .frame(width: 34, height: 46)
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                if !page.issues.isEmpty { warningBadge }
            }
            .overlay {
                shape.strokeBorder(chosen ? SnapflyTokens.protectTint : Color.primary.opacity(0.1), lineWidth: chosen ? 2 : 0.5)
                    .padding(-2)
            }
            .frame(width: SnapflyTokens.touch, height: 52)
            .contentShape(Rectangle())
    }

    /// A page with something wrong: a small orange circle with an
    /// exclamation mark, at its top trailing corner.
    private var warningBadge: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Color.orange, in: Circle())
            .offset(x: 5, y: -5)
    }

    /// "Page 2 of 2, hard to read", and that it is being made.
    private func label(_ page: ScannedPages.Page, index: Int) -> String {
        var words = [String(format: L("Page %d of %d"), index + 1, store.pages.count)]
        if !page.issues.isEmpty { words.append(L("hard to read")) }
        if page.state == .waiting || page.state == .improving { words.append(L("being brightened")) }
        return words.joined(separator: ", ")
    }
}

/// The open page's own tools, in one capsule of glass over the tools that
/// cover: Compare Before and After, Crop, Turn, the document's colours and
/// Delete.
struct ScanPageTools: View {
    let comparing: Bool
    let mode: ScanColor
    let ready: Bool
    let compare: () -> Void
    let crop: () -> Void
    let turn: () -> Void
    let choose: (ScanColor) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: compare) { DockIcon(symbol: "rectangle.split.2x1", chosen: comparing) }
                .accessibilityLabel(L("Compare"))
                .accessibilityAddTraits(comparing ? .isSelected : [])
                .accessibilityIdentifier("scan-compare")
                .disabled(!ready)
            Button(action: crop) { DockIcon(symbol: "crop") }
                .accessibilityLabel(L("Crop"))
                .accessibilityIdentifier("scan-crop")
            Button(action: turn) { DockIcon(symbol: "rotate.right") }
                .accessibilityLabel(L("Turn"))
                .accessibilityIdentifier("scan-turn")
            Menu {
                ForEach(ScanColor.allCases) { option in
                    Button { choose(option) } label: {
                        Text(option.title)
                        if let detail = option.detail { Text(detail) }
                        if option == mode { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                DockIcon(symbol: "circle.lefthalf.filled")
            }
            .accessibilityLabel(L("Color"))
            .accessibilityValue(mode.title)
            .accessibilityIdentifier("scan-color")
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 4)
            Button(action: delete) { DockIcon(symbol: "trash") }
                .accessibilityLabel(L("Delete Page"))
                .accessibilityIdentifier("scan-delete")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .editorGlass(in: Capsule())
    }
}

/// Before and After, named over the page's top corners while they are compared.
struct CompareLabels: View {
    var body: some View {
        HStack {
            label(L("Before"))
            Spacer()
            label(L("After"))
        }
        .padding(.horizontal, 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .editorGlass(in: Capsule())
    }
}
