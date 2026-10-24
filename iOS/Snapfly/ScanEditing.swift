import SwiftUI
import UIKit

// MARK: The editor's pages

/// A scanned page in the editor: which page it is, and the way to another
/// page of the document.
struct ScanContext {
    let page: UUID
    let open: (UUID) -> Void
    /// Another page opened with its own tools in Review's bar, to look at a fault.
    var look: (UUID) -> Void = { _ in }
    /// Review opens with the page's own tools, as Look asked.
    var opensOnPage = false
    /// Where the page came in from: after the one before (1), before the
    /// one after (-1); 0 as Review first opens.
    var arrival: CGFloat = 0
}

/// The editor for a document's scanned pages, one page at a time, its strip
/// switching between them. A page's editor starts afresh when its shape
/// changes: turned, cut again or taken again. When the page open is taken
/// away, the page in its place opens, or the one before it; with none
/// left, the Scan tab shows again.
struct ScanEditor: View {
    @ObservedObject private var store = ScannedPages.shared
    @State private var current: UUID
    /// The open page's shape, kept while the page is taken away, so no
    /// editor is made for a page that is gone.
    @State private var revision: Int
    /// The page opened came in from this side, and with its own tools.
    @State private var arrival: CGFloat = 0
    @State private var onPage = false
    @Environment(\.dismiss) private var dismiss

    init(page: UUID) {
        _current = State(initialValue: page)
        _revision = State(initialValue: ScannedPages.shared.page(page)?.revision ?? 0)
    }

    var body: some View {
        ProtectView(source: .scanned(current),
                    scan: ScanContext(page: current, open: { show($0) }, look: { show($0, onPage: true) },
                                      opensOnPage: onPage, arrival: arrival))
            .id("\(current.uuidString)-\(revision)")
            .onChange(of: store.page(current)?.revision) { _, shape in
                if let shape { revision = shape }
            }
            .onChange(of: store.pages.map(\.id)) { before, ids in
                guard !ids.contains(current) else { return }
                guard let place = before.firstIndex(of: current), !ids.isEmpty else { return dismiss() }
                show(ids[min(place, ids.count - 1)])
            }
    }

    /// Another page of the document, its protection made first, before
    /// its editor is drawn; it comes in from the side it lies on.
    private func show(_ page: UUID, onPage: Bool = false) {
        _ = store.session(page)
        if let from = store.index(of: current), let to = store.index(of: page) {
            arrival = to > from ? 1 : to < from ? -1 : 0
        }
        self.onPage = onPage
        revision = store.page(page)?.revision ?? 0
        current = page
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

/// A page whose corners are set again, with its picture as it came,
/// decoded once for the corner editor.
struct ScanCrop: Identifiable {
    let id: UUID
    let picture: CGImage
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
/// spinner and what is happening; that its corners wait to be set, with
/// Set Corners; or that it could not be read, with Take Again.
struct ScanWorking: View {
    let state: ScannedPages.Page.State
    let retake: () -> Void
    let corners: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(L("The page could not be read."))
                Button(L("Take Again"), action: retake).fontWeight(.semibold)
            case .needsCorners:
                Image(systemName: "crop").foregroundStyle(.orange)
                Text(L("Set the page's corners."))
                Button(L("Set Corners"), action: corners).fontWeight(.semibold)
            default:
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
