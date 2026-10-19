import SwiftUI
import UIKit

/// What one finger does on the picture: select and move a place, or hide
/// more by hand with the marker, a box or an outline, or take covers away
/// with the eraser. Two fingers always zoom and move the picture.
enum EditTool: String, CaseIterable, Identifiable {
    case select, marker, box, lasso, eraser

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: "hand.point.up.left"
        case .marker: "pencil.tip"
        case .box: "rectangle"
        case .lasso: "lasso"
        case .eraser: "eraser"
        }
    }

    var title: String {
        switch self {
        case .select: L("Select")
        case .marker: L("Marker")
        case .box: L("Box")
        case .lasso: L("Lasso")
        case .eraser: L("Eraser")
        }
    }

    /// Whether one finger draws, rather than moves the picture.
    var draws: Bool { self != .select }
}

/// What the canvas tells, each place from 0 to 1 from the bottom left of
/// the original picture, whatever the zoom.
struct CanvasActions {
    var tap: (CGPoint) -> Void = { _ in }
    var longPress: (CGPoint) -> Void = { _ in }
    var draw: (HandShape) -> Void = { _ in }
    var erase: ([CGPoint]) -> Void = { _ in }
    var move: (Int, CGPoint) -> Void = { _, _ in }
    var resize: (Int, CGRect) -> Void = { _, _ in }
    var turn: (Int, CGFloat) -> Void = { _, _ in }
}

/// The picture being protected, to zoom with two fingers or a double tap,
/// with its places marked: ink over a covered place, a dashed outline round
/// one to check or left, and handles round the one selected.
struct MarkCanvas: UIViewRepresentable {
    let image: UIImage
    let marks: [ProtectionPlan.Mark]
    /// Marks still to check, outlined in the accent.
    let checking: Set<Int>
    /// Whether the picture is the covered copy itself, so a covered place
    /// needs no ink of its own on it.
    let isCopy: Bool
    let tool: EditTool
    let selected: Int?
    let markerWidth: CGFloat
    let eraserReach: CGFloat
    let actions: CanvasActions

    func makeUIView(context: Context) -> CanvasView {
        CanvasView()
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.actions = actions
        view.show(image, marks: marks, checking: checking, isCopy: isCopy, tool: tool, selected: selected,
                  markerWidth: markerWidth, eraserReach: eraserReach)
    }
}

final class CanvasView: UIScrollView, UIScrollViewDelegate {
    var actions = CanvasActions()
    private let content = UIView()
    private let picture = UIImageView()
    private let overlay = MarksView()
    private var imageSize = CGSize.zero
    /// The size the picture was last fitted to, so it is fitted again only
    /// when the room changes.
    private var fitted = CGSize.zero
    private var tool = EditTool.select
    private var markerWidth: CGFloat = HandShape.widths[1]
    private var eraserReach: CGFloat = 0.03

    /// What a drag on the selected mark takes hold of.
    enum GrabKind {
        case body
        case corner(Int)
        case turn
    }

    private var grab: GrabKind?
    private var start: CGPoint?
    private var points: [CGPoint] = []

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
    private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
    private lazy var edit = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        addSubview(content)
        content.addSubview(picture)
        content.addSubview(overlay)
        picture.contentMode = .scaleToFill
        picture.layer.cornerRadius = 12
        picture.layer.cornerCurve = .continuous
        picture.clipsToBounds = true
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.contentMode = .redraw
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        hold.minimumPressDuration = 0.45
        edit.maximumNumberOfTouches = 1
        edit.delegate = self
        for gesture in [tap, doubleTap, hold, edit] { content.addGestureRecognizer(gesture) }
        isAccessibilityElement = true
        accessibilityLabel = L("Covered screenshot")
        accessibilityHint = L("Details lists every place, to cover or uncover each one.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ image: UIImage, marks: [ProtectionPlan.Mark], checking: Set<Int>, isCopy: Bool, tool: EditTool,
              selected: Int?, markerWidth: CGFloat, eraserReach: CGFloat) {
        if picture.image !== image {
            picture.image = image
            if image.size != imageSize {
                imageSize = image.size
                fitted = .zero
                setNeedsLayout()
            }
        }
        self.tool = tool
        self.markerWidth = markerWidth
        self.eraserReach = eraserReach
        overlay.aspect = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        overlay.marks = marks
        overlay.checking = checking
        overlay.isCopy = isCopy
        overlay.selected = selected
        overlay.zoom = zoomScale
        overlay.setNeedsDisplay()
        // While drawing, one finger draws and two move the picture.
        panGestureRecognizer.minimumNumberOfTouches = tool.draws ? 2 : 1
        hold.isEnabled = tool == .select
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != fitted {
            fitted = bounds.size
            zoomScale = 1
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            content.bounds = CGRect(origin: .zero, size: size)
            picture.frame = content.bounds
            overlay.frame = content.bounds
            contentSize = size
        }
        center()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
        // Handles keep their size on the screen.
        overlay.zoom = zoomScale
        overlay.setNeedsDisplay()
    }

    /// The picture in the middle while it is smaller than the room.
    private func center() {
        content.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                                 y: max(contentSize.height, bounds.height) / 2)
    }

    // MARK: Places

    /// A point on the picture, from 0 to 1 from the bottom left.
    private func normalized(_ point: CGPoint) -> CGPoint {
        let size = content.bounds.size
        return CGPoint(x: point.x / max(size.width, 1), y: 1 - point.y / max(size.height, 1))
    }

    // MARK: Gestures

    /// One finger draws with a drawing tool; selecting, it moves the mark
    /// selected where it holds it, and the picture anywhere else.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === edit {
            if tool.draws { return true }
            grab = overlay.grab(at: gesture.location(in: content))
            return grab != nil
        }
        if gesture === panGestureRecognizer, !tool.draws, overlay.grab(at: gesture.location(in: content)) != nil {
            return false
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = normalized(gesture.location(in: content))
        switch tool {
        case .select: actions.tap(point)
        case .eraser: actions.erase([point])
        case .marker: actions.draw(.stroke([point], width: markerWidth))
        case .box, .lasso: break
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: content)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width,
                            height: size.height), animated: true)
        }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        actions.longPress(normalized(gesture.location(in: content)))
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: content)
        switch gesture.state {
        case .began:
            start = point
            points = [point]
        case .changed:
            guard let last = points.last else { return }
            if hypot(point.x - last.x, point.y - last.y) >= 2 / max(zoomScale, 1) { points.append(point) }
            preview(to: point)
        case .ended:
            commit(at: point)
            fallthrough
        default:
            start = nil
            points = []
            grab = nil
            overlay.live = nil
            overlay.rubbing = []
            overlay.pending = nil
            overlay.setNeedsDisplay()
        }
    }

    /// The shape being drawn, or the selected mark as it would be.
    private func preview(to point: CGPoint) {
        guard let start else { return }
        let shown = points.map(normalized)
        switch tool {
        case .marker:
            overlay.live = .stroke(shown, width: markerWidth)
        case .lasso:
            overlay.live = .outline(shown)
        case .box:
            overlay.live = .box(rect(from: normalized(start), to: normalized(point)), angle: 0)
        case .eraser:
            overlay.rubbing = points
            overlay.reach = eraserReach
        case .select:
            overlay.pending = change(from: start, to: point)
        }
        overlay.setNeedsDisplay()
    }

    private func commit(at point: CGPoint) {
        guard let start else { return }
        let shown = points.map(normalized)
        // The start of a two-finger zoom is no stroke.
        let length = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        switch tool {
        case .marker:
            if length >= 4 / max(zoomScale, 1) { actions.draw(.stroke(shown, width: markerWidth)) }
        case .lasso:
            if shown.count >= 3 { actions.draw(.outline(shown)) }
        case .box:
            actions.draw(.box(rect(from: normalized(start), to: normalized(point)), angle: 0))
        case .eraser:
            actions.erase(shown)
        case .select:
            guard let id = overlay.selected, let change = change(from: start, to: point) else { return }
            switch change {
            case .moved(let offset): actions.move(id, offset)
            case .resized(let rect): actions.resize(id, rect)
            case .turned(let angle): actions.turn(id, angle)
            }
        }
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// What a drag from one point to another does to the selected mark.
    private func change(from start: CGPoint, to point: CGPoint) -> MarksView.Change? {
        guard let grab, let mark = overlay.selectedMark else { return nil }
        let a = normalized(start), b = normalized(point)
        let aspect = overlay.aspect
        switch grab {
        case .body:
            return .moved(CGPoint(x: b.x - a.x, y: b.y - a.y))
        case .turn:
            guard case .box(let box, _) = mark.shape else { return nil }
            let middle = CGPoint(x: box.midX * aspect, y: box.midY)
            let from = atan2(a.y - middle.y, a.x * aspect - middle.x)
            let to = atan2(b.y - middle.y, b.x * aspect - middle.x)
            return .turned(to - from)
        case .corner(let index):
            if case .box(let box, let angle) = mark.shape, abs(angle) > 0.001 {
                // A turned box grows or shrinks about its middle.
                let middle = CGPoint(x: box.midX * aspect, y: box.midY)
                let x = b.x * aspect - middle.x, y = b.y - middle.y
                let along = abs(x * cos(-angle) - y * sin(-angle)), across = abs(x * sin(-angle) + y * cos(-angle))
                let width = along * 2 / max(aspect, 0.01), height = across * 2
                return .resized(CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height))
            }
            var frame = mark.rect
            if case .box(let box, _) = mark.shape { frame = box }
            let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                           CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
            return .resized(rect(from: corners[(index + 2) % 4], to: b))
        }
    }
}

/// The marks over the picture: ink over a covered place until the copy is
/// made, a dashed outline in the accent round a place to check, a dashed
/// grey one round a place left uncovered, the shape being drawn, the eraser's
/// path, and handles round the mark selected.
private final class MarksView: UIView {
    enum Change {
        case moved(CGPoint)
        case resized(CGRect)
        case turned(CGFloat)
    }

    var marks: [ProtectionPlan.Mark] = []
    var checking: Set<Int> = []
    var isCopy = false
    var aspect: CGFloat = 1
    var selected: Int?
    var zoom: CGFloat = 1
    /// A shape being drawn.
    var live: HandShape?
    /// The eraser's path, and how far it reaches across the picture.
    var rubbing: [CGPoint] = []
    var reach: CGFloat = 0.03
    /// The selected mark as a drag would leave it.
    var pending: Change?

    var selectedMark: ProtectionPlan.Mark? { marks.first { $0.id == selected } }

    /// A handle's reach for a finger, on the screen.
    private var touch: CGFloat { 22 / max(zoom, 1) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for mark in marks {
            let shown = mark.id == selected ? adjusted(mark) : mark
            draw(shown, in: context)
        }
        if let live { ink(live, preview: true, in: context) }
        if !rubbing.isEmpty {
            context.saveGState()
            UIColor.systemBackground.withAlphaComponent(0.55).setStroke()
            let path = UIBezierPath()
            path.move(to: rubbing[0])
            for point in rubbing.dropFirst() { path.addLine(to: point) }
            if rubbing.count == 1 { path.addLine(to: rubbing[0]) }
            path.lineWidth = reach * 2 * bounds.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            context.restoreGState()
        }
        if let mark = selectedMark { handles(round: adjusted(mark), in: context) }
    }

    // MARK: Marks

    private func draw(_ mark: ProtectionPlan.Mark, in context: CGContext) {
        let path = self.path(of: mark)
        if mark.covered {
            if !isCopy || mark.id == selected && pending != nil {
                // The cover ink, as the copy will show it.
                if let shape = mark.shape { ink(shape, preview: false, in: context) } else { fill(path) }
            }
            if checking.contains(mark.id) { outline(path, color: tintColor, in: context) }
        } else {
            outline(path, color: checking.contains(mark.id) ? tintColor : .secondaryLabel, in: context)
        }
    }

    private func fill(_ path: UIBezierPath) {
        UIColor(white: 0.12, alpha: 1).setFill()
        path.fill()
    }

    /// A shape drawn in ink; while it is drawn, a little see-through.
    private func ink(_ shape: HandShape, preview: Bool, in context: CGContext) {
        context.saveGState()
        let color = UIColor(white: 0.12, alpha: preview ? 0.75 : 1)
        let points = shape.corners(aspect: aspect).map(view)
        guard let first = points.first else { return context.restoreGState() }
        if case .stroke(_, let width) = shape {
            color.setStroke()
            let path = UIBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if points.count == 1 { path.addLine(to: first) }
            path.lineWidth = width * bounds.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        } else {
            color.setFill()
            let path = polygon(points)
            path.usesEvenOddFillRule = false
            path.fill()
            if preview, case .outline = shape { outline(path, color: tintColor, in: context) }
        }
        context.restoreGState()
    }

    private func path(of mark: ProtectionPlan.Mark) -> UIBezierPath {
        if let shape = mark.shape {
            if case .stroke = shape { return UIBezierPath(rect: view(mark.rect)) }
            return polygon(shape.corners(aspect: aspect).map(view))
        }
        let place = view(mark.rect)
        return UIBezierPath(roundedRect: place, cornerRadius: min(place.height / 4, place.width / 2, 8))
    }

    private func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        return path
    }

    private func outline(_ path: UIBezierPath, color: UIColor, in context: CGContext) {
        context.saveGState()
        color.setStroke()
        path.lineWidth = 2 / max(zoom, 1)
        let dash = [5 / max(zoom, 1), 3 / max(zoom, 1)]
        path.setLineDash(dash, count: 2, phase: 0)
        path.stroke()
        context.restoreGState()
    }

    // MARK: The selected mark

    /// The selected mark as the drag under way would leave it.
    private func adjusted(_ mark: ProtectionPlan.Mark) -> ProtectionPlan.Mark {
        guard let pending else { return mark }
        var mark = mark
        switch pending {
        case .moved(let offset):
            if let shape = mark.shape {
                mark.shape = shape.moved(by: offset)
                mark.rect = mark.shape!.bounds(aspect: aspect)
            } else {
                mark.rect = mark.rect.offsetBy(dx: offset.x, dy: offset.y)
            }
        case .resized(let rect):
            if let shape = mark.shape {
                mark.shape = shape.resized(to: rect, aspect: aspect)
                mark.rect = mark.shape!.bounds(aspect: aspect)
            } else {
                mark.rect = rect
            }
        case .turned(let angle):
            mark.shape = mark.shape?.turned(by: angle)
            if let shape = mark.shape { mark.rect = shape.bounds(aspect: aspect) }
        }
        return mark
    }

    /// The corners that resize it: of the box as turned, else of the box round it.
    private func corners(of mark: ProtectionPlan.Mark) -> [CGPoint] {
        if case .box = mark.shape, let shape = mark.shape { return shape.corners(aspect: aspect).map(view) }
        let place = view(mark.rect)
        // From the bottom left round, as a box's corners go.
        return [CGPoint(x: place.minX, y: place.maxY), CGPoint(x: place.maxX, y: place.maxY),
                CGPoint(x: place.maxX, y: place.minY), CGPoint(x: place.minX, y: place.minY)]
    }

    /// The handle that turns a box: above the middle of its top edge.
    private func turnHandle(of mark: ProtectionPlan.Mark) -> CGPoint? {
        guard case .box = mark.shape else { return nil }
        let corners = corners(of: mark)
        let middle = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let top = CGPoint(x: (corners[2].x + corners[3].x) / 2, y: (corners[2].y + corners[3].y) / 2)
        let length = max(hypot(top.x - middle.x, top.y - middle.y), 0.001)
        let away = 28 / max(zoom, 1)
        return CGPoint(x: top.x + (top.x - middle.x) / length * away, y: top.y + (top.y - middle.y) / length * away)
    }

    private func handles(round mark: ProtectionPlan.Mark, in context: CGContext) {
        let corners = corners(of: mark)
        outline(polygon(corners), color: tintColor, in: context)
        let size = 12 / max(zoom, 1)
        if let turn = turnHandle(of: mark) {
            let top = CGPoint(x: (corners[2].x + corners[3].x) / 2, y: (corners[2].y + corners[3].y) / 2)
            let stem = UIBezierPath()
            stem.move(to: top)
            stem.addLine(to: turn)
            stem.lineWidth = 1.5 / max(zoom, 1)
            tintColor.setStroke()
            stem.stroke()
            knob(at: turn, size: size)
        }
        for corner in corners { knob(at: corner, size: size) }
    }

    private func knob(at point: CGPoint, size: CGFloat) {
        let circle = UIBezierPath(ovalIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        UIColor.white.setFill()
        circle.fill()
        tintColor.setStroke()
        circle.lineWidth = 2 / max(zoom, 1)
        circle.stroke()
    }

    /// What a finger at a point would drag of the selected mark: a corner,
    /// the turn handle or the mark itself; nil when it is elsewhere.
    func grab(at point: CGPoint) -> CanvasView.GrabKind? {
        guard let mark = selectedMark else { return nil }
        if let turn = turnHandle(of: mark), hypot(point.x - turn.x, point.y - turn.y) <= touch { return .turn }
        for (index, corner) in corners(of: mark).enumerated() where hypot(point.x - corner.x, point.y - corner.y) <= touch {
            return .corner(index)
        }
        let at = CGPoint(x: point.x / max(bounds.width, 1), y: 1 - point.y / max(bounds.height, 1))
        let inside = mark.shape?.contains(at, aspect: aspect, room: touch / max(bounds.width, 1) * aspect)
            ?? view(mark.rect).insetBy(dx: -touch / 2, dy: -touch / 2).contains(point)
        return inside ? .body : nil
    }

    // MARK: From the picture to the view

    private func view(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: (1 - point.y) * bounds.height)
    }

    private func view(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * bounds.width, y: (1 - rect.maxY) * bounds.height,
               width: rect.width * bounds.width, height: rect.height * bounds.height)
    }
}
