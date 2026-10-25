import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

/// The pages' text, and the pages it was read on as small JPEGs, covered as
/// the text was read (or cleaned only, without covers), to check it by.
struct ScanReadingResult {
    var pages: [ScanReading.Page]
    var previews: [Data]

    /// A page small enough to keep a few in memory, large enough to read
    /// small print on: no larger than 1800 pixels.
    static func preview(of image: CGImage) -> Data {
        guard let small = ScanCleaner.smaller(image, longest: 1800) else { return Data() }
        return UIImage(cgImage: small).jpegData(compressionQuality: 0.8) ?? Data()
    }
}

/// A paragraph or a cell being corrected.
struct ReadingCorrection: Identifiable {
    let id = UUID()
    let spot: ScanReading.Spot
    /// What a correction is kept under: the text as it was read.
    let key: String
    let original: String
    /// As shown now, with an earlier correction.
    let current: String

    var corrected: Bool { current != original }
}

/// What is marked in a paragraph's or a cell's text: the places found, the
/// one the search is at, and the word being spoken.
struct ReadingMarks {
    var found: [Range<Int>] = []
    var foundNow: Range<Int>?
    var spoken: Range<Int>?
}

enum ReadingText {
    /// A wash of the orange of what is still to check on Review.
    static let unsure = SnapflyTokens.reviewOpen.opacity(0.22)
    static let found = Color.yellow.opacity(0.55)
    static let foundNow = Color.orange.opacity(0.65)
    static let spoken = SnapflyTokens.protectTint.opacity(0.3)

    /// The stretches as styled text: the unsure ones washed, then what the
    /// search and the voice mark over them.
    static func attributed(_ runs: [ScanReading.Run], marks: ReadingMarks = ReadingMarks()) -> AttributedString {
        var text = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if run.unsure { piece.backgroundColor = unsure }
            text.append(piece)
        }
        func paint(_ range: Range<Int>, _ color: Color) {
            let characters = text.characters
            guard range.lowerBound >= 0, range.lowerBound < range.upperBound, range.upperBound <= characters.count else { return }
            let from = characters.index(characters.startIndex, offsetBy: range.lowerBound)
            let to = characters.index(from, offsetBy: range.count)
            text[from..<to].backgroundColor = color
        }
        for range in marks.found { paint(range, Self.found) }
        if let range = marks.foundNow { paint(range, Self.foundNow) }
        if let range = marks.spoken { paint(range, Self.spoken) }
        return text
    }
}

// MARK: Blocks

/// A paragraph or a heading: text to select, or, while correcting, a button
/// that opens it to be corrected.
struct ReadingParagraph: View {
    let runs: [ScanReading.Run]
    /// What VoiceOver says, a cover as a word.
    let label: String
    let heading: Bool
    let marks: ReadingMarks
    /// The line the voice is on, or the paragraph's block is the one marked.
    let speaking: Bool
    let correcting: Bool
    let onCorrect: () -> Void

    var body: some View {
        if correcting {
            Button(action: onCorrect) { content(selectable: false) }
                .buttonStyle(.plain)
                .accessibilityHint(L("Opens the text to correct it."))
        } else {
            content(selectable: true)
        }
    }

    private func content(selectable: Bool) -> some View {
        let text = Text(ReadingText.attributed(runs, marks: marks))
            .font(heading ? .title3.weight(.semibold) : .body)
            .lineSpacing(heading ? 0 : 3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(correcting ? 8 : 0)
            .background(correcting ? AnyShapeStyle(Color.primary.opacity(0.05)) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                if speaking {
                    Capsule().fill(SnapflyTokens.protectTint).frame(width: 3).padding(.vertical, 2).offset(x: -10)
                }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(heading ? .isHeader : [])
        return Group {
            if selectable { text.textSelection(.enabled) } else { text }
        }
    }
}

/// A table as a grid that scrolls sideways where it is wide, with a menu to
/// hand it to a spreadsheet.
struct ReadingTable: View {
    let table: ScanReading.Table
    let page: Int
    let block: Int
    let marks: (ScanReading.Spot) -> ReadingMarks
    /// The row the voice is on.
    let speakingRow: Int?
    let correcting: Bool
    let onCorrect: (ScanReading.Spot) -> Void
    let onCopy: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Menu {
                Button(action: onCopy) { Label(L("Copy Table"), systemImage: "doc.on.doc") }
                Button(action: onShare) { Label(L("Share as CSV"), systemImage: "tablecells") }
            } label: {
                Label(L("Table"), systemImage: "ellipsis.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: SnapflyTokens.touch)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("scan-reading-table-menu")
            grid
        }
    }

    private var grid: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            self.cell(cell, ScanReading.Spot(page: page, block: block, row: index, column: column))
                        }
                    }
                    .background(speakingRow == index ? SnapflyTokens.protectTint.opacity(0.14) : Color.clear)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Table"))
    }

    @ViewBuilder private func cell(_ words: [ScanReading.Word], _ spot: ScanReading.Spot) -> some View {
        let text = Text(ReadingText.attributed(ScanReading.runs(ofCell: words), marks: marks(spot)))
            .font(.callout)
            .monospacedDigit()
            .fixedSize()
            .accessibilityLabel(ScanReading.line(of: words, mark: L("covered")))
        if correcting {
            Button { onCorrect(spot) } label: { text }
                .buttonStyle(.plain)
                .accessibilityHint(L("Opens the text to correct it."))
        } else {
            text.textSelection(.enabled)
        }
    }
}

// MARK: The page

/// A page as it was read, with the lines the reading was unsure of outlined
/// where they lie, each a button that opens it to be corrected, and the
/// block in focus (what the search or the voice is at) washed in green.
struct ReadingPageImage: View {
    let data: Data
    let spots: [ScanReading.UnsureSpot]
    let focus: CGRect?
    let onCorrect: (ScanReading.Spot) -> Void

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay { marks }
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(210 / 297, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .task {
            let bytes = data
            image = await Task.detached(priority: .userInitiated) { UIImage(data: bytes)?.preparingForDisplay() }.value
        }
    }

    private var marks: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let focus {
                    let rect = Self.frame(focus, in: proxy.size)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(SnapflyTokens.protectTint.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(SnapflyTokens.protectTint, lineWidth: 2))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
                ForEach(spots) { spot in
                    let rect = Self.frame(spot.box, in: proxy.size)
                    Button { onCorrect(spot.spot) } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(SnapflyTokens.reviewOpenFill)
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(SnapflyTokens.reviewOpen, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle().inset(by: -6))
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel(L("Read unsurely. Tap to correct."))
                }
            }
        }
    }

    /// A box from 0 to 1 from the bottom left, in the picture's points from the top left.
    static func frame(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height)
            .insetBy(dx: -3, dy: -2)
    }
}

// MARK: Correcting

/// A paragraph or a cell opened to be corrected, with the part of the page
/// it was read from above it, to read it against.
struct ScanTextEditSheet: View {
    let correction: ReadingCorrection
    let page: UIImage?
    let onSave: (String) -> Void
    let onRevert: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(correction: ReadingCorrection, page: UIImage?, onSave: @escaping (String) -> Void, onRevert: @escaping () -> Void) {
        self.correction = correction
        self.page = page
        self.onSave = onSave
        self.onRevert = onRevert
        _text = State(initialValue: correction.current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let page {
                        VStack(alignment: .leading, spacing: 6) {
                            caption(L("On the page"))
                            Image(uiImage: page)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                                .accessibilityHidden(true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        caption(L("Text"))
                        TextEditor(text: $text)
                            .focused($focused)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 140)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("scan-edit-text")
                    }
                    if correction.corrected {
                        Button {
                            onRevert()
                            dismiss()
                        } label: {
                            Label(L("Back to What Was Read"), systemImage: "arrow.uturn.backward")
                                .frame(minHeight: SnapflyTokens.touch)
                        }
                        .accessibilityIdentifier("scan-edit-revert")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(L("Correct Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("scan-edit-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func caption(_ words: String) -> some View {
        Text(words)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// The part of a page a box lies on, with a little round it.
    static func crop(of data: Data, box: CGRect) -> UIImage? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let left = max(0, (box.minX - 0.015) * width), right = min(width, (box.maxX + 0.015) * width)
        let top = max(0, (1 - box.maxY - 0.01) * height), bottom = min(height, (1 - box.minY + 0.01) * height)
        guard right > left, bottom > top, let part = cg.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else { return nil }
        return UIImage(cgImage: part)
    }
}

// MARK: Speaking

/// The voice's controls over the bar: back a piece, pause or go on, on to
/// the next, how fast, and stop.
struct ReadingPlayer: View {
    @ObservedObject var speaker: ScanSpeaker

    var body: some View {
        HStack(spacing: 4) {
            button("backward.fill", L("Previous"), id: "previous") { speaker.skip(-1) }
            button(speaker.state == .paused ? "play.fill" : "pause.fill", speaker.state == .paused ? L("Resume") : L("Pause"), id: "pause") {
                if speaker.state == .paused { speaker.resume() } else { speaker.pause() }
            }
            button("forward.fill", L("Next"), id: "next") { speaker.skip(1) }
            Spacer(minLength: 8)
            Menu {
                Picker(L("Speed"), selection: Binding(get: { speaker.speed }, set: { speaker.setSpeed($0) })) {
                    ForEach(ScanSpeaker.speeds, id: \.self) { speed in
                        Text(Self.label(speed)).tag(speed)
                    }
                }
            } label: {
                Text(Self.label(speaker.speed))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: SnapflyTokens.touch, minHeight: SnapflyTokens.touch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("Speed"))
            .accessibilityValue(Self.label(speaker.speed))
            .accessibilityIdentifier("scan-reading-speed")
            button("stop.fill", L("Stop"), id: "stop") { speaker.stop() }
        }
        .foregroundStyle(.primary)
    }

    private func button(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("scan-reading-\(id)")
    }

    /// "1×", "1.25×".
    static func label(_ speed: Double) -> String {
        String(format: "%g×", speed)
    }
}

// MARK: Translating

/// The system's own translation of the text, on this iPhone, from iOS 17.4.
struct ReadingTranslation: ViewModifier {
    @Binding var isPresented: Bool
    let text: String

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
