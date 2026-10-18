import AppKit
import SwiftUI

/// Crop…, from a photo's menu or an ⌥-click on it: the photo large over the
/// dimmed screen, to drag over the part to keep. Letting go keeps that part,
/// as the crop of the photo's drawing, so what leaves the line is cut to it
/// and the file stays as it is. Return keeps the whole photo again; Escape,
/// a right-click or a click beside the photo cancels.
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

/// Draws the dimming, the photo, the part being dragged over or the one kept
/// before, and the pixels that will go.
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
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Crop"))
        showHint(L("Drag over the part to keep. Return keeps the whole photo, Escape cancels."),
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
    override func mouseMoved(with event: NSEvent) { updateCursor() }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard dragging || max(abs(point.x - start.x), abs(point.y - start.y)) >= QuickCropLayout.threshold else { return }
        dragging = true
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
            if let area, let crop = QuickCropLayout.crop(area, in: photo) {
                finish(.keep(crop))
            } else {
                // Too small to be meant: wait for another try.
                area = nil
                needsDisplay = true
                updateCursor()
            }
        } else if !photo.contains(point) {
            finish(.cancel)
        }
    }

    override func rightMouseDown(with event: NSEvent) { finish(.cancel) }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            finish(.cancel)
        case 36, 76: // Return, Enter
            finish(.whole)
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
