import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The scanned pages as one PDF, for the system's file exporter.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
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

/// Save and Share: the scanned pages as one A4 PDF or as a PNG each, with
/// their covers (recommended, and where every save starts) or only cleaned,
/// and for a PDF its text to find and copy or not; then Copy, Save (a PDF
/// to Files, pictures to Photos) or Share. Without covers, a warning says
/// the file holds every private detail, and nothing that leaves is called
/// protected. A line under it says what was done to the pages.
struct ScanSaveSheet: View {
    enum Format: Hashable {
        case pdf, picture
    }

    enum Way {
        case copy, save, share
    }

    @ObservedObject private var store = ScannedPages.shared
    @State private var format = Format.pdf
    /// Every save starts covered.
    @State private var covered = !ScanDemo.uncovered
    @State private var searchable = true
    @State private var working: Way?
    @State private var exporting: PDFFile?
    @State private var sharing: SharedFiles?
    @State private var note: (text: String, failed: Bool)?
    /// What the sheet holds, and its buttons, so it is as tall as they are.
    @State private var contentHeight: CGFloat = 520
    @State private var waysHeight: CGFloat = 110
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var count: Int { store.pages.count }

    /// As tall as what it holds, its title bar too; at the accessibility
    /// text sizes, the whole screen, where it scrolls.
    private var detent: PresentationDetent {
        typeSize.isAccessibilitySize ? .large : .height(contentHeight + waysHeight + 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    formats
                    covers
                    if format == .pdf { text }
                    checked
                }
                .padding(16)
                .measuredHeight($contentHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { ways.measuredHeight($waysHeight) }
            .navigationTitle(L("Save and Share"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86), value: covered)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86), value: format)
        }
        .presentationDetents([detent])
        .presentationDragIndicator(.visible)
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .pdf, defaultFilename: ScannedPages.fileName) { result in
            switch result {
            case .success: done(covered ? L("Saved to Files") : L("Saved to Files, without covers"))
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { failed() }
            }
        }
        .sheet(item: $sharing) { files in
            ShareFilesSheet(files: files)
                .ignoresSafeArea()
        }
        .task(id: note?.text) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            note = nil
        }
    }

    // MARK: Format

    private var formats: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(L("Format"))
            HStack(spacing: 12) {
                tile(.pdf, symbol: "doc.richtext", title: "PDF",
                     detail: count == 1 ? L("A4, 1 page") : String(format: L("A4, %d pages"), count))
                tile(.picture, symbol: "photo", title: L("Picture"),
                     detail: count == 1 ? L("PNG, 1 file") : String(format: L("PNG, %d files"), count))
            }
        }
    }

    private func tile(_ kind: Format, symbol: String, title: String, detail: String) -> some View {
        let chosen = format == kind
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            format = kind
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(chosen ? SnapflyTokens.protectTint : .secondary)
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(chosen ? SnapflyTokens.protectTint : Color.primary.opacity(0.08), lineWidth: chosen ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(kind == .pdf ? "scan-format-pdf" : "scan-format-picture")
    }

    // MARK: Covers

    /// Said under Without Covers while it is chosen.
    private static var warning: String {
        L("This file holds every private detail. Share it only with people you trust.")
    }

    private var covers: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(L("Covers"))
            VStack(spacing: 0) {
                choice(true, title: L("With Covers"), detail: L("Private details stay covered"), badge: L("Recommended"))
                Divider().padding(.leading, 52)
                choice(false, title: L("Without Covers"), detail: L("Only scanned clean, for a tax adviser, say"), badge: nil)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !covered {
                Label {
                    Text(Self.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SnapflyTokens.scanWarnText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SnapflyTokens.scanWarn, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SnapflyTokens.scanWarnEdge))
                .transition(.opacity.combined(with: .move(edge: .top)))
                // Read with Without Covers itself, so it is never missed.
                .accessibilityHidden(true)
                .accessibilityIdentifier("scan-uncovered-warning")
            }
        }
    }

    private func choice(_ withCovers: Bool, title: String, detail: String, badge: String?) -> some View {
        let chosen = covered == withCovers
        return Button {
            covered = withCovers
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? SnapflyTokens.protectTint : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.body.weight(.medium))
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SnapflyTokens.hideAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(SnapflyTokens.hideAccentSoft, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: SnapflyTokens.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(!withCovers && chosen ? Self.warning : "")
        .accessibilityIdentifier(withCovers ? "scan-with-covers" : "scan-without-covers")
    }

    // MARK: Text

    private var text: some View {
        Toggle(isOn: $searchable) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Searchable Text")).font(.body.weight(.medium))
                Text(covered ? L("Without the covered details") : L("Holds all the text"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(SnapflyTokens.protect)
        .accessibilityIdentifier("scan-searchable")
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity)
    }

    /// What was done to the pages, as the checks found it: only geometry and
    /// light, and no text or number changed where every page read the same;
    /// and the places still to check on pages opened, with covers.
    private var checked: some View {
        let lessText = store.pages.contains { page in page.issues.contains { $0.kind == .lessText } }
        let kept = !store.pages.isEmpty && store.pages.allSatisfy { $0.textKept == true }
        let words = lessText ? L("Only straightened and brightened. Check the marked places.")
            : kept ? L("Only straightened and brightened. No text, no number changed.")
            : L("Only straightened and brightened.")
        let toCheck = store.pages.reduce(0) { $0 + (store.opened($1.id)?.plan.tally.toCheck ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(words).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: lessText ? "exclamationmark.triangle" : "checkmark.seal")
                    .foregroundStyle(lessText ? Color.orange : SnapflyTokens.protectTint)
            }
            if covered, toCheck > 0 {
                Label {
                    Text(String(format: L("%d places still to check"), toCheck))
                } icon: {
                    Image(systemName: "circle.dashed").foregroundStyle(Color.orange)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan-check-line")
    }

    // MARK: Ways out

    private var ways: some View {
        VStack(spacing: 10) {
            if let making = store.making, working != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(format: L("Page %d of %d"), making, count))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if let index = store.pages.firstIndex(where: { $0.state == .failed }) {
                Label(String(format: L("Page %d could not be read. Delete it or take it again."), index + 1),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.scanWarnText)
            } else if let index = store.pages.firstIndex(where: { $0.state == .needsCorners }) {
                Label(String(format: L("Page %d waits for its corners. Open it to set them."), index + 1),
                      systemImage: "crop")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.scanWarnText)
            } else if let improving = store.improving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(format: L("Page %d of %d is being improved"), improving, count))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if let note {
                noted(note.text, failed: note.failed)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                way(.copy, title: L("Copy"), symbol: "doc.on.doc")
                way(.save, title: L("Save"), symbol: format == .pdf ? "folder" : "photo.on.rectangle.angled")
                way(.share, title: L("Share"), symbol: "square.and.arrow.up")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// What the last way out did, or why it could not, in one line that
    /// VoiceOver reads as its words alone: its symbol only shows it.
    private func noted(_ text: String, failed: Bool) -> some View {
        let symbol: String = failed ? "exclamationmark.triangle.fill" : covered ? "checkmark.circle.fill" : "checkmark.circle"
        let tint: Color = failed ? Color.orange : covered ? SnapflyTokens.protectTint : Color.secondary
        let line = Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
        return line
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("scan-note")
    }

    private func way(_ way: Way, title: String, symbol: String) -> some View {
        Button {
            run(way)
        } label: {
            Group {
                if working == way {
                    ProgressView().tint(way == .share ? .white : nil)
                } else {
                    Label(title, systemImage: symbol)
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("scan-way-\(way)")
        .tint(way == .share ? SnapflyTokens.protect : Color(.tertiarySystemFill))
        .foregroundStyle(way == .share ? Color.white : Color.primary)
        .disabled(working != nil || store.pages.isEmpty || store.pages.contains { $0.state != .ready })
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Doing it

    private func run(_ way: Way) {
        guard working == nil else { return }
        working = way
        note = nil
        let covered = covered, searchable = searchable, format = format
        Task {
            defer { working = nil }
            do {
                try await make(way, covered: covered, searchable: searchable, format: format)
            } catch {
                failed((error as? ScanProblem)?.message)
            }
        }
    }

    /// The PDF or the pictures made, then copied, saved or shared.
    private func make(_ way: Way, covered: Bool, searchable: Bool, format: Format) async throws {
        if format == .pdf {
            let pdf = try await store.pdf(covered: covered, text: searchable)
            switch way {
            case .copy:
                UIPasteboard.general.setData(pdf, forPasteboardType: UTType.pdf.identifier)
                done(covered ? L("Copied") : L("Copied, without covers"))
            case .save:
                exporting = PDFFile(data: pdf)
            case .share:
                guard let url = write(pdf, as: ScannedPages.fileName + ".pdf") else { return failed() }
                sharing = SharedFiles(urls: [url])
            }
            return
        }
        let failing = switch way {
        case .copy: L("Page %d could not be covered, so nothing was copied.")
        case .save: L("Page %d could not be covered, so nothing was saved.")
        case .share: L("Page %d could not be covered, so nothing was sent.")
        }
        let pngs = try await store.pngs(covered: covered, failing: failing)
        switch way {
        case .copy:
            UIPasteboard.general.setItems(pngs.map { [UTType.png.identifier: $0] })
            done(covered ? L("Copied") : L("Copied, without covers"))
        case .save:
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for png in pngs { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil) }
                }
                done(covered ? L("Saved to Photos") : L("Saved to Photos, without covers"))
            } catch {
                failed(L("The picture could not be saved."))
            }
        case .share:
            let urls = pngs.enumerated().compactMap { index, png in
                write(png, as: ScannedPages.fileName + (pngs.count == 1 ? "" : " \(index + 1)") + ".png")
            }
            guard urls.count == pngs.count else { return failed() }
            sharing = SharedFiles(urls: urls)
        }
    }

    /// A file in the temporary folder, kept safe while the device is locked.
    private func write(_ data: Data, as name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    private func done(_ text: String) {
        note = (text, false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func failed(_ text: String? = nil) {
        note = (text ?? L("The file could not be made."), true)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
