import AppKit
import AVFoundation
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
/// A click on the page's address in a time band opens the page instead.
/// ChatGPT, Claude, WhatsApp and Gmail stand in a row under the photo, which
/// this view reaches down to. ⌘-click, or the circle opposite the
/// cross, picks several, which go together.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line
    /// The pointer is over the photo or the row of icons under it.
    @Binding var overStrip: Bool
    /// The pointer rests on the lock of a covered photo.
    @Binding var overLock: Bool

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
        view.onDiscard = { pinned ? line.togglePin(id) : line.takeDown(id) }
        view.onForceClick = { line.quickLook(id) }
        view.onCrop = isImage ? { line.crop(id) } : nil
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
        let chats = ChatTarget.row(ChatTarget.takes(item) ? ChatTarget.onPhotosNow : [])
        view.chats = chats.shown
        view.moreChats = chats.more
        view.stripHeight = chats.count == 0 ? 0 : PhotoButtons.stripHeight
        let over = $overStrip
        view.onHoverChange = { inside in if over.wrappedValue != inside { over.wrappedValue = inside } }
        view.covered = item.covered
        let lock = $overLock
        view.onLockHover = { inside in if lock.wrappedValue != inside { lock.wrappedValue = inside } }
        // The page the time band names, and where its address is on the
        // photo: a click there opens it. Found again only for a new picture.
        if view.bandPicture !== item.thumb || view.bandStampOn != TimeStamp.isOn {
            view.bandPicture = item.thumb
            view.bandStampOn = TimeStamp.isOn
            view.pages = line.pages(id)
            view.bandLinks = nil
            if item.isRecording {
                // A recording's size is read from its file, a moment later.
                let thumb = ObjectIdentifier(item.thumb)
                Task { @MainActor [weak view] in
                    let links = await line.recordingBandLinks(id)
                    // Unless another picture came meanwhile.
                    guard let view, view.bandPicture.map({ ObjectIdentifier($0) }) == thumb else { return }
                    view.bandLinks = links
                }
            } else {
                view.bandLinks = line.bandLinks(id)
            }
        }
        view.onOpenPage = { url in line.openPage(url.absoluteString) }
        // A right-click on one of them: the questions and prompts from Settings.
        let questions = AIQuestions.offered()
        let prompts = AIPrompts.offered()
        view.hasQuestions = !questions.isEmpty || !prompts.isEmpty
        view.chatMenuProvider = { chat in
            guard chat.isAI, !questions.isEmpty || !prompts.isEmpty else { return nil }
            let menu = Self.questionMenu(questions, prompts, for: chat, line: line, id: id)
            let what = NSMenuItem(title: String(format: L("Ask %@"), chat.name), action: nil, keyEquivalent: "")
            what.isEnabled = false
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(what, at: 0)
            return menu
        }
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
            MainActor.assumeIsolated { _ = line.paste(id) }
            return true
        }
        let pin = NSAccessibilityCustomAction(name: pinned ? L("Unpin") : L("Pin")) {
            MainActor.assumeIsolated { line.togglePin(id) }
            return true
        }
        let takeDown = NSAccessibilityCustomAction(name: inInbox ? L("Discard") : L("Take down")) {
            MainActor.assumeIsolated { line.takeDown(id) }
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
        let chatActions = ChatTarget.takes(item) ? ChatTarget.ordered().map { chat in
            NSAccessibilityCustomAction(name: String(format: L("Send to %@"), chat.name)) {
                MainActor.assumeIsolated { line.send(id, to: chat) }
                return true
            }
        } : []
        // The page the time band names, as a click on its address opens it;
        // a recording's each, with when it was opened.
        let pages = view.pages
        let pageActions: [NSAccessibilityCustomAction] = pages.map { page in
            let name = pages.count == 1 ? L("Open Page") : L("Open Page") + ": " + Self.pageTitle(page)
            return NSAccessibilityCustomAction(name: name) {
                MainActor.assumeIsolated { line.openPage(page.address) }
                return true
            }
        }
        let actions: [NSAccessibilityCustomAction] = (pinned ? [send, pin] : [send, pin, takeDown]) + chatActions
            + pageActions + [pick, earlier, later]
        view.setAccessibilityCustomActions(actions)
        view.menuProvider = {
            // Short, as a Mac app's own menus are: what is done most at the
            // top, the rest gathered in a few submenus by what it is for.
            let menu = NSMenu()
            // Items say themselves whether they can be used.
            menu.autoenablesItems = false
            // First, what was covered in what leaves the line, and where a
            // photo like it went lately.
            if let covered = line.coveredSentence(id) {
                let what = NSMenuItem(title: covered, action: nil, keyEquivalent: "")
                what.isEnabled = false
                if #available(macOS 26, *) { what.image = MenuSymbol.image("lock.fill") }
                menu.addItem(what)
            }
            if let sent = line.sentSentence(id) {
                let when = NSMenuItem(title: sent, action: nil, keyEquivalent: "")
                when.isEnabled = false
                if #available(macOS 26, *) { when.image = MenuSymbol.image("paperplane") }
                menu.addItem(when)
            }

            // Copy it, or put it where it goes.
            Self.gap(menu)
            menu.addItem(ClosureMenuItem(L("Copy"), symbol: "doc.on.doc") { line.copy(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Copy Text"), symbol: "text.viewfinder") { line.copyText(id) })
            }
            let frontApp = Paste.frontApp?.localizedName
            if let frontApp {
                menu.addItem(ClosureMenuItem(String(format: L("Paste into %@"), frontApp), symbol: "paperplane") { line.paste(id) })
            }
            // To the iPhone nearby, with Handoff.
            if isImage {
                menu.addItem(ClosureMenuItem(L("Open on iPhone"), symbol: "iphone") { line.openOnPhone(id) })
            }
            // A link to paste anywhere, for seven days.
            if LinkSharing.isAvailable {
                menu.addItem(ClosureMenuItem(L("Copy Link"), symbol: "link") { line.copyLink(id) })
                if line.hasShareLink(id) {
                    menu.addItem(ClosureMenuItem(L("Delete Link"), symbol: "minus.circle") { line.deleteShareLink(id) })
                }
            }

            // Into a chat, a question for an AI, and what the words say.
            Self.gap(menu)
            if let send = Self.group(L("Send to"), symbol: "paperplane.circle", { sub in
                guard ChatTarget.takes(item) else { return }
                // The chats under photos first, as they stand there; the rest one level further.
                let ordered = ChatTarget.ordered()
                for chat in ordered where ChatTarget.shows(chat) {
                    sub.addItem(Self.chatItem(chat, String(format: L("Send to %@"), chat.name)) { line.send(id, to: chat) })
                }
                if let more = Self.group(L("More Chats"), symbol: "ellipsis.bubble", { others in
                    for chat in ordered where !ChatTarget.shows(chat) {
                        others.addItem(Self.chatItem(chat, chat.name) { line.send(id, to: chat) })
                    }
                }) {
                    Self.gap(sub)
                    sub.addItem(more)
                }
                if frontApp != nil && isImage {
                    // For a customer: under a band with the shop's name, logo, order and day.
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Send with Shop Header"), symbol: "storefront") { line.sendWithHeader(id) })
                }
            }) {
                menu.addItem(send)
            }
            // With one of the questions from Settings after the photo.
            if ChatTarget.takes(item), !questions.isEmpty || !prompts.isEmpty,
               let ask = Self.group(L("Ask AI"), symbol: "questionmark.bubble", { sub in
                   for chat in ChatTarget.ordered() where chat.isAI {
                       let entry = Self.chatItem(chat, chat.name) {}
                       entry.submenu = Self.questionMenu(questions, prompts, for: chat, line: line, id: id)
                       sub.addItem(entry)
                   }
               }) {
                menu.addItem(ask)
            }
            if isImage, let words = Self.group(L("Text and AI"), symbol: "sparkles", { sub in
                // What the screenshot says, translated or summed up, on this Mac.
                if #available(macOS 15, *) {
                    let translate = NSMenuItem(title: L("Translate Text"), action: nil, keyEquivalent: "")
                    if #available(macOS 26, *) { translate.image = MenuSymbol.image("translate") }
                    let languages = NSMenu()
                    for language in Languages.mine {
                        languages.addItem(ClosureMenuItem(Languages.name(language)) { line.translate(id, to: language) })
                    }
                    languages.addItem(.separator())
                    for language in Languages.others {
                        languages.addItem(ClosureMenuItem(Languages.name(language)) { line.translate(id, to: language) })
                    }
                    translate.submenu = languages
                    sub.addItem(translate)
                }
                sub.addItem(ClosureMenuItem(L("Describe"), symbol: "text.below.photo") { line.describe(id) })
                sub.addItem(ClosureMenuItem(L("Order Details"), symbol: "list.bullet.rectangle") { line.orderDetails(id) })
                // The AI assistant, with the owner's own key; without one,
                // the card says where it goes.
                Self.gap(sub)
                sub.addItem(ClosureMenuItem(L("Write a Reply"), symbol: "arrowshape.turn.up.left") { line.writeReply(id) })
                sub.addItem(ClosureMenuItem(String(format: L("Explain with %@"), AIAccount.provider.name),
                                            symbol: "bubble.left.and.text.bubble.right") { line.askAssistant(id) })
            }) {
                menu.addItem(words)
            }

            // Changing it, and keeping it in another form.
            Self.gap(menu)
            if let edit = Self.group(L("Edit"), symbol: "slider.horizontal.3", { sub in
                if isImage {
                    sub.addItem(ClosureMenuItem(L("Crop…"), symbol: "crop") { line.crop(id) })
                    if line.isCropped(id) {
                        sub.addItem(ClosureMenuItem(L("Keep Whole Photo"), symbol: "arrow.up.left.and.arrow.down.right") {
                            line.keepWhole(id)
                        })
                    }
                    sub.addItem(ClosureMenuItem(L("Hide Part…"), symbol: "rectangle.dashed") { line.hidePart(id) })
                    sub.addItem(ClosureMenuItem(L("Draw on Photo…"), symbol: "scribble.variable") { line.drawOn(id) })
                    sub.addItem(ClosureMenuItem(L("Background…"), symbol: "photo.artframe") { line.background(id) })
                    if line.hasBackground(id) {
                        sub.addItem(ClosureMenuItem(L("Remove Background"), symbol: "rectangle.slash") {
                            line.removeBackground(id)
                        })
                    }
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Markup"), symbol: "pencil.tip.crop.circle") { line.markup(id) })
                }
                if isRecording {
                    sub.addItem(ClosureMenuItem(L("Edit in Studio…"), symbol: "wand.and.stars") { line.studio(id) })
                    sub.addItem(ClosureMenuItem(L("Trim…"), symbol: "scissors") { line.markup(id) })
                    sub.addItem(ClosureMenuItem(L("Make GIF"), symbol: "photo.stack") { line.makeGIF(id) })
                }
            }) {
                menu.addItem(edit)
            }
            let inInbox = line.isInInbox(id)
            if let export = Self.group(L("Save and Export"), symbol: "square.and.arrow.up", { sub in
                // What goes out differs from the file: drawn on, cropped,
                // covered or stamped. It can be kept as a file of its own.
                if !isRecording && PrivateDetails.alters(item.url) {
                    sub.addItem(ClosureMenuItem(L("Save Copy…"), symbol: "square.and.arrow.down") { line.saveCopy(id) })
                }
                if isImage {
                    // The photos picked with it, or only this one, a page each.
                    sub.addItem(ClosureMenuItem(L("Make PDF"), symbol: "doc.richtext") { line.makePDF(id) })
                }
                if line.photosToCombine.count > 1 {
                    let combine = NSMenuItem(title: L("Combine into one image"), action: nil, keyEquivalent: "")
                    if #available(macOS 26, *) { combine.image = MenuSymbol.image("rectangle.stack") }
                    let ways = NSMenu()
                    ways.addItem(ClosureMenuItem(L("One under another")) { line.combine(.stacked) })
                    ways.addItem(ClosureMenuItem(L("Side by side")) { line.combine(.sideBySide) })
                    combine.submenu = ways
                    sub.addItem(combine)
                }
                if isImage {
                    sub.addItem(ClosureMenuItem(L("Convert to SVG…"), symbol: "point.topleft.down.curvedto.point.bottomright.up") {
                        line.convertToSVG(id)
                    })
                    // For the books: a covered copy with a name that says what it is.
                    let url = item.url
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Save for Bookkeeping"), symbol: "folder.badge.plus") { Bookkeeping.save(url) })
                    sub.addItem(ClosureMenuItem(L("Email to Bookkeeping…"), symbol: "envelope") { Bookkeeping.mail(url) })
                }
                // When it was made, signed by an independent authority, for a
                // lawyer or a court.
                if isImage || isRecording {
                    let url = item.url
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Save Proof of Time…"), symbol: "checkmark.seal") { TimeProof.save(url) })
                }
                // The App Store edition may not write to the Desktop; a drag
                // into a folder keeps a photo there instead.
                if inInbox && !Edition.appStore {
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Save to Desktop"), symbol: "menubar.dock.rectangle") { line.saveToDesktop(id) })
                }
            }) {
                menu.addItem(export)
            }

            // Filing it in the Workspace: this one, or the photos picked with it.
            let workspace = Workspace.shared
            if workspace.isReady, WorkspaceFiles.isManaged(item.url) {
                let files = picked ? line.items.filter { line.pickedIDs.contains($0.id) && !$0.falling }.map(\.url) : [item.url]
                let here = workspace.config.category(containing: item.url, root: workspace.root)
                Self.gap(menu)
                if let move = Self.group(L("Move to Folder"), symbol: "folder.badge.gearshape", { sub in
                    for category in workspace.config.visible {
                        let entry = ClosureMenuItem(category.name) { workspace.move(files, to: category.id) }
                        entry.state = files.count == 1 && category.id == here?.id ? .on : .off
                        sub.addItem(entry)
                    }
                    Self.gap(sub)
                    sub.addItem(ClosureMenuItem(L("Open Workspace"), symbol: "folder") { workspace.reveal() })
                }) {
                    menu.addItem(move)
                }
            }

            // Looking at it.
            Self.gap(menu)
            menu.addItem(ClosureMenuItem(L("Open"), symbol: "arrow.up.forward.app") { line.open(id) })
            // The page the time band names, in the browser; a recording's
            // each, with when it was opened.
            let pages = line.pages(id)
            if pages.count == 1, let page = pages.first {
                let openPage = ClosureMenuItem(L("Open Page"), symbol: "globe") { line.openPage(page.address) }
                openPage.toolTip = page.address
                menu.addItem(openPage)
            } else if let openPage = Self.group(L("Open Page"), symbol: "globe", { sub in
                for page in pages {
                    let entry = ClosureMenuItem(Self.pageTitle(page)) { line.openPage(page.address) }
                    entry.toolTip = page.address
                    sub.addItem(entry)
                }
            }) {
                menu.addItem(openPage)
            }
            menu.addItem(ClosureMenuItem(L("Quick Look"), symbol: "eye") { line.quickLook(id) })
            if isImage {
                menu.addItem(ClosureMenuItem(L("Keep on Top"), symbol: "pip") { line.keepOnTop(id) })
            }
            menu.addItem(ClosureMenuItem(L("Show in Finder"), symbol: "folder") { line.reveal(id) })
            menu.addItem(ClosureMenuItem(pinned ? L("Unpin") : L("Pin"), symbol: pinned ? "pin.slash" : "pin") {
                line.togglePin(id)
            })

            // The others on the line, then letting this one go.
            Self.gap(menu)
            if let all = Self.group(L("All Photos"), symbol: "square.on.square", { sub in
                if line.liveCount > 1 {
                    sub.addItem(ClosureMenuItem(L("Copy all"), symbol: "doc.on.doc") { line.copyAll() })
                    if line.pickedIDs.count < line.liveCount {
                        sub.addItem(ClosureMenuItem(L("Pick All"), symbol: "checkmark.circle") { line.pickAll() })
                    }
                }
                if !line.pickedIDs.isEmpty {
                    sub.addItem(ClosureMenuItem(L("Unpick All"), symbol: "circle") { line.unpickAll() })
                }
                let left = !line.neighbours(of: id, toTheLeft: true).isEmpty
                let right = !line.neighbours(of: id, toTheLeft: false).isEmpty
                if left || right {
                    Self.gap(sub)
                    let toLeft = ClosureMenuItem(L("Take down everything to the left"), symbol: "arrow.left.to.line") {
                        line.takeDown(id, toTheLeft: true)
                    }
                    toLeft.isEnabled = left
                    sub.addItem(toLeft)
                    let toRight = ClosureMenuItem(L("Take down everything to the right"), symbol: "arrow.right.to.line") {
                        line.takeDown(id, toTheLeft: false)
                    }
                    toRight.isEnabled = right
                    sub.addItem(toRight)
                }
            }) {
                menu.addItem(all)
            }
            if inInbox {
                menu.addItem(ClosureMenuItem(L("Discard"), symbol: "trash") { line.takeDown(id) })
            } else {
                menu.addItem(ClosureMenuItem(L("Take down"), symbol: "eye.slash") { line.takeDown(id) })
                menu.addItem(ClosureMenuItem(L("Move to Trash"), symbol: "trash") { line.moveToTrash(id) })
            }
            return menu
        }
    }

    /// A page the time band names, short: a recording's from when it was
    /// opened, then its website.
    private static func pageTitle(_ page: TimeProof.Seen.Page) -> String {
        let site = StampSite.host(of: page.address) ?? page.address
        guard let at = page.at else { return site }
        return String(format: L("From %@"), TimeProof.moment(at)) + " · " + site
    }

    /// A separator, unless the menu is empty or already ends in one.
    private static func gap(_ menu: NSMenu) {
        guard let last = menu.items.last, !last.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    /// One item opening a submenu of the items `fill` puts in it, with
    /// separators at its ends taken away; nil when it holds nothing.
    private static func group(_ title: String, symbol: String, _ fill: (NSMenu) -> Void) -> NSMenuItem? {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        fill(submenu)
        while let last = submenu.items.last, last.isSeparatorItem { submenu.removeItem(last) }
        guard !submenu.items.isEmpty else { return nil }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if #available(macOS 26, *) { item.image = MenuSymbol.image(symbol) }
        item.submenu = submenu
        return item
    }

    /// A chat as an item: its icon, as under the photo, on every macOS, since
    /// it says more than its name.
    private static func chatItem(_ chat: ChatTarget, _ title: String, action: @escaping () -> Void) -> ClosureMenuItem {
        let item = ClosureMenuItem(title, symbol: "bubble.left", handler: action)
        if let icon = chat.icon?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return item
    }

    /// The questions for a chat, each sending the photo with itself after,
    /// then the prompts by their numbers, as beside the send button.
    private static func questionMenu(_ questions: [AIQuestion], _ prompts: [AIPrompt], for chat: ChatTarget,
                                     line: Line, id: UUID) -> NSMenu {
        let menu = NSMenu()
        for question in questions {
            menu.addItem(ClosureMenuItem(question.text) { line.send(id, to: chat, asking: question.text) })
        }
        if !prompts.isEmpty {
            if !questions.isEmpty { menu.addItem(.separator()) }
            let header = NSMenuItem(title: L("Prompts"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (index, prompt) in prompts.enumerated() {
                // Its number, as beside the send button over the chat.
                menu.addItem(ClosureMenuItem(prompt.name(number: index + 1), symbol: "\(index + 1).circle") {
                    line.send(id, to: chat, asking: prompt.text)
                })
            }
        }
        return menu
    }
}

final class GrabView: NSView, NSDraggingSource, NSViewToolTipOwner {
    static var isDragging = false
    /// When the last photo was let go of, as the app it was dropped on may
    /// still be reading its file.
    static var lastDragEnd = Date.distantPast
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
    /// A chat's icon under the photo.
    var onSendToChat: (ChatTarget) -> Void = { _ in }
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
    /// ⌥-click on a photo: Crop, to drag over the part to keep; nil where
    /// there is nothing to crop, and the click copies.
    var onCrop: (() -> Void)?
    var onPressChange: (Bool) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }
    /// A right-click on ChatGPT or Claude: the questions to send the photo
    /// with; nil without any, and the photo's own menu opens.
    var chatMenuProvider: (ChatTarget) -> NSMenu? = { _ in nil }
    var hasQuestions = false
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
    /// The chats under the photo, and the room below it that this view
    /// reaches into for their icons: the card is the rest of its height.
    var chats: [ChatTarget] = [] {
        didSet { if chats != oldValue { placeTips() } }
    }
    /// The chats behind the ⋯ at the row's end, when more are on than it holds.
    var moreChats: [ChatTarget] = [] {
        didSet { if moreChats != oldValue { placeTips() } }
    }
    var stripHeight: CGFloat = 0 {
        didSet { if stripHeight != oldValue { placeTips() } }
    }
    /// The pointer is over this view, the photo or the row under it.
    var onHoverChange: (Bool) -> Void = { _ in }
    /// Something is covered, and the lock shows.
    var covered = false
    /// The pointer comes to rest on the lock, or leaves it.
    var onLockHover: (Bool) -> Void = { _ in }
    /// The links in the photo's time band: a click on one opens its page,
    /// rather than copying the photo.
    var bandLinks: BandLinks? {
        didSet { if bandLinks != oldValue { placeTips() } }
    }
    /// What the links were found for, so they are found again only for a
    /// new picture or with the stamp turned on or off.
    var bandPicture: NSImage?
    var bandStampOn = false
    /// The pages the time band names, for VoiceOver.
    var pages: [TimeProof.Seen.Page] = []
    var onOpenPage: (URL) -> Void = { _ in }
    private var tips: [NSView.ToolTipTag] = []
    /// The page under a press that began on a link in the band.
    private var pressedPage: URL?
    /// The pointer shows a hand, over a link.
    private var pointing = false

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

    /// The card's height: all of this view's but the room below it.
    private var cardHeight: CGFloat { bounds.height - stripHeight }

    private var sendRect: NSRect {
        placed(CGRect(x: bounds.width - Self.sendHitSize, y: cardHeight - Self.sendHitSize,
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

    /// The chats' icons in a row under the card, the ⋯ last.
    private var chatRects: [NSRect] {
        PhotoButtons.chats(card: CGSize(width: bounds.width, height: cardHeight),
                           count: chats.count + (moreChats.isEmpty ? 0 : 1))
            .map { placed($0.insetBy(dx: -2, dy: -2)) }
    }

    private func chat(at point: NSPoint) -> ChatTarget? {
        zip(chats, chatRects).first { $0.1.contains(point) }?.0
    }

    /// The ⋯ in the row's last place, when there is one.
    private var moreRect: NSRect? {
        moreChats.isEmpty ? nil : chatRects.last
    }

    private func isOnMore(_ point: NSPoint) -> Bool {
        moreRect?.contains(point) ?? false
    }

    /// The chats behind the ⋯, each with its icon, to send the photo to.
    private func moreMenu() -> NSMenu {
        let menu = NSMenu()
        for chat in moreChats {
            let item = ClosureMenuItem(String(format: L("Send to %@"), chat.name)) { [weak self] in
                self?.onSendToChat(chat)
            }
            if let icon = chat.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        return menu
    }

    /// Opens the list of the rest under the ⋯, as a pop-up button does.
    private func showMore() {
        guard let rect = moreRect else { return }
        GrabView.isShowingMenu = true
        _ = moreMenu().popUp(positioning: nil, at: NSPoint(x: rect.minX, y: isFlipped ? rect.maxY : rect.minY), in: self)
        GrabView.isShowingMenu = false
    }

    /// The lock of a covered photo, in the bottom corner where lines of
    /// text start.
    static let lockHitSize: CGFloat = 28

    private var lockRect: NSRect {
        // Each badge after the first adds its 18 pt and the 4 between them.
        let width = Self.lockHitSize + CGFloat(max(0, lockBadges - 1)) * 22
        let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0
        return NSRect(x: x, y: isFlipped ? cardHeight - Self.lockHitSize : stripHeight,
                      width: width, height: Self.lockHitSize)
    }

    /// The least height a link takes under the pointer, however small its
    /// band is drawn on the photo.
    static let linkReach: CGFloat = 6

    /// The band's links where the photo shows them: inside the frame's inset,
    /// and grown from the card's top, as the pointer on the card grows it.
    private var linkRects: [(rect: NSRect, url: URL)] {
        guard let bandLinks else { return [] }
        let photo = CGSize(width: bounds.width - 2 * Frame.inset, height: cardHeight - 2 * Frame.inset)
        guard photo.width > 0, photo.height > 0 else { return [] }
        let grow = PeggedView.hoverScale
        return bandLinks.places(on: photo, least: Self.linkReach).map { strip -> (rect: NSRect, url: URL) in
            // Counted from the card's top left; the picture reads left to right in every language.
            let card = strip.rect.offsetBy(dx: Frame.inset, dy: Frame.inset)
            let shown = CGRect(x: bounds.midX + (card.minX - bounds.midX) * grow, y: card.minY * grow,
                               width: card.width * grow, height: card.height * grow)
            return (rect: NSRect(x: shown.minX, y: isFlipped ? shown.minY : bounds.height - shown.maxY,
                                 width: shown.width, height: shown.height), url: strip.url)
        }
    }

    /// The page of the link under a point in the band, if there is one.
    private func page(at point: NSPoint) -> URL? {
        linkRects.first { $0.rect.contains(point) }?.url
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
        tips += linkRects.map { addToolTip($0.rect, owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        if crossRect.contains(point) { return cornerHelp }
        if pickRect.contains(point) { return picked ? L("Unpick") : L("Pick") }
        if sendRect.contains(point) { return sendHelp }
        if let target = chat(at: point) {
            return String(format: hasQuestions && target.isAI ? L("Send to %@. Right-click to ask a question.") : L("Send to %@"),
                          target.name)
        }
        if isOnMore(point) {
            return String(format: L("More: %@"), ListFormatter.localizedString(byJoining: moreChats.map(\.name)))
        }
        if !lockHelp.isEmpty && lockRect.contains(point) { return lockHelp }
        // A link says where it leads, as a browser does.
        if let address = page(at: point) { return address.absoluteString }
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
        Guide.shared.happened(.photoMenu)
        return true
    }

    /// Holding ⌘ or ⇧ picks photos one by one, however fast you click.
    private func isPick(_ event: NSEvent) -> Bool {
        !event.modifierFlags.intersection([.command, .shift]).isEmpty
    }

    // MARK: Pointer

    /// Only the card and the chats' icons take the pointer, not the room
    /// between them below it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard stripHeight > 0 else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        if NSRect(x: 0, y: stripHeight, width: bounds.width, height: cardHeight).contains(local) {
            return super.hitTest(point)
        }
        return chatRects.contains { $0.contains(local) } ? self : nil
    }

    /// The whole view, the row under the card included, says when the pointer
    /// is over it, so the icons stay while it goes down to one.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
        followLock(event)
        followLink(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChange(true)
        followLock(event)
        followLink(event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
        onLockHover(false)
        if pointing {
            pointing = false
            NSCursor.arrow.set()
        }
    }

    /// Over the lock, the places covered light up on the photo. The photo
    /// keeps whether it is, so a line tucked away under the pointer starts
    /// afresh.
    private func followLock(_ event: NSEvent) {
        onLockHover(covered && lockRect.contains(convert(event.locationInWindow, from: nil)))
    }

    /// Over a link in the time band, the pointer is a hand, as over a link
    /// anywhere; the corners keep their buttons.
    private func followLink(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let over = page(at: point) != nil && !crossRect.contains(point) && !pickRect.contains(point)
        guard over != pointing else { return }
        pointing = over
        (over ? NSCursor.pointingHand : NSCursor.arrow).set()
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
        if isOnMore(point), !isPick(event) {
            downPoint = nil
            showMore()
            return
        }
        // On a link in the time band, a click opens its page instead.
        let link = isPick(event) ? nil : page(at: point)
        if event.clickCount == 2 && !isPick(event) {
            downPoint = nil
            // The first click opened the page; the second does no more.
            if link == nil { onDoubleClick() }
            return
        }
        pressedPage = link
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
            if isPick(event) {
                onPick()
            } else if event.clickCount == 1 {
                if event.modifierFlags.contains(.option), let onCrop {
                    onCrop()
                } else if let pressedPage {
                    onOpenPage(pressedPage)
                } else {
                    onClick()
                }
            }
        }
        downPoint = nil
        pressedPage = nil
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
        Guide.shared.happened(.photoMenu)
    }

    override func rightMouseDown(with event: NSEvent) {
        // On ChatGPT or Claude, the questions to ask with the photo.
        let point = convert(event.locationInWindow, from: nil)
        // On the ⋯, the rest of the chats, as a click lists them.
        let menu = isOnMore(point) ? moreMenu() : chat(at: point).flatMap(chatMenuProvider) ?? menuProvider()
        // The menu runs until it closes, and the line stays down meanwhile.
        GrabView.isShowingMenu = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        GrabView.isShowingMenu = false
        Guide.shared.happened(.photoMenu)
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
        GrabView.lastDragEnd = Date()
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
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: stripHeight, width: bounds.width, height: cardHeight)
        }
        let scale = min(bounds.width / size.width, cardHeight / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: stripHeight + (cardHeight - h) / 2, width: w, height: h)
    }
}

/// Where the links of a time band are on a picture that carries one, so a
/// click on the photo as it hangs follows them: each address's lines as a
/// strip across the band, from 0 to 1 of the picture from its top left.
struct BandLinks: Equatable {
    struct Strip: Equatable {
        var rect: CGRect
        var url: URL
    }

    /// The band on the picture.
    var band: CGRect
    var strips: [Strip]
    /// The picture's width over its height.
    var aspect: CGFloat

    /// The links of a band, in its pixels from its top left, where the band
    /// sits at `band` on a picture `canvas` pixels large; nil without any.
    static func make(_ links: [TimeStamp.Link], band: CGRect, canvas: CGSize) -> BandLinks? {
        guard canvas.width > 0, canvas.height > 0, band.width > 0, band.height > 0 else { return nil }
        // The lines of one address make one strip, the band's width.
        var rows: [(url: URL, top: CGFloat, bottom: CGFloat)] = []
        for link in links {
            let top = band.minY + link.rect.minY, bottom = band.minY + link.rect.maxY
            if let i = rows.firstIndex(where: { $0.url == link.url }) {
                rows[i].top = min(rows[i].top, top)
                rows[i].bottom = max(rows[i].bottom, bottom)
            } else {
                rows.append((url: link.url, top: top, bottom: bottom))
            }
        }
        guard !rows.isEmpty else { return nil }
        let place = CGRect(x: band.minX / canvas.width, y: band.minY / canvas.height,
                           width: band.width / canvas.width, height: band.height / canvas.height)
        let strips = rows.map { row in
            Strip(rect: CGRect(x: place.minX, y: row.top / canvas.height, width: place.width,
                               height: (row.bottom - row.top) / canvas.height), url: row.url)
        }
        return BandLinks(band: place, strips: strips, aspect: canvas.width / canvas.height)
    }

    /// A screenshot's band as the copy on the line has it (`Cover.covering`):
    /// above the picture as drawn on and cut to the part kept, then set on
    /// its backdrop, if it has one.
    static func screenshot(_ url: URL, _ mark: TimeStamp.Mark) -> BandLinks? {
        guard let size = uprightSize(of: url) else { return nil }
        let drawing = Drawings.saved(url)
        var width = size.width, height = size.height
        if !drawing.isEmpty, let crop = drawing.crop, let kept = Drawing.pixels(of: crop, width: width, height: height) {
            width = Int(kept.width)
            height = Int(kept.height)
        }
        return screenshot(mark, width: width, height: height, backdrop: drawing.backdrop)
    }

    /// The band drawn above a picture `width` × `height` pixels large, and
    /// the two set on a backdrop when there is one.
    static func screenshot(_ mark: TimeStamp.Mark, width: Int, height: Int, backdrop: Backdrop?) -> BandLinks? {
        guard width > 0, height > 0, let band = TimeStamp.band(mark, width: width), !band.links.isEmpty else { return nil }
        let stamped = CGSize(width: CGFloat(width), height: CGFloat(height + band.image.height))
        var canvas = stamped
        var origin = CGPoint.zero
        if let backdrop {
            // The backdrop places the picture from the bottom left.
            let layout = backdrop.layout(width: width, height: Int(stamped.height))
            canvas = layout.canvas
            origin = CGPoint(x: layout.picture.minX, y: layout.canvas.height - layout.picture.maxY)
        }
        let place = CGRect(origin: origin, size: CGSize(width: CGFloat(width), height: CGFloat(band.image.height)))
        return make(band.links, band: place, canvas: canvas)
    }

    /// A recording's band on its first picture, which the line shows: drawn
    /// into its pictures at their top, as wide as the video and as tall all
    /// through it (`VideoStamp`).
    static func recording(_ url: URL) async -> BandLinks? {
        guard VideoStamp.isDrawnIn(url), let stamp = VideoStamp.stamp(for: url),
              let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize) else { return nil }
        let width = Int(abs(natural.width).rounded()), height = Int(abs(natural.height).rounded())
        guard width > 0, height > 0,
              let band = TimeStamp.band(VideoStamp.mark(at: 0, of: stamp), width: width) else { return nil }
        let place = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(VideoStamp.bandHeight(stamp, width: width)))
        return make(band.links, band: place, canvas: CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

    /// A picture's size in pixels, the right way up.
    static func uprightSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        // Orientations 5 to 8 turn it on its side.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? (width: height, height: width) : (width: width, height: height)
    }

    /// Whether a photo this size shows the picture: the same shape, give or
    /// take the rounding of its pixels.
    func fits(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs(size.width / size.height - aspect) <= aspect * 0.015
    }

    /// Each strip on a photo drawn `photo` points large, from its top left,
    /// at least `least` points tall where the band has the room, so a band
    /// drawn small can still be clicked.
    func places(on photo: CGSize, least: CGFloat) -> [Strip] {
        let band = CGRect(x: self.band.minX * photo.width, y: self.band.minY * photo.height,
                          width: self.band.width * photo.width, height: self.band.height * photo.height)
        return strips.map { strip -> Strip in
            var rect = CGRect(x: strip.rect.minX * photo.width, y: strip.rect.minY * photo.height,
                              width: strip.rect.width * photo.width, height: strip.rect.height * photo.height)
            if rect.height < least {
                rect = rect.insetBy(dx: 0, dy: (rect.height - least) / 2)
                // Kept on the band.
                if rect.minY < band.minY { rect.origin.y = band.minY }
                if rect.maxY > band.maxY { rect.origin.y = band.maxY - rect.height }
                rect = rect.intersection(band)
            }
            return Strip(rect: rect, url: strip.url)
        }
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
            image = MenuSymbol.image(symbol)
        }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
