import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Save and Share for a PDF project, or for the pages chosen in it, as tall
/// as what it holds: the file's name before its fixed ".pdf"; how pictures
/// sit on their pages, where there are pictures; how sharp the pages are,
/// with how large the file will be, worked out from its own pages; with
/// covers (where every save starts) or without, with the scan's warning;
/// its text to find and copy or not; then Copy, Save to Files and Share.
/// While the pages are covered, which page it is. Nothing of the files the
/// pages come from is changed.
struct ProjectExportSheet: View {
    enum Way {
        case copy, save, share
    }

    /// The pages chosen, or all of them.
    var only: Set<UUID>? = nil
    @ObservedObject private var store = ProjectStore.shared
    @State private var name = ProjectStore.shared.project?.name ?? "Snapfly"
    @State private var options = ProjectExport(covered: !ProjectDemo.uncovered,
                                               paper: ProjectStore.shared.project?.paper ?? .original,
                                               quality: ProjectStore.shared.project?.quality ?? .medium)
    @State private var estimate: Int?
    /// From the start, so the first moment shows the spinner, not the dash.
    @State private var estimating = true
    @State private var working: Way?
    @State private var exporting: PDFFile?
    @State private var sharing: SharedFiles?
    @State private var note: (text: String, failed: Bool)?
    @State private var contentHeight: CGFloat = 560
    @State private var waysHeight: CGFloat = 110
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var pages: [ProjectPage] {
        guard let project = store.project else { return [] }
        return only.map { project.only($0).pages } ?? project.pages
    }

    private var hasPictures: Bool {
        pages.contains { page in
            if case .picture = page.source { return true }
            return false
        }
    }

    /// As tall as what it holds; at the accessibility text sizes, the whole screen, where it scrolls.
    private var detent: PresentationDetent {
        typeSize.isAccessibilitySize ? .large : .height(contentHeight + waysHeight + 24)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                named
                if hasPictures { paper }
                quality
                covers
                text
                if options.covered { checked }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .measuredHeight($contentHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { ways.measuredHeight($waysHeight) }
        .presentationDetents([detent])
        .presentationDragIndicator(.visible)
        .animation(motion, value: options.covered)
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .pdf, defaultFilename: fileName) { result in
            switch result {
            case .success: done(options.covered ? L("Saved to Files") : L("Saved to Files, without covers"))
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { failed() }
            }
        }
        .sheet(item: $sharing) { files in
            ShareFilesSheet(files: files)
                .ignoresSafeArea()
        }
        .task(id: options) { await estimateSize() }
        .task(id: note?.text) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            note = nil
        }
        .onChange(of: options) { _, now in store.setExport(paper: now.paper, quality: now.quality) }
    }

    // MARK: What it holds

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Save and Share"))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(String(format: L("PDF, %@"), ProjectNaming.pages(pages.count)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Close"))
            .accessibilityIdentifier("project-export-close")
        }
    }

    /// The name, typed or as the project is called, and its ".pdf", which stays.
    private var named: some View {
        HStack(spacing: 4) {
            TextField(L("Name"), text: $name)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .accessibilityIdentifier("project-export-name")
            Text(verbatim: ".pdf")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L("Page Size for Pictures"))
            Picker(L("Page Size for Pictures"), selection: $options.paper) {
                ForEach(PaperSize.allCases, id: \.self) { size in Text(size.title).tag(size) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("project-export-paper")
        }
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                heading(L("Quality"))
                Spacer()
                // The spinner only while it is worked out; a dash where no page could be drawn for it.
                Group {
                    if estimating {
                        ProgressView().controlSize(.mini)
                    } else if let estimate {
                        Text(String(format: L("about %@"), ByteCountFormatter.string(fromByteCount: Int64(estimate), countStyle: .file)))
                            .contentTransition(.numericText())
                    } else {
                        Text(verbatim: "–")
                            .accessibilityLabel(L("Size unknown"))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("project-export-estimate")
            }
            Picker(L("Quality"), selection: $options.quality) {
                ForEach(ExportQuality.allCases, id: \.self) { quality in Text(quality.title).tag(quality) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("project-export-quality")
        }
    }

    /// Said under Without Covers while it is chosen.
    private static var warning: String {
        L("This file holds every private detail. Share it only with people you trust.")
    }

    private var covers: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                choice(true, title: L("With Covers"), detail: L("Private details stay covered"), badge: L("Recommended"))
                Divider().padding(.leading, 52)
                choice(false, title: L("Without Covers"), detail: L("Only the pages"), badge: nil)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !options.covered {
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
                .accessibilityHidden(true)
                .accessibilityIdentifier("project-uncovered-warning")
            }
        }
    }

    private func choice(_ withCovers: Bool, title: String, detail: String, badge: String?) -> some View {
        let chosen = options.covered == withCovers
        return Button {
            options.covered = withCovers
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
            .padding(12)
            .frame(minHeight: SnapflyTokens.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(!withCovers && chosen ? Self.warning : "")
        .accessibilityIdentifier(withCovers ? "project-with-covers" : "project-without-covers")
    }

    private var text: some View {
        Toggle(isOn: $options.searchable) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Searchable Text")).font(.body.weight(.medium))
                Text(options.covered ? L("Without the covered details") : L("Holds all the text"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(SnapflyTokens.protect)
        .accessibilityIdentifier("project-searchable")
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The places still to check on the pages opened, which go covered as they are.
    @ViewBuilder private var checked: some View {
        let toCheck = pages.reduce(0) { $0 + (store.opened($1.id)?.plan.tally.toCheck ?? 0) }
        if toCheck > 0 {
            Label {
                Text(toCheck == 1 ? L("1 place still to check") : String(format: L("%d places still to check"), toCheck))
            } icon: {
                Image(systemName: "circle.dashed").foregroundStyle(Color.orange)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Ways out

    private var ways: some View {
        VStack(spacing: 10) {
            if let making = store.making, working != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(format: L("Covering page %d of %d …"), min(making.done + 1, making.total), making.total))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("project-export-progress")
            } else if let note {
                Label(note.text, systemImage: note.failed ? "exclamationmark.triangle.fill"
                      : options.covered ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(note.failed ? SnapflyTokens.reviewOpen : options.covered ? SnapflyTokens.protectTint : Color.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(note.text)
                    .accessibilityIdentifier("project-export-note")
                    .transition(.opacity)
            }
            let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            row {
                way(.copy, title: L("Copy"), symbol: "doc.on.doc")
                way(.save, title: L("Save"), symbol: "folder")
                way(.share, title: L("Share"), symbol: "square.and.arrow.up")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
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
        .tint(way == .share ? SnapflyTokens.protect : Color(.tertiarySystemFill))
        .foregroundStyle(way == .share ? Color.white : Color.primary)
        .disabled(working != nil || pages.isEmpty || store.locked != nil)
        .accessibilityIdentifier("project-way-\(way)")
    }

    // MARK: Doing it

    private var fileName: String {
        let safe = ScanNaming.safe(name)
        return safe.isEmpty ? "Snapfly" : safe
    }

    /// How large the file will be, worked out again a moment after a choice changes.
    private func estimateSize() async {
        estimating = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let size = await store.estimate(options, only: only)
        guard !Task.isCancelled else { return }
        estimate = size
        estimating = false
    }

    private func run(_ way: Way) {
        guard working == nil else { return }
        working = way
        note = nil
        let options = options
        Task {
            defer { working = nil }
            do {
                let pdf = try await store.pdf(options, only: only)
                switch way {
                case .copy:
                    Clipboard.put(pdf, as: .pdf, covered: options.covered)
                    done(options.covered ? L("Copied") : L("Copied, without covers"))
                case .save:
                    exporting = PDFFile(data: pdf)
                case .share:
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName + ".pdf")
                    try pdf.write(to: url, options: [.atomic, .completeFileProtection])
                    sharing = SharedFiles(urls: [url])
                }
            } catch {
                failed((error as? ScanProblem)?.message)
            }
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

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }
}
