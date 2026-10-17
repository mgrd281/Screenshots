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
/// unpins a pinned photo, and the paper plane in the opposite corner sends,
/// with ChatGPT and Claude beside it. ⌘-click, or the circle opposite the
/// cross, picks several, which go together.
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
        view.outgoingURL = { PrivateDetails.shareable(item.url, covering: CoveringProfile.detailsNow) }
        view.onClick = { line.copy(id) }
        view.onPick = { line.pick(id) }
        view.onPickCircle = { line.pick(id, quietly: true) }
        view.onSendToChat = { chat in line.send(id, to: chat) }
        view.onSentByDrag = { line.sentByDrag(id) }
        view.onSend = { line.paste(id) }
        view.onDoubleClick = { line.open(id) }
        view.onDragStart = { line.draggingID = id }
        view.onDragMoved = { point in line.dragMoved(id, to: point) }
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
        // What was covered, and where one like it went lately, said by the
        // badges in the lock's corner and to VoiceOver.
        let covered = item.covered ? PrivateDetails.report(for: item.url)?.sentence : nil
        let sent = Line.marksSentBefore ? line.sentSentence(id) : nil
        let said = [covered, sent].compactMap { $0 }
        view.lockHelp = said.joined(separator: "\n")
        view.lockBadges = (item.covered ? 1 : 0) + (sent == nil ? 0 : 1)
        let picked = line.pickedIDs.contains(id)
        view.picked = picked
        // ChatGPT and Claude beside the paper plane, where the photo has room.
        view.leadingRoom = PhotoButtons.leadingRoom(badges: item.isDocument ? 0 : view.lockBadges, document: item.isDocument)
        view.chats = AIChat.takes(item) ? AIChat.onPhotosNow : []
        // VoiceOver hears one button named after the file, and reaches what
        // the pointer finds on hover as actions.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        // A PDF keeps its extension, so it says what it is.
        view.setAccessibilityLabel(item.isDocument ? item.url.lastPathComponent
                                                   : item.url.deletingPathExtension().lastPathComponent)
        view.setAccessibilityValue(said.isEmpty ? nil : said.joined(separator: ". "))
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
        let earlier = NSAccessibilityCustomAction(name: L("Move Earlier")) {
            MainActor.assumeIsolated { line.move(id, by: -1) }
            return true
        }
        let later = NSAccessibilityCustomAction(name: L("Move Later")) {
            MainActor.assumeIsolated { line.move(id, by: 1) }
            return true
        }
        let pick = NSAccessibilityCustomAction(name: picked ? L("Unpick") : L("Pick")) {
            MainActor.assumeIsolated { line.pick(id, quietly: true) }
            return true
        }
        let chats = AIChat.takes(item) ? AIChat.allCases.map { chat in
            NSAccessibilityCustomAction(name: String(format: L("Send to %@"), chat.name)) {
                MainActor.assumeIsolated { line.send(id, to: chat) }
                return true
            }
        } : []
        view.setAccessibilityCustomActions((pinned ? [send, pin] : [send, pin, takeDown]) + chats + [pick, earlier, later])
        view.menuProvider = {
            let menu = NSMenu()
            // Items say themselves whether they can be used.
            menu.autoenablesItems = false
            // First, what was covered in what leaves the line, and where a
            // photo like it went lately.
            if let covered = line.coveredSentence(id) {
                let what = NSMenuItem(title: covered, action: nil, keyEquivalent: "")
                what.isEnabled = false
                if #available(macOS 26, *) { what.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) }
                menu.addItem(what)
            }
            if let sent = line.sentSentence(id) {
                let when = NSMenuItem(title: sent, action: nil, keyEquivalent: "")
                when.isEnabled = false
                if #available(macOS 26, *) { when.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil) }
                menu.addItem(when)
            }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(ClosureMenuItem(L("Copy"), symbol: "doc.on.doc") { line.copy(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Copy Text"), symbol: "text.viewfinder") { line.copyText(id) })
            }
            if line.liveCount > 1 {
                menu.addItem(ClosureMenuItem(L("Copy all"), symbol: "square.on.square") { line.copyAll() })
                if line.pickedIDs.count < line.liveCount {
                    menu.addItem(ClosureMenuItem(L("Pick All"), symbol: "checkmark.circle") { line.pickAll() })
                }
            }
            if !line.pickedIDs.isEmpty {
                menu.addItem(ClosureMenuItem(L("Unpick All"), symbol: "circle") { line.unpickAll() })
            }
            if let app = Paste.frontApp?.localizedName {
                menu.addItem(ClosureMenuItem(String(format: L("Paste into %@"), app), symbol: "paperplane") { line.paste(id) })
                if isImage {
                    // For a customer: under a band with the shop's name, logo, order and day.
                    menu.addItem(ClosureMenuItem(L("Send with Shop Header"), symbol: "storefront") { line.sendWithHeader(id) })
                }
            }
            // Straight into ChatGPT or Claude: their app, or else their website.
            if AIChat.takes(item) {
                for chat in AIChat.allCases {
                    let send = ClosureMenuItem(String(format: L("Send to %@"), chat.name), symbol: "bubble.left") {
                        line.send(id, to: chat)
                    }
                    if #available(macOS 26, *), let icon = chat.icon?.copy() as? NSImage {
                        icon.size = NSSize(width: 16, height: 16)
                        send.image = icon
                    }
                    menu.addItem(send)
                }
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
                menu.addItem(ClosureMenuItem(L("Order Details"), symbol: "list.bullet.rectangle") { line.orderDetails(id) })
                // For the books: a covered copy with a name that says what it is.
                let url = item.url
                menu.addItem(ClosureMenuItem(L("Save for Bookkeeping"), symbol: "folder.badge.plus") { Bookkeeping.save(url) })
                menu.addItem(ClosureMenuItem(L("Email to Bookkeeping…"), symbol: "envelope") { Bookkeeping.mail(url) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(L("Open"), symbol: "arrow.up.forward.app") { line.open(id) })
            menu.addItem(ClosureMenuItem(L("Quick Look"), symbol: "eye") { line.quickLook(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Keep on Top"), symbol: "pip") { line.keepOnTop(id) })
            }
            if isImage {
                menu.addItem(ClosureMenuItem(L("Markup"), symbol: "pencil.tip.crop.circle") { line.markup(id) })
                menu.addItem(ClosureMenuItem(L("Hide Part…"), symbol: "rectangle.dashed") { line.hidePart(id) })
                menu.addItem(ClosureMenuItem(L("Draw on Photo…"), symbol: "scribble.variable") { line.drawOn(id) })
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
    /// The circle opposite the cross: picks the photo, or puts it back.
    var onPickCircle: () -> Void = {}
    /// ChatGPT or Claude beside the paper plane.
    var onSendToChat: (AIChat) -> Void = { _ in }
    /// The paper plane: into the app in front.
    var onSend: () -> Void = {}
    /// Dropped into an app, which took a copy.
    var onSentByDrag: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onDragStart: () -> Void = {}
    /// Where the drag is, in screen coordinates; true while it is along the
    /// line, where letting go keeps the photo's new place.
    var onDragMoved: (CGPoint) -> Bool = { _ in false }
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
    /// What was covered, and where one like it went lately, said when the
    /// pointer rests on the lock's corner; empty with no badge there.
    var lockHelp = "" {
        didSet { if lockHelp != oldValue { placeTips() } }
    }
    /// How many badges sit in the lock's corner: the lock, and the paper
    /// plane of a photo sent before.
    var lockBadges = 1 {
        didSet { if lockBadges != oldValue { placeTips() } }
    }
    /// The photo is picked: its circle puts it back.
    var picked = false
    /// The AI chats beside the paper plane, and the room the lock's corner
    /// takes, which together say where they fit.
    var chats: [AIChat] = [] {
        didSet { if chats != oldValue { placeTips() } }
    }
    var leadingRoom: CGFloat = 0 {
        didSet { if leadingRoom != oldValue { placeTips() } }
    }
    private var tips: [NSView.ToolTipTag] = []

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false

    /// How long you hold before the menu opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A rect counted from the card's top left, left to right, as this view
    /// counts: from the bottom unless flipped, and mirrored for right to
    /// left, where SwiftUI draws the leading corner on the right.
    private func placed(_ rect: CGRect) -> NSRect {
        let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - rect.maxX : rect.minX
        return NSRect(x: x, y: isFlipped ? rect.minY : bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The discard cross drawn in the top leading corner of the card. It is
    /// handled here because this view sits on top of the SwiftUI card.
    static let crossHitSize: CGFloat = 26

    private var crossRect: NSRect {
        placed(CGRect(x: 0, y: 0, width: Self.crossHitSize, height: Self.crossHitSize))
    }

    private func isInCross(_ event: NSEvent) -> Bool {
        crossRect.contains(convert(event.locationInWindow, from: nil))
    }

    /// The paper plane drawn in the bottom trailing corner, the cross's opposite.
    static let sendHitSize: CGFloat = 30

    private var sendRect: NSRect {
        placed(CGRect(x: bounds.width - Self.sendHitSize, y: bounds.height - Self.sendHitSize,
                      width: Self.sendHitSize, height: Self.sendHitSize))
    }

    private func isInSend(_ event: NSEvent) -> Bool {
        sendRect.contains(convert(event.locationInWindow, from: nil))
    }

    /// The pick circle in the top trailing corner, kept clear of the cross
    /// on a narrow photo.
    private var pickRect: NSRect {
        var rect = PhotoButtons.pick(card: bounds.size).insetBy(dx: -3, dy: -3)
        rect.origin.x = max(rect.minX, Self.crossHitSize)
        rect.size.width = max(0, bounds.width - rect.minX)
        return placed(rect)
    }

    /// ChatGPT's and Claude's icons beside the paper plane, where they fit.
    private var chatRects: [NSRect] {
        let card = bounds.size
        let arrangement = PhotoButtons.arrangement(card: card, chats: chats.count, leadingRoom: leadingRoom)
        return PhotoButtons.chats(card: card, count: chats.count, arrangement: arrangement)
            .map { placed($0.insetBy(dx: -2, dy: -2)) }
    }

    private func chat(at point: NSPoint) -> AIChat? {
        zip(chats, chatRects).first { $0.1.contains(point) }?.0
    }

    /// The lock of a covered photo, in the bottom corner where lines of
    /// text start.
    static let lockHitSize: CGFloat = 28

    private var lockRect: NSRect {
        // Each badge after the first adds its 18 pt and the 4 between them.
        let width = Self.lockHitSize + CGFloat(max(0, lockBadges - 1)) * 22
        let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0
        return NSRect(x: x, y: isFlipped ? bounds.height - Self.lockHitSize : 0,
                      width: width, height: Self.lockHitSize)
    }

    // MARK: Tooltips and VoiceOver

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeTips()
    }

    private func placeTips() {
        for tip in tips { removeToolTip(tip) }
        tips = [addToolTip(crossRect, owner: self, userData: nil),
                addToolTip(pickRect, owner: self, userData: nil),
                addToolTip(sendRect, owner: self, userData: nil)]
        tips += chatRects.map { addToolTip($0, owner: self, userData: nil) }
        if !lockHelp.isEmpty { tips.append(addToolTip(lockRect, owner: self, userData: nil)) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        if crossRect.contains(point) { return cornerHelp }
        if pickRect.contains(point) { return picked ? L("Unpick") : L("Pick") }
        if sendRect.contains(point) { return sendHelp }
        if let target = chat(at: point) { return String(format: L("Send to %@"), target.name) }
        if !lockHelp.isEmpty && lockRect.contains(point) { return lockHelp }
        return sendHelp
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
        let point = convert(event.locationInWindow, from: nil)
        if pickRect.contains(point) {
            downPoint = nil
            onPickCircle()
            return
        }
        if isInSend(event) && !isPick(event) {
            downPoint = nil
            onSend()
            return
        }
        if let target = chat(at: point), !isPick(event) {
            downPoint = nil
            onSendToChat(target)
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

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        // Let go along the line, it stays in its new place instead of
        // flying back to the old one.
        session.animatesToStartingPositionsOnCancelOrFail = !onDragMoved(screenPoint)
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
