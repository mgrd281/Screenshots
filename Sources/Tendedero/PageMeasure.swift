import AppKit
import ApplicationServices

/// How far the content of a window moved between two moments, as the app
/// itself tells it through Accessibility, the way it tells VoiceOver where
/// its things are: a few things on the page, like lines of text and
/// pictures, are noted with where they are, and found again after a
/// scroll. A browser extension knows this from inside the page; this works
/// in any app that tells VoiceOver where its things are, Safari, Chrome and
/// Firefox among them. `PageWalk` checks what it tells against the
/// pictures, and goes by the pictures alone when it tells nothing.
///
/// Chrome tells where a thing half out of view is as if it were cut there,
/// so there only things wholly in view count, at both moments; Safari and
/// Firefox tell where things are wherever they are, and Safari also where
/// the whole page is, which tells its move even across a white stretch
/// taller than the window. The Mac App Store edition is sandboxed, and the
/// sandbox does not let it ask.
@MainActor
final class PageMeasure {
    /// A thing noted: where it was, how tall, and what it says, to tell it
    /// from a row a list has reused for something else.
    private struct Noted {
        let element: AXUIElement
        let frame: CGRect
        let says: String
    }

    private let app: AXUIElement
    /// Whether the app tells where things out of view are, as Safari and
    /// Firefox do; Chrome cuts them at the window's edge.
    private let whole: Bool
    /// Whether the area that holds the page moves with it, as Safari's does:
    /// then it tells the move too.
    private let pageMoves: Bool
    /// That area, once found, and where it was when last noted.
    private var page: (element: AXUIElement, y: Double)?
    /// Where to look for things, from the top left of the main screen: a
    /// few columns down the part that scrolls, most of them low in the
    /// window, so they are still in view after a scroll down.
    private let points: [CGPoint]
    /// The window, from the top left of the main screen.
    private let frame: CGRect
    private var noted: [Noted] = []
    /// Those that stayed put when the page last moved, like a sticky
    /// header: they tell nothing of a move.
    private var stuck: [AXUIElement] = []
    /// What the app had asked of its own accessibility before, given back
    /// once the page is taken.
    private var manual: CFTypeRef?
    private var wokeIt = false

    /// Nil without the Accessibility permission, and in the Mac App Store
    /// edition.
    /// - Parameters:
    ///   - frame: the window, from the top left of the main screen.
    ///   - over: where the page is scrolled.
    ///   - band: the columns that scroll, as samples of the window's width,
    ///     when only part of it does.
    init?(pid: pid_t, bundle: String?, frame: CGRect, over: CGPoint, band: Range<Int>?) {
        #if APP_STORE
        return nil
        #else
        guard AXIsProcessTrusted() else { return nil }
        app = AXUIElementCreateApplication(pid)
        pageMoves = bundle.map(Self.webKit.contains) ?? false
        whole = pageMoves || (bundle.map(Self.gecko.contains) ?? false)
        AXUIElementSetMessagingTimeout(app, 0.3)
        self.frame = frame
        points = Self.points(in: frame, over: over, band: band)
        // Chrome, Edge, Brave and Firefox build what they tell VoiceOver
        // once someone asks the app what it is; apps made with Electron,
        // once asked to by name, given back as it was at the end.
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &role)
        var before: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, Self.manualAttribute, &before) == .success { manual = before }
        wokeIt = AXUIElementSetAttributeValue(app, Self.manualAttribute, kCFBooleanTrue) == .success
        #endif
    }

    private static let manualAttribute = "AXManualAccessibility" as CFString

    /// Browsers made with WebKit, as Safari is, and with Firefox's engine.
    private static let webKit: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS",
        "com.duckduckgo.macos.browser",
    ]
    private static let gecko: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "net.waterfox.waterfox", "app.zen-browser.zen", "org.mozilla.floorp", "io.gitlab.librewolf-community",
    ]

    /// Gives the app back its accessibility as it was.
    func finish() {
        guard wokeIt else { return }
        _ = AXUIElementSetAttributeValue(app, Self.manualAttribute, manual ?? (kCFBooleanFalse as CFTypeRef))
        wokeIt = false
    }

    /// Notes where the things on the page are now: those noted before that
    /// are still wholly in view and moved with the page, where they are now,
    /// and more found down the window while there are few.
    func mark() {
        let started = Date()
        noted = noted.compactMap { old in
            guard !stuck.contains(where: { CFEqual($0, old.element) }),
                  let now = read(old.element), now.says == old.says, counts(now.frame) else { return nil }
            return now
        }
        for point in points where noted.count < 10 {
            // A slow app is not waited for long.
            if Date().timeIntervalSince(started) > 0.4 { break }
            guard let element = thing(at: point), !noted.contains(where: { CFEqual($0.element, element) }),
                  let found = read(element), inView(found.frame) else { continue }
            noted.append(found)
            if pageMoves, page == nil { page = area(holding: element).map { ($0, 0) } }
        }
        if let held = page?.element {
            page = Self.top(of: held).map { (held, $0) }
        }
    }

    /// How far the page moved since `mark`, in points, down when positive,
    /// as the things noted then tell it (`PageWalk.told(by:)`): only those
    /// still wholly in view, as tall as they were and saying what they did.
    /// Nil when they do not agree, or are gone.
    func measured() -> Double? {
        let started = Date()
        var deltas: [(element: AXUIElement, delta: Double)] = []
        for old in noted {
            if Date().timeIntervalSince(started) > 0.4 { break }
            guard let now = read(old.element), now.says == old.says, counts(now.frame),
                  abs(now.frame.height - old.frame.height) <= 0.5, abs(now.frame.minX - old.frame.minX) <= 1
            else { continue }
            deltas.append((old.element, Double(old.frame.minY - now.frame.minY)))
        }
        // Safari's page tells its own move, twice over, as surely as two
        // things on it.
        if let page, let now = Self.top(of: page.element) {
            deltas += [(page.element, page.y - now), (page.element, page.y - now)]
        }
        let told = PageWalk<CGImage>.told(by: deltas.map(\.delta))
        if let told, told != 0 {
            stuck += deltas.filter { abs($0.delta) < 0.75 }.map(\.element)
            if let held = page?.element, stuck.contains(where: { CFEqual($0, held) }) { page = nil }
        }
        return told
    }

    /// Wholly in the window, below its top and above its foot, and not
    /// most of it.
    private func inView(_ rect: CGRect) -> Bool {
        rect.height >= 2 && rect.height <= frame.height * 0.6 && rect.minY > frame.minY + 2
            && rect.maxY < frame.maxY - 2
    }

    /// Whether where a thing is tells a move now: wholly in view, or, where
    /// the app tells where things out of view are, within two windows.
    private func counts(_ rect: CGRect) -> Bool {
        guard whole else { return inView(rect) }
        return rect.height >= 2 && rect.height <= frame.height * 0.6 && rect.minY > frame.minY - frame.height * 2
            && rect.maxY < frame.maxY + frame.height * 2
    }

    /// The area holding the whole page around a thing on it, as Safari
    /// tells it: it moves with the page.
    private func area(holding element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<40 {
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = parent as! AXUIElement
            AXUIElementSetMessagingTimeout(current, 0.2)
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXWebArea" { return current }
        }
        return nil
    }

    /// How far down the screen a thing's top is, in points.
    private static func top(of element: AXUIElement) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, let point = Self.value(value, as: .cgPoint, CGPoint.zero), point.y.isFinite else { return nil }
        return Double(point.y)
    }

    /// The thing on the page at a point, when it is part of the page and
    /// not the window, its toolbar or the area that holds the page.
    private func thing(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.2)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String, !Self.holders.contains(role) else { return nil }
        return hit
    }

    /// Roles of what holds a page rather than shows it: they stay where
    /// they are as the page scrolls.
    private static let holders: Set<String> = [
        kAXApplicationRole, kAXWindowRole, kAXScrollAreaRole, kAXScrollBarRole, kAXSplitGroupRole,
        kAXSplitterRole, kAXToolbarRole, kAXTabGroupRole, kAXMenuBarRole, kAXSheetRole, kAXDrawerRole,
        "AXWebArea", kAXUnknownRole,
    ]

    /// Where a thing is and what it says, in one question to the app.
    private func read(_ element: AXUIElement) -> Noted? {
        let names = [kAXPositionAttribute, kAXSizeAttribute, kAXValueAttribute, kAXTitleAttribute,
                     kAXDescriptionAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0),
                                                     &values) == .success,
              let answers = (values as NSArray?) as? [AnyObject], answers.count == 5,
              let position = Self.value(answers[0], as: .cgPoint, CGPoint.zero),
              let size = Self.value(answers[1], as: .cgSize, CGSize.zero),
              position.y.isFinite, size.height.isFinite else { return nil }
        let says = answers[2...].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
        return Noted(element: element, frame: CGRect(origin: position, size: size), says: String(says.prefix(40)))
    }

    /// A point or a size the app answered with, unless it answered that it
    /// has none.
    private static func value<T>(_ answer: AnyObject, as type: AXValueType, _ empty: T) -> T? {
        guard CFGetTypeID(answer) == AXValueGetTypeID(), AXValueGetType(answer as! AXValue) == type else { return nil }
        var result = empty
        return AXValueGetValue(answer as! AXValue, type, &result) ? result : nil
    }

    /// Three columns down the part that scrolls, most rows low in the
    /// window, below its toolbar.
    nonisolated static func points(in frame: CGRect, over: CGPoint, band: Range<Int>?) -> [CGPoint] {
        let width = frame.width / CGFloat(PageStitch.samples)
        var xs = [over.x]
        if let band, band.count > 2 {
            xs += [0.25, 0.75].map { frame.minX + (CGFloat(band.lowerBound) + CGFloat(band.count) * $0) * width }
        } else {
            xs += [0.3, 0.7].map { frame.minX + frame.width * $0 }
        }
        return [0.3, 0.45, 0.55, 0.65, 0.72, 0.79, 0.86, 0.92].flatMap { part in
            xs.map { CGPoint(x: $0, y: frame.minY + frame.height * CGFloat(part)) }
        }
    }
}
