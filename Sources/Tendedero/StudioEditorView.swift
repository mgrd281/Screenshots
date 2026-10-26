import AppKit
import AVFoundation
import SwiftUI

/// Studio's window: the recording as it will be saved, with Play and the
/// time under it, then the timeline; the inspector on the trailing edge.
struct StudioEditorView: View {
    @ObservedObject var model: StudioModel
    let title: String
    /// Save Video (true) or Cancel (false).
    let finish: (Bool) -> Void
    /// Stops Save Video while it works.
    let stop: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                StudioCanvas(model: model, title: title)
                Divider()
                transport
                Divider()
                StudioTimelineView(model: model)
                    .frame(height: StudioLayout.timelineHeight)
            }
            // Nothing changes while the video is being saved.
            .disabled(model.exporting != nil)
            Divider()
            inspector
        }
        .frame(minWidth: StudioLayout.minimum.width, minHeight: StudioLayout.minimum.height)
        .onChange(of: fieldFocused) { _, focused in
            if !focused { model.end() }
        }
    }

    // MARK: Play and the time

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlaying()
            } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.playing ? L("Pause") : L("Play"))
            .accessibilityLabel(model.playing ? L("Pause") : L("Play"))
            .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.space, modifiers: []))
            // A second back and on, with the arrow keys.
            Button { model.step(by: -1) } label: { EmptyView() }
                .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Button { model.step(by: 1) } label: { EmptyView() }
                .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            TimelineView(.animation(paused: !model.playing)) { _ in
                Text(StudioTimeline.text(model.now) + " / " + StudioTimeline.text(model.duration))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: $model.timelineZoom, in: 1...12)
                .controlSize(.small)
                .frame(width: 120)
                .help(L("Timeline Zoom"))
                .accessibilityLabel(L("Timeline Zoom"))
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: StudioLayout.transportHeight)
    }

    // MARK: The inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                zooms
                if let zoom = model.selectedZoom { chosen(zoom) }
                tools
                style
                if let item = model.selectedMark { chosen(item) }
                clicks
            }
            .formStyle(.grouped)
            .disabled(model.exporting != nil)
            Divider()
            footer
        }
        .frame(width: StudioLayout.panelWidth)
    }

    private var zooms: some View {
        Section {
            Toggle(L("Zoom in on clicks and typing"), isOn: Binding(get: { model.project.autoZoom },
                                                                     set: { model.setAutoZoom($0) }))
                .disabled(model.events == nil)
            LabeledContent(L("How close")) {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { model.autoScale }, set: { model.setAutoScale($0) }),
                           in: StudioZoom.scales.lowerBound...3, onEditingChanged: { editing in
                               if !editing { model.end() }
                           })
                        .controlSize(.small)
                    Text(Self.times(model.autoScale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .disabled(model.events == nil || !model.project.autoZoom)
            LabeledContent {
                Button(L("Add Zoom")) { model.addZoom() }
                    .disabled(!model.canAddZoom)
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut("z", modifiers: []))
            } label: {
                Text(String(format: L("Zooms: %d"), model.project.zooms.count))
                Text(L("From where the video is, for three seconds."))
            }
        } header: {
            Text(L("Zoom"))
        } footer: {
            Text(model.events == nil
                 ? L("This recording was made before Studio, so it has no clicks to zoom in on. Add zooms by hand.")
                 : L("Drag a zoom on the timeline to move it, or its ends to make it longer or shorter."))
                .foregroundStyle(.secondary)
        }
    }

    /// The zoom chosen: how close, and whether it follows the pointer.
    private func chosen(_ zoom: StudioZoom) -> some View {
        Section {
            LabeledContent(L("How close")) {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { model.selectedZoom?.scale ?? zoom.scale }, set: { scale in
                        model.changing()
                        model.update(zoom: zoom.id) { $0.scale = (scale * 10).rounded() / 10 }
                    }), in: StudioZoom.scales.lowerBound...3, onEditingChanged: { editing in
                        if !editing { model.end() }
                    })
                    .controlSize(.small)
                    Text(Self.times(model.selectedZoom?.scale ?? zoom.scale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            Picker(L("Looks at"), selection: Binding(get: { Self.follows(model.selectedZoom ?? zoom) }, set: { follow in
                let area = model.area(of: zoom)
                model.begin()
                model.update(zoom: zoom.id) {
                    $0.focus = follow ? .pointer : .point(x: Double(area.midX), y: Double(area.midY))
                }
                model.end()
            })) {
                Text(L("The Pointer")).tag(true)
                Text(L("One Place")).tag(false)
            }
            .pickerStyle(.segmented)
            LabeledContent {
                Button(L("Delete")) { model.deleteSelected() }
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.delete, modifiers: []))
            } label: {
                Text(L("Zoom"))
                Text(StudioTimeline.text(zoom.start) + " – " + StudioTimeline.text(zoom.end))
                    .monospacedDigit()
            }
        } footer: {
            Text(L("Drag the frame on the picture to choose what it looks at."))
                .foregroundStyle(.secondary)
        }
    }

    private static func follows(_ zoom: StudioZoom) -> Bool {
        if case .pointer = zoom.focus { return true }
        return false
    }

    /// How close a zoom comes, "2.0×", its number written as the Mac's
    /// region writes numbers, like "2,0×" in German.
    static func times(_ scale: Double) -> String {
        scale.formatted(.number.precision(.fractionLength(1))) + "×"
    }

    /// The tools in a row, the chosen one in the accent, with how to use it.
    private var tools: some View {
        Section {
            HStack(spacing: 4) {
                ForEach(StudioModel.tools) { tool in
                    toolButton(tool)
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text(L("Draw"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.tool.hint)
                if model.tool.kind != nil {
                    Text(L("It shows for three seconds from where the video is. Drag it on the timeline to change when."))
                }
            }
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
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(chosen ? Color.accentColor.opacity(0.16) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
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
            Picker(L("Size"), selection: Binding(get: { model.shownSize }, set: { model.use($0) })) {
                ForEach(Drawing.Size.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
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

    /// The mark chosen: its words, for words, when it shows, and a way to
    /// take it away.
    private func chosen(_ item: StudioProject.Mark) -> some View {
        Section {
            if item.mark.kind == .text {
                TextField(L("Words on the video"), text: Binding(get: { model.selectedMark?.mark.text ?? "" },
                                                                 set: { model.type($0) }),
                          prompt: Text(L("Type the words to show")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { fieldFocused = false }
                    .onExitCommand { fieldFocused = false }
            }
            LabeledContent {
                Button(L("Delete")) { model.deleteSelected() }
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut(.delete, modifiers: []))
            } label: {
                Text(model.name(of: item))
                Text(StudioTimeline.text(item.start) + " – " + StudioTimeline.text(item.end))
                    .monospacedDigit()
            }
        }
        .onAppear {
            if item.mark.kind == .text, item.mark.text.isEmpty { DispatchQueue.main.async { fieldFocused = true } }
        }
    }

    private var clicks: some View {
        Section {
            Toggle(L("Show clicks"), isOn: Binding(get: { model.project.showsClicks }, set: { model.setShowsClicks($0) }))
                .disabled(model.events == nil)
        } footer: {
            Text(L("A ring where each click landed."))
                .foregroundStyle(.secondary)
        }
    }

    /// Undo and Redo on the leading edge; Cancel and Save Video on the
    /// trailing, and how far Save Video has come while it works.
    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo || model.exporting != nil)
            .help(L("Undo"))
            .accessibilityLabel(L("Undo"))
            .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut("z", modifiers: .command))
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo || model.exporting != nil)
            .help(L("Redo"))
            .accessibilityLabel(L("Redo"))
            .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
            Spacer()
            if let progress = model.exporting {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .frame(width: 72)
                    .accessibilityLabel(L("Saving the video…"))
                Button(L("Stop")) { stop() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(L("Cancel")) { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button(L("Save Video")) { finish(true) }
                    .keyboardShortcut(fieldFocused ? nil : KeyboardShortcut.defaultAction)
            }
        }
        .padding(16)
    }
}

// MARK: - The picture

/// The recording as it will be saved, and what is drawn on it: marks are
/// drawn and changed here as on Draw on Photo, on the recording as the
/// camera shows it at that moment. With a zoom chosen, the whole recording
/// shows with the part the zoom looks at, to drag where it looks.
private struct StudioCanvas: View {
    @ObservedObject var model: StudioModel
    let title: String

    @State private var action: Action?
    @State private var cursor: NSCursor?

    /// How far from a handle a drag still takes it, in points.
    private static let reach: CGFloat = 8

    private enum Action {
        /// Pressed and not moved yet: a click unless it moves, on a mark or not.
        case pressing(UUID?)
        /// A new arrow, box or circle.
        case drawing(UUID)
        case moving(Drawing.Mark, from: CGPoint)
        case reshaping(Drawing.Mark, handle: Int)
        /// The part a chosen zoom looks at, dragged.
        case aiming(CGRect, from: CGPoint)
        case idle
    }

    var body: some View {
        GeometryReader { geometry in
            let margin = StudioLayout.margin
            let size = HidePartLayout.fitted(model.pixels, in: CGSize(width: geometry.size.width - 2 * margin,
                                                                     height: geometry.size.height - 2 * margin))
            StudioSurface(model: model)
                .frame(width: size.width, height: size.height)
                .clipShape(Rectangle())
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag($0, in: size) }
                                .onEnded { ended($0, in: size) }
                        )
                        .onHover { inside in pointer(inside ? cursorShape : nil) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: L("Zooms: %d"), model.project.zooms.count) + ", "
                                    + String(format: L("Drawings: %d"), model.project.marks.count))
        }
        // Laid out from the left, as the recording is, in every language, so
        // what is drawn lands where the pointer is.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onChange(of: model.tool) { _, _ in
            if cursor != nil { pointer(cursorShape) }
        }
        .onDisappear { pointer(nil) }
    }

    private var cursorShape: NSCursor {
        if model.selectedZoom != nil { return .openHand }
        switch model.tool {
        case .select: return .arrow
        case .text: return .iBeam
        default: return .crosshair
        }
    }

    private func pointer(_ new: NSCursor?) {
        guard new !== cursor else { return }
        if cursor != nil { NSCursor.pop() }
        new?.push()
        cursor = new
    }

    // MARK: Places

    /// What the picture shows now: the whole recording with a zoom chosen,
    /// else what the camera sees.
    private var seen: CGRect {
        model.selectedZoom != nil ? CGRect(x: 0, y: 0, width: 1, height: 1) : model.look.camera.rect(at: model.time)
    }

    /// From the view, counted from the top left, to the recording, from 0
    /// to 1 from the bottom left, kept on it.
    private func recorded(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let shown = CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
        let p = StudioCamera.recorded(shown, through: seen)
        return CGPoint(x: max(0, min(1, p.x)), y: max(0, min(1, p.y)))
    }

    /// The marks showing now, placed as the view shows them.
    private func shownMarks() -> [Drawing.Mark] {
        let rect = seen
        return model.marks(at: model.time).map { item in
            var mark = item.mark
            mark.from = StudioCamera.shown(mark.from, through: rect)
            mark.to = StudioCamera.shown(mark.to, through: rect)
            return mark
        }
    }

    private func unit(_ size: CGSize) -> CGFloat {
        model.look.unit(for: size)
    }

    // MARK: Dragging

    private func drag(_ value: DragGesture.Value, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let point = recorded(value.location, in: size)
        guard let action else {
            self.action = start(at: value.startLocation, in: size)
            return
        }
        switch action {
        case let .pressing(hit):
            guard hypot(value.translation.width, value.translation.height) >= 3 else { return }
            let start = recorded(value.startLocation, in: size)
            switch model.tool {
            case .arrow, .box, .circle:
                guard var mark = model.newMark(at: start) else { return }
                mark.to = point
                model.put(mark, keepOpen: true)
                self.action = .drawing(mark.id)
            default:
                // A step or words dragged by the hand, whatever the tool.
                guard let hit, let item = model.project.marks.first(where: { $0.id == hit }) else {
                    self.action = .idle
                    return
                }
                model.choose(.mark(hit))
                model.begin()
                self.action = .moving(item.mark, from: start)
            }
        case let .drawing(id):
            guard var mark = model.project.marks.first(where: { $0.id == id })?.mark else { return }
            mark.to = point
            model.replace(mark)
        case let .moving(mark, from):
            model.replace(Drawing.moved(mark, by: CGVector(dx: point.x - from.x, dy: point.y - from.y)))
        case let .reshaping(mark, handle):
            model.replace(Drawing.reshaped(mark, handle: handle, to: point))
        case let .aiming(area, from):
            guard let zoom = model.selectedZoom else { return }
            let x = min(1 - area.width / 2, max(area.width / 2, area.midX + point.x - from.x))
            let y = min(1 - area.height / 2, max(area.height / 2, area.midY + point.y - from.y))
            model.update(zoom: zoom.id) { $0.focus = .point(x: Double(x), y: Double(y)) }
        case .idle:
            break
        }
    }

    /// What a press starts: the zoom's frame, a chosen mark's handle, a mark
    /// to move, or a click yet to be told from a drag.
    private func start(at location: CGPoint, in size: CGSize) -> Action {
        model.pause()
        let point = recorded(location, in: size)
        let here = CGPoint(x: location.x, y: size.height - location.y)
        if let zoom = model.selectedZoom {
            var area = model.area(of: zoom)
            model.begin()
            if !area.contains(point) {
                // A press outside the frame brings it there.
                let x = min(1 - area.width / 2, max(area.width / 2, point.x))
                let y = min(1 - area.height / 2, max(area.height / 2, point.y))
                model.update(zoom: zoom.id) { $0.focus = .point(x: Double(x), y: Double(y)) }
                area = model.area(of: model.selectedZoom ?? zoom)
            }
            return .aiming(area, from: point)
        }
        let shown = shownMarks()
        if let chosen = model.selectedMark, let index = shown.firstIndex(where: { $0.id == chosen.id }),
           let handle = Drawing.handles(of: shown[index])
               .firstIndex(where: { near(Drawing.point($0, in: size), here, Self.reach) }) {
            model.begin()
            return .reshaping(chosen.mark, handle: handle)
        }
        let hit = Drawing(marks: shown).mark(at: here, size: size, unit: unit(size), slack: 4, placeholder: L("Text"))
        let item = hit.flatMap { hit in model.project.marks.first { $0.id == hit.id } }
        if model.tool == .select {
            guard let item else {
                model.choose(nil)
                return .idle
            }
            model.choose(.mark(item.id))
            model.begin()
            return .moving(item.mark, from: point)
        }
        return .pressing(item?.id)
    }

    private func ended(_ value: DragGesture.Value, in size: CGSize) {
        defer { action = nil }
        guard size.width > 0, size.height > 0 else { return }
        switch action {
        case let .pressing(hit):
            // A click: on a mark it is chosen; elsewhere a step or words go down.
            if let hit {
                model.choose(.mark(hit))
                return
            }
            switch model.tool {
            case .step, .text:
                guard let mark = model.newMark(at: recorded(value.startLocation, in: size)) else { return }
                model.put(mark)
            default:
                model.choose(nil)
            }
        case let .drawing(id):
            guard let mark = model.project.marks.first(where: { $0.id == id })?.mark else { return }
            let rect = seen
            let a = Drawing.point(StudioCamera.shown(mark.from, through: rect), in: size)
            let b = Drawing.point(StudioCamera.shown(mark.to, through: rect), in: size)
            let big = mark.kind == .arrow ? hypot(b.x - a.x, b.y - a.y) >= 8 : abs(b.x - a.x) >= 4 && abs(b.y - a.y) >= 4
            if !big { model.remove(id) }
            model.end()
        case .moving, .reshaping, .aiming:
            model.end()
        case .idle, nil:
            break
        }
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ reach: CGFloat) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= reach
    }
}

/// The video itself, seen through the camera, and over it the marks, the
/// clicks, what is chosen and a chosen zoom's frame. It follows the video
/// frame by frame while it plays, outside SwiftUI, so playing stays smooth.
private struct StudioSurface: NSViewRepresentable {
    @ObservedObject var model: StudioModel

    func makeNSView(context: Context) -> StudioSurfaceView {
        let view = StudioSurfaceView()
        view.model = model
        return view
    }

    func updateNSView(_ view: StudioSurfaceView, context: Context) {
        view.model = model
        view.refresh()
    }

    static func dismantleNSView(_ view: StudioSurfaceView, coordinator: ()) {
        view.stop()
    }
}

final class StudioSurfaceView: NSView {
    weak var model: StudioModel?

    private let still = CALayer()
    private let video = AVPlayerLayer()
    private let marks = StudioOverlayLayer()
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        video.videoGravity = .resize
        still.contentsGravity = .resize
        layer?.addSublayer(still)
        layer?.addSublayer(video)
        layer?.addSublayer(marks)
        marks.needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The picture never takes the pointer: the view over it does.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard let window else { return }
        marks.contentsScale = window.backingScaleFactor
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        link.isPaused = !(model?.playing ?? false)
        self.link = link
    }

    override func layout() {
        super.layout()
        refresh()
    }

    @objc private func tick() {
        guard let model, window != nil else { return stop() }
        guard model.playing else { return }
        place(at: model.now)
    }

    /// Everything again, for a change made while the video is still.
    func refresh() {
        guard let model else { return }
        if video.player !== model.player { video.player = model.player }
        // Frame by frame only while it plays.
        link?.isPaused = !model.playing
        place(at: model.now)
    }

    /// Lets the video and the frame-by-frame updates go, as the window closes.
    func stop() {
        link?.invalidate()
        link = nil
        video.player = nil
    }

    private func place(at t: Double) {
        guard let model else { return }
        let whole = model.selectedZoom != nil && !model.playing
        let rect = whole ? CGRect(x: 0, y: 0, width: 1, height: 1) : model.look.camera.rect(at: t)
        let size = bounds.size
        let scale = 1 / max(rect.width, 0.0001)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        video.frame = CGRect(x: -rect.minX * size.width * scale, y: -rect.minY * size.height * scale,
                             width: size.width * scale, height: size.height * scale)
        still.frame = video.frame
        still.contents = model.poster
        marks.frame = bounds
        // The chosen mark's outline, while it shows and the video is still.
        var chosen: Drawing.Mark?
        if !model.playing, let item = model.selectedMark, t >= item.start, t < item.end {
            var mark = item.mark
            mark.from = StudioCamera.shown(mark.from, through: rect)
            mark.to = StudioCamera.shown(mark.to, through: rect)
            chosen = mark
        }
        var area: CGRect?
        if whole, let zoom = model.selectedZoom { area = model.area(of: zoom) }
        marks.state = StudioOverlayLayer.State(look: model.look, time: t, rect: rect, chosen: chosen, area: area,
                                               accent: NSColor.controlAccentColor.cgColor, still: Motion.reduced)
        CATransaction.commit()
        marks.setNeedsDisplay()
    }
}

/// Draws over the video: the marks and clicks as the saved video has them,
/// the chosen mark's outline and handles, and a chosen zoom's frame.
private final class StudioOverlayLayer: CALayer {
    struct State {
        var look: StudioLook
        var time: Double
        var rect: CGRect
        /// The chosen mark as the view shows it, while it shows.
        var chosen: Drawing.Mark?
        /// The part a chosen zoom looks at, on the whole recording.
        var area: CGRect?
        var accent: CGColor
        /// Reduce Motion: marks only fade in the window. The saved video
        /// draws them in, for whoever watches it.
        var still: Bool
    }

    var state: State?

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func action(forKey event: String) -> CAAction? { NSNull() }

    override func draw(in context: CGContext) {
        guard let state else { return }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // The layer counts from its bottom left, as the video is drawn.
        StudioDraw.overlay(state.look, at: state.time, rect: state.rect, in: context, size: size, still: state.still)
        if let area = state.area { drawArea(Drawing.rect(area, in: size), in: context, size: size, accent: state.accent) }
        if let chosen = state.chosen {
            drawSelection(chosen, in: context, size: size, unit: state.look.unit(for: size), accent: state.accent)
        }
    }

    /// Outside the zoom's part dimmed, with a white edge and corners to drag.
    private func drawArea(_ area: CGRect, in context: CGContext, size: CGSize, accent: CGColor) {
        context.addRect(CGRect(origin: .zero, size: size))
        context.addRect(area)
        context.setFillColor(CGColor(gray: 0, alpha: 0.45))
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(1.5)
        context.stroke(area.insetBy(dx: 0.75, dy: 0.75))
        let arm = min(18, area.width / 2, area.height / 2)
        context.setLineWidth(3)
        context.setLineCap(.round)
        for corner in Drawing.corners(of: area) {
            let dx: CGFloat = corner.x == area.minX ? arm : -arm
            let dy: CGFloat = corner.y == area.minY ? arm : -arm
            context.move(to: CGPoint(x: corner.x + dx, y: corner.y))
            context.addLine(to: corner)
            context.addLine(to: CGPoint(x: corner.x, y: corner.y + dy))
        }
        context.strokePath()
    }

    /// A dashed outline in the accent, and a white handle at each point it
    /// can be reshaped by, as Draw on Photo shows them.
    private func drawSelection(_ mark: Drawing.Mark, in context: CGContext, size: CGSize, unit: CGFloat, accent: CGColor) {
        let handles = Drawing.handles(of: mark).map { Drawing.point($0, in: size) }
        if mark.kind != .arrow {
            context.setStrokeColor(accent)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            let frame = Drawing.frame(of: mark, size: size, unit: unit, placeholder: L("Text")).insetBy(dx: -4, dy: -4)
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

// MARK: - The timeline

/// The timeline: a ruler with the time and a tick at each click, pictures
/// along the recording with its sound, then the zooms and the marks, each
/// a block to move, or to stretch by its ends. A click or a drag on the
/// ruler or the pictures moves the video there.
private struct StudioTimelineView: View {
    @ObservedObject var model: StudioModel

    /// A block being dragged: which, by what, and where it was.
    @State private var grab: Grab?

    private struct Grab {
        enum Part { case body, start, end }
        var selection: StudioSelection
        var part: Part
        var start: Double
        var end: Double
        var moved = false
    }

    private static let ruler: CGFloat = 20
    private static let strip: CGFloat = 40
    private static let track: CGFloat = 26
    private static let markRow: CGFloat = 18
    private static let rows = 3
    private static let gap: CGFloat = 6
    private static let gutter: CGFloat = 28
    private static let space = "studio-timeline"

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            labels
            GeometryReader { geometry in
                let fit = max(100, geometry.size.width - 16)
                let width = fit * CGFloat(model.timelineZoom)
                let pps = width / CGFloat(max(model.duration, 0.1))
                ScrollView(.horizontal, showsIndicators: model.timelineZoom > 1.01) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: Self.gap) {
                            ruler(pps: pps, width: width)
                            strip(pps: pps, width: width)
                            zoomTrack(pps: pps, width: width)
                            markTrack(pps: pps, width: width)
                        }
                        playhead(pps: pps)
                    }
                    .frame(width: width, alignment: .leading)
                    .coordinateSpace(name: Self.space)
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        // Time runs from the left in every language, as a video's does, so the
        // ruler, the pictures, the blocks and the playhead agree.
        .environment(\.layoutDirection, .leftToRight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// What each row is, on the leading edge.
    private var labels: some View {
        VStack(spacing: Self.gap) {
            Color.clear.frame(height: Self.ruler)
            row("film", L("Recording"), height: Self.strip)
            row("plus.magnifyingglass", L("Zoom"), height: Self.track)
            row("pencil.tip", L("Draw"), height: CGFloat(Self.rows) * Self.markRow + 4)
        }
        .padding(.vertical, 10)
        .frame(width: Self.gutter + 16)
    }

    private func row(_ symbol: String, _ title: String, height: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.gutter, height: height)
            .help(title)
            .accessibilityLabel(title)
    }

    private func seconds(_ x: CGFloat, _ pps: CGFloat) -> Double {
        min(model.duration, max(0, Double(x / pps)))
    }

    /// A click or drag here moves the video; it leaves what is chosen alone.
    private func scrub(_ pps: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { model.seek(to: seconds($0.location.x, pps), exact: false) }
            .onEnded { model.seek(to: seconds($0.location.x, pps)) }
    }

    // MARK: Ruler and pictures

    private func ruler(pps: CGFloat, width: CGFloat) -> some View {
        let step = StudioTimeline.tick(pointsPerSecond: Double(pps))
        let clicks = model.project.showsClicks ? (model.events?.clicks ?? []).map(\.t) : []
        return Canvas { context, size in
            var t = 0.0
            while t <= model.duration + 0.0001 {
                let x = CGFloat(t) * pps
                context.fill(Path(CGRect(x: x, y: size.height - 6, width: 1, height: 6)),
                             with: .color(.secondary.opacity(0.6)))
                context.draw(Text(StudioTimeline.text(t)).font(.system(size: 10)).monospacedDigit()
                                 .foregroundColor(.secondary),
                             at: CGPoint(x: x + 3, y: 1), anchor: .topLeading)
                let half = CGFloat(t + step / 2) * pps
                if step >= 1, half < width {
                    context.fill(Path(CGRect(x: half, y: size.height - 3, width: 1, height: 3)),
                                 with: .color(.secondary.opacity(0.4)))
                }
                t += step
            }
            for click in clicks {
                let x = CGFloat(click) * pps
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: size.height - 10, width: 4, height: 4)),
                             with: .color(.accentColor))
            }
        }
        .frame(width: width, height: Self.ruler)
        .contentShape(Rectangle())
        .gesture(scrub(pps))
        .accessibilityElement()
        .accessibilityLabel(L("Time"))
        .accessibilityValue(StudioTimeline.text(model.time))
        .accessibilityAdjustableAction { direction in
            model.step(by: direction == .increment ? 1 : -1)
        }
    }

    /// Pictures along the recording, its sound's loudness over their foot.
    private func strip(pps: CGFloat, width: CGFloat) -> some View {
        let wave = model.wave
        return ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                if model.strip.isEmpty {
                    Color.primary.opacity(0.06)
                } else {
                    ForEach(Array(model.strip.enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width / CGFloat(model.strip.count), height: Self.strip)
                            .clipped()
                    }
                }
            }
            if !wave.isEmpty {
                Canvas { context, size in
                    let bar = size.width / CGFloat(wave.count)
                    var shape = Path()
                    for (i, peak) in wave.enumerated() {
                        let height = max(1, CGFloat(peak) * size.height)
                        shape.addRect(CGRect(x: CGFloat(i) * bar, y: size.height - height, width: max(1, bar * 0.7),
                                             height: height))
                    }
                    context.fill(shape, with: .color(.white.opacity(0.85)))
                }
                .frame(height: Self.strip * 0.45)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: Self.strip)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .gesture(scrub(pps))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Recording"))
    }

    // MARK: Zooms and marks

    private func zoomTrack(pps: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            emptyTrack(pps: pps, width: width, height: Self.track)
            ForEach(model.project.zooms) { zoom in
                zoomBlock(zoom, pps: pps)
                    .offset(x: CGFloat(zoom.start) * pps)
            }
        }
        .frame(width: width, height: Self.track, alignment: .topLeading)
    }

    private func markTrack(pps: CGFloat, width: CGFloat) -> some View {
        let marks = model.project.marks
        let rows = StudioTimeline.rows(of: marks.map { (start: $0.start, end: $0.end) }, rows: Self.rows)
        let height = CGFloat(Self.rows) * Self.markRow + 4
        return ZStack(alignment: .topLeading) {
            emptyTrack(pps: pps, width: width, height: height)
            ForEach(Array(marks.enumerated()), id: \.element.id) { index, item in
                markBlock(item, pps: pps)
                    .offset(x: CGFloat(item.start) * pps, y: 2 + CGFloat(rows[index]) * Self.markRow)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// A track's ground: a click on it chooses nothing and moves the video.
    private func emptyTrack(pps: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    model.choose(nil)
                    model.seek(to: seconds(value.location.x, pps), exact: false)
                }
                .onEnded { model.seek(to: seconds($0.location.x, pps)) })
    }

    private func zoomBlock(_ zoom: StudioZoom, pps: CGFloat) -> some View {
        let chosen = model.selection == .zoom(zoom.id)
        let width = max(10, CGFloat(zoom.duration) * pps)
        // Worked out apart, so the view below stays quick to compile.
        let scale: String = StudioEditorView.times(zoom.scale)
        let icon: String = zoom.automatic ? "sparkle.magnifyingglass" : "plus.magnifyingglass"
        let tip: String = zoom.automatic ? L("Made from your clicks and typing") : L("Zoom")
        let span: String = StudioTimeline.text(zoom.start) + " – " + StudioTimeline.text(zoom.end)
        let value: String = span + ", " + scale
        let traits: AccessibilityTraits = chosen ? [.isButton, .isSelected] : .isButton
        let fill: Color = chosen ? Color.accentColor : Color.accentColor.opacity(0.28)
        let edge: Color = Color.accentColor.opacity(chosen ? 0 : 0.7)
        let words: Color = chosen ? Color.white : Color.primary
        let block = RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(edge, lineWidth: 1))
            .overlay(alignment: .leading) {
                if width > 56 {
                    Label(scale, systemImage: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(words)
                        .lineLimit(1)
                        .padding(.leading, 8)
                }
            }
            .overlay { if chosen { grips(width: width, height: Self.track) } }
            .frame(width: width, height: Self.track)
        let handled = block
            .contentShape(Rectangle())
            .gesture(blockDrag(.zoom(zoom.id), start: zoom.start, end: zoom.end, pps: pps))
            .contextMenu {
                Button(L("Delete")) {
                    model.choose(.zoom(zoom.id))
                    model.deleteSelected()
                }
            }
            .help(tip)
        return handled
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Zoom"))
            .accessibilityValue(value)
            .accessibilityAddTraits(traits)
            .accessibilityAction { model.choose(.zoom(zoom.id)) }
    }

    private func markBlock(_ item: StudioProject.Mark, pps: CGFloat) -> some View {
        let chosen = model.selection == .mark(item.id)
        let width = max(10, CGFloat(item.end - item.start) * pps)
        let ink = Color(cgColor: item.mark.ink.color)
        // Worked out apart, so the view below stays quick to compile.
        let name: String = model.name(of: item)
        let said: String = item.mark.kind == .text && !item.mark.text.isEmpty ? " · " + item.mark.text : ""
        let title: String = name + said
        let value: String = StudioTimeline.text(item.start) + " – " + StudioTimeline.text(item.end)
        let traits: AccessibilityTraits = chosen ? [.isButton, .isSelected] : .isButton
        let fill: Color = ink.opacity(chosen ? 0.9 : 0.32)
        let edge: Color = chosen ? Color.accentColor : ink.opacity(0.8)
        let line: CGFloat = chosen ? 2 : 1
        let words: Color = chosen ? Color(cgColor: item.mark.ink.onColor) : Color.primary
        let block = RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(edge, lineWidth: line))
            .overlay(alignment: .leading) {
                if width > 40 {
                    Text(verbatim: title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(words)
                        .lineLimit(1)
                        .padding(.leading, 6)
                        .padding(.trailing, 4)
                }
            }
            .overlay { if chosen { grips(width: width, height: Self.markRow - 2) } }
            .frame(width: width, height: Self.markRow - 2)
        let handled = block
            .contentShape(Rectangle())
            .gesture(blockDrag(.mark(item.id), start: item.start, end: item.end, pps: pps))
            .contextMenu {
                Button(L("Delete")) {
                    model.choose(.mark(item.id))
                    model.deleteSelected()
                }
            }
        return handled
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(value)
            .accessibilityAddTraits(traits)
            .accessibilityAction { model.choose(.mark(item.id)) }
    }

    /// The ends of a chosen block, to stretch it by.
    private func grips(width: CGFloat, height: CGFloat) -> some View {
        HStack {
            Capsule().fill(Color.white).frame(width: 3, height: height * 0.5)
            Spacer(minLength: 0)
            Capsule().fill(Color.white).frame(width: 3, height: height * 0.5)
        }
        .padding(.horizontal, 3)
        .frame(width: width)
        .allowsHitTesting(false)
    }

    /// A block dragged: by its middle it moves, by an end it stretches. A
    /// click chooses it, and for a mark brings the video to it.
    private func blockDrag(_ selection: StudioSelection, start: Double, end: Double, pps: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if grab?.selection != selection {
                    let x = value.startLocation.x - CGFloat(start) * pps
                    let width = max(10, CGFloat(end - start) * pps)
                    let edge = min(8, width / 4)
                    let part: Grab.Part = x <= edge ? .start : (x >= width - edge ? .end : .body)
                    model.pause()
                    model.choose(selection)
                    model.begin()
                    grab = Grab(selection: selection, part: part, start: start, end: end)
                }
                guard var grab else { return }
                let delta = Double(value.translation.width / pps)
                guard grab.moved || abs(value.translation.width) >= 2 else { return }
                grab.moved = true
                self.grab = grab
                switch (selection, grab.part) {
                case let (.zoom(id), .body): model.move(zoom: id, from: (grab.start, grab.end), by: delta)
                case let (.zoom(id), .start): model.retime(zoom: id, start: grab.start + delta, end: grab.end)
                case let (.zoom(id), .end): model.retime(zoom: id, start: grab.start, end: grab.end + delta)
                case let (.mark(id), .body): model.move(mark: id, from: (grab.start, grab.end), by: delta)
                case let (.mark(id), .start): model.retime(mark: id, start: grab.start + delta, end: grab.end)
                case let (.mark(id), .end): model.retime(mark: id, start: grab.start, end: grab.end + delta)
                }
            }
            .onEnded { _ in
                defer { grab = nil }
                model.end()
                // A mark clicked shows: the video goes to it when it isn't.
                if case let .mark(id) = selection, grab?.moved != true,
                   let item = model.project.marks.first(where: { $0.id == id }),
                   model.time < item.start || model.time >= item.end {
                    model.seek(to: min(item.end - 0.01, item.start + StudioFade.appear))
                }
            }
    }

    // MARK: The playhead

    private func playhead(pps: CGFloat) -> some View {
        TimelineView(.animation(paused: !model.playing)) { _ in
            let x = CGFloat(model.now) * pps
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 9, height: 12)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1.5)
            }
            .frame(width: 9)
            .offset(x: x - 4.5)
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}
