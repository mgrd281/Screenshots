import AppKit
import SwiftUI

/// What the canvas shows of the two pictures.
enum VectorShow: String, CaseIterable {
    case compare, vector, original
}

/// The picture and its vector one over the other, split at a divider to drag,
/// and zoomable, to see how close the edges are. The vector is drawn at the
/// zoom it is seen at, so it stays sharp; the photo's pixels are not blurred.
final class VectorCanvasView: NSView {
    /// Around the picture when it fits the canvas.
    private static let margin: CGFloat = 24
    /// A small picture may be shown up to this many times its size.
    private static let largestFit: CGFloat = 4
    /// How far the picture can be zoomed, in pixels on the screen for each of its own.
    private static let largestScale: CGFloat = 64

    var original: CGImage? {
        didSet { needsDisplay = true }
    }
    var vector: VectorImage? {
        didSet {
            paths = (vector?.layers ?? []).map { layer in
                ShownLayer(path: layer.fillsPicture ? nil : VectorRaster.path(of: layer),
                           color: CGColor(srgbRed: CGFloat(layer.color.red) / 255, green: CGFloat(layer.color.green) / 255,
                                          blue: CGFloat(layer.color.blue) / 255, alpha: 1))
            }
            needsDisplay = true
        }
    }
    /// Which result `vector` is, so the same one is not made into paths again.
    var resultID = -1
    var show = VectorShow.compare {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Where the divider is, from 0 at the left of the picture to 1 at its right.
    var divider: CGFloat = 0.5 {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// How much larger than fitting the window the picture is shown.
    private(set) var zoom: CGFloat = 1
    /// How far the picture's centre lies from the canvas's, when it is zoomed.
    private var offset = CGPoint.zero

    /// Tells the window the zoom, as a percent of the picture's own size, and the divider.
    var onChange: ((_ percent: Int, _ divider: CGFloat) -> Void)?

    private struct ShownLayer {
        var path: CGPath?
        var color: CGColor
    }
    private var paths: [ShownLayer] = []

    private enum Drag {
        case none, divider, pan
    }
    private var drag = Drag.none
    private var lastPoint = CGPoint.zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(L("Compare the photo with its SVG"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Where the picture is

    private var pictureSize: CGSize? {
        if let original { return CGSize(width: original.width, height: original.height) }
        if let vector { return CGSize(width: vector.width, height: vector.height) }
        return nil
    }

    /// The scale that fits the picture in the canvas.
    private var fitScale: CGFloat {
        guard let size = pictureSize, size.width > 0, size.height > 0 else { return 1 }
        let room = CGSize(width: max(1, bounds.width - 2 * Self.margin), height: max(1, bounds.height - 2 * Self.margin))
        return max(0.001, min(Self.largestFit, room.width / size.width, room.height / size.height))
    }

    private var scale: CGFloat { fitScale * zoom }

    private var pictureRect: CGRect {
        guard let size = pictureSize else { return .zero }
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: bounds.midX + offset.x - width / 2, y: bounds.midY + offset.y - height / 2,
                      width: width, height: height)
    }

    private var dividerX: CGFloat {
        let rect = pictureRect
        return rect.minX + rect.width * divider
    }

    /// Keeps some of the picture on the canvas.
    private func clampOffset() {
        let rect = pictureRect
        let keep: CGFloat = 48
        let spareX = max(0, (rect.width + bounds.width) / 2 - keep)
        let spareY = max(0, (rect.height + bounds.height) / 2 - keep)
        offset.x = min(max(offset.x, -spareX), spareX)
        offset.y = min(max(offset.y, -spareY), spareY)
        if zoom <= 1.0001 { offset = .zero }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampOffset()
        reportChange()
    }

    private func reportChange() {
        let percent = Int((scale * 100).rounded())
        onChange?(percent, divider)
    }

    // MARK: Zoom

    /// Zooms by a factor, keeping the point under `point` where it is.
    func zoomBy(_ factor: CGFloat, at point: CGPoint? = nil) {
        let anchor = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let before = scale
        let largest = max(1, Self.largestScale / fitScale)
        zoom = min(max(zoom * factor, 1), largest)
        let ratio = scale / before
        let centre = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        offset = CGPoint(x: anchor.x - (anchor.x - centre.x) * ratio - bounds.midX,
                         y: anchor.y - (anchor.y - centre.y) * ratio - bounds.midY)
        clampOffset()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        reportChange()
    }

    /// The whole picture in the canvas again.
    func fit() {
        zoom = 1
        offset = .zero
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        reportChange()
    }

    private func moveDivider(to x: CGFloat) {
        let rect = pictureRect
        guard rect.width > 0 else { return }
        divider = min(max((x - rect.minX) / rect.width, 0), 1)
        reportChange()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext, pictureSize != nil else { return }
        let rect = pictureRect
        guard rect.width > 0, rect.height > 0 else { return }

        // The picture floats over the canvas, as in Hide Part.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.restoreGState()
        if hasTransparency { drawChecks(in: rect, context) }

        let split = rect.minX + rect.width * divider
        switch show {
        case .original:
            drawOriginal(in: rect, clip: rect, context)
        case .vector:
            drawVector(in: rect, clip: rect, context)
        case .compare:
            drawOriginal(in: rect, clip: CGRect(x: rect.minX, y: rect.minY, width: split - rect.minX, height: rect.height), context)
            drawVector(in: rect, clip: CGRect(x: split, y: rect.minY, width: rect.maxX - split, height: rect.height), context)
            drawDivider(at: split, in: rect, context)
            drawLabels(in: rect, split: split)
        }
    }

    /// A picture with clear parts shows the canvas through them, as chequers.
    private var hasTransparency: Bool {
        guard let original else { return false }
        switch original.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private func drawChecks(in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        let square: CGFloat = 8
        context.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
        context.fill(rect)
        context.setFillColor(NSColor(white: 0.78, alpha: 1).cgColor)
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : square)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: square, height: square))
                x += 2 * square
            }
            y += square
            row += 1
        }
        context.restoreGState()
    }

    private func drawOriginal(in rect: CGRect, clip: CGRect, _ context: CGContext) {
        guard let original, clip.width > 0 else { return }
        context.saveGState()
        context.clip(to: clip)
        // Pixels are shown as pixels when zoomed in, so the edges can be judged.
        context.interpolationQuality = scale > 1 ? .none : .high
        context.draw(original, in: rect)
        context.restoreGState()
    }

    private func drawVector(in rect: CGRect, clip: CGRect, _ context: CGContext) {
        guard let vector, clip.width > 0 else { return }
        context.saveGState()
        context.clip(to: clip)
        context.setShouldAntialias(true)
        // The vector counts from its top left; the canvas, from its bottom left.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / CGFloat(vector.width), y: -rect.height / CGFloat(vector.height))
        for layer in paths {
            context.setFillColor(layer.color)
            if let path = layer.path {
                context.addPath(path)
                context.fillPath(using: .evenOdd)
            } else {
                context.fill(CGRect(x: 0, y: 0, width: vector.width, height: vector.height))
            }
        }
        context.restoreGState()
    }

    private func drawDivider(at x: CGFloat, in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: x - 1, y: rect.minY, width: 2, height: rect.height))
        // The handle stays in view when the picture is taller than the canvas.
        let middle = min(max(rect.midY, bounds.minY + 30), bounds.maxY - 30)
        let handle = CGRect(x: x - 15, y: middle - 15, width: 30, height: 30)
        context.fillEllipse(in: handle)
        context.restoreGState()
        if let glyph = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) {
            let size = glyph.size
            NSColor.black.set()
            glyph.draw(in: CGRect(x: handle.midX - size.width / 2, y: handle.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

    /// Which side is which, at the top of the picture's corners.
    private func drawLabels(in rect: CGRect, split: CGFloat) {
        let top = min(rect.maxY, bounds.maxY) - 10
        let left = max(rect.minX, bounds.minX) + 10
        let right = min(rect.maxX, bounds.maxX) - 10
        if split - left > 90 { drawLabel(L("Original"), x: left, top: top, leading: true) }
        if right - split > 70 { drawLabel(L("SVG"), x: right, top: top, leading: false) }
    }

    private func drawLabel(_ text: String, x: CGFloat, top: CGFloat, leading: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pill = CGRect(x: leading ? x : x - size.width - 14, y: top - size.height - 4, width: size.width + 14, height: size.height + 4)
        let fill = PhotoBadge.reduced ? NSColor(white: 0.12, alpha: 1) : NSColor.black.withAlphaComponent(0.55)
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: CGPoint(x: pill.minX + 7, y: pill.minY + 2))
    }

    // MARK: The pointer

    override func resetCursorRects() {
        if show == .compare, pictureSize != nil {
            let rect = pictureRect.intersection(bounds)
            addCursorRect(CGRect(x: dividerX - 8, y: rect.minY, width: 16, height: rect.height), cursor: .resizeLeftRight)
        }
        if zoom > 1.0001 { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point
        if event.clickCount == 2 {
            // Double-click to look closely at a spot, and again to see it all.
            if zoom > 1.0001 { fit() } else { zoomBy(4, at: point) }
            return
        }
        let onDivider = show == .compare && abs(point.x - dividerX) < 14
        if onDivider || (show == .compare && zoom <= 1.0001) {
            drag = .divider
            moveDivider(to: point.x)
        } else if zoom > 1.0001 {
            drag = .pan
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .divider:
            moveDivider(to: point.x)
        case .pan:
            offset.x += point.x - lastPoint.x
            offset.y += point.y - lastPoint.y
            clampOffset()
            needsDisplay = true
        case .none:
            break
        }
        lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        if drag == .pan { NSCursor.pop() }
        drag = .none
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !event.modifierFlags.intersection([.command, .option]).isEmpty {
            zoomBy(exp(event.scrollingDeltaY * 0.01), at: point)
        } else if zoom > 1.0001 {
            offset.x += event.scrollingDeltaX
            offset.y -= event.scrollingDeltaY
            clampOffset()
            needsDisplay = true
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        zoomBy(1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+", "=": zoomBy(1.25)
        case "-": zoomBy(0.8)
        case "0": fit()
        default:
            switch event.keyCode {
            case 123: nudge(by: event.modifierFlags.contains(.shift) ? -0.01 : -0.05)
            case 124: nudge(by: event.modifierFlags.contains(.shift) ? 0.01 : 0.05)
            default: super.keyDown(with: event)
            }
        }
    }

    private func nudge(by step: CGFloat) {
        guard show == .compare else { return }
        divider = min(max(divider + step, 0), 1)
        reportChange()
    }

    // MARK: VoiceOver

    override func accessibilityValue() -> Any? {
        "\(Int((divider * 100).rounded()))%"
    }

    override func accessibilityPerformIncrement() -> Bool {
        nudge(by: 0.1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        nudge(by: -0.1)
        return true
    }
}

/// The canvas in the window.
struct VectorCanvas: NSViewRepresentable {
    @ObservedObject var model: VectorEditorModel

    func makeNSView(context: Context) -> VectorCanvasView {
        let view = VectorCanvasView()
        view.onChange = { [weak model] percent, divider in
            // Out of the gesture, so SwiftUI is not changed while it draws.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let model else { return }
                    if model.scalePercent != percent { model.scalePercent = percent }
                    if abs(model.divider - divider) > 0.0001 { model.divider = divider }
                }
            }
        }
        model.canvas = view
        return view
    }

    func updateNSView(_ view: VectorCanvasView, context: Context) {
        if view.original !== model.original { view.original = model.original }
        if view.resultID != model.resultID {
            view.resultID = model.resultID
            view.vector = model.result
        }
        if view.show != model.show { view.show = model.show }
        if abs(view.divider - model.divider) > 0.0001 { view.divider = model.divider }
    }
}
