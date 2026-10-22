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
    /// A tap beside the picture, not on it.
    var outside: () -> Void = {}
    /// The divider between Before and After moved, from 0 to 1 from the
    /// leading edge.
    var split: (CGFloat) -> Void = { _ in }
    /// A PDF's page swiped up or down while it is shown whole: whether there
    /// is a page that way (1 the next, -1 the one before), and going there.
    var canPage: (Int) -> Bool = { _ in false }
    var page: (Int) -> Void = { _ in }
}

/// A place to show close up, each time its count changes.
struct Reveal: Equatable {
    /// From 0 to 1 from the bottom left of the original picture.
    let rect: CGRect
    let count: Int
}

/// The picture being protected, to zoom with two fingers or a double tap,
/// with its places marked: ink over a covered place, a dashed outline round
/// one to check or left, and handles round the one selected. It fills the
/// screen; the picture is fitted into the room the floating controls leave,
/// with a soft shadow under it, and once zoomed it scrolls out from under
/// them on every side.
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
    /// What the floating controls cover on each side, safe areas included.
    var chrome = UIEdgeInsets.zero
    /// Whether changes are shown moving: the room growing or shrinking, the
    /// first covers growing in, the cleaned page wiping in; not with Reduce
    /// Motion.
    var animated = true
    var reveal: Reveal?
    /// A scanned page as it was before it was cleaned: shown on the leading
    /// side of the divider while comparing, without the covers, which show
    /// on the cleaned side, and under the wipe; nil for a screenshot.
    var before: UIImage? = nil
    /// Where the divider stands while Before and After are compared, from 0
    /// to 1 from the leading edge; nil while they are not.
    var split: CGFloat? = nil
    /// Each time it grows, the cleaned page wipes in over the page before.
    var wipes = 0
    /// The page before shown whole, until its wipe begins.
    var holdsBefore = false
    /// Places to look at again, from 0 to 1 from the bottom left, outlined
    /// in orange over the page; never in the copy.
    var issues: [CGRect] = []
    /// How far two fingers or a double tap zoom in: 6 times, 8 on a PDF's page.
    var maxZoom: CGFloat = 6
    /// Where a PDF's page came in from as it opens: from below (1), the
    /// next page, or from above (-1); 0 for any other picture.
    var arrival: CGFloat = 0
    let actions: CanvasActions

    func makeUIView(context: Context) -> CanvasView {
        CanvasView()
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.actions = actions
        view.animates = animated
        if view.maximumZoomScale != maxZoom { view.maximumZoomScale = maxZoom }
        if arrival != 0, !context.coordinator.arrived {
            context.coordinator.arrived = true
            view.arrive(from: arrival)
        }
        view.show(image, marks: marks, checking: checking, isCopy: isCopy, tool: tool, selected: selected,
                  markerWidth: markerWidth, eraserReach: eraserReach)
        view.compare(before: before, split: split, issues: issues, holding: holdsBefore)
        view.place(chrome: chrome, animated: animated)
        if let reveal, reveal != context.coordinator.revealed {
            context.coordinator.revealed = reveal
            view.reveal(reveal.rect)
        }
        if wipes != context.coordinator.wipes {
            context.coordinator.wipes = wipes
            view.wipe(animated: animated)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// The place last shown close up, so it is shown once.
        var revealed: Reveal?
        /// The wipes shown.
        var wipes = 0
        /// The page came in once.
        var arrived = false
    }
}

final class CanvasView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var actions = CanvasActions()
    private let content = UIView()
    private let picture = UIImageView()
    private let overlay = MarksView()
    /// A scanned page before it was cleaned, over the picture and its
    /// covers where its mask lets it show: on the leading side of the
    /// divider, or all of it until the wipe has passed.
    private let before = UIImageView()
    private let beforeMask = CALayer()
    private let scanMarks = ScanMarksView()
    private var split: CGFloat?
    private var wiping = false
    private var holding = false
    /// A wipe asked for before the page was laid out, run once it is.
    private var pendingWipe: Bool?
    private var imageSize = CGSize.zero
    /// The room the picture was last fitted to, so it is fitted again only
    /// when the room changes.
    private var fitted = CGSize.zero
    /// What the floating controls cover on each side.
    private var chrome = UIEdgeInsets.zero
    private var tool = EditTool.select
    private var markerWidth: CGFloat = HandShape.widths[1]
    private var eraserReach: CGFloat = 0.03
    /// Whether the first covers grow in, rather than show at once.
    var animates = true

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
    private lazy var besideTap = UITapGestureRecognizer(target: self, action: #selector(tappedBeside(_:)))
    private lazy var swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
    private lazy var swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
    private lazy var swipes = SwipeGate(canvas: self)
    /// Where the page comes in from once it is on screen; 0 once it came.
    private var arriving: CGFloat = 0

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
        content.addSubview(before)
        content.addSubview(scanMarks)
        before.contentMode = .scaleToFill
        before.layer.cornerRadius = 12
        before.layer.cornerCurve = .continuous
        before.clipsToBounds = true
        before.isHidden = true
        before.isUserInteractionEnabled = false
        beforeMask.backgroundColor = UIColor.black.cgColor
        before.layer.mask = beforeMask
        scanMarks.isOpaque = false
        scanMarks.backgroundColor = .clear
        scanMarks.isUserInteractionEnabled = false
        scanMarks.contentMode = .redraw
        picture.contentMode = .scaleToFill
        picture.layer.cornerRadius = 12
        picture.layer.cornerCurve = .continuous
        picture.clipsToBounds = true
        // The page stands on the ground with a soft shadow under it.
        content.layer.shadowColor = UIColor.black.cgColor
        content.layer.shadowOpacity = 0.08
        content.layer.shadowRadius = 12
        content.layer.shadowOffset = CGSize(width: 0, height: 4)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.contentMode = .redraw
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        hold.minimumPressDuration = 0.45
        edit.maximumNumberOfTouches = 1
        edit.delegate = self
        for gesture in [tap, doubleTap, hold, edit] as [UIGestureRecognizer] { content.addGestureRecognizer(gesture) }
        // Beside the picture only: a tap on it is the picture's.
        besideTap.require(toFail: tap)
        addGestureRecognizer(besideTap)
        // A PDF's next page is a swipe up away, the one before a swipe down.
        swipeUp.direction = .up
        swipeDown.direction = .down
        for swipe in [swipeUp, swipeDown] {
            swipe.delegate = swipes
            addGestureRecognizer(swipe)
        }
        isAccessibilityElement = true
        accessibilityIdentifier = "protect-canvas"
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
        // The first covers found grow in over their places, line by line.
        let arriving = !isCopy && !overlay.marks.contains(where: \.covered) && marks.contains(where: \.covered)
        overlay.marks = marks
        if arriving, animates { overlay.arrive() }
        overlay.checking = checking
        overlay.isCopy = isCopy
        overlay.selected = selected
        overlay.zoom = zoomScale
        overlay.setNeedsDisplay()
        // While drawing, one finger draws and two move the picture.
        panGestureRecognizer.minimumNumberOfTouches = tool.draws ? 2 : 1
        hold.isEnabled = tool == .select
    }

    /// The room the floating controls leave. A new room fits the picture
    /// to it, growing or shrinking, unless it is zoomed in, when it only
    /// scrolls to the new edges and is fitted once it is all in sight again.
    func place(chrome: UIEdgeInsets, animated: Bool) {
        guard chrome != self.chrome else { return }
        self.chrome = chrome
        guard animated, fitted != .zero, window != nil else { return setNeedsLayout() }
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, arriving != 0 { comeIn() }
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let room = bounds.inset(by: chrome).size
        if room != fitted, fitted == .zero || zoomScale <= minimumZoomScale + 0.01 {
            fit(in: room)
        } else {
            center()
        }
    }

    /// The whole picture, as large as the room allows, in its middle.
    private func fit(in room: CGSize) {
        guard room.width > 0, room.height > 0 else { return }
        fitted = room
        zoomScale = 1
        let scale = min(room.width / imageSize.width, room.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        content.bounds = CGRect(origin: .zero, size: size)
        content.center = CGPoint(x: size.width / 2, y: size.height / 2)
        picture.frame = content.bounds
        overlay.frame = content.bounds
        before.frame = content.bounds
        scanMarks.frame = content.bounds
        masked()
        if let animated = pendingWipe {
            pendingWipe = nil
            wipe(animated: animated)
        }
        content.layer.shadowPath = UIBezierPath(roundedRect: content.bounds, cornerRadius: 12).cgPath
        contentSize = size
        center()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
        // Handles keep their size on the screen.
        overlay.zoom = zoomScale
        overlay.setNeedsDisplay()
        scanMarks.zoom = zoomScale
        scanMarks.setNeedsDisplay()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Back to all of it after the room changed: fitted to the room now.
        if scale <= minimumZoomScale + 0.01, bounds.inset(by: chrome).size != fitted { setNeedsLayout() }
    }

    /// The picture in the middle of the room while it is smaller than it;
    /// larger, it scrolls out from under the floating controls.
    private func center() {
        let room = bounds.inset(by: chrome)
        let x = max(0, (room.width - contentSize.width) / 2), y = max(0, (room.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: chrome.top + y, left: chrome.left + x, bottom: chrome.bottom + y,
                                  right: chrome.right + x)
        if contentInset != insets { contentInset = insets }
    }

    /// A place close up, with room round it, in the middle of the screen.
    func reveal(_ rect: CGRect) {
        let size = content.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let place = CGRect(x: rect.minX * size.width, y: (1 - rect.maxY) * size.height,
                           width: rect.width * size.width, height: rect.height * size.height)
        let room = bounds.inset(by: chrome)
        let scale = min(3, maximumZoomScale, room.width / max(place.width * 1.4, 1), room.height / max(place.height * 4, 1))
        let shown = max(scale, minimumZoomScale)
        let seen = CGSize(width: bounds.width / shown, height: bounds.height / shown)
        zoom(to: CGRect(x: place.midX - seen.width / 2, y: place.midY - seen.height / 2, width: seen.width,
                        height: seen.height), animated: true)
    }

    // MARK: A PDF's pages

    /// Whether a swipe may turn to another page: only with Select in hand,
    /// the page shown whole, not comparing and not on the mark selected.
    fileprivate func swipeMayBegin(_ gesture: UIGestureRecognizer) -> Bool {
        let step = gesture === swipeUp ? 1 : -1
        return !tool.draws && split == nil && zoomScale <= minimumZoomScale + 0.01
            && overlay.grab(at: gesture.location(in: content)) == nil && actions.canPage(step)
    }

    /// The page leaves the way it was swiped, a little and fading, and the
    /// next one is opened; with Reduce Motion it only fades.
    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        let step = gesture.direction == .up ? 1 : -1
        let away = CGAffineTransform(translationX: 0, y: -CGFloat(step) * bounds.height * 0.3)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            if self.animates { self.transform = away }
            self.alpha = 0
        } completion: { _ in
            // The pages changed meanwhile: the page comes back rather than staying gone.
            guard self.actions.canPage(step) else {
                UIView.animate(withDuration: 0.2) {
                    self.transform = .identity
                    self.alpha = 1
                }
                return
            }
            self.actions.page(step)
        }
    }

    /// The page comes in from below or above once it is on screen.
    func arrive(from side: CGFloat) {
        arriving = side
        alpha = 0
        if window != nil { comeIn() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, arriving != 0 { comeIn() }
    }

    /// Once the page has its size, so it comes from as far as it should.
    private func comeIn() {
        guard arriving != 0, bounds.height > 0 else { return }
        let side = arriving
        arriving = 0
        alpha = 0
        if animates { transform = CGAffineTransform(translationX: 0, y: side * bounds.height * 0.3) }
        UIView.animate(withDuration: animates ? 0.42 : 0.2, delay: 0, usingSpringWithDamping: animates ? 0.86 : 1,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    /// With VoiceOver, three fingers up or down turn to the next page or the one before.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let step: Int
        switch direction {
        case .down, .next: step = 1
        case .up, .previous: step = -1
        default: return false
        }
        guard actions.canPage(step) else { return false }
        actions.page(step)
        return true
    }

    // MARK: Before and after

    /// A scanned page's page before cleaning, the divider while comparing
    /// and the places to look at again. While comparing, one finger moves
    /// the divider and two move the page, and VoiceOver adjusts it in
    /// tenths.
    func compare(before image: UIImage?, split: CGFloat?, issues: [CGRect], holding: Bool = false) {
        if before.image !== image { before.image = image }
        self.holding = holding
        let comparing = split != nil && image != nil
        self.split = comparing ? split : nil
        scanMarks.split = self.split
        scanMarks.issues = issues
        scanMarks.zoom = zoomScale
        scanMarks.setNeedsDisplay()
        masked()
        if comparing { panGestureRecognizer.minimumNumberOfTouches = 2 }
        hold.isEnabled = hold.isEnabled && !comparing
        if let split = self.split {
            accessibilityLabel = L("Comparison of Before and After")
            accessibilityValue = Double(split).formatted(.percent.precision(.fractionLength(0)))
            accessibilityHint = nil
            accessibilityTraits = .adjustable
        } else {
            accessibilityLabel = L("Covered screenshot")
            accessibilityValue = nil
            accessibilityHint = L("Details lists every place, to cover or uncover each one.")
            accessibilityTraits = []
        }
    }

    override func accessibilityIncrement() {
        guard let split else { return }
        actions.split(min(1, ((split + 0.1) * 10).rounded() / 10))
    }

    override func accessibilityDecrement() {
        guard let split else { return }
        actions.split(max(0, ((split - 0.1) * 10).rounded() / 10))
    }

    /// The cleaned page sweeping in over the page before it, from the
    /// leading edge, in 0.5 s, easing out; with Reduce Motion it fades in.
    func wipe(animated: Bool) {
        guard before.image != nil else { return }
        guard before.bounds.width > 0 else {
            pendingWipe = animated
            return
        }
        wiping = true
        before.isHidden = false
        let bounds = before.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beforeMask.frame = bounds
        before.alpha = 1
        CATransaction.commit()
        let finish = { [weak self] in
            self?.wiping = false
            self?.masked()
        }
        guard animated else {
            UIView.animate(withDuration: 0.3, animations: { self.before.alpha = 0 }, completion: { _ in
                self.before.alpha = 1
                finish()
            })
            return
        }
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock(finish)
        beforeMask.frame = CGRect(x: rightToLeft ? 0 : bounds.width, y: 0, width: 0, height: bounds.height)
        CATransaction.commit()
    }

    /// Before shown on the leading side of the divider while comparing, and
    /// not at all otherwise; left alone while the wipe passes.
    private func masked() {
        guard !wiping else { return }
        let bounds = before.bounds
        if holding, before.image != nil {
            before.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            beforeMask.frame = bounds
            CATransaction.commit()
            return
        }
        guard let split, before.image != nil else {
            before.isHidden = true
            return
        }
        before.isHidden = false
        let width = bounds.width * split
        let leading = effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beforeMask.frame = CGRect(x: leading, y: 0, width: width, height: bounds.height)
        CATransaction.commit()
    }

    private func moveSplit(to point: CGPoint) {
        let across = min(max(point.x / max(content.bounds.width, 1), 0), 1)
        actions.split(effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - across : across)
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
            if tool.draws || split != nil { return true }
            grab = overlay.grab(at: gesture.location(in: content))
            return grab != nil
        }
        if gesture === panGestureRecognizer, !tool.draws, split == nil, overlay.grab(at: gesture.location(in: content)) != nil {
            return false
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        // While comparing, a tap moves the divider there.
        if split != nil { return moveSplit(to: gesture.location(in: content)) }
        let point = normalized(gesture.location(in: content))
        switch tool {
        case .select: actions.tap(point)
        case .eraser: actions.erase([point])
        case .marker: actions.draw(.stroke([point], width: markerWidth))
        case .box, .lasso: break
        }
    }

    @objc private func tappedBeside(_ gesture: UITapGestureRecognizer) {
        guard !content.frame.contains(gesture.location(in: self)) else { return }
        actions.outside()
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
        if split != nil {
            if gesture.state == .began || gesture.state == .changed { moveSplit(to: point) }
            return
        }
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

    // MARK: Covers growing in

    /// When the first covers arrived, and each one's turn, top to bottom.
    private var arrival: CFTimeInterval?
    private var turns: [Int: Int] = [:]
    private var ticker: CADisplayLink?
    /// One cover after another (`stagger.cover`), each grown in this long.
    private static let stagger = 0.045
    private static let growth = 0.32

    /// The covers grow in over their places in reading order, as if laid
    /// on one by one; at once with Reduce Motion.
    func arrive() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // From 0 to 1 from the bottom: the highest first, then along the line.
        let ordered = marks.filter(\.covered).sorted {
            abs($0.rect.maxY - $1.rect.maxY) > 0.01 ? $0.rect.maxY > $1.rect.maxY : $0.rect.minX < $1.rect.minX
        }
        turns = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, min($0.offset, 24)) })
        arrival = CACurrentMediaTime()
        ticker?.invalidate()
        let ticker = CADisplayLink(target: self, selector: #selector(tick))
        ticker.add(to: .main, forMode: .common)
        self.ticker = ticker
    }

    @objc private func tick() {
        setNeedsDisplay()
        guard let arrival else { return }
        let last = Double(turns.values.max() ?? 0)
        if CACurrentMediaTime() - arrival > last * Self.stagger + Self.growth {
            self.arrival = nil
            ticker?.invalidate()
            ticker = nil
        }
    }

    /// How much of a cover shows, from 0 to 1, eased out.
    private func grown(_ mark: ProtectionPlan.Mark) -> CGFloat {
        guard let arrival, let turn = turns[mark.id] else { return 1 }
        let t = (CACurrentMediaTime() - arrival - Double(turn) * Self.stagger) / Self.growth
        let clamped = min(max(t, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 3))
    }

    /// A handle's reach for a finger, on the screen.
    private var touch: CGFloat { 22 / max(zoom, 1) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // What Settings leaves visible shows once covered, or selected.
        for mark in marks where mark.covered || mark.origin != .spared || mark.id == selected {
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
                // The cover ink, as the copy will show it, growing in along
                // the reading direction while it arrives.
                let shown = grown(mark)
                if shown > 0 {
                    context.saveGState()
                    if shown < 1 {
                        let whole = path.bounds.insetBy(dx: -bounds.width * 0.02, dy: -bounds.width * 0.02)
                        let width = whole.width * shown
                        let leading = effectiveUserInterfaceLayoutDirection == .rightToLeft ? whole.maxX - width : whole.minX
                        context.clip(to: CGRect(x: leading, y: whole.minY, width: width, height: whole.height))
                    }
                    if let shape = mark.shape { ink(shape, preview: false, in: context) } else { fill(path) }
                    context.restoreGState()
                }
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
        let points = shape.corners(aspect: aspect).map { view($0) }
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
            return polygon(shape.corners(aspect: aspect).map { view($0) })
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
        if case .box = mark.shape, let shape = mark.shape { return shape.corners(aspect: aspect).map { view($0) } }
        let place = view(mark.rect)
        // From the bottom left round, as a box's corners go.
        return [CGPoint(x: place.minX, y: place.maxY), CGPoint(x: place.maxX, y: place.maxY),
                CGPoint(x: place.maxX, y: place.minY), CGPoint(x: place.minX, y: place.minY)]
    }

    /// The handle that turns a box: above the middle of its top edge.
    private func turnHandle(of mark: ProtectionPlan.Mark) -> CGPoint? {
        guard case .box = mark.shape else { return nil }
        let edge = corners(of: mark)
        let middle = CGPoint(x: edge.map(\.x).reduce(0, +) / 4, y: edge.map(\.y).reduce(0, +) / 4)
        let top = CGPoint(x: (edge[2].x + edge[3].x) / 2, y: (edge[2].y + edge[3].y) / 2)
        let length = max(hypot(top.x - middle.x, top.y - middle.y), 0.001)
        let away = 28 / max(zoom, 1)
        return CGPoint(x: top.x + (top.x - middle.x) / length * away, y: top.y + (top.y - middle.y) / length * away)
    }

    private func handles(round mark: ProtectionPlan.Mark, in context: CGContext) {
        let edge = corners(of: mark)
        outline(polygon(edge), color: tintColor, in: context)
        let size = 12 / max(zoom, 1)
        if let turn = turnHandle(of: mark) {
            let top = CGPoint(x: (edge[2].x + edge[3].x) / 2, y: (edge[2].y + edge[3].y) / 2)
            let stem = UIBezierPath()
            stem.move(to: top)
            stem.addLine(to: turn)
            stem.lineWidth = 1.5 / max(zoom, 1)
            tintColor.setStroke()
            stem.stroke()
            knob(at: turn, size: size)
        }
        for corner in edge { knob(at: corner, size: size) }
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

/// Over a scanned page: the divider between Before and After while they
/// are compared, a white line with a round handle that keeps its size on
/// the screen, and the places to look at again, outlined in orange.
private final class ScanMarksView: UIView {
    /// From 0 to 1 from the leading edge; nil while not comparing.
    var split: CGFloat?
    /// From 0 to 1 from the bottom left.
    var issues: [CGRect] = []
    var zoom: CGFloat = 1

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let scale = 1 / max(zoom, 1)
        for issue in issues {
            let place = CGRect(x: issue.minX * bounds.width, y: (1 - issue.maxY) * bounds.height,
                               width: issue.width * bounds.width, height: issue.height * bounds.height)
                .insetBy(dx: -4 * scale, dy: -4 * scale)
            let path = UIBezierPath(roundedRect: place, cornerRadius: 6 * scale)
            UIColor.systemOrange.withAlphaComponent(0.12).setFill()
            path.fill()
            UIColor.systemOrange.setStroke()
            path.lineWidth = 2 * scale
            path.setLineDash([5 * scale, 3 * scale], count: 2, phase: 0)
            path.stroke()
        }
        guard let split else { return }
        let across = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - split : split
        let x = across * bounds.width
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1 * scale), blur: 4 * scale,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(x: x - 1 * scale, y: 0, width: 2 * scale, height: bounds.height)).fill()
        let size = 32 * scale
        let handle = CGRect(x: x - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        UIBezierPath(ovalIn: handle).fill()
        context.restoreGState()
        // Two small arrows on the handle, pointing apart.
        UIColor.darkGray.setFill()
        for direction: CGFloat in [-1, 1] {
            let tip = CGPoint(x: x + direction * 9 * scale, y: bounds.midY)
            let arrow = UIBezierPath()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - direction * 5 * scale, y: tip.y - 5 * scale))
            arrow.addLine(to: CGPoint(x: tip.x - direction * 5 * scale, y: tip.y + 5 * scale))
            arrow.close()
            arrow.fill()
        }
    }
}

/// Lets a swipe over a PDF's page turn to another page while the picture's
/// own pan goes on as before.
@MainActor
private final class SwipeGate: NSObject, UIGestureRecognizerDelegate {
    weak var canvas: CanvasView?

    init(canvas: CanvasView) {
        self.canvas = canvas
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        canvas?.swipeMayBegin(gesture) ?? false
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
