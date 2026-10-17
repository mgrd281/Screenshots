import AppKit

/// Keep on Top, from a photo's menu: the photo in a small window of its own
/// that floats over every app, to read from while writing in a chat. It is
/// the screenshot as it is, for the user's eyes only; nothing leaves from
/// it. Up to three float at once, a fourth putting the oldest away.
@MainActor
final class FloatingPhotos {
    static let shared = FloatingPhotos()
    static let limit = 3
    /// The longest side a photo floats at, in points, until it is resized.
    static let side: CGFloat = 360

    private var panels: [FloatingPhotoPanel] = []

    /// - Parameter frame: where the photo hangs on the line, to float near it.
    func show(_ url: URL, from frame: CGRect?) {
        if let open = panels.first(where: { $0.url == url }) {
            open.orderFrontRegardless()
            return
        }
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return }
        if panels.count >= Self.limit { panels.first?.close() }
        let size = Self.fitted(image.size, within: Self.side)
        let panel = FloatingPhotoPanel(url: url, image: image, size: size) { [weak self] closed in
            self?.panels.removeAll { $0 === closed }
        }
        panel.setFrame(CGRect(origin: origin(for: size, from: frame), size: size), display: false)
        panels.append(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// A photo's size with its longer side at the given length, and never
    /// larger than it is.
    nonisolated static func fitted(_ size: CGSize, within side: CGFloat) -> CGSize {
        let scale = min(1, side / max(size.width, size.height))
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Below the photo on the line, or a little down and along from the last
    /// one floating, and always on the screen.
    private func origin(for size: CGSize, from frame: CGRect?) -> CGPoint {
        let screen = frame.flatMap { photo in NSScreen.screens.first { $0.frame.intersects(photo) } } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var point: CGPoint
        if let last = panels.last {
            point = CGPoint(x: last.frame.minX + 24, y: last.frame.maxY - 24 - size.height)
        } else if let frame {
            point = CGPoint(x: frame.midX - size.width / 2, y: frame.minY - 16 - size.height)
        } else {
            point = CGPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
        }
        point.x = min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8)
        point.y = min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8)
        return point
    }
}

/// A utility panel over every app that never takes the keyboard, so the
/// chat keeps it. Dragged anywhere on the photo, it moves; at its edges, it
/// resizes, keeping the photo's shape.
private final class FloatingPhotoPanel: NSPanel {
    let url: URL
    private let onClose: (FloatingPhotoPanel) -> Void

    init(url: URL, image: NSImage, size: CGSize, onClose: @escaping (FloatingPhotoPanel) -> Void) {
        self.url = url
        self.onClose = onClose
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = url.deletingPathExtension().lastPathComponent
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentAspectRatio = size
        minSize = FloatingPhotos.fitted(size, within: 120)
        let view = MovableImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel(title)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        onClose(self)
    }
}

/// The photo, which moves its window when dragged.
private final class MovableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
}
