import AppKit
import SwiftUI

/// Bridges each photo to AppKit's drag and drop, so it can be dragged into
/// any app as a real file. Each destination means one thing:
///
/// - An app gets a copy, and the photo leaves the line, as anything sent does
///   (unless Take photos down once sent is off, or it is pinned).
/// - A folder or the Desktop keeps the file, and the photo leaves the line.
/// - The Trash discards it.
/// - Nowhere that accepts it: the photo flies back to the line.
///
/// Click copies, press and hold opens Markup, the corner cross discards, or
/// unpins a pinned photo, and the paper plane in the opposite corner sends.
/// ⌘-click picks several, which copy together.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: GrabView) {
        let id = item.id
        let line = line
        let isImage = item.isImage
        let isRecording = item.isRecording
        let pinned = item.pinned
        view.url = item.url
        view.dragImage = item.thumb
        // With Hide private details on, a drag hands over the covered copy.
        view.outgoingURL = { PrivateDetails.shareable(item.url) }
        view.onClick = { line.copy(id) }
        view.onPick = { line.pick(id) }
        view.onSentByDrag = { line.sentByDrag(id) }
        view.onSend = { line.paste(id) }
        view.onDoubleClick = { line.open(id) }
        view.onDragStart = { line.draggingID = id }
        view.onDragEnd = {
            line.draggingID = nil
            // Moved into a folder: it is saved where you wanted it.
            line.prune()
        }
        view.onTrash = { line.trash(id) }
        // A pinned photo's corner holds its pin, which unpins.
        view.onDiscard = { pinned ? line.togglePin(id) : line.discard(id) }
        view.onForceClick = { line.quickLook(id) }
        view.onPressChange = { pressed in line.pressedID = pressed ? id : nil }
        let inInbox = line.isInInbox(id)
        view.cornerHelp = pinned ? L("Unpin") : (inInbox ? L("Discard") : L("Take down"))
        view.sendHelp = L("Paste into the app in front")
        // VoiceOver hears one button named after the file, and reaches what
        // the pointer finds on hover as actions.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        // A PDF keeps its extension, so it says what it is.
        view.setAccessibilityLabel(item.isDocument ? item.url.lastPathComponent
                                                   : item.url.deletingPathExtension().lastPathComponent)
        // AppKit runs accessibility actions on the main thread.
        let send = NSAccessibilityCustomAction(name: L("Paste into the app in front")) {
            MainActor.assumeIsolated { line.paste(id) }
            return true
        }
        let pin = NSAccessibilityCustomAction(name: pinned ? L("Unpin") : L("Pin")) {
            MainActor.assumeIsolated { line.togglePin(id) }
            return true
        }
        let takeDown = NSAccessibilityCustomAction(name: inInbox ? L("Discard") : L("Take down")) {
            MainActor.assumeIsolated { line.discard(id) }
            return true
        }
        view.setAccessibilityCustomActions(pinned ? [send, pin] : [send, pin, takeDown])
        view.menuProvider = {
            let menu = NSMenu()
            // Items say themselves whether they can be used.
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(L("Copy"), symbol: "doc.on.doc") { line.copy(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Copy Text"), symbol: "text.viewfinder") { line.copyText(id) })
            }
            if line.liveCount > 1 {
                menu.addItem(ClosureMenuItem(L("Copy all"), symbol: "square.on.square") { line.copyAll() })
            }
            if let app = Paste.frontApp?.localizedName {
                menu.addItem(ClosureMenuItem(String(format: L("Paste into %@"), app), symbol: "paperplane") { line.paste(id) })
            }
            if isImage {
                // The photos picked with it, or only this one, a page each.
                menu.addItem(ClosureMenuItem(L("Make PDF"), symbol: "doc.richtext") { line.makePDF(id) })
            }
            if line.photosToCombine.count > 1 {
                let combine = NSMenuItem(title: L("Combine into one image"), action: nil, keyEquivalent: "")
                if #available(macOS 26, *) { combine.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil) }
                let ways = NSMenu()
                ways.addItem(ClosureMenuItem(L("One under another")) { line.combine(.stacked) })
                ways.addItem(ClosureMenuItem(L("Side by side")) { line.combine(.sideBySide) })
                combine.submenu = ways
                menu.addItem(combine)
            }
            menu.addItem(ClosureMenuItem(pinned ? L("Unpin") : L("Pin"), symbol: pinned ? "pin.slash" : "pin") {
                line.togglePin(id)
            })
            if isImage {
                // What the screenshot says, translated or summed up, on this Mac.
                menu.addItem(.separator())
                if #available(macOS 15, *) {
                    let translate = NSMenuItem(title: L("Translate Text"), action: nil, keyEquivalent: "")
                    if #available(macOS 26, *) { translate.image = NSImage(systemSymbolName: "translate", accessibilityDescription: nil) }
                    let languages = NSMenu()
                    for language in Languages.mine {
                        languages.addItem(ClosureMenuItem(Languages.name(language)) { line.translate(id, to: language) })
                    }
                    languages.addItem(.separator())
                    for language in Languages.others {
                        languages.addItem(ClosureMenuItem(Languages.name(language)) { line.translate(id, to: language) })
                    }
                    translate.submenu = languages
                    menu.addItem(translate)
                }
                menu.addItem(ClosureMenuItem(L("Describe"), symbol: "sparkles") { line.describe(id) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(L("Open"), symbol: "arrow.up.forward.app") { line.open(id) })
            menu.addItem(ClosureMenuItem(L("Quick Look"), symbol: "eye") { line.quickLook(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Markup"), symbol: "pencil.tip.crop.circle") { line.markup(id) })
                menu.addItem(ClosureMenuItem(L("Hide Part…"), symbol: "rectangle.dashed") { line.hidePart(id) })
            }
            if isRecording {
                menu.addItem(ClosureMenuItem(L("Trim…"), symbol: "scissors") { line.markup(id) })
                menu.addItem(ClosureMenuItem(L("Make GIF"), symbol: "photo.stack") { line.makeGIF(id) })
            }
            menu.addItem(ClosureMenuItem(L("Show in Finder"), symbol: "folder") { line.reveal(id) })
            let inInbox = line.isInInbox(id)
            // The App Store edition may not write to the Desktop; a drag
            // into a folder keeps a photo there instead.
            if inInbox && !Edition.appStore {
                menu.addItem(ClosureMenuItem(L("Save to Desktop"), symbol: "menubar.dock.rectangle") { line.saveToDesktop(id) })
            }
            menu.addItem(.separator())
            if inInbox {
                menu.addItem(ClosureMenuItem(L("Discard"), symbol: "trash") { line.discard(id) })
            } else {
                menu.addItem(ClosureMenuItem(L("Take down"), symbol: "eye.slash") { line.discard(id) })
                menu.addItem(ClosureMenuItem(L("Move to Trash"), symbol: "trash") { line.trash(id) })
            }
            let left = ClosureMenuItem(L("Take down everything to the left"), symbol: "arrow.left.to.line") {
                line.takeDown(id, toTheLeft: true)
            }
            left.isEnabled = !line.neighbours(of: id, toTheLeft: true).isEmpty
            menu.addItem(left)
            let right = ClosureMenuItem(L("Take down everything to the right"), symbol: "arrow.right.to.line") {
                line.takeDown(id, toTheLeft: false)
            }
            right.isEnabled = !line.neighbours(of: id, toTheLeft: false).isEmpty
            menu.addItem(right)
            return menu
        }
    }
}

final class GrabView: NSView, NSDraggingSource, NSViewToolTipOwner {
    static var isDragging = false
    /// A photo's menu is open. It reaches past the line, so the line waits.
    static var isShowingMenu = false

    var url: URL?
    /// The file a drag hands over, when it is not the photo's own.
    var outgoingURL: () -> URL? = { nil }
    var dragImage: NSImage?
    var onClick: () -> Void = {}
    /// ⌘-click or ⇧-click: picks the photo, to copy along with others.
    var onPick: () -> Void = {}
    /// The paper plane: into the app in front.
    var onSend: () -> Void = {}
    /// Dropped into an app, which took a copy.
    var onSentByDrag: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onTrash: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onForceClick: () -> Void = {}
    var onPressChange: (Bool) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }
    /// What the corner button and the paper plane do, said when the pointer
    /// rests on them.
    var cornerHelp = ""
    var sendHelp = ""
    private var tips: [NSView.ToolTipTag] = []

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false

    /// How long you hold before the menu opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The discard cross drawn in the top left corner of the card. It is
    /// handled here because this view sits on top of the SwiftUI card.
    static let crossHitSize: CGFloat = 26

    private var crossRect: NSRect {
        NSRect(x: 0, y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
               width: Self.crossHitSize, height: Self.crossHitSize)
    }

    private func isInCross(_ event: NSEvent) -> Bool {
        crossRect.contains(convert(event.locationInWindow, from: nil))
    }

    /// The paper plane drawn in the bottom right corner, the cross's opposite.
    static let sendHitSize: CGFloat = 30

    private var sendRect: NSRect {
        NSRect(x: bounds.width - Self.sendHitSize, y: isFlipped ? bounds.height - Self.sendHitSize : 0,
               width: Self.sendHitSize, height: Self.sendHitSize)
    }

    private func isInSend(_ event: NSEvent) -> Bool {
        sendRect.contains(convert(event.locationInWindow, from: nil))
    }

    // MARK: Tooltips and VoiceOver

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        for tip in tips { removeToolTip(tip) }
        tips = [addToolTip(crossRect, owner: self, userData: nil),
                addToolTip(sendRect, owner: self, userData: nil)]
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        crossRect.contains(point) ? cornerHelp : sendHelp
    }

    /// VoiceOver's press is a click: it copies.
    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        GrabView.isShowingMenu = true
        _ = menuProvider().popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        GrabView.isShowingMenu = false
        return true
    }

    /// Holding ⌘ or ⇧ picks photos one by one, however fast you click.
    private func isPick(_ event: NSEvent) -> Bool {
        !event.modifierFlags.intersection([.command, .shift]).isEmpty
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click is the Mac's right click: it opens the menu, rather
        // than copying the photo or, held, opening Markup.
        if event.modifierFlags.contains(.control) {
            downPoint = nil
            rightMouseDown(with: event)
            return
        }
        if isInCross(event) {
            downPoint = nil
            onDiscard()
            return
        }
        if isInSend(event) && !isPick(event) {
            downPoint = nil
            onSend()
            return
        }
        if event.clickCount == 2 && !isPick(event) {
            downPoint = nil
            onDoubleClick()
            return
        }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onPressChange(false)
                self.showMenuFromHold()
            }
        }
    }

    /// A force click on a trackpad opens Quick Look, as it does in Finder.
    /// It counts instead of the click and of a long press.
    override func pressureChange(with event: NSEvent) {
        guard event.stage == 2, downPoint != nil, !startedDrag, !didLongPress else { return }
        didLongPress = true
        endPress()
        onForceClick()
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag, let url else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }
        startedDrag = true
        endPress()

        let item = NSDraggingItem(pasteboardWriter: (outgoingURL() ?? url) as NSURL)
        item.setDraggingFrame(imageFrame(), contents: dragImage)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Released where nothing accepts it: it flies back to the line.
        session.animatesToStartingPositionsOnCancelOrFail = true
        GrabView.isDragging = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        endPress()
        if downPoint != nil && !startedDrag && !didLongPress {
            if isPick(event) { onPick() } else if event.clickCount == 1 { onClick() }
        }
        downPoint = nil
        didLongPress = false
    }

    /// Holding a photo opens its menu, as a long press does on iPhone, so
    /// Make PDF, Markup and the rest are found without a right-click.
    private func showMenuFromHold() {
        guard let start = downPoint else { return }
        // The menu takes the mouse up, so the press ends here.
        downPoint = nil
        GrabView.isShowingMenu = true
        _ = menuProvider().popUp(positioning: nil, at: convert(start, from: nil), in: self)
        GrabView.isShowingMenu = false
    }

    override func rightMouseDown(with event: NSEvent) {
        // The menu runs until it closes, and the line stays down meanwhile.
        GrabView.isShowingMenu = true
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
        GrabView.isShowingMenu = false
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Apps pick copy. Finder picks move, so a folder or the Desktop keeps
        // the file. Delete is what lets the Dock's Trash accept it.
        context == .outsideApplication ? [.copy, .move, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        GrabView.isDragging = false
        startedDrag = false
        downPoint = nil
        log.notice("Drag ended with operation \(operation.rawValue, privacy: .public)")
        // Dropped on the Trash: macOS only tells us, we move the file.
        if operation.contains(.delete) {
            onDragEnd()
            onTrash()
            return
        }
        onDragEnd()
        // An app took a copy: it was sent, like with the paper plane.
        if operation == .copy { onSentByDrag() }
        // Finder finishes a move a moment later. Check again then, so a photo
        // saved into a folder leaves the line.
        if operation.contains(.move) {
            let done = onDragEnd
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done() }
        }
    }

    /// The drag preview keeps the photo's aspect ratio inside the card.
    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        // Menus have icons from macOS 26 on, as Apple's own apps do.
        if #available(macOS 26, *), let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
