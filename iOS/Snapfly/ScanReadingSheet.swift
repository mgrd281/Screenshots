import AVFoundation
import NaturalLanguage
import SwiftUI
import UIKit

/// The scanned pages' text, to read, copy, share or hear: in reading order
/// (`ScanReading`), a column to its end before the next, a table row by row
/// as a grid, a heading set larger, every covered place a black bar whose
/// words are never shown or spoken. With covers, read again on the covered
/// pages; without, all of it, under a warning. Copy, Read Aloud (the
/// system's voice for the text's language, on this iPhone) and Share (a
/// .txt file) wait on the bar at the bottom.
struct ScanReadingSheet: View {
    /// With covers: every covered place a bar.
    let covered: Bool
    /// The name a shared file goes under.
    let fileName: String
    let read: () async throws -> [ScanReading.Page]

    @State private var pages: [ScanReading.Page]?
    @State private var failure: String?
    /// What the last tap did, or why it could not, for a moment.
    @State private var note: Note?
    @State private var sharing: SharedFiles?
    @StateObject private var speaker = ScanSpeaker()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scan-reading")
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            .navigationTitle(L("Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
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
    }

    // MARK: What it shows

    @ViewBuilder private var content: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SnapflyTokens.scanWarnText)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("scan-reading-failed")
        } else if let pages {
            if pages.allSatisfy(\.blocks.isEmpty) {
                ContentUnavailableView(L("No Text Found"), systemImage: "text.magnifyingglass",
                                       description: Text(L("Snapfly found no words on these pages.")))
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if !covered { warning }
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page, number: index + 1, of: pages.count)
                    }
                    footnote
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(L("Reading the text…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .accessibilityElement(children: .combine)
        }
    }

    private func pageView(_ page: ScanReading.Page, number: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if count > 1 {
                Text(String(format: L("Page %d of %d"), number, count))
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
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                ReadingBlock(block: block, rightToLeft: page.rightToLeft)
            }
        }
        .environment(\.layoutDirection, page.rightToLeft ? .rightToLeft : .leftToRight)
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

    private var footnote: some View {
        Label {
            Text(covered ? L("Read on this iPhone. Each covered place is a black bar; what it hides is never shown or read aloud.")
                 : L("Read on this iPhone, without covers."))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: covered ? "checkmark.shield" : "doc.text")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: Copy, Read Aloud, Share

    private var bar: some View {
        VStack(spacing: 10) {
            if let note {
                Label(note.text, systemImage: note.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(note.failed ? Color.orange : SnapflyTokens.protectTint)
                    .transition(.opacity)
                    .accessibilityIdentifier("scan-reading-note")
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

    /// The pages' text as it is copied and shared, every cover a bar.
    private var text: String {
        ScanReading.text(pages ?? [])
    }

    /// As it is read aloud: every cover the word "covered", a table's cells parted by a pause.
    private var spoken: String {
        ScanReading.text(pages ?? [], mark: L("covered")).replacingOccurrences(of: "\t", with: ", ")
    }

    private func load() async {
        do {
            pages = try await read()
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
        if speaker.speaking { speaker.stop() } else { speaker.speak(spoken) }
    }

    private func share() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName + ".txt")
        do {
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            sharing = SharedFiles(urls: [url])
        } catch {
            note = Note(text: L("The file could not be made."), failed: true)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    struct Note: Equatable {
        let text: String
        let failed: Bool
    }
}

/// One block of a page: a paragraph or a heading as text to select, a
/// table as a grid that scrolls sideways where it is wide.
private struct ReadingBlock: View {
    let block: ScanReading.Block
    let rightToLeft: Bool

    var body: some View {
        switch block {
        case .paragraph(let paragraph):
            let page = ScanReading.Page(blocks: [block], rightToLeft: rightToLeft)
            Text(ScanReading.text(page))
                .font(paragraph.heading ? .title3.weight(.semibold) : .body)
                .lineSpacing(paragraph.heading ? 0 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityLabel(ScanReading.text(page, mark: L("covered")))
                .accessibilityAddTraits(paragraph.heading ? .isHeader : [])
        case .table(let table):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                        }
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(ScanReading.line(of: cell))
                                    .font(.callout)
                                    .monospacedDigit()
                                    .fixedSize()
                                    .textSelection(.enabled)
                                    .accessibilityLabel(ScanReading.line(of: cell, mark: L("covered")))
                            }
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Table"))
        }
    }
}

/// Reads text aloud with the system's voice for its language, on this
/// iPhone, ducking other sound while it speaks.
@MainActor
final class ScanSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
           let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        synthesizer.speak(utterance)
        speaking = true
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finished()
    }

    private func finished() {
        guard speaking else { return }
        speaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
