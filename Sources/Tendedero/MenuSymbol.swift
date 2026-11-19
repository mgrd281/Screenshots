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
    static let timer = "timer"
    static let wholePage = "rectangle.expand.vertical"
    static let wholeChat = "bubble.left.and.text.bubble.right"
    static let record = "record.circle"
    /// Stop Recording, Stop Capturing the Chat and Finish Guide, while each runs.
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

    static let all = [
        permissions, paste, showLine, hideLine, search, history, clear, screenshot, timer, wholePage, wholeChat,
        record, stop, cancel, guide, recentGuides, addFiles, coverFiles, folder, privacy, button, desktopIcons,
        settings, updates, help, introduction, quit,
    ]
}
