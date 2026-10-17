import AppKit
import SwiftUI

/// Draw on Photo: the photo large, to draw arrows, boxes, highlights,
/// numbered steps and words on it and to choose the part to keep, in a
/// window laid out like Hide Part's. What Hide private details covers shows
/// too, so what you see is what goes. The drawing is kept with the photo, and
/// the file itself is never changed.
@MainActor
final class DrawEditor: NSObject, NSWindowDelegate {
    static let shared = DrawEditor()

    private var window: NSWindow?

    /// How the window was left: the drawing saved, or saved with a copy of
    /// the photo as it goes out, or neither.
    enum Ending {
        case cancel, done, saveCopy
    }

    /// Calls back once the drawing is saved, saying whether a copy is to be
    /// saved too; not when cancelled.
    func edit(_ url: URL, saved: @escaping (_ copy: Bool) -> Void) {
        window?.close()
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            Notice.show(L("Could not open the screenshot."))
            return
        }
        let model = DrawModel(image: image, pixels: Self.pixels(of: url) ?? image.size,
                              drawing: Drawings.saved(url), hand: PrivateDetails.hand(url))
        readCovered(url, into: model)
        let title = url.deletingPathExtension().lastPathComponent
        let view = DrawEditorView(model: model, title: title) { [weak self] ending in
            if ending != .cancel {
                model.end()
                Drawings.set(model.drawing.tidied, for: url)
            }
            self?.window?.close()
            // After the window, so the save panel comes up on its own.
            if ending != .cancel { saved(ending == .saveCopy) }
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        let hosting = NSHostingView(rootView: view)
        // The window sets the size; the view fills it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = HidePartLayout.minimum
        // As large as fits the screen, with the picture never larger than
        // itself, as Hide Part opens.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
        window.setContentSize(HidePartLayout.windowSize(for: image.size, pages: 1, in: room))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
    }

    /// The picture's pixels across and down, upright, for the marks' sizes
    /// and the size of the part kept.
    private static func pixels(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
        // A photo stored turned is shown upright, its sides swapped.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// What Hide private details covers, read in the background, and the
    /// picture with it and the parts hidden by hand covered in the chosen
    /// look and checked, as it goes out.
    private func readCovered(_ url: URL, into model: DrawModel) {
        let chosen = PrivateDetails.details
        let hand = model.hand
        guard !chosen.isEmpty || !hand.isEmpty else { return }
        let size = model.image.size
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Cover.upright(source),
                  let made = Finder.covered(image, chosen, hand: hand) else { return }
            let found = made.areas.map(\.rect)
            let covered = NSImage(cgImage: made.image, size: size)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    model?.found = found
                    model?.covered = covered
                }
            }
        }
    }
}

/// What can be done on the picture, one at a time, each with its key.
enum DrawTool: String, CaseIterable, Identifiable {
    case select, arrow, box, highlight, step, text, crop

    var id: String { rawValue }

    /// What it draws, if it draws.
    var kind: Drawing.Mark.Kind? {
        switch self {
        case .arrow: .arrow
        case .box: .box
        case .highlight: .highlight
        case .step: .step
        case .text: .text
        case .select, .crop: nil
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .highlight: "highlighter"
        case .step: "1.circle"
        case .text: "textformat"
        case .crop: "crop"
        }
    }

    var title: String {
        switch self {
        case .select: L("Select")
        case .arrow: L("Arrow")
        case .box: L("Box")
        case .highlight: L("Highlight")
        case .step: L("Numbered Steps")
        case .text: L("Text")
        case .crop: L("Crop")
        }
    }

    /// Its key, as in Preview's and other editors' tools.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .box: "r"
        case .highlight: "h"
        case .step: "n"
        case .text: "t"
        case .crop: "c"
        }
    }

    /// How to use it, under the tools.
    var hint: String {
        switch self {
        case .select: L("Click a drawing to choose it, then drag it or its handles.")
        case .arrow: L("Drag from where the arrow starts to what it points at.")
        case .box: L("Drag to draw a box around something.")
        case .highlight: L("Drag over words to highlight them.")
        case .step: L("Click each place in turn. The numbers follow the order.")
        case .text: L("Click where the words go, then type them.")
        case .crop: L("Drag over the part to keep, or drag its corners.")
        }
    }
}

@MainActor
final class DrawModel: ObservableObject {
    let image: NSImage
    /// The picture's pixels across and down.
    let pixels: CGSize
    /// Hidden by hand, and covered by Hide private details once read, from
    /// 0 to 1 from the bottom left.
    let hand: [CGRect]
    @Published var found: [CGRect] = []
    /// The picture as it goes out, covered in the chosen look, once read.
    /// Until then, what is covered shows as ink.
    @Published var covered: NSImage?

    @Published var drawing: Drawing
    @Published var tool: DrawTool = .arrow {
        didSet {
            // The crop's corners take the place of a mark's handles.
            if tool == .crop { choose(nil) }
        }
    }
    @Published private(set) var selected: UUID?

    /// What the next mark is drawn in. A highlighter keeps an ink of its
    /// own; each is kept for the next time.
    @Published private(set) var ink: Drawing.Ink
    @Published private(set) var highlightInk: Drawing.Ink
    @Published private(set) var size: Drawing.Size

    @Published private var undone: [Drawing] = []
    @Published private var redone: [Drawing] = []
    /// The drawing as it was when a change began, kept for Undo once it ends.
    private var before: Drawing?

    private static let inkKey = "drawInk"
    private static let highlightInkKey = "drawHighlightInk"
    private static let sizeKey = "drawSize"

    init(image: NSImage, pixels: CGSize, drawing: Drawing, hand: [CGRect]) {
        self.image = image
        self.pixels = pixels
        self.drawing = drawing
        self.hand = hand
        let defaults = UserDefaults.standard
        ink = defaults.string(forKey: Self.inkKey).flatMap(Drawing.Ink.init(rawValue:)) ?? .red
        highlightInk = defaults.string(forKey: Self.highlightInkKey).flatMap(Drawing.Ink.init(rawValue:)) ?? .yellow
        size = defaults.string(forKey: Self.sizeKey).flatMap(Drawing.Size.init(rawValue:)) ?? .medium
    }

    /// The unit the marks are measured in, for the picture shown `size` large.
    func unit(in size: CGSize) -> CGFloat {
        let area = pixels.width * pixels.height
        guard area > 0 else { return Drawing.unit(width: size.width, height: size.height) }
        return Drawing.unit(width: pixels.width, height: pixels.height) * (size.width * size.height / area).squareRoot()
    }

    var selectedMark: Drawing.Mark? {
        selected.flatMap { id in drawing.marks.first { $0.id == id } }
    }

    /// The ink the swatches show: the chosen mark's, else the next one's.
    var shownInk: Drawing.Ink {
        if let mark = selectedMark { return mark.ink }
        return tool == .highlight ? highlightInk : ink
    }

    var shownSize: Drawing.Size { selectedMark?.size ?? size }

    /// Whether an ink can be chosen: not while cropping.
    var inkApplies: Bool { selectedMark != nil || tool != .crop }

    /// Whether the size changes anything: a highlight is as large as it is
    /// drawn, and a crop has none.
    var sizeApplies: Bool {
        if let mark = selectedMark { return mark.kind != .highlight }
        return tool != .highlight && tool != .crop
    }

    /// The part kept, in the picture's pixels; nil for all of it.
    var keptPixels: CGSize? {
        drawing.crop.flatMap { Drawing.pixels(of: $0, width: Int(pixels.width), height: Int(pixels.height))?.size }
    }

    // MARK: Changes, for Undo

    /// Starts a change that ends with `end`, like a drag.
    func begin() {
        end()
        before = drawing
    }

    /// Ends a change, kept for Undo if it changed anything.
    func end() {
        guard let before else { return }
        self.before = nil
        guard before != drawing else { return }
        undone.append(before)
        if undone.count > 200 { undone.removeFirst() }
        redone = []
    }

    /// A change made at once, like a click on a button.
    func change(_ make: (inout Drawing) -> Void) {
        begin()
        make(&drawing)
        end()
    }

    var canUndo: Bool { !undone.isEmpty || (before.map { $0 != drawing } ?? false) }
    var canRedo: Bool { !redone.isEmpty }

    func undo() {
        end()
        guard let last = undone.popLast() else { return }
        redone.append(drawing)
        drawing = last
        if selectedMark == nil { selected = nil }
    }

    func redo() {
        end()
        guard let next = redone.popLast() else { return }
        undone.append(drawing)
        drawing = next
        if selectedMark == nil { selected = nil }
    }

    // MARK: Marks

    /// Chooses a mark, or none. Words left empty go as another is chosen.
    func choose(_ id: UUID?) {
        guard id != selected else { return }
        if let mark = selectedMark, mark.kind == .text,
           mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawing.marks.removeAll { $0.id == mark.id }
        }
        end()
        selected = id
    }

    /// The ink of the chosen mark, and of the next ones like it.
    func use(_ ink: Drawing.Ink) {
        let kind = selectedMark?.kind ?? tool.kind
        if let id = selected {
            change { drawing in
                if let i = drawing.marks.firstIndex(where: { $0.id == id }) { drawing.marks[i].ink = ink }
            }
        }
        if kind == .highlight {
            highlightInk = ink
            UserDefaults.standard.set(ink.rawValue, forKey: Self.highlightInkKey)
        } else {
            self.ink = ink
            UserDefaults.standard.set(ink.rawValue, forKey: Self.inkKey)
        }
    }

    func use(_ size: Drawing.Size) {
        if let id = selected {
            change { drawing in
                if let i = drawing.marks.firstIndex(where: { $0.id == id }) { drawing.marks[i].size = size }
            }
        }
        self.size = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey)
    }

    /// A new mark of the tool's kind, from a point to the same point.
    func newMark(at point: CGPoint) -> Drawing.Mark? {
        guard let kind = tool.kind else { return nil }
        return Drawing.Mark(kind: kind, from: point, to: point, ink: kind == .highlight ? highlightInk : ink, size: size)
    }

    /// A step or words put down with a click, and chosen. Words wait for
    /// what is typed, which ends their change.
    func put(_ mark: Drawing.Mark) {
        choose(nil)
        begin()
        drawing.marks.append(mark)
        if mark.kind != .text { end() }
        selected = mark.id
    }

    /// The words of the chosen mark, as they are typed: one change for Undo.
    func type(_ text: String) {
        guard let id = selected, let i = drawing.marks.firstIndex(where: { $0.id == id }),
              drawing.marks[i].kind == .text, drawing.marks[i].text != text else { return }
        if before == nil { before = drawing }
        drawing.marks[i].text = text
    }

    func deleteSelected() {
        guard let id = selected else { return }
        change { $0.marks.removeAll { $0.id == id } }
        selected = nil
    }

    func removeAll() {
        selected = nil
        change { $0.marks = [] }
    }

    /// Replaces a mark while it is dragged.
    func replace(_ mark: Drawing.Mark) {
        guard let i = drawing.marks.firstIndex(where: { $0.id == mark.id }) else { return }
        drawing.marks[i] = mark
    }

    func remove(_ id: UUID) {
        drawing.marks.removeAll { $0.id == id }
        if selected == id { selected = nil }
    }
}

/// The window: the picture on its canvas, and on the trailing edge the
/// inspector, a grouped form of tools, ink and size over Cancel and Done.
private struct DrawEditorView: View {
    @ObservedObject var model: DrawModel
    let title: String
    let finish: (DrawEditor.Ending) -> Void

    /// What the drag in progress does.
    @State private var action: Action?
    @State private var cursor: NSCursor?
    @FocusState private var fieldFocused: Bool

    /// Room around the picture for the handles at its edges.
    private static let handleRoom: CGFloat = 12
    /// How far from a handle a drag still takes it, in points.
    private static let reach: CGFloat = 8
    private static let cropReach: CGFloat = 14
    /// A crop smaller than this, in points, is taken for a slip.
    private static let smallestCrop: CGFloat = 12

    private enum Action {
        /// Pressed and not moved yet: a click unless it moves, on a mark or not.
        case pressing(UUID?)
        /// A new arrow, box or highlight.
        case drawing(UUID)
        case moving(Drawing.Mark, from: CGPoint)
        case reshaping(Drawing.Mark, handle: Int)
        /// A new crop, or one of its corners dragged: the corner that stays.
        case cropping(fixed: CGPoint, before: CGRect?)
        case movingCrop(CGRect, from: CGPoint)
        case idle
    }

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            inspector
        }
        .frame(minWidth: HidePartLayout.minimum.width, minHeight: HidePartLayout.minimum.height)
        .onChange(of: fieldFocused) { _, focused in
            if !focused { model.end() }
        }
    }

    // MARK: The canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let margin = HidePartLayout.margin
            let size = HidePartLayout.fitted(model.image.size,
                                             in: CGSize(width: geometry.size.width - 2 * margin,
                                                        height: geometry.size.height - 2 * margin))
            picture(size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// The picture at that size, under what is covered, the marks and the
    /// crop, drawn the way the copy is.
    private func picture(_ size: CGSize) -> some View {
        let shown = model.covered ?? model.image
        let covers = model.covered == nil ? model.found + model.hand : []
        let layer = Overlay(image: shown, drawing: model.drawing, covers: covers,
                            unit: model.unit(in: size), selected: model.selectedMark, cropping: model.tool == .crop,
                            placeholder: L("Text"), accent: NSColor.controlAccentColor.cgColor)
        let room = Self.handleRoom
        return Image(nsImage: shown)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .overlay(alignment: .topLeading) {
                Canvas { context, _ in
                    layer.draw(in: &context, picture: CGRect(x: room, y: room, width: size.width, height: size.height))
                }
                .frame(width: size.width + 2 * room, height: size.height + 2 * room)
                .offset(x: -room, y: -room)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag($0, in: size) }
                    .onEnded { ended($0, in: size) }
            )
            .onHover { inside in pointer(inside ? Self.cursor(for: model.tool) : nil) }
            .onChange(of: model.tool) { _, tool in
                if cursor != nil { pointer(Self.cursor(for: tool)) }
            }
            .onDisappear { pointer(nil) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(String(format: L("Drawings: %d"), model.drawing.marks.count))
    }

    private static func cursor(for tool: DrawTool) -> NSCursor {
        switch tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
    }

    private func pointer(_ new: NSCursor?) {
        guard new !== cursor else { return }
        if cursor != nil { NSCursor.pop() }
        new?.push()
        cursor = new
    }

    // MARK: Dragging

    /// From the view, counted from the top left, to the picture, from 0 to 1
    /// from the bottom left, and kept on it.
    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: max(0, min(1, point.x / size.width)), y: max(0, min(1, 1 - point.y / size.height)))
    }

    /// The same point in the picture's points, from its bottom left.
    private func flipped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: size.height - point.y)
    }

    private func drag(_ value: DragGesture.Value, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let point = normalized(value.location, in: size)
        guard let action else {
            self.action = start(at: value.startLocation, in: size)
            return
        }
        switch action {
        case let .pressing(hit):
            guard hypot(value.translation.width, value.translation.height) >= 3 else { return }
            let start = normalized(value.startLocation, in: size)
            switch model.tool {
            case .arrow, .box, .highlight:
                guard var mark = model.newMark(at: start) else { return }
                mark.to = point
                model.choose(nil)
                model.begin()
                model.drawing.marks.append(mark)
                self.action = .drawing(mark.id)
            case .step, .text:
                // A step or words dragged by the hand, whatever the tool.
                guard let hit, let mark = model.drawing.marks.first(where: { $0.id == hit }) else {
                    self.action = .idle
                    return
                }
                model.choose(hit)
                model.begin()
                self.action = .moving(mark, from: start)
            case .select, .crop:
                self.action = .idle
            }
        case let .drawing(id):
            guard var mark = model.drawing.marks.first(where: { $0.id == id }) else { return }
            mark.to = point
            model.replace(mark)
        case let .moving(mark, from):
            model.replace(Drawing.moved(mark, by: CGVector(dx: point.x - from.x, dy: point.y - from.y)))
        case let .reshaping(mark, handle):
            model.replace(Drawing.reshaped(mark, handle: handle, to: point))
        case let .cropping(fixed, _):
            model.drawing.crop = CGRect(x: min(fixed.x, point.x), y: min(fixed.y, point.y),
                                        width: abs(point.x - fixed.x), height: abs(point.y - fixed.y))
        case let .movingCrop(crop, from):
            let x = max(0, min(1 - crop.width, crop.minX + point.x - from.x))
            let y = max(0, min(1 - crop.height, crop.minY + point.y - from.y))
            model.drawing.crop = CGRect(x: x, y: y, width: crop.width, height: crop.height)
        case .idle:
            break
        }
    }

    /// What a press starts: a crop's corner or the crop itself, a chosen
    /// mark's handle, a mark to move, or a click yet to be told from a drag.
    private func start(at location: CGPoint, in size: CGSize) -> Action {
        let point = normalized(location, in: size)
        let here = flipped(location, in: size)
        if model.tool == .crop {
            let before = model.drawing.crop
            model.begin()
            if let crop = before {
                let corners = Drawing.corners(of: crop)
                if let i = corners.firstIndex(where: { near(Drawing.point($0, in: size), here, Self.cropReach) }) {
                    return .cropping(fixed: corners[(i + 2) % 4], before: before)
                }
                if crop.contains(point) { return .movingCrop(crop, from: point) }
            }
            return .cropping(fixed: point, before: before)
        }
        if let mark = model.selectedMark,
           let handle = Drawing.handles(of: mark).firstIndex(where: { near(Drawing.point($0, in: size), here, Self.reach) }) {
            model.begin()
            return .reshaping(mark, handle: handle)
        }
        let hit = model.drawing.mark(at: here, size: size, unit: model.unit(in: size), slack: 4, placeholder: L("Text"))
        if model.tool == .select {
            guard let hit else {
                model.choose(nil)
                return .idle
            }
            model.choose(hit.id)
            model.begin()
            return .moving(hit, from: point)
        }
        return .pressing(hit?.id)
    }

    private func ended(_ value: DragGesture.Value, in size: CGSize) {
        defer { action = nil }
        guard size.width > 0, size.height > 0 else { return }
        switch action {
        case let .pressing(hit):
            // A click: on a mark it is chosen; elsewhere a step or words go down.
            if let hit {
                model.choose(hit)
                if model.selectedMark?.kind == .text { focusField() }
                return
            }
            let point = normalized(value.startLocation, in: size)
            switch model.tool {
            case .step, .text:
                guard let mark = model.newMark(at: point) else { return }
                model.put(mark)
                if mark.kind == .text { focusField() }
            default:
                model.choose(nil)
            }
        case let .drawing(id):
            guard let mark = model.drawing.marks.first(where: { $0.id == id }) else { return }
            let a = Drawing.point(mark.from, in: size), b = Drawing.point(mark.to, in: size)
            let big = mark.kind == .arrow ? hypot(b.x - a.x, b.y - a.y) >= 8 : abs(b.x - a.x) >= 4 && abs(b.y - a.y) >= 4
            if big {
                model.choose(id)
            } else {
                model.remove(id)
            }
            model.end()
        case let .cropping(_, before):
            if let crop = model.drawing.crop {
                if crop.width * size.width < Self.smallestCrop || crop.height * size.height < Self.smallestCrop {
                    model.drawing.crop = before
                } else if crop.width > 0.995 && crop.height > 0.995 {
                    model.drawing.crop = nil
                }
            }
            model.end()
        case .moving, .reshaping, .movingCrop:
            model.end()
        case .idle, nil:
            break
        }
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ reach: CGFloat) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= reach
    }

    /// The words' field, once it shows for words just chosen.
    private func focusField() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    // MARK: The inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                tools
                style
                if let mark = model.selectedMark {
                    chosen(mark)
                }
                if model.tool == .crop || model.drawing.crop != nil {
                    cropping
                }
                drawn
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: HidePartLayout.panelWidth)
    }

    /// The tools in a row, the chosen one in the accent, with how to use it.
    private var tools: some View {
        Section {
            HStack(spacing: 4) {
                ForEach(DrawTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text(L("Tool"))
        } footer: {
            Text(model.tool.hint)
                .foregroundStyle(.secondary)
        }
    }

    private func toolButton(_ tool: DrawTool) -> some View {
        let chosen = model.tool == tool
        return Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(chosen ? Color.accentColor : Color.primary)
                .frame(width: 34, height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(chosen ? Color.accentColor.opacity(0.16) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        // Typed in the words' field, the letters are words.
        .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(KeyEquivalent(tool.key), modifiers: []))
    }

    /// The ink as swatches and the size, for the chosen mark and the next.
    private var style: some View {
        Section {
            LabeledContent(L("Color")) {
                HStack(spacing: 4) {
                    ForEach(Drawing.Ink.allCases, id: \.self) { ink in
                        swatch(ink)
                    }
                }
            }
            .disabled(!model.inkApplies)
            Picker(L("Size"), selection: Binding(get: { model.shownSize }, set: { model.use($0) })) {
                ForEach(Drawing.Size.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.sizeApplies)
        }
    }

    private func swatch(_ ink: Drawing.Ink) -> some View {
        let chosen = model.shownInk == ink
        return Button {
            model.use(ink)
        } label: {
            Circle()
                .fill(Color(cgColor: ink.color))
                // A hairline, so white and yellow show on a light form.
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(chosen ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ink.title)
        .accessibilityLabel(ink.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The chosen mark: its words, for words, and a way to take it away.
    private func chosen(_ mark: Drawing.Mark) -> some View {
        Section {
            if mark.kind == .text {
                TextField(L("Words on the photo"), text: Binding(get: { model.selectedMark?.text ?? "" },
                                                                 set: { model.type($0) }),
                          prompt: Text(L("Type the words to show")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    // Return and Escape end the typing; the next Return is Done.
                    .onSubmit { fieldFocused = false }
                    .onExitCommand { fieldFocused = false }
            }
            LabeledContent {
                Button(L("Delete")) { model.deleteSelected() }
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.delete, modifiers: []))
            } label: {
                Text(name(of: mark))
            }
        }
    }

    private func name(of mark: Drawing.Mark) -> String {
        switch mark.kind {
        case .arrow: L("Arrow")
        case .box: L("Box")
        case .highlight: L("Highlight")
        case .step: String(format: L("Step %d"), model.drawing.number(of: mark) ?? 1)
        case .text: L("Text")
        }
    }

    /// The part kept, in pixels, and a way back to the whole photo.
    private var cropping: some View {
        Section {
            LabeledContent {
                Button(L("Keep Whole Photo")) { model.change { $0.crop = nil } }
                    .disabled(model.drawing.crop == nil)
            } label: {
                Text(L("Crop"))
                if let kept = model.keptPixels {
                    Text(String(format: L("%d × %d pixels kept"), Int(kept.width), Int(kept.height)))
                        .monospacedDigit()
                } else {
                    Text(L("The whole photo is kept."))
                }
            }
        }
    }

    /// How many marks there are, a way to take them all away, and a way to
    /// keep the photo as it goes out as a file of its own.
    private var drawn: some View {
        Section {
            LabeledContent {
                Button(L("Remove All")) { model.removeAll() }
                    .disabled(model.drawing.marks.isEmpty)
            } label: {
                Text(String(format: L("Drawings: %d"), model.drawing.marks.count))
                Text(L("Drawn on what is sent. The photo itself stays as it is."))
            }
            LabeledContent {
                Button(L("Save Copy…")) { finish(.saveCopy) }
            } label: {
                Text(L("Keep as a file"))
                Text(L("Saves the photo as it goes out, drawn on and cropped, as a file of its own."))
            }
        }
    }

    /// Undo and Redo on the leading edge; Cancel and Done on the trailing.
    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help(L("Undo"))
            .accessibilityLabel(L("Undo"))
            .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut("z", modifiers: .command))
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .help(L("Redo"))
            .accessibilityLabel(L("Redo"))
            .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
            Spacer()
            Button(L("Cancel")) { finish(.cancel) }
                .keyboardShortcut(.cancelAction)
            Button(L("Done")) { finish(.done) }
                // Return in the words' field ends the typing instead.
                .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut.defaultAction)
        }
        .padding(16)
    }
}

/// What the window draws over the picture: the picture again, what is
/// covered, the marks as the copy has them, the crop, and the chosen mark's
/// outline and handles. The picture is drawn here too, so a highlight
/// multiplies into it as it does in the copy.
private struct Overlay {
    var image: NSImage
    var drawing: Drawing
    var covers: [CGRect]
    var unit: CGFloat
    var selected: Drawing.Mark?
    var cropping: Bool
    var placeholder: String
    var accent: CGColor

    /// - Parameter picture: where the picture lies in the canvas, which has
    ///   room around it for the handles.
    func draw(in context: inout GraphicsContext, picture: CGRect) {
        let size = picture.size
        // From the picture's bottom left, as marks are kept, to the canvas.
        let placed = { (rect: CGRect) in
            CGRect(x: picture.minX + rect.minX, y: picture.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        var under = context
        under.clip(to: Path(picture))
        under.draw(Image(nsImage: image).interpolation(.high), in: picture)
        for box in covers {
            under.fill(Path(roundedRect: placed(Drawing.rect(box, in: size)), cornerRadius: 3), with: .color(Color(white: 0.12)))
        }
        for mark in drawing.marks where mark.kind == .highlight {
            let box = Drawing.rect(mark.rect, in: size)
            guard box.width > 0, box.height > 0 else { continue }
            let fill = Drawing.highlightFill(mark.ink)
            var pen = under
            pen.blendMode = fill.multiplies ? .multiply : .normal
            pen.fill(Path(roundedRect: placed(box), cornerRadius: Drawing.highlightRadius(mark, box: box, unit: unit)),
                     with: .color(Color(cgColor: fill.color)))
        }
        context.withCGContext { cg in
            // Counted from the bottom left, as the copy is drawn.
            cg.translateBy(x: picture.minX, y: picture.maxY)
            cg.scaleBy(x: 1, y: -1)
            let area = CGRect(origin: .zero, size: size)
            cg.saveGState()
            cg.clip(to: area)
            Drawing.draw(drawing.marks, in: cg, size: size, unit: unit, placeholder: placeholder, highlights: false)
            if let crop = drawing.crop { drawCrop(Drawing.rect(crop, in: size), in: cg, picture: area) }
            cg.restoreGState()
            if let selected { drawSelection(selected, in: cg, size: size) }
        }
    }

    /// Outside the part kept dimmed, as it will not go; while cropping, its
    /// thirds and corners to drag.
    private func drawCrop(_ crop: CGRect, in context: CGContext, picture: CGRect) {
        context.addRect(picture)
        context.addRect(crop)
        context.setFillColor(CGColor(gray: 0, alpha: cropping ? 0.45 : 0.6))
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(1)
        context.stroke(crop.insetBy(dx: 0.5, dy: 0.5))
        guard cropping else { return }
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        context.setLineWidth(0.5)
        for third in [1.0 / 3, 2.0 / 3] {
            let x = crop.minX + crop.width * third, y = crop.minY + crop.height * third
            context.strokeLineSegments(between: [CGPoint(x: x, y: crop.minY), CGPoint(x: x, y: crop.maxY),
                                                 CGPoint(x: crop.minX, y: y), CGPoint(x: crop.maxX, y: y)])
        }
        let arm = min(18, crop.width / 2, crop.height / 2)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(3)
        context.setLineCap(.round)
        for corner in Drawing.corners(of: crop) {
            let dx: CGFloat = corner.x == crop.minX ? arm : -arm
            let dy: CGFloat = corner.y == crop.minY ? arm : -arm
            context.move(to: CGPoint(x: corner.x + dx, y: corner.y))
            context.addLine(to: corner)
            context.addLine(to: CGPoint(x: corner.x, y: corner.y + dy))
        }
        context.strokePath()
    }

    /// A dashed outline in the accent, and a white handle at each point it
    /// can be reshaped by.
    private func drawSelection(_ mark: Drawing.Mark, in context: CGContext, size: CGSize) {
        let handles = Drawing.handles(of: mark).map { Drawing.point($0, in: size) }
        if mark.kind != .arrow {
            context.setStrokeColor(accent)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            let frame = Drawing.frame(of: mark, size: size, unit: unit, placeholder: placeholder).insetBy(dx: -4, dy: -4)
            context.addPath(CGPath(roundedRect: frame, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
        for handle in handles {
            let dot = CGRect(x: handle.x - 4.5, y: handle.y - 4.5, width: 9, height: 9)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillEllipse(in: dot)
            context.setStrokeColor(accent)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: dot)
        }
    }
}
