import SwiftUI
import UIKit

/// The scanned pages' text, to read, search, correct, translate, copy,
/// share or hear: in reading order (`ScanReading`), a column to its end
/// before the next, a table row by row as a grid that goes to a
/// spreadsheet, a heading set larger, every covered place a black bar whose
/// words are never shown, searched or spoken. With covers, read again on the
/// covered pages; without, all of it, under a warning. A line the reading
/// was not sure of is washed in orange; Page shows the pages with those
/// lines outlined where they lie, each a tap to correct it against the
/// page; a correction is kept in the text that is copied, shared and
/// spoken (never in the PDF). Copy, Read Aloud (the system's voice, on this
/// iPhone, with a player for pausing, skipping and speed) and Share (a .txt
/// file) wait on the bar at the bottom.
struct ScanReadingSheet: View {
    /// With covers: every covered place a bar.
    let covered: Bool
    /// The name a shared file goes under.
    let fileName: String
    /// The corrections made, kept by the text as it was read.
    @Binding var edits: [String: String]
    let read: () async throws -> ScanReadingResult

    private enum Mode: Hashable {
        case text, page
    }

    @State private var result: ScanReadingResult?
    @State private var failure: String?
    @State private var mode = ScanDemo.readsPage ? Mode.page : Mode.text
    @State private var query = ""
    @State private var searching = false
    @State private var matchIndex = 0
    @State private var correcting = ScanDemo.corrects
    @State private var correction: ReadingCorrection?
    /// What the last tap did, or why it could not, for a moment.
    @State private var note: Note?
    @State private var sharing: SharedFiles?
    @State private var translating = false
    @StateObject private var speaker = ScanSpeaker()
    /// Which page is being covered, while the text waits for it.
    @ObservedObject private var scans = ScannedPages.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Note: Equatable {
        let text: String
        let failed: Bool
    }

    /// The pages with the corrections made.
    private var shown: [ScanReading.Page] {
        (result?.pages ?? []).map { ScanReading.applying(edits, to: $0) }
    }

    /// The text as it is copied and shared, every cover a bar.
    private var text: String {
        ScanReading.text(shown)
    }

    private var hasPreviews: Bool {
        result?.previews.contains { !$0.isEmpty } ?? false
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
                .navigationTitle(L("Text"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: L("Search in the text"))
                .onChange(of: query) { _, _ in matchIndex = 0 }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .task(id: note) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            note = nil
        }
        .onDisappear { speaker.stop() }
        .sheet(item: $sharing) { files in
            ShareFilesSheet(files: files)
                .ignoresSafeArea()
        }
        .sheet(item: $correction) { correction in
            editor(correction)
        }
        .modifier(ReadingTranslation(isPresented: $translating, text: text))
    }

    // MARK: What it shows

    @ViewBuilder private var content: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SnapflyTokens.scanWarnText)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("scan-reading-failed")
        } else if result == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text(L("Reading the text…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let making = scans.making, scans.pages.count > 1 {
                    Text(String(format: L("Page %d of %d"), making, scans.pages.count))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .combine)
        } else if shown.allSatisfy({ $0.blocks.isEmpty }) {
            ContentUnavailableView(L("No Text Found"), systemImage: "text.magnifyingglass",
                                   description: Text(L("Snapfly found no words on these pages.")))
                .padding(.top, 40)
                .frame(maxHeight: .infinity, alignment: .top)
        } else if mode == .page && hasPreviews {
            pagePane
        } else {
            textPane
        }
    }

    // MARK: Text

    /// What the search and the voice are at, matched to blocks.
    private struct Following {
        var matches: [ScanReading.Match] = []
        var current = 0
        var piece: ScanReading.Utterance?
        var spoken: NSRange?

        func marks(at spot: ScanReading.Spot) -> ReadingMarks {
            var marks = ReadingMarks()
            for (index, match) in matches.enumerated() where match.spot == spot {
                if index == current { marks.foundNow = match.range } else { marks.found.append(match.range) }
            }
            if let piece, let spoken, spot.row == nil, piece.row == nil, piece.page == spot.page, piece.block == spot.block {
                marks.spoken = ScanReading.characterRange(spoken, in: piece.shown)
            }
            return marks
        }

        func speaking(page: Int, block: Int) -> Bool {
            guard let piece else { return false }
            return piece.page == page && piece.block == block && piece.row == nil
        }

        func row(page: Int, block: Int) -> Int? {
            guard let piece, piece.page == page, piece.block == block else { return nil }
            return piece.row
        }

        /// The block in focus, for the page and for scrolling: what is spoken, else the search's.
        var focus: ScanReading.Spot? {
            if let piece { return ScanReading.Spot(page: piece.page, block: piece.block) }
            guard matches.indices.contains(current) else { return nil }
            return matches[current].spot
        }
    }

    private var following: Following {
        let matches = ScanReading.matches(query, in: shown)
        return Following(matches: matches, current: matches.isEmpty ? 0 : min(matchIndex, matches.count - 1),
                         piece: speaker.piece, spoken: speaker.shownRange)
    }

    private var textPane: some View {
        let following = self.following
        let pages = shown
        let unsure = ScanReading.unsureCount(pages)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !covered { warning }
                    if unsure > 0 { unsureRow(unsure) }
                    if correcting { correctingHint }
                    ForEach(Array(pages.enumerated()), id: \.offset) { number, page in
                        pageText(page, number: number, count: pages.count, following: following)
                    }
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scan-reading")
            }
            .onChange(of: following.focus) { _, spot in
                guard let spot else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("b-\(spot.page)-\(spot.block)", anchor: .center) }
            }
        }
    }

    private func pageText(_ page: ScanReading.Page, number: Int, count: Int, following: Following) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if count > 1 {
                Text(String(format: L("Page %d of %d"), number + 1, count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }
            if page.blocks.isEmpty {
                Text(L("No words on this page."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, number: number, index: index, rightToLeft: page.rightToLeft, following: following)
                    .id("b-\(number)-\(index)")
            }
        }
        .environment(\.layoutDirection, page.rightToLeft ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private func blockView(_ block: ScanReading.Block, number: Int, index: Int, rightToLeft: Bool, following: Following) -> some View {
        let spot = ScanReading.Spot(page: number, block: index)
        switch block {
        case .paragraph(let paragraph):
            ReadingParagraph(runs: ScanReading.runs(of: paragraph, rightToLeft: rightToLeft),
                             label: ScanReading.runs(of: paragraph, rightToLeft: rightToLeft, mark: L("covered")).map(\.text).joined(),
                             heading: paragraph.heading,
                             marks: following.marks(at: spot),
                             speaking: following.speaking(page: number, block: index),
                             correcting: correcting,
                             onCorrect: { startCorrecting(spot) })
        case .table(let table):
            ReadingTable(table: table, page: number, block: index,
                         marks: { following.marks(at: $0) },
                         speakingRow: following.row(page: number, block: index),
                         correcting: correcting,
                         onCorrect: { startCorrecting($0) },
                         onCopy: { copyTable(table) },
                         onShare: { shareTable(table, at: spot) })
        }
    }

    /// Said first without covers, in the warning's colours.
    private var warning: some View {
        Label {
            Text(L("This file holds every private detail. Share it only with people you trust."))
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
    }

    /// How many lines were read unsurely, washed in orange below, with a way
    /// to the page to check them.
    private func unsureRow(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(SnapflyTokens.reviewOpen)
            Text(count == 1 ? L("1 line was read unsurely. It is marked; check it on the page.")
                 : String(format: L("%d lines were read unsurely. They are marked; check them on the page."), count))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if hasPreviews {
                Button(L("Check on Page")) { mode = .page }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("scan-reading-check")
            }
        }
        .font(.footnote)
        .padding(12)
        .background(SnapflyTokens.reviewOpenFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("scan-reading-unsure")
    }

    private var correctingHint: some View {
        Label(L("Tap a paragraph or a table cell to correct it."), systemImage: "pencil")
            .font(.footnote.weight(.medium))
            .foregroundStyle(SnapflyTokens.protectTint)
            .accessibilityIdentifier("scan-reading-correcting")
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(covered ? L("Read on this iPhone. Each covered place is a black bar; what it hides is never shown or read aloud.")
                     : L("Read on this iPhone, without covers."))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: covered ? "checkmark.shield" : "doc.text")
            }
            if !edits.isEmpty {
                Label {
                    Text(L("Includes your corrections. The PDF's text keeps what was read."))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "pencil")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: Page

    private var pagePane: some View {
        let pages = shown
        let spot = following.focus
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { number, page in
                        ReadingPageImage(data: preview(number),
                                         spots: ScanReading.unsureSpots(page, number: number),
                                         focus: spot.flatMap { $0.page == number ? ScanReading.box(at: $0, in: pages) : nil },
                                         onCorrect: { startCorrecting($0) })
                            .id("p-\(number)")
                    }
                }
                .padding(20)
                .accessibilityIdentifier("scan-reading-pages")
            }
            .onAppear {
                guard let spot else { return }
                proxy.scrollTo("p-\(spot.page)", anchor: .top)
            }
            .onChange(of: spot) { _, new in
                guard let new else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("p-\(new.page)", anchor: .top) }
            }
        }
    }

    private func preview(_ number: Int) -> Data {
        guard let previews = result?.previews, previews.indices.contains(number) else { return Data() }
        return previews[number]
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L("Done")) { dismiss() }
        }
        ToolbarItem(placement: .topBarLeading) {
            menu
        }
        ToolbarItem(placement: .principal) {
            if result != nil && hasPreviews {
                Picker(L("View"), selection: $mode) {
                    Text(L("Text")).tag(Mode.text)
                    Text(L("Page")).tag(Mode.page)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityIdentifier("scan-reading-mode")
            }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                mode = .text
                searching = true
            } label: {
                Label(L("Search"), systemImage: "magnifyingglass")
            }
            Button {
                mode = .text
                correcting.toggle()
            } label: {
                Label(correcting ? L("Done Correcting") : L("Correct Text"), systemImage: correcting ? "checkmark" : "pencil")
            }
            Button {
                translating = true
            } label: {
                Label(L("Translate"), systemImage: "character.bubble")
            }
            if !edits.isEmpty {
                Button(role: .destructive) {
                    edits = [:]
                } label: {
                    Label(L("Undo All Corrections"), systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: SnapflyTokens.touch, minHeight: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .disabled(result == nil || text.isEmpty)
        .accessibilityLabel(L("More"))
        .accessibilityIdentifier("scan-reading-menu")
    }

    // MARK: Copy, Read Aloud, Share

    private var bottom: some View {
        VStack(spacing: 10) {
            if let note {
                Label(note.text, systemImage: note.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(note.failed ? Color.orange : SnapflyTokens.protectTint)
                    .transition(.opacity)
                    .accessibilityIdentifier("scan-reading-note")
            }
            if mode == .text, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchBar
            }
            if speaker.speaking {
                ReadingPlayer(speaker: speaker)
            }
            let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            row {
                action(L("Copy"), symbol: "doc.on.doc", id: "copy", prominent: false, run: copy)
                action(speaker.speaking ? L("Stop") : L("Read Aloud"),
                       symbol: speaker.speaking ? "stop.fill" : "speaker.wave.2", id: "speak", prominent: false, run: speak)
                action(L("Share"), symbol: "square.and.arrow.up", id: "share", prominent: true, run: share)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .animation(.easeOut(duration: 0.2), value: note)
        .animation(.easeOut(duration: 0.2), value: speaker.speaking)
    }

    /// Where the search is, and a way to the next place and the one before.
    private var matchBar: some View {
        let count = following.matches.count
        return HStack(spacing: 4) {
            Text(count == 0 ? L("No matches") : String(format: L("%d of %d"), min(matchIndex, count - 1) + 1, count))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(count == 0 ? .secondary : .primary)
                .accessibilityIdentifier("scan-reading-matches")
            Spacer(minLength: 8)
            stepButton("chevron.up", L("Previous"), id: "previous-match", by: -1, count: count)
            stepButton("chevron.down", L("Next"), id: "next-match", by: 1, count: count)
        }
    }

    private func stepButton(_ symbol: String, _ title: String, id: String, by step: Int, count: Int) -> some View {
        Button {
            guard count > 0 else { return }
            matchIndex = (min(matchIndex, count - 1) + step + count) % count
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .disabled(count == 0)
        .accessibilityLabel(title)
        .accessibilityIdentifier("scan-reading-\(id)")
    }

    private func action(_ title: String, symbol: String, id: String, prominent: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: SnapflyTokens.touch)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? SnapflyTokens.protect : Color(.tertiarySystemFill))
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .disabled(text.isEmpty)
        .accessibilityIdentifier("scan-reading-\(id)")
    }

    private func load() async {
        do {
            result = try await read()
        } catch {
            failure = (error as? ScanProblem)?.message ?? L("The text could not be read.")
        }
    }

    private func copy() {
        UIPasteboard.general.string = text
        note = Note(text: covered ? L("Copied") : L("Copied, without covers"), failed: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func speak() {
        if speaker.speaking {
            speaker.stop()
            return
        }
        let pieces = ScanReading.utterances(shown, spokenMark: L("covered"))
        guard !pieces.isEmpty else { return }
        if !speaker.start(pieces) {
            note = Note(text: L("No voice for this language is on this iPhone."), failed: true)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func share() {
        guard let url = write(Data(text.utf8), as: fileName + ".txt") else { return }
        sharing = SharedFiles(urls: [url])
    }

    /// A table copied as tabs, to paste into cells in Numbers or Excel.
    private func copyTable(_ table: ScanReading.Table) {
        UIPasteboard.general.string = ScanReading.tsv(table)
        note = Note(text: L("Table copied"), failed: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A table as a CSV file a spreadsheet opens: UTF-8 with its byte order
    /// mark, the delimiter this iPhone's numbers call for.
    private func shareTable(_ table: ScanReading.Table, at spot: ScanReading.Spot) {
        let delimiter = ScanReading.csvDelimiter(decimalSeparator: Locale.current.decimalSeparator)
        let csv = ScanReading.csv(table, delimiter: delimiter)
        var number = 1
        for (pageIndex, page) in shown.enumerated() {
            for (blockIndex, block) in page.blocks.enumerated() {
                if case .table = block, (pageIndex, blockIndex) < (spot.page, spot.block) { number += 1 }
            }
        }
        let name = number == 1 ? fileName : "\(fileName) \(number)"
        guard let url = write(Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8), as: name + ".csv") else { return }
        sharing = SharedFiles(urls: [url])
    }

    private func write(_ data: Data, as name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            note = Note(text: L("The file could not be made."), failed: true)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
    }

    // MARK: Correcting

    private func startCorrecting(_ spot: ScanReading.Spot) {
        guard let pages = result?.pages, let key = ScanReading.editKey(at: spot, in: pages),
              let current = ScanReading.text(at: spot, in: shown) else { return }
        correction = ReadingCorrection(spot: spot, key: key, original: ScanReading.text(at: spot, in: pages) ?? current, current: current)
    }

    private func editor(_ correction: ReadingCorrection) -> some View {
        var crop: UIImage?
        if let result, result.previews.indices.contains(correction.spot.page),
           let box = ScanReading.box(at: correction.spot, in: result.pages) {
            crop = ScanTextEditSheet.crop(of: result.previews[correction.spot.page], box: box)
        }
        return ScanTextEditSheet(correction: correction, page: crop,
                                 onSave: { typed in save(typed, for: correction) },
                                 onRevert: { edits[correction.key] = nil })
    }

    /// What was typed is kept under the text as it was read; typing that
    /// text again is no correction at all.
    private func save(_ typed: String, for correction: ReadingCorrection) {
        let kept = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if kept == correction.original.trimmingCharacters(in: .whitespacesAndNewlines) {
            edits[correction.key] = nil
        } else {
            edits[correction.key] = kept
        }
    }
}
