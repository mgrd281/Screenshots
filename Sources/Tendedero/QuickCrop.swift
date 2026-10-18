import AppKit
import SwiftUI

/// Crop…, from a photo's menu or an ⌥-click on it: the photo large over the
/// dimmed screen, to drag over the part to keep. Letting go keeps that part,
/// as the crop of the photo's drawing, so what leaves the line is cut to it
/// and the file stays as it is. Return keeps the whole photo again; Escape,
/// a right-click or a click beside the photo cancels. With smart selection
/// on, the part of the photo under the pointer is outlined for a click to
/// keep, the scroll wheel chooses a bigger or smaller one, a drag keeps to
/// the edges in the photo, and the empty space round it is cut away to an
/// even margin.
@MainActor
final class QuickCrop {
    static let shared = QuickCrop()

    private var panel: QuickCropPanel?

    /// How the photo was left: cut to a part, whole again, or as it was.
    enum Ending: Equatable {
        case keep(CGRect)
        case whole
        case cancel
    }

    /// Calls back once the part to keep is chosen, saying whether the photo
    /// is cropped now; not when cancelled or when nothing changed.
    func crop(_ url: URL, done: @escaping (_ cropped: Bool) -> Void) {
        close()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = Cover.upright(source) else {
            Notice.show(L("Could not open the screenshot."))
            return
        }
        let saved = Drawings.saved(url)
        // What is drawn on it shows too, so the part is chosen from what goes.
        let shown = saved.marks.isEmpty ? image : Drawing.render(image, Drawing(marks: saved.marks)) ?? image
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let pixels = CGSize(width: image.width, height: image.height)
        let view = QuickCropView(screen: screen, image: shown, pixels: pixels, kept: saved.crop) { [weak self] ending in
            self?.close()
            var drawing = Drawings.saved(url)
            let before = drawing.crop
            switch ending {
            case .cancel:
                return
            case .whole:
                drawing.crop = nil
            case let .keep(crop):
                // Dragged over all of it, it keeps the whole photo.
                drawing.crop = Drawing.pixels(of: crop, width: image.width, height: image.height) == nil ? nil : crop
            }
            guard drawing.crop != before else { return }
            Drawings.set(drawing, for: url)
            done(drawing.crop != nil)
        }
        view.solidBadges = PhotoBadge.reduced
        let panel = QuickCropPanel(screen: screen, view: view)
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        view.updateCursor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func close() {
        guard let panel else { return }
        self.panel = nil
        NSCursor.arrow.set()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

/// Where the photo shows and how a drag over it becomes the part to keep.
enum QuickCropLayout {
    /// How far the pointer moves before a click becomes a drag, and the
    /// smallest part that can be kept, in points.
    static let threshold: CGFloat = 4

    /// Room kept free above the bottom of the screen for the hint.
    static let hintRoom: CGFloat = 80

    /// Centred in the room, as large as fits in 80% of it, and never larger
    /// than itself at the screen's scale, as Hide Part opens.
    static func frame(for pixels: CGSize, scale: CGFloat, in room: CGRect) -> CGRect {
        let scale = max(scale, 1)
        let natural = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        guard natural.width > 0, natural.height > 0, room.width > 0, room.height > 0 else { return .zero }
        let fit = min(1, room.width * 0.8 / natural.width, room.height * 0.8 / natural.height)
        let size = CGSize(width: max(1, (natural.width * fit).rounded()), height: max(1, (natural.height * fit).rounded()))
        return CGRect(x: (room.midX - size.width / 2).rounded(), y: (room.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    /// The part of the photo dragged over, from 0 to 1 from its bottom left,
    /// as a drawing keeps it; nil when too little of it is on the photo to
    /// be meant.
    static func crop(_ area: CGRect, in photo: CGRect) -> CGRect? {
        let kept = area.intersection(photo)
        guard !kept.isNull, kept.width >= threshold, kept.height >= threshold,
              photo.width > 0, photo.height > 0 else { return nil }
        return CGRect(x: (kept.minX - photo.minX) / photo.width, y: (kept.minY - photo.minY) / photo.height,
                      width: kept.width / photo.width, height: kept.height / photo.height)
    }

    /// A part kept before, where it shows on the photo.
    static func area(of crop: CGRect, in photo: CGRect) -> CGRect {
        CGRect(x: photo.minX + crop.minX * photo.width, y: photo.minY + crop.minY * photo.height,
               width: crop.width * photo.width, height: crop.height * photo.height)
    }
}

/// The dimmed screen with the photo on it, over everything else.
private final class QuickCropPanel: NSPanel {
    init(screen: NSScreen, view: QuickCropView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the dimming, the photo, the part being dragged over, outlined or
/// kept before, and the pixels that will go.
private final class QuickCropView: NSView {
    private let image: CGImage
    private let pixels: CGSize
    private let photo: CGRect
    private let kept: CGRect?
    private let done: (QuickCrop.Ending) -> Void

    /// Whether the size label is solid, with Reduce Transparency on.
    var solidBadges = false

    private var dragStart: CGPoint?
    private var dragging = false
    private var area: CGRect?
    private var hint: NSView?
    private var finished = false
    private var smart: SmartSelection?
    /// The parts of the photo under the pointer, from the smallest out, and
    /// the one outlined.
    private var parts: [CGRect] = []
    private var level = 0
    private var scrolled: CGFloat = 0

    init(screen: NSScreen, image: CGImage, pixels: CGSize, kept: CGRect?, done: @escaping (QuickCrop.Ending) -> Void) {
        self.image = image
        self.pixels = pixels
        self.kept = kept
        self.done = done
        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        var room = visible
        room.origin.y += QuickCropLayout.hintRoom
        room.size.height -= QuickCropLayout.hintRoom
        photo = QuickCropLayout.frame(for: pixels, scale: screen.backingScaleFactor, in: room)
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        if SmartSelection.isOn {
            smart = SmartSelection(image: image, frame: photo.integral) { [weak self] in self?.updateParts() }
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Crop"))
        showHint(SmartSelection.isOn
                    ? L("Click what is outlined or drag over the part to keep. Scroll for a bigger or smaller part. Return keeps the whole photo, Escape cancels.")
                    : L("Drag over the part to keep. Return keeps the whole photo, Escape cancels."),
                 above: visible.minY)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func showHint(_ text: String, above bottom: CGFloat) {
        let host = NSHostingView(rootView: CaptureHint(text: text))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Above the Dock, where there is one on this screen.
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottom - 16),
            host.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
        ])
        hint = host
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The crosshair over the photo and while dragging, the arrow beside it,
    /// where a click cancels.
    func updateCursor() {
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        (dragging || photo.contains(point) ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    override func mouseMoved(with event: NSEvent) {
        updateCursor()
        updateParts()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = toEdges(convert(event.locationInWindow, from: nil), event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = toEdges(convert(event.locationInWindow, from: nil), event)
        guard dragging || max(abs(point.x - start.x), abs(point.y - start.y)) >= QuickCropLayout.threshold else { return }
        dragging = true
        parts = []
        // A drag begun beside the photo keeps to its edge.
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(photo)
        area = rect.isNull ? nil : rect
        hint?.isHidden = true
        updateCursor()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        let point = convert(event.locationInWindow, from: nil)
        if dragging {
            dragging = false
            // The empty space round what was dragged over goes, to an even
            // margin; ⌘ keeps it as dragged.
            if let smart, let dragged = area, !event.modifierFlags.contains(.command) {
                area = smart.trimmed(dragged)
            }
            if let area, let crop = QuickCropLayout.crop(area, in: photo) {
                finish(.keep(crop))
            } else {
                // Too small to be meant: wait for another try.
                area = nil
                needsDisplay = true
                updateCursor()
                updateParts()
            }
        } else if !photo.contains(point) {
            finish(.cancel)
        } else if parts.indices.contains(level), let crop = QuickCropLayout.crop(parts[level], in: photo) {
            // A click keeps the part outlined.
            finish(.keep(crop))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard !dragging, parts.count > 1 else { return }
        // Away from you, or fingers up, is bigger, whichever way the Mac scrolls.
        scrolled += event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        let notch: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        guard abs(scrolled) >= notch else { return }
        step(scrolled > 0 ? 1 : -1)
        scrolled = 0
    }

    private func step(_ by: Int) {
        let next = max(0, min(parts.count - 1, level + by))
        guard next != level else { return }
        level = next
        needsDisplay = true
    }

    /// A point of a drag, kept to the nearest edge in the photo; ⌘ lets it go
    /// anywhere.
    private func toEdges(_ point: CGPoint, _ event: NSEvent) -> CGPoint {
        guard let smart, !event.modifierFlags.contains(.command) else { return point }
        return smart.snapped(point, within: smart.frame)
    }

    /// The parts of the photo under the pointer; the whole photo is Return's.
    private func updateParts() {
        guard let smart, !dragging, dragStart == nil, !finished else { return }
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let found = photo.contains(point)
            ? smart.parts(at: point, within: smart.frame).filter { !SmartArea.alike($0, smart.frame) }
            : []
        guard found != parts else { return }
        // The same smallest part keeps the size chosen; another starts small.
        level = found.first == parts.first ? min(level, max(found.count - 1, 0)) : 0
        parts = found
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { finish(.cancel) }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            finish(.cancel)
        case 36, 76: // Return, Enter
            finish(.whole)
        case 126 where parts.count > 1: // Up arrow: a bigger part
            step(1)
        case 125 where parts.count > 1: // Down arrow: a smaller one
            step(-1)
        default:
            NSSound.beep()
        }
    }

    private func finish(_ ending: QuickCrop.Ending) {
        guard !finished else { return }
        finished = true
        done(ending)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The screen dims, so the photo is the one thing to look at.
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill(using: .copy)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14,
                          color: NSColor.black.withAlphaComponent(0.18).cgColor)
        context.interpolationQuality = .high
        context.draw(image, in: photo)
        context.restoreGState()

        if dragging {
            // Outside the part dimmed, as Draw on Photo shows it while cropping.
            dim(outside: area, alpha: 0.45)
            guard let area else { return }
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let edge = NSBezierPath(rect: area.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
            if let crop = QuickCropLayout.crop(area, in: photo) { drawSize(of: crop, under: area) }
        } else if parts.indices.contains(level) {
            // The part a click keeps, outlined in the accent colour.
            let rect = parts[level]
            dim(outside: rect, alpha: 0.3)
            NSColor.controlAccentColor.setStroke()
            let edge = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
            edge.lineWidth = 2
            edge.stroke()
            if let crop = QuickCropLayout.crop(rect, in: photo) { drawSize(of: crop, under: rect) }
        } else if let kept {
            // The part kept before, as Draw on Photo shows it at rest.
            let rect = QuickCropLayout.area(of: kept, in: photo)
            dim(outside: rect, alpha: 0.6)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let edge = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
        }
    }

    /// The photo dimmed but for the part, or all of it without one.
    private func dim(outside part: CGRect?, alpha: CGFloat) {
        let shade = NSBezierPath(rect: photo)
        if let part { shade.append(NSBezierPath(rect: part)) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(alpha).setFill()
        shade.fill()
    }

    /// The pixels the part keeps, as Draw on Photo says them, in the capture
    /// screens' capsule.
    private func drawSize(of crop: CGRect, under area: CGRect) {
        let kept = Drawing.pixels(of: crop, width: Int(pixels.width), height: Int(pixels.height))?.size ?? pixels
        SizeCapsule.draw("\(Int(kept.width)) × \(Int(kept.height))", under: area, in: bounds, solid: solidBadges)
    }
}
