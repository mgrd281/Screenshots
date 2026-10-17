import AppKit

/// Snapfly's mark in the menu bar and in Settings: a photo hanging from a
/// clip on a line, a little crooked, drawn as a template so macOS colours
/// it. Filled, it says copied images are hung too. A small dot at its
/// corner says something new hangs that the line has not shown yet.
enum LineIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(filled: Bool, dot: Bool = false, description: String) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            draw(filled: filled)
            if dot { drawDot() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    /// Drawn on an 18 point square with the origin at the top left.
    private static func draw(filled: Bool) {
        NSColor.black.set()

        // The line, sagging a little between the edges.
        let rope = NSBezierPath()
        rope.move(to: NSPoint(x: 0.6, y: 3.6))
        rope.curve(to: NSPoint(x: 17.4, y: 3.6),
                   controlPoint1: NSPoint(x: 6.2, y: 5.33),
                   controlPoint2: NSPoint(x: 11.8, y: 5.33))
        rope.lineWidth = 1.25
        rope.lineCapStyle = .round
        rope.stroke()

        // The clip and the photo turn together, as a photo hangs.
        NSGraphicsContext.saveGraphicsState()
        let turn = NSAffineTransform()
        turn.translateX(by: 9, yBy: 6)
        turn.rotate(byDegrees: -7)
        turn.translateX(by: -9, yBy: -6)
        turn.concat()

        NSBezierPath(roundedRect: NSRect(x: 8.3, y: 3.7, width: 1.4, height: 3.4), xRadius: 0.5, yRadius: 0.5).fill()

        let photo = NSBezierPath(roundedRect: NSRect(x: 4, y: 6.6, width: 10, height: 8.6), xRadius: 1.8, yRadius: 1.8)
        photo.lineWidth = 1.45
        if filled { photo.fill() }
        photo.stroke()

        // A sun over a hill, so it reads as a picture. Filled, they are cut
        // out of the photo.
        if filled { NSGraphicsContext.current?.compositingOperation = .destinationOut }
        NSBezierPath(ovalIn: NSRect(x: 10.3, y: 8.5, width: 1.8, height: 1.8)).fill()
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: 6.2, y: 13.1))
        hill.line(to: NSPoint(x: 8.3, y: 10.9))
        hill.line(to: NSPoint(x: 10.9, y: 13.3))
        hill.lineWidth = 1.2
        hill.lineCapStyle = .round
        hill.lineJoinStyle = .round
        hill.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    /// A dot at the bottom trailing corner, cut free of the photo by a thin
    /// gap so it reads apart from it.
    private static func drawDot() {
        let dot = NSRect(x: 13.4, y: 12.4, width: 4.6, height: 4.6)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSBezierPath(ovalIn: dot).fill()
    }
}
