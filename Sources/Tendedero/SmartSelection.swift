import AppKit

/// Smart selection on a picture shown in a view: the still screen of the
/// capture screens, or the photo in Crop. The picture is read once, off the
/// main thread, and each part of it under the pointer, a window of it at a
/// time, as the pointer first comes to it. Until then there is nothing to
/// outline and nothing to keep to, and both screens work as they did.
@MainActor
final class SmartSelection {
    /// From Settings › General. On unless turned off.
    nonisolated static var isOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "smartSelectionOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "smartSelectionOff") }
    }

    /// Where the picture shows in the view, in its points from the bottom left.
    let frame: CGRect
    private let changed: () -> Void
    private var grid: PixelGrid?
    private var trees: [String: (tree: SmartPart, edges: (across: [CGFloat], down: [CGFloat]))] = [:]
    private var reading: Set<String> = []

    private static let queue = DispatchQueue(label: "Snapfly.smartSelection", qos: .userInteractive)

    /// - Parameter changed: called once a part of the picture has been read,
    ///   so what the pointer is over can be outlined.
    init(image: CGImage, frame: CGRect, changed: @escaping () -> Void) {
        self.frame = frame
        self.changed = changed
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        Self.queue.async { [weak self] in
            let grid = PixelGrid(image, width: width, height: height)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.grid = grid
                    self.changed()
                }
            }
        }
    }

    /// The parts under a point within `root`, smallest first, in the view's
    /// points; none until that much of the picture has been read.
    func parts(at point: CGPoint, within root: CGRect) -> [CGRect] {
        guard let tree = tree(for: root) else { return [] }
        return SmartArea.nested(in: tree, at: toGrid(point)).map(toView)
    }

    /// A point of a drag, kept to the nearest edge of a part within `root`,
    /// or of `root` itself, when one is within reach.
    func snapped(_ point: CGPoint, within root: CGRect) -> CGPoint {
        guard let edges = edges(for: root) else { return point }
        let local = toGrid(point)
        return toView(CGPoint(x: SmartArea.snap(local.x, to: edges.across), y: SmartArea.snap(local.y, to: edges.down)))
    }

    /// A rect dragged over, its empty edges cut down to an even margin.
    func trimmed(_ rect: CGRect) -> CGRect {
        guard let grid else { return rect }
        let cut = SmartArea.trimmed(toGrid(rect), in: grid)
        return cut == toGrid(rect) ? rect : toView(cut)
    }

    // MARK: Reading

    private func tree(for root: CGRect) -> SmartPart? {
        let key = Self.key(toGrid(root))
        if let known = trees[key] { return known.tree }
        read(root, key: key)
        return nil
    }

    private func edges(for root: CGRect) -> (across: [CGFloat], down: [CGFloat])? {
        let key = Self.key(toGrid(root))
        if let known = trees[key] { return known.edges }
        read(root, key: key)
        return nil
    }

    /// Reads the parts of one rect of the picture, a window on the still
    /// screen or the whole photo, once.
    private func read(_ root: CGRect, key: String) {
        guard let grid, !reading.contains(key) else { return }
        reading.insert(key)
        let rect = toGrid(root)
        Self.queue.async { [weak self] in
            let tree = SmartArea.parts(of: grid, in: rect)
            let edges = SmartArea.edges(of: tree)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trees[key] = (tree, edges)
                    self.reading.remove(key)
                    self.changed()
                }
            }
        }
    }

    private static func key(_ rect: CGRect) -> String {
        let r = rect.integral
        return "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"
    }

    // MARK: From the view to the grid and back

    /// The grid counts from the top left of the picture, the view from the
    /// bottom left of itself.
    private func toGrid(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    private func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + frame.minX, y: frame.maxY - point.y)
    }

    private func toGrid(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// What an app says is under a point, through Accessibility: the element
/// there and those holding it, a picture on a web page, a button, a list, up
/// to its window. Only in the direct edition, with Accessibility allowed;
/// the store edition can't ask other apps.
enum AppElements {
    @MainActor
    static var available: Bool { !Edition.appStore && AXIsProcessTrusted() }

    /// The frames, in AppKit screen coordinates, of the element at a point
    /// and those holding it, inside the window; none when the app doesn't
    /// answer in time. Called off the main thread: a busy app can be slow.
    /// - Parameter top: the top of the main screen, where Accessibility
    ///   counts from.
    static func frames(at point: CGPoint, of pid: pid_t, in window: CGRect, top: CGFloat) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(top - point.y), &hit) == .success,
              var element = hit else { return [] }
        var frames: [CGRect] = []
        for _ in 0..<16 {
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = string(element, kAXRoleAttribute)
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            if let frame = frame(of: element, top: top)?.intersection(window), !frame.isNull, frame.contains(point) {
                frames.append(frame)
            }
            guard let parent = child(element, kAXParentAttribute) else { break }
            element = parent
        }
        return frames
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// An element's frame, which Accessibility gives from the top left of the
    /// main screen, turned into AppKit's, from the bottom left.
    private static func frame(of element: AXUIElement, top: CGFloat) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(x: point.x, y: top - point.y - extent.height, width: extent.width, height: extent.height)
    }
}
