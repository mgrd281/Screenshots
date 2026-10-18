import AppKit
import UniformTypeIdentifiers

/// The Workspace's folder in the Finder: the system's own folder with
/// Snapfly's icon on its front, drawn at every size the Finder uses, so it
/// stays sharp small and large. It is set with the public icon call, which
/// keeps the icon inside the folder itself, so the folder is an ordinary
/// folder in every other way. If macOS refuses, the folder keeps the usual
/// look and works the same.
@MainActor
enum FolderIcon {
    /// The sizes of an icon file: each in points, at 1× and 2×.
    private static let sizes: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
    ]

    /// The icon, or nil without the app's own icon to put on the folder.
    static func image() -> NSImage? {
        guard let mark = NSApp.applicationIconImage else { return nil }
        let base = NSWorkspace.shared.icon(for: .folder)
        let icon = NSImage(size: NSSize(width: 512, height: 512))
        for (points, scale) in sizes {
            let pixels = points * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            rep.size = NSSize(width: points, height: points)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            draw(base: base, mark: mark, size: CGFloat(points))
            NSGraphicsContext.restoreGraphicsState()
            icon.addRepresentation(rep)
        }
        return icon
    }

    /// Where the mark sits on the folder, as shares of its side: the middle
    /// of the folder's front, a little larger when small, so it still reads.
    static func badge(points: CGFloat) -> CGRect {
        let share: CGFloat = points <= 32 ? 0.62 : 0.5
        let side = points * share
        return CGRect(x: (points - side) / 2, y: points * 0.40 - side / 2, width: side, height: side)
    }

    private static func draw(base: NSImage, mark: NSImage, size: CGFloat) {
        let whole = CGRect(x: 0, y: 0, width: size, height: size)
        base.draw(in: whole, from: .zero, operation: .sourceOver, fraction: 1)
        let rect = badge(points: size)
        NSGraphicsContext.saveGraphicsState()
        // A soft shadow lifts it off the folder; at the smallest sizes it
        // would only blur it.
        if size > 32 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
            shadow.shadowBlurRadius = size * 0.03
            shadow.set()
        }
        mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Puts the icon on a folder. Returns whether macOS took it.
    @discardableResult
    static func apply(to folder: URL) -> Bool {
        guard let icon = image() else { return false }
        return NSWorkspace.shared.setIcon(icon, forFile: folder.path, options: [])
    }
}
