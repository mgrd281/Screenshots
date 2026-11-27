import AppKit

/// The symbols before the items of the menu bar's menu, one for each line,
/// shown on every macOS (DESIGN.md, "Menu bar menu"). All are in SF Symbols
/// on macOS 14, the oldest Snapfly runs on.
enum MenuSymbol {
    static let permissions = "exclamationmark.triangle"
    static let paste = "paperplane"
    static let showLine = "arrow.down.to.line"
    static let hideLine = "arrow.up.to.line"
    static let search = "magnifyingglass"
    static let history = "clock.arrow.circlepath"
    static let clear = "rectangle.stack.badge.minus"
    static let screenshot = "camera.viewfinder"
    /// Capture and Ask AI.
    static let ask = "questionmark.bubble"
    /// Copy Text from Screen.
    static let text = "text.viewfinder"
    static let timer = "timer"
    static let wholePage = "rectangle.expand.vertical"
    /// Capture Whole Page as PDF.
    static let wholePagePDF = "doc.richtext"
    static let wholeChat = "bubble.left.and.text.bubble.right"
    static let record = "record.circle"
    /// Stop Recording, Stop Capturing the Page, Stop Capturing the Chat and
    /// Finish Guide, while each runs.
    static let stop = "stop.circle"
    static let cancel = "xmark.circle"
    static let guide = "list.bullet.clipboard"
    static let recentGuides = "clock"
    static let addFiles = "plus.rectangle.on.folder"
    static let coverFiles = "lock.doc"
    static let folder = "folder"
    static let privacy = "hand.raised"
    static let button = "camera.circle"
    static let desktopIcons = "menubar.dock.rectangle"
    static let settings = "gearshape"
    static let updates = "arrow.triangle.2.circlepath"
    static let help = "questionmark.circle"
    static let introduction = "hand.wave"
    static let quit = "power"

    /// A symbol as a menu shows it before a line: drawn as a picture of its
    /// own, 18 × 16 points, in the menu's colour and white on the highlight.
    /// macOS 27 hides symbols in menus unless each item asks for them, and
    /// shows pictures, so a picture shows on every macOS.
    static func image(_ name: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) else { return nil }
        let image = NSImage(size: box, flipped: false) { rect in
            let size = symbol.size
            let scale = min(1, rect.width / max(size.width, 1), rect.height / max(size.height, 1))
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            symbol.draw(in: NSRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The room each symbol is drawn in, so the lines' words start together.
    static let box = NSSize(width: 18, height: 16)

    static let all = [
        permissions, paste, showLine, hideLine, search, history, clear, screenshot, ask, text, timer, wholePage, wholePagePDF,
        wholeChat, record, stop, cancel, guide, recentGuides, addFiles, coverFiles, folder, privacy, button, desktopIcons,
        settings, updates, help, introduction, quit,
    ]
}
