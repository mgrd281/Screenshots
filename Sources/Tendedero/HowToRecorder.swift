import AppKit
import NaturalLanguage
import ScreenCaptureKit
import SwiftUI

/// Record a Guide, from the menu bar: every click from then on is a step,
/// with a screenshot of the screen it was on, taken as the button goes down,
/// and a sentence saying what was clicked, from what the app tells
/// Accessibility. Nothing typed is recorded. A capsule above the Dock counts
/// the steps, and a click on it finishes; the guide then opens to be read
/// through, written again where needed, and sent or saved. Snapfly's own
/// windows stay out of the screenshots, and clicks on them are not steps.
@MainActor
final class HowToRecorder {
    static let shared = HowToRecorder()

    private(set) var isRecording = false
    /// At most this many steps in one guide.
    static let mostSteps = 100

    private var guide = HowToGuide()
    private var monitor: Any?
    private var content: SCShareableContent?
    private var badge: CaptureBadge?
    /// Screenshots still being taken or written.
    private var inFlight = 0
    private var finishing = false
    /// The last click, so a second one there at once makes it a double-click.
    private var lastClick: (point: CGPoint, time: Date, step: UUID)?
    /// What each step's click went on, once its app has said, to say it
    /// again for a double-click.
    private var elements: [UUID: HowToWording.Element] = [:]
    /// What was clicked is asked for off the main thread, in order: a busy
    /// app can be slow to answer.
    private let asking = DispatchQueue(label: "Snapfly.HowTo.asking", qos: .userInitiated)

    func start() {
        guard !isRecording, !Recording.shared.isRecording, Capture.shared.hasPermission() else { return }
        isRecording = true
        finishing = false
        guide = HowToGuide()
        lastClick = nil
        elements = [:]
        inFlight = 0
        Task { @MainActor in
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                log.error("Could not start a guide: \(error.localizedDescription, privacy: .public)")
                isRecording = false
                Notice.show(L("Could not record the steps."))
                return
            }
            guard isRecording else { return }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                // Global events carry the point on the screen.
                let point = event.locationInWindow
                let right = event.type == .rightMouseDown
                let count = event.clickCount
                MainActor.assumeIsolated { HowToRecorder.shared.clicked(at: point, right: right, count: count) }
            }
            let badge = CaptureBadge(kind: .steps, label: L("Finish Guide")) { HowToRecorder.shared.finish() }
            badge.show(on: LinePanel.screenUnderPointer())
            self.badge = badge
        }
    }

    /// The steps so far open in the guide's window, once every screenshot
    /// is written. Without a step, nothing is kept.
    func finish() {
        guard isRecording, !finishing else { return }
        finishing = true
        stopWatching()
        guard inFlight == 0 else { return }
        wrapUp()
    }

    /// Lets the steps so far go.
    func cancel() {
        guard isRecording else { return }
        stopWatching()
        HowToStore.delete(guide.id)
        guide = HowToGuide()
        isRecording = false
        finishing = false
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        badge?.orderOut(nil)
        badge = nil
    }

    private func wrapUp() {
        isRecording = false
        finishing = false
        content = nil
        elements = [:]
        let guide = guide
        self.guide = HowToGuide()
        guard !guide.steps.isEmpty else {
            HowToStore.delete(guide.id)
            Notice.show(L("No steps were recorded. Click through what you want to show, then finish."))
            return
        }
        do {
            try HowToStore.save(guide)
        } catch {
            log.error("Could not keep a guide: \(error.localizedDescription, privacy: .public)")
            Notice.show(L("Could not keep the guide."))
            return
        }
        HowToStore.prune(sparing: guide.id)
        HowToEditor.shared.open(guide)
    }

    // MARK: A click

    private func clicked(at point: CGPoint, right: Bool, count: Int) {
        guard isRecording, !finishing else { return }
        // A second click there at once: the step was a double-click.
        if count >= 2, !right, let last = lastClick,
           Date().timeIntervalSince(last.time) <= NSEvent.doubleClickInterval + 0.2,
           hypot(point.x - last.point.x, point.y - last.point.y) <= 8,
           let index = guide.steps.firstIndex(where: { $0.id == last.step }) {
            guide.steps[index].click = .double
            guide.steps[index].text = HowToWording.sentence(.double, on: elements[last.step],
                                                            isPrivate: HowToElement.isPrivate)
            lastClick = nil
            return
        }
        guard guide.steps.count < Self.mostSteps,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        var step = HowToStep(text: right ? L("Right-click here.") : L("Click here."),
                             click: right ? .right : .single, file: "",
                             width: Int(frame.width * scale), height: Int(frame.height * scale),
                             point: CGPoint(x: (point.x - frame.minX) / frame.width,
                                            y: (frame.maxY - point.y) / frame.height))
        step.file = step.id.uuidString + ".png"
        // In click order, whatever finishes first.
        guide.steps.append(step)
        lastClick = (point, Date(), step.id)
        badge?.model.steps = guide.steps.count
        HowToFlash.show(at: point)

        inFlight += 2
        let id = step.id
        let asks = HowToElement.available
        let top = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        asking.async {
            let found = asks ? HowToElement.at(point, top: top) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HowToRecorder.shared.named(id, found, on: frame) }
            }
        }
        let file = HowToStore.file(step.file, of: guide.id)
        Task { @MainActor in
            let image = await shoot(screen)
            DispatchQueue.global(qos: .utility).async {
                let written = image.map { Capture.write($0, to: file) } ?? false
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HowToRecorder.shared.shot(id, written: written) }
                }
            }
        }
    }

    /// What was clicked, once its app has said: the sentence and the box
    /// around it.
    private func named(_ id: UUID, _ found: HowToElement.Found?, on frame: CGRect) {
        if let index = guide.steps.firstIndex(where: { $0.id == id }) {
            elements[id] = found?.element
            // A double-click noticed before the name came back says so too.
            guide.steps[index].text = HowToWording.sentence(guide.steps[index].click, on: found?.element,
                                                            isPrivate: HowToElement.isPrivate)
            guide.steps[index].app = found?.app
            if let box = found?.frame {
                guide.steps[index].target = CGRect(x: (box.minX - frame.minX) / frame.width,
                                                   y: (frame.maxY - box.maxY) / frame.height,
                                                   width: box.width / frame.width, height: box.height / frame.height)
            }
        }
        settled()
    }

    private func shot(_ id: UUID, written: Bool) {
        if !written {
            log.error("Could not take a guide's step")
            guide.steps.removeAll { $0.id == id }
            badge?.model.steps = guide.steps.count
        }
        settled()
    }

    private func settled() {
        inFlight -= 1
        if inFlight == 0, finishing { wrapUp() }
    }

    /// The screen as it is now, without Snapfly's own windows.
    private func shoot(_ screen: NSScreen) async -> CGImage? {
        for attempt in 0..<2 {
            do {
                if content == nil || attempt > 0 {
                    content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                }
                guard let content, let id = screen.displayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.showsCursor = false
                config.captureResolution = .best
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                log.error("Could not take a guide's screenshot: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}

/// What was clicked, as the app tells Accessibility: its kind, its name and
/// where it is. Only in the direct edition, with Accessibility allowed; the
/// store edition's steps say "Click here." and mark the click with a ring.
/// The value of a field, what was typed into it, is never read.
enum HowToElement {
    struct Found: Sendable {
        var element: HowToWording.Element
        /// In AppKit screen coordinates.
        var frame: CGRect?
        var app: String?
    }

    @MainActor
    static var available: Bool { !Edition.appStore && AXIsProcessTrusted() }

    /// Whether a name could be private: a detail found by its shape, one of
    /// the owner's own words, or what reads like a person's name.
    static func isPrivate(_ name: String) -> Bool {
        if !Finder.patternRanges(in: name, Set(PrivateDetail.allCases)).isEmpty { return true }
        if !Finder.ruleRanges(in: name, OwnRules.all).isEmpty { return true }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = name
        var person = false
        tagger.enumerateTags(in: name.startIndex..<name.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, _ in
            if tag == .personalName { person = true }
            return !person
        }
        return person
    }

    /// The element at a point, or what holds it when that is what a click
    /// there is for: the button around a word, the link around a picture.
    /// Called off the main thread.
    /// - Parameter top: the top of the main screen, where Accessibility
    ///   counts from.
    static func at(_ point: CGPoint, top: CGFloat) -> Found? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(top - point.y), &hit) == .success,
              let hit else { return nil }
        var element = hit
        var chosen = hit
        for _ in 0..<4 {
            AXUIElementSetMessagingTimeout(element, 0.25)
            let role = string(element, kAXRoleAttribute)
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            if HowToWording.kind(role: role, subrole: string(element, kAXSubroleAttribute)) != .content {
                chosen = element
                break
            }
            guard let parent = child(element, kAXParentAttribute) else { break }
            element = parent
        }
        let role = string(chosen, kAXRoleAttribute)
        let subrole = string(chosen, kAXSubroleAttribute)
        let kind = HowToWording.kind(role: role, subrole: subrole)
        var pid: pid_t = 0
        AXUIElementGetPid(chosen, &pid)
        let app = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.localizedName : nil
        return Found(element: .init(role: role, subrole: subrole, name: name(of: chosen, kind: kind, clicked: hit)),
                     frame: frame(of: chosen, top: top), app: app)
    }

    /// A control's title or description, a field's label or the hint shown
    /// in it, or the words of a text clicked; never what was typed.
    private static func name(of element: AXUIElement, kind: HowToWording.Kind, clicked: AXUIElement) -> String? {
        let said = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { string(element, $0) }
        if let first = said.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return first
        }
        if kind == .field {
            if let label = child(element, kAXTitleUIElementAttribute),
               let words = string(label, kAXValueAttribute) ?? string(label, kAXTitleAttribute) {
                return words
            }
            return string(element, "AXPlaceholderValue")
        }
        // The words in or under it.
        if string(clicked, kAXRoleAttribute) == kAXStaticTextRole, let words = string(clicked, kAXValueAttribute) {
            return words
        }
        if string(element, kAXRoleAttribute) == kAXStaticTextRole { return string(element, kAXValueAttribute) }
        for item in children(of: element).prefix(6) where string(item, kAXRoleAttribute) == kAXStaticTextRole {
            if let words = string(item, kAXValueAttribute) { return words }
        }
        return nil
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

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AnyObject] else { return [] }
        return list.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
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

/// A ring that spreads from a click and fades as the step is taken, so it is
/// clear each click counted. With Reduce Motion it only fades. It is
/// Snapfly's own window, so it is never in a screenshot.
@MainActor
enum HowToFlash {
    static let size: CGFloat = 64

    static func show(at point: CGPoint) {
        let panel = NSPanel(contentRect: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FlashRing(reduced: Motion.reduced))
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { panel.orderOut(nil) }
    }
}

private struct FlashRing: View {
    let reduced: Bool
    @State private var spread = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor, lineWidth: 3)
            .frame(width: 40, height: 40)
            .scaleEffect(spread || reduced ? 1 : 0.45)
            .opacity(spread ? 0 : 1)
            .frame(width: HowToFlash.size, height: HowToFlash.size)
            .onAppear {
                withAnimation(.easeOut(duration: reduced ? 0.3 : 0.45)) { spread = true }
            }
            .accessibilityHidden(true)
    }
}
