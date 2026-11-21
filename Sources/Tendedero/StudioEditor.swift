import AppKit
import AVFoundation
import CoreImage
import SwiftUI

/// Studio: a screen recording made ready to explain something. The window
/// plays it as it will be saved: zoomed in where you clicked and typed,
/// following the pointer there, with a ring at each click and the arrows,
/// boxes, circles, numbered steps and words drawn over it, each for as
/// long as it is wanted. Under the picture, the timeline; on the trailing
/// edge, the inspector. Save Video makes a new recording beside it, and the
/// recording itself is never changed.
@MainActor
final class StudioEditor: NSObject, NSWindowDelegate {
    static let shared = StudioEditor()

    /// Called with each video saved, to hang it on the line.
    var onSaved: (URL) -> Void = { _ in }

    private var window: NSWindow?
    private var model: StudioModel?
    private var export: StudioExport.Stop?

    /// A recording to open once the video being saved is done, or once
    /// Studio is closed.
    private var waiting: URL?
    /// Cancel was clicked: the work goes back to how it was kept.
    private var discarding = false
    /// When the recording open last changed, as Studio opened it: trimmed
    /// meanwhile, its work is kept as the trim moved it, not as Studio had it.
    private var openedVersion: Date?

    /// Opens a recording in Studio, as it was left: when a video was last
    /// saved from it, or its window last closed. While a video is being
    /// saved, it opens once that is done. The recording open comes forward
    /// when it is opened again, and one just recorded waits, with a note,
    /// while Studio holds changes, so the work in front stays where it is.
    func open(_ url: URL, justRecorded: Bool = false) {
        guard export == nil else {
            waiting = url
            return
        }
        if let window, let model {
            // The same recording: its window comes forward, as it was left.
            guard model.url != url else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
            if justRecorded, model.hasChanges {
                waiting = url
                Notice.show(L("Your new recording opens in Studio once you close this one."), done: true, lasting: 6)
                return
            }
        }
        // Opened now, so none waits for Studio to close any more.
        waiting = nil
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration).seconds, duration > 0,
                  let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let natural = try? await track.load(.naturalSize), natural.width > 0, natural.height > 0 else {
                Notice.show(L("Could not open the recording."))
                return
            }
            let events = StudioStore.events(for: url)
            let project = StudioStore.project(for: url) ?? .first(events: events, duration: duration)
            show(StudioModel(url: url, source: StudioStore.cleanSource(for: url), duration: duration, pixels: natural,
                             events: events, project: project))
        }
    }

    private func show(_ model: StudioModel) {
        window?.close()
        openedVersion = Self.version(of: model.url)
        let name = model.url.deletingPathExtension().lastPathComponent
        let view = StudioEditorView(model: model, title: name) { [weak self] save in
            if save { self?.save(model) } else { self?.cancel() }
        } stop: { [weak self] in
            self?.export?.set()
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = name
        window.subtitle = L("Studio")
        let hosting = NSHostingView(rootView: view)
        // The window sets the size; the view fills it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = StudioLayout.minimum
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window.setContentSize(StudioLayout.windowSize(for: model.pixels,
                                                      in: CGSize(width: screen.width * 0.85, height: screen.height * 0.85)))
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.load()
    }

    /// Cancel: the window closes, and the work goes back to how it was kept.
    private func cancel() {
        discarding = true
        window?.close()
    }

    /// When a file last changed, to tell a recording trimmed meanwhile.
    private static func version(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        export?.set()
        export = nil
        // Closed any way but Cancel, by its close button or for another
        // recording, the work is kept for next time, as Save Video keeps it;
        // unless the recording was trimmed meanwhile, which moved it.
        if let model, !discarding, model.hasChanges, Self.version(of: model.url) == openedVersion {
            model.end()
            StudioStore.setProject(model.project, for: model.url)
        }
        discarding = false
        model?.close()
        model = nil
        window = nil
        // A recording that waited for Studio opens now.
        if let next = waiting {
            waiting = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { StudioEditor.shared.open(next) } }
        }
    }

    /// Writes the video as Studio shows it, beside the recording, at the
    /// size and as the kind of file chosen, keeps the work for next time,
    /// and hangs the video on the line.
    private func save(_ model: StudioModel) {
        guard export == nil else { return }
        model.pause()
        model.end()
        StudioStore.setProject(model.project, for: model.url)
        model.markKept()
        if let backdrop = model.project.backdrop { StudioModel.lastBackdrop = backdrop }
        let base = model.url.deletingPathExtension().lastPathComponent
        let name = String(format: L("%@ (edited)"), base)
        let output = model.output
        // A GIF is made from a movie made first, out of sight.
        let gif = output.kind == .gif
        let movie = gif
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Snapfly-Studio-\(UUID().uuidString).mov")
            : Collage.newFile(name, output.kind.rawValue)
        let stop = StudioExport.Stop()
        export = stop
        model.exporting = 0
        let look = model.look
        let backdrop = model.project.backdrop
        let source = model.source
        Task { @MainActor in
            do {
                defer { if gif { try? FileManager.default.removeItem(at: movie) } }
                try await StudioExport.run(source, look: look, backdrop: backdrop, quality: output.size, to: movie,
                                           stop: stop) { progress in
                    let shown = gif ? progress * 0.8 : progress
                    DispatchQueue.main.async { MainActor.assumeIsolated { StudioEditor.shared.progressed(shown) } }
                }
                var target = movie
                if gif {
                    progressed(0.9)
                    guard let made = await GIF.make(from: movie, named: name) else { throw StudioExport.Failure.cannotWrite }
                    target = made
                }
                onSaved(target)
                // The window it was saved from, unless it was closed meanwhile.
                if export === stop {
                    export = nil
                    window?.close()
                }
            } catch {
                if export === stop {
                    export = nil
                    model.exporting = nil
                }
                if !stop.isSet {
                    log.error("Could not save a Studio video: \(error.localizedDescription, privacy: .private)")
                    Notice.show(L("Could not save the video."))
                }
            }
            if export == nil, let next = waiting {
                waiting = nil
                open(next)
            }
        }
    }

    /// How far Save Video has come, while its window is open.
    private func progressed(_ progress: Double) {
        guard export != nil else { return }
        model?.exporting = progress
    }
}

/// The window's measures.
enum StudioLayout {
    /// The inspector on the trailing edge, as Hide Part's.
    static let panelWidth: CGFloat = 340
    /// Around the picture.
    static let margin: CGFloat = 24
    /// The row with Play and the time.
    static let transportHeight: CGFloat = 44
    /// The timeline: the ruler, the pictures with the sound, the zooms and
    /// the marks.
    static let timelineHeight: CGFloat = 184
    static let minimum = CGSize(width: 960, height: 640)

    /// The window to open: the recording as large as fits beside the
    /// inspector and over the timeline, never larger than itself.
    static func windowSize(for pixels: CGSize, in room: CGSize) -> CGSize {
        let bars = transportHeight + timelineHeight
        let area = CGSize(width: room.width - panelWidth - 2 * margin, height: room.height - 2 * margin - bars)
        let picture = HidePartLayout.fitted(pixels, in: area)
        let wanted = CGSize(width: picture.width + 2 * margin + panelWidth, height: picture.height + 2 * margin + bars)
        return CGSize(width: max(minimum.width, min(room.width, wanted.width)).rounded(),
                      height: max(minimum.height, min(room.height, wanted.height)).rounded())
    }
}

/// What is chosen: a zoom or a mark.
enum StudioSelection: Equatable {
    case zoom(UUID)
    case mark(UUID)
}

/// Studio's state for one recording: the work on it with Undo, where the
/// video is, and what is chosen.
@MainActor
final class StudioModel: ObservableObject {
    let url: URL
    let duration: Double
    /// The recording's pixels across and down.
    let pixels: CGSize
    /// What was done while recording; nil for one made before Studio.
    let events: StudioEvents?
    let player: AVPlayer
    /// What is played and saved from: the recording itself, or, for one
    /// made with Smooth pointer, as it was made, without any pointer.
    let source: URL
    /// Studio draws its own pointer on it.
    let drawsPointer: Bool

    @Published var project: StudioProject {
        didSet {
            guard project != oldValue else { return }
            // The camera is worked out again only when the zooms change.
            let camera = project.zooms == oldValue.zooms && project.follow == oldValue.follow ? look.camera : nil
            let pointer = project.pointer == oldValue.pointer ? look.pointer : nil
            look = StudioLook(project: project, events: events, duration: duration, pixels: pixels, camera: camera,
                              drawsPointer: drawsPointer, pointer: pointer)
            blurs.look = look
            if Self.blurred(project) != Self.blurred(oldValue) { refreshBlurs() }
        }
    }

    /// The project as it is drawn, made again as it changes.
    @Published private(set) var look: StudioLook
    @Published private(set) var selection: StudioSelection?
    @Published var tool: DrawTool {
        didSet {
            if tool.kind != nil { UserDefaults.standard.set(tool.rawValue, forKey: Self.toolKey) }
        }
    }

    @Published private(set) var ink: Drawing.Ink
    @Published private(set) var size: Drawing.Size
    /// Where the video stands while it is still; while it plays, `now`.
    @Published private(set) var time: Double = 0
    @Published private(set) var playing = false
    /// Pictures along the recording, and its sound's loudness, once read.
    @Published private(set) var strip: [CGImage] = []
    @Published private(set) var wave: [Float] = []
    /// How far Save Video has come, from 0 to 1, while it works.
    @Published var exporting: Double?
    /// How much wider than the window the timeline is.
    @Published var timelineZoom: Double = 1
    /// A still of the video under it, for pictures of the window made in
    /// CI, where the video itself is not drawn. Nil in use.
    @Published var poster: CGImage?
    /// How large, and as which kind of file, Save Video writes it.
    @Published var output: StudioOutput {
        didSet { Self.lastOutput = output }
    }

    @Published private var undone: [StudioProject] = []
    @Published private var redone: [StudioProject] = []
    private var before: StudioProject?
    private var finished: NSObjectProtocol?
    /// What the preview's video blurs, and the next time it is made again.
    private let blurs = StudioBlurs()
    private var blurRefresh: DispatchWorkItem?
    /// Follows the video while it plays, past the parts cut out and at the
    /// speed of each part.
    private var pacer: Any?
    /// The work as it was opened or last kept with Save Video.
    private var keptWork: StudioProject

    /// The tools that draw over a recording, with Select first.
    static let tools: [DrawTool] = [.select, .arrow, .box, .circle, .step, .text, .blur]
    private static let toolKey = "studioTool"

    /// - Parameter source: the recording as made, without the Mac's pointer,
    ///   which Studio plays and draws its own pointer on; nil to play `url`.
    init(url: URL, source: URL? = nil, duration: Double, pixels: CGSize, events: StudioEvents?, project: StudioProject) {
        self.url = url
        self.source = source ?? url
        drawsPointer = source != nil && events?.drawsPointer == true
        self.duration = duration
        self.pixels = pixels
        self.events = events
        self.project = project
        keptWork = project
        look = StudioLook(project: project, events: events, duration: duration, pixels: pixels,
                          drawsPointer: source != nil && events?.drawsPointer == true)
        output = Self.lastOutput
        player = AVPlayer(playerItem: AVPlayerItem(url: source ?? url))
        player.actionAtItemEnd = .pause
        let defaults = UserDefaults.standard
        let kept = defaults.string(forKey: Self.toolKey).flatMap(DrawTool.init(rawValue:))
        tool = kept.flatMap { StudioModel.tools.contains($0) && $0.kind != nil ? $0 : nil } ?? .arrow
        // The same ink and size as Draw on Photo, kept between the two.
        ink = defaults.string(forKey: "drawInk").flatMap(Drawing.Ink.init(rawValue:)) ?? .red
        size = defaults.string(forKey: "drawSize").flatMap(Drawing.Size.init(rawValue:)) ?? .medium
        blurs.look = look
        if !Self.blurred(project).isEmpty { applyBlurs() }
    }

    /// Reads the pictures and the sound for the timeline, and follows the
    /// video to its end.
    func load() {
        finished = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                          object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
        pacer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.pace(at: time.seconds) }
        }
        let url = source
        Task { [weak self] in
            let strip = await StudioMedia.strip(of: url, count: 24, height: 40)
            self?.strip = strip
            let wave = await StudioMedia.wave(of: url, count: 720)
            self?.wave = wave
        }
    }

    func close() {
        player.pause()
        playing = false
        if let finished { NotificationCenter.default.removeObserver(finished) }
        finished = nil
        if let pacer { player.removeTimeObserver(pacer) }
        pacer = nil
    }

    /// While it plays: on past a part cut out, and each part at its speed,
    /// as the saved video has them.
    private func pace(at t: Double) {
        guard playing, t.isFinite else { return }
        let parts = look.parts
        guard StudioCuts.edits(parts), let i = StudioCuts.index(at: t, in: parts) else {
            if player.rate != 1 { player.rate = 1 }
            return
        }
        guard !parts[i].removed else {
            if let next = StudioCuts.playable(from: t, in: parts) {
                player.seek(to: CMTime(seconds: next, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                // Nothing kept follows: it ends here.
                player.pause()
                playing = false
                time = parts[i].start
            }
            return
        }
        let rate = Float(parts[i].speed)
        if player.rate != rate { player.rate = rate }
    }

    // MARK: Playing

    /// Where the video is now, also while it plays.
    var now: Double {
        guard playing else { return time }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? min(duration, max(0, seconds)) : time
    }

    func togglePlaying() {
        if playing { pause() } else { play() }
    }

    func play() {
        end()
        if time >= duration - 0.05 { seek(to: 0) }
        player.play()
        playing = true
    }

    func pause() {
        guard playing else { return }
        time = now
        player.pause()
        playing = false
    }

    /// At the end it stands on the last frame, where what shows to the end
    /// still shows.
    private func reachedEnd() {
        playing = false
        time = max(0, duration - 1.0 / 60)
    }

    /// Moves the video to a time; `exact` once a drag ends, roughly while
    /// it goes on, so it keeps up.
    func seek(to t: Double, exact: Bool = true) {
        pause()
        time = min(duration, max(0, t))
        let tolerance = exact ? CMTime.zero : CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func step(by seconds: Double) {
        seek(to: now + seconds)
    }

    // MARK: Changes, for Undo

    /// Starts a change that ends with `end`, like a drag.
    func begin() {
        end()
        before = project
    }

    /// Ends a change, kept for Undo if it changed anything.
    func end() {
        guard let before else { return }
        self.before = nil
        guard before != project else { return }
        undone.append(before)
        if undone.count > 200 { undone.removeFirst() }
        redone = []
    }

    /// Keeps a change going, like a slider being moved: one change for Undo
    /// once it ends.
    func changing() {
        if before == nil { before = project }
    }

    func change(_ make: (inout StudioProject) -> Void) {
        begin()
        make(&project)
        end()
    }

    var canUndo: Bool { !undone.isEmpty || (before.map { $0 != project } ?? false) }
    var canRedo: Bool { !redone.isEmpty }

    /// Whether the work changed since it was opened or kept.
    var hasChanges: Bool { project != keptWork }

    /// The work as it is now is kept, as Save Video keeps it.
    func markKept() {
        keptWork = project
    }

    func undo() {
        end()
        guard let last = undone.popLast() else { return }
        redone.append(project)
        project = last
        dropStaleSelection()
    }

    func redo() {
        end()
        guard let next = redone.popLast() else { return }
        undone.append(project)
        project = next
        dropStaleSelection()
    }

    private func dropStaleSelection() {
        switch selection {
        case let .zoom(id) where !project.zooms.contains(where: { $0.id == id }): selection = nil
        case let .mark(id) where !project.marks.contains(where: { $0.id == id }): selection = nil
        default: break
        }
    }

    // MARK: Choosing

    func choose(_ new: StudioSelection?) {
        guard new != selection else { return }
        // Words left empty go as something else is chosen.
        if case let .mark(id)? = selection, let item = project.marks.first(where: { $0.id == id }),
           item.mark.kind == .text, item.mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            project.marks.removeAll { $0.id == id }
        }
        end()
        selection = new
    }

    var selectedZoom: StudioZoom? {
        guard case let .zoom(id)? = selection else { return nil }
        return project.zooms.first { $0.id == id }
    }

    var selectedMark: StudioProject.Mark? {
        guard case let .mark(id)? = selection else { return nil }
        return project.marks.first { $0.id == id }
    }

    func deleteSelected() {
        switch selection {
        case let .zoom(id)?: change { $0.zooms.removeAll { $0.id == id } }
        case let .mark(id)?: change { $0.marks.removeAll { $0.id == id } }
        case nil: return
        }
        selection = nil
    }

    // MARK: Zooms

    /// Zooming in on the clicks and typing, on or off: on, they are made
    /// again; off, the ones made so go and the ones made by hand stay.
    func setAutoZoom(_ on: Bool) {
        change { project in
            project.autoZoom = on
            if on, let events {
                project.zooms = StudioAutoZoom.remade(project.zooms, events: events, duration: duration,
                                                      scale: project.autoScale)
            } else {
                project.zooms.removeAll { $0.automatic }
            }
        }
        dropStaleSelection()
    }

    /// How close the automatic zooms come.
    var autoScale: Double {
        project.autoScale ?? StudioAutoZoom.defaultScale(width: events?.width ?? Double(pixels.width) / 2,
                                                         height: events?.height ?? Double(pixels.height) / 2)
    }

    /// While the slider moves, the automatic zooms come closer or go
    /// further, each no closer than its run of clicks allows.
    func setAutoScale(_ scale: Double) {
        changing()
        project.autoScale = (scale * 10).rounded() / 10
        guard project.autoZoom, let events else { return }
        project.zooms = StudioAutoZoom.remade(project.zooms, events: events, duration: duration, scale: project.autoScale)
        dropStaleSelection()
    }

    /// A zoom from where the video stands, chosen.
    func addZoom() {
        pause()
        guard let zoom = StudioTimeline.added(at: time, scale: autoScale, among: project.zooms, duration: duration) else {
            NSSound.beep()
            return
        }
        change { $0.zooms = ($0.zooms + [zoom]).sorted { $0.start < $1.start } }
        choose(.zoom(zoom.id))
    }

    var canAddZoom: Bool {
        let t = now
        return !project.zooms.contains { $0.contains(t) } && t < duration - StudioZoom.shortest / 2
    }

    /// Changes a zoom, which is the owner's from then on.
    func update(zoom id: UUID, _ make: (inout StudioZoom) -> Void) {
        guard let i = project.zooms.firstIndex(where: { $0.id == id }) else { return }
        var zoom = project.zooms[i]
        make(&zoom)
        zoom.automatic = false
        zoom.scale = min(StudioZoom.scales.upperBound, max(StudioZoom.scales.lowerBound, zoom.scale))
        project.zooms[i] = zoom
    }

    /// A zoom's span while it is dragged on the timeline, between its
    /// neighbours.
    func retime(zoom id: UUID, start: Double, end: Double) {
        let room = StudioTimeline.room(for: id, among: project.zooms, duration: duration)
        let start = max(room.low, min(start, end - StudioZoom.shortest))
        let end = min(room.high, max(end, start + StudioZoom.shortest))
        guard end - start >= StudioZoom.shortest - 0.0001 else { return }
        update(zoom: id) { $0.start = start; $0.end = end }
    }

    func move(zoom id: UUID, from original: (start: Double, end: Double), by delta: Double) {
        let room = StudioTimeline.room(for: id, among: project.zooms, duration: duration)
        let moved = StudioTimeline.moved(start: original.start, end: original.end, by: delta, low: room.low, high: room.high)
        update(zoom: id) { $0.start = moved.start; $0.end = moved.end }
    }

    /// The part a zoom looks at, while it is chosen and the video still:
    /// its place, or where the camera is then for one that follows the
    /// pointer.
    func area(of zoom: StudioZoom) -> CGRect {
        let center: CGPoint
        switch zoom.focus {
        case let .point(x, y):
            center = CGPoint(x: x, y: y)
        case .pointer:
            let settled = min(zoom.end - 0.01, max(zoom.start + StudioCamera.zoomResponse, time))
            let frame = look.camera.frame(at: settled)
            center = CGPoint(x: frame.x, y: frame.y)
        }
        return StudioCamera.rect(of: StudioCamera.Frame(x: Double(center.x), y: Double(center.y), scale: zoom.scale))
    }

    // MARK: Marks

    var shownInk: Drawing.Ink { selectedMark?.mark.ink ?? ink }
    var shownSize: Drawing.Size { selectedMark?.mark.size ?? size }

    func use(_ ink: Drawing.Ink) {
        if case let .mark(id)? = selection {
            change { project in
                if let i = project.marks.firstIndex(where: { $0.id == id }) { project.marks[i].mark.ink = ink }
            }
        }
        self.ink = ink
        UserDefaults.standard.set(ink.rawValue, forKey: "drawInk")
    }

    func use(_ size: Drawing.Size) {
        if case let .mark(id)? = selection {
            change { project in
                if let i = project.marks.firstIndex(where: { $0.id == id }) { project.marks[i].mark.size = size }
            }
        }
        self.size = size
        UserDefaults.standard.set(size.rawValue, forKey: "drawSize")
    }

    /// A new mark of the tool's kind at a place on the recording.
    func newMark(at point: CGPoint) -> Drawing.Mark? {
        guard let kind = tool.kind else { return nil }
        return Drawing.Mark(kind: kind, from: point, to: point, ink: ink, size: size)
    }

    /// A mark put down from where the video stands, for a few seconds, and
    /// chosen. Words wait for what is typed, which ends their change.
    func put(_ mark: Drawing.Mark, keepOpen: Bool = false) {
        choose(nil)
        begin()
        let span = StudioTimeline.kept(start: time, end: time + StudioFade.shown, duration: duration,
                                       shortest: StudioFade.shortest)
        project.marks.append(StudioProject.Mark(mark: mark, start: span.start, end: span.end))
        if !keepOpen && mark.kind != .text { end() }
        selection = .mark(mark.id)
    }

    /// Replaces a mark's drawing while it is dragged.
    func replace(_ mark: Drawing.Mark) {
        guard let i = project.marks.firstIndex(where: { $0.id == mark.id }) else { return }
        project.marks[i].mark = mark
    }

    func remove(_ id: UUID) {
        project.marks.removeAll { $0.id == id }
        if selection == .mark(id) { selection = nil }
    }

    /// The words of the chosen mark, as they are typed: one change for Undo.
    func type(_ text: String) {
        guard case let .mark(id)? = selection, let i = project.marks.firstIndex(where: { $0.id == id }),
              project.marks[i].mark.kind == .text, project.marks[i].mark.text != text else { return }
        if before == nil { before = project }
        project.marks[i].mark.text = text
    }

    /// A mark's span while it is dragged on the timeline.
    func retime(mark id: UUID, start: Double, end: Double) {
        guard let i = project.marks.firstIndex(where: { $0.id == id }) else { return }
        let start = max(0, min(start, end - StudioFade.shortest))
        let end = min(duration, max(end, start + StudioFade.shortest))
        project.marks[i].start = start
        project.marks[i].end = end
    }

    func move(mark id: UUID, from original: (start: Double, end: Double), by delta: Double) {
        guard let i = project.marks.firstIndex(where: { $0.id == id }) else { return }
        let moved = StudioTimeline.moved(start: original.start, end: original.end, by: delta, low: 0, high: duration)
        project.marks[i].start = moved.start
        project.marks[i].end = moved.end
    }

    /// The marks showing at a time.
    func marks(at t: Double) -> [StudioProject.Mark] {
        project.marks.filter { t >= $0.start && t < $0.end }
    }

    /// A mark's name, as the inspector and the timeline say it.
    func name(of item: StudioProject.Mark) -> String {
        switch item.mark.kind {
        case .arrow: L("Arrow")
        case .box: L("Box")
        case .circle: L("Circle")
        case .highlight: L("Highlight")
        case .step: String(format: L("Step %d"), project.numbers[item.id] ?? 1)
        case .text: L("Text")
        case .blur: L("Blur")
        }
    }

    // MARK: Clicks

    func setShowsClicks(_ on: Bool) {
        change { $0.showsClicks = on }
    }

    func setClickStyle(_ style: StudioClickStyle) {
        change { $0.clickStyle = style }
    }

    func setFollow(_ follow: StudioCamera.Follow) {
        change { $0.follow = follow }
    }

    /// A change to Studio's pointer: one step for Undo, or, `going`, part of
    /// one that goes on, like a slider being moved, ended by `end`.
    func setPointer(going: Bool = false, _ make: (inout StudioPointerStyle) -> Void) {
        if going { changing() } else { begin() }
        make(&project.pointer)
        if !going { end() }
    }

    // MARK: Background and saving

    private static let backdropKey = "studioBackdrop"
    private static let outputKey = "studioOutput"

    /// The background last saved with, the one a recording starts from when
    /// it is turned on.
    static var lastBackdrop: Backdrop {
        get {
            UserDefaults.standard.data(forKey: backdropKey).flatMap { try? JSONDecoder().decode(Backdrop.self, from: $0) }
                ?? Backdrop()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: backdropKey) }
    }

    /// How Save Video writes the video, as last chosen.
    static var lastOutput: StudioOutput {
        get {
            UserDefaults.standard.data(forKey: outputKey).flatMap { try? JSONDecoder().decode(StudioOutput.self, from: $0) }
                ?? StudioOutput()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: outputKey) }
    }

    /// Where the recording sits, as the preview shows it.
    var framing: StudioFraming {
        StudioFraming(pixels: pixels, backdrop: project.backdrop)
    }

    /// The video's size in pixels as it will be saved.
    var savedSize: CGSize {
        StudioFraming(pixels: pixels, backdrop: project.backdrop, quality: output.size).canvas
    }

    func setBackdrop(_ on: Bool) {
        change { $0.backdrop = on ? ($0.backdrop ?? Self.lastBackdrop) : nil }
    }

    /// A change to the background, turning it on if it was off, as a shape
    /// other than the recording's needs it: one step for Undo, or, `going`,
    /// part of one that goes on, like a slider being moved, ended by `end`.
    func adjustBackdrop(going: Bool = false, _ make: (inout Backdrop) -> Void) {
        if going { changing() } else { begin() }
        var backdrop = project.backdrop ?? Self.lastBackdrop
        make(&backdrop)
        project.backdrop = backdrop
        if !going { end() }
    }

    /// The shape of the video: the recording's own, without a background
    /// unless one was chosen, or a post's, on its background.
    func setRatio(_ ratio: Backdrop.Ratio) {
        guard ratio != .fit || project.backdrop != nil else { return }
        adjustBackdrop { $0.ratio = ratio }
    }

    var ratio: Backdrop.Ratio {
        project.backdrop?.ratio ?? .fit
    }

    // MARK: Captions

    private static let languageKey = "studioCaptionLanguage"

    /// The languages this Mac can hear by itself, read once Captions shows.
    @Published private(set) var languages: [Locale] = []
    /// The language captions are made in, as last chosen.
    @Published var language: Locale? = nil {
        didSet { UserDefaults.standard.set(language?.identifier, forKey: Self.languageKey) }
    }
    /// Captions being made.
    @Published private(set) var listening = false

    func loadLanguages() {
        guard languages.isEmpty else { return }
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { StudioListener.languages() }.value
            guard let self else { return }
            self.languages = found
            let kept = UserDefaults.standard.string(forKey: Self.languageKey)
            self.language = found.first { $0.identifier == kept } ?? StudioListener.preferred(among: found)
        }
    }

    /// The caption where the video stands.
    var caption: StudioCaption? {
        project.captions.first { $0.contains(time) }
    }

    /// Hears what is said and puts it at the foot of the video, line by line,
    /// in place of captions made before.
    func makeCaptions() {
        guard !listening, let language else { return }
        pause()
        listening = true
        let url = source
        Task { @MainActor [weak self] in
            do {
                let captions = try await StudioListener.captions(for: url, in: language)
                self?.change { $0.captions = captions }
            } catch {
                log.error("Could not make captions: \(String(describing: error), privacy: .public)")
                Notice.show(Self.why(error))
            }
            self?.listening = false
        }
    }

    private static func why(_ error: Error) -> String {
        switch error as? StudioListener.Failure {
        case .notAllowed?:
            L("Snapfly may not use speech recognition. Allow it in System Settings › Privacy & Security › Speech Recognition.")
        case .noSound?: L("This recording has no sound to make captions from.")
        case .notOnThisMac?: L("This Mac cannot hear this language by itself. Choose another one.")
        case .nothingHeard?: L("No words were heard in this recording.")
        case nil: L("Could not make captions.")
        }
    }

    /// The words of a caption, as they are typed: one change for Undo.
    func setCaption(_ id: UUID, text: String) {
        guard let i = project.captions.firstIndex(where: { $0.id == id }), project.captions[i].text != text else { return }
        if before == nil { before = project }
        project.captions[i].text = text
    }

    func removeCaptions() {
        change { $0.captions = [] }
    }

    // MARK: Blur

    private static func blurred(_ project: StudioProject) -> [StudioProject.Mark] {
        project.marks.filter { $0.mark.kind == .blur }
    }

    /// The preview's video blurred where the saved video is, made again a
    /// moment after the parts to blur change, so a drag stays quick.
    private func refreshBlurs() {
        blurRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyBlurs() }
        }
        blurRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func applyBlurs() {
        guard let item = player.currentItem else { return }
        guard !Self.blurred(project).isEmpty else {
            if item.videoComposition != nil { item.videoComposition = nil }
            return
        }
        let blurs = blurs
        // A new one each time, so the picture standing still is drawn again.
        item.videoComposition = AVVideoComposition(asset: item.asset) { request in
            let image = blurs.look.map {
                StudioDraw.blurred(request.sourceImage, look: $0, at: request.compositionTime.seconds)
            }
            request.finish(with: image ?? request.sourceImage, context: nil)
        }
    }

    // MARK: Cut and speed

    /// The part the video stands in, while it is still.
    var part: StudioPart? {
        let parts = look.parts
        return StudioCuts.index(at: time, in: parts).map { parts[$0] }
    }

    /// How long the saved video is.
    var savedLength: Double {
        StudioCuts.length(of: look.parts)
    }

    /// Whether the video can be split where it stands: not too near a split.
    var canSplit: Bool {
        StudioCuts.split(look.parts, at: time) != nil
    }

    /// Splits the part the video stands in, where it stands.
    func split() {
        pause()
        guard let split = StudioCuts.split(look.parts, at: time) else { return }
        change { $0.parts = split }
    }

    /// The part the video stands in, at a speed.
    func setSpeed(_ speed: Double) {
        editPart { $0.speed = speed }
    }

    /// Whether the part the video stands in can be cut out: not the last
    /// one kept.
    var canCut: Bool {
        guard let part else { return false }
        return part.removed || look.parts.contains { !$0.removed && $0.id != part.id }
    }

    /// The part the video stands in cut out, or back in.
    func toggleCut() {
        guard canCut else { return }
        editPart { $0.removed.toggle() }
    }

    /// Whether a part follows the one the video stands in, to join it to.
    var canJoin: Bool {
        guard let i = StudioCuts.index(at: time, in: look.parts) else { return false }
        return i + 1 < look.parts.count
    }

    /// The part the video stands in joined to the next, as one.
    func joinNext() {
        let parts = look.parts
        guard let i = StudioCuts.index(at: time, in: parts), let joined = StudioCuts.joined(parts, at: i) else { return }
        change { $0.parts = joined.count > 1 || StudioCuts.edits(joined) ? joined : [] }
    }

    private func editPart(_ make: (inout StudioPart) -> Void) {
        pause()
        var parts = look.parts
        guard let i = StudioCuts.index(at: time, in: parts) else { return }
        make(&parts[i])
        change { $0.parts = parts.count > 1 || StudioCuts.edits(parts) ? parts : [] }
    }
}
