import AppKit
import AVFoundation
import Combine
import os

let log = Logger(subsystem: "de.ghazarian.Snapfly", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// Shown, and handed out, with private details covered.
    var covered = false
    /// Pinned: it stays when the line is cleared or full, until unpinned.
    var pinned = false
    /// A screen recording rather than a screenshot.
    var isRecording: Bool { Tendedero.isRecording(url) }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying && a.thumb === b.thumb
            && a.covered == b.covered && a.pinned == b.pinned
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedIDs: Set<UUID> = []
    /// Photos picked with ⌘-click, to copy together. Cleared when the line
    /// tucks away.
    @Published var pickedIDs: Set<UUID> = []
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false
    /// What the photos hang on, from Settings.
    @Published var style = Layout.style
    /// A card stack spread out, while the pointer is at it.
    @Published var spread = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]
    /// The tag at the end of the line, in the same coordinates. It catches
    /// clicks too.
    var tagRect = CGRect.null

    var maxItems = 8
    /// How many photos fit across the screen. With Keep on line set, the
    /// line can hold more, and the rest are reached by scrolling.
    var visibleCount = 8
    /// How far the line is scrolled towards older photos, in points; 0 shows
    /// the newest.
    @Published var scroll: CGFloat = 0

    /// Keep on line, from the menu bar: how many photos the line keeps, or
    /// nil for as many as fit across the screen.
    nonisolated static let keepChoices = [25, 50, 100]
    nonisolated static var keepOnLine: Int? {
        get {
            let n = UserDefaults.standard.integer(forKey: "keepOnLine")
            return keepChoices.contains(n) ? n : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "keepOnLine") }
    }


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"
    private let pinnedKey = "pinnedPhotos"

    init() {
        restore()
        trashWaiting()
        PrivateDetails.onRead = { [weak self] url, shown in self?.show(shown, for: url) }
        TextIndex.onRead = { [weak self] in self?.refreshSearch() }
        readPrivateDetails()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return nil }
        var item = Pegged(url: url, thumb: thumb)
        item.flying = flying
        items.append(item)
        scroll = 0
        // A full line lets the oldest photo fall off the far end. Only one: a
        // line hung on a wider screen keeps its length here instead of losing
        // several photos to a single capture.
        if liveCount > maxItems, let oldest = items.first(where: { !$0.falling && !$0.pinned }) {
            letGo(oldest.id)
        }
        save()
        PrivateDetails.prepare(url)
        TextIndex.read(url)
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    /// - Parameter falls: whether it falls over the screen. A photo sent
    ///   into a chat has flown there instead.
    func drop(_ id: UUID, quietly: Bool = false, falls: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        if falls { onFall?(items[i]) }
        items[i].falling = true
        hitRects[id] = nil
        pickedIDs.remove(id)
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    /// "Take everything down": every photo goes the way of its corner cross,
    /// but for the ones pinned.
    func clear() {
        takeDown(items.filter { !$0.falling && !$0.pinned })
    }

    /// The photos hung before (left) or after (right) this one, that would
    /// go with it: pinned ones stay.
    func neighbours(of id: UUID, toTheLeft: Bool) -> [Pegged] {
        let live = items.filter { !$0.falling }
        guard let i = live.firstIndex(where: { $0.id == id }) else { return [] }
        return (toTheLeft ? Array(live[..<i]) : Array(live[(i + 1)...])).filter { !$0.pinned }
    }

    /// Pins a photo to the line, or lets it go with the rest again.
    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        items[i].pinned.toggle()
        save()
    }

    /// Takes down everything on one side of a photo. Each one goes the way
    /// of its own corner button: to the Trash from Tendedero's folder, and
    /// only off the line from anywhere else.
    func takeDown(_ id: UUID, toTheLeft: Bool) {
        takeDown(neighbours(of: id, toTheLeft: toTheLeft))
    }

    /// One after another, and only the first makes a sound.
    private func takeDown(_ live: [Pegged]) {
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.discard(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        pickedIDs = []
        copy([item])
    }

    /// ⌘-click: picks the photo, or puts it back, and copies every photo
    /// picked, so they paste together into a chat or a message.
    func pick(_ id: UUID) {
        if pickedIDs.contains(id) { pickedIDs.remove(id) } else { pickedIDs.insert(id) }
        let picked = items.filter { pickedIDs.contains($0.id) && !$0.falling }
        if !picked.isEmpty { copy(picked) }
    }

    /// Every photo on the line, to paste them all at once.
    func copyAll() {
        pickedIDs = []
        copy(items.filter { !$0.falling })
    }

    /// What Combine joins: the photos picked, or every photo when fewer
    /// than two are. Recordings stay out of it.
    var photosToCombine: [Pegged] {
        let still = items.filter { !$0.falling && !$0.isRecording }
        let picked = still.filter { pickedIDs.contains($0.id) }
        return picked.count > 1 ? picked : still
    }

    /// Joins several photos into one image, which hangs as the newest and
    /// comes picked and copied, so the send button sends just that one.
    func combine(_ arrangement: Collage.Arrangement? = nil) {
        // Parts hidden by hand stay hidden in the joined image; the details
        // chosen in Settings are found again in it once it hangs.
        let photos = photosToCombine.map { ($0.url, PrivateDetails.hand($0.url)) }
        guard photos.count > 1 else { return }
        pickedIDs = []
        DispatchQueue.global(qos: .userInitiated).async {
            let urls = photos.map { url, hand in hand.isEmpty ? url : Cover.copy(of: url, [], hand: hand) ?? url }
            let joined = Collage.join(urls, arrangement)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let joined, let id = self.hang(joined) else {
                        NSSound.beep()
                        return
                    }
                    self.pick(id)
                }
            }
        }
    }

    /// The send button on the tag: the photos picked, or every photo when
    /// none is, go straight into the app in front, a chat for example.
    func paste() {
        let picked = items.filter { pickedIDs.contains($0.id) && !$0.falling }
        paste(picked.isEmpty ? items.filter { !$0.falling } : picked)
    }

    /// From a photo's menu: the photos picked when it is one of them, or
    /// only this one.
    func paste(_ id: UUID) {
        let picked = items.filter { pickedIDs.contains($0.id) && !$0.falling }
        if pickedIDs.contains(id) {
            paste(picked)
        } else if let item = items.first(where: { $0.id == id }) {
            paste([item])
        }
    }

    /// The send shortcut: the photos picked, or else the newest one.
    func pasteNewest() {
        let picked = items.filter { pickedIDs.contains($0.id) && !$0.falling }
        guard let newest = items.last(where: { !$0.falling }) else {
            NSSound.beep()
            return
        }
        paste(picked.isEmpty ? [newest] : picked)
    }

    /// Flies sent photos over to where they will land, and says how long
    /// until the last one does.
    var onSend: (([Pegged]) -> TimeInterval)?

    /// - Parameter caption: text to paste after the photos, like a
    ///   description in a chat.
    private func paste(_ photos: [Pegged], then caption: String? = nil) {
        guard !photos.isEmpty else { return }
        copy(photos)
        pickedIDs = []
        // Only when the paste will happen: a photo flying into a chat that
        // never gets it would say the opposite.
        let willPaste = Paste.willPaste
        let flight = willPaste ? onSend?(photos) ?? 0 : 0
        Paste.intoFrontApp(after: flight)
        if willPaste { takeDown(sent: photos, after: flight) }
        // Once the app has taken the photos, the clipboard turns to the text.
        guard let caption, willPaste else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + flight + 0.5) {
            MainActor.assumeIsolated { Self.pasteText(caption) }
        }
    }

    // MARK: Sent

    /// Take photos down once sent, from Settings. On unless turned off.
    nonisolated static var takesDownSent: Bool {
        get { !UserDefaults.standard.bool(forKey: "keepSent") }
        set { UserDefaults.standard.set(!newValue, forKey: "keepSent") }
    }

    /// Sent into a chat: the photos leave the line as their copies land in
    /// it, but for the ones pinned.
    private func takeDown(sent photos: [Pegged], after flight: TimeInterval) {
        guard Self.takesDownSent else { return }
        let ids = photos.filter { !$0.pinned }.map(\.id)
        // Their cards step aside while the copies fly.
        for id in ids {
            if let i = items.firstIndex(where: { $0.id == id && !$0.falling }) { items[i].flying = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flight + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                for id in ids { self?.leave(id) }
            }
        }
    }

    /// Dragged into an app, a photo has been sent too.
    func sentByDrag(_ id: UUID) {
        guard Self.takesDownSent, let item = items.first(where: { $0.id == id && !$0.falling }),
              !item.pinned else { return }
        leave(id)
    }

    /// Off the line without falling. A file from Snapfly's folder goes the
    /// way of its corner cross, to the Trash, but a minute later, so the
    /// chat has surely read it by then.
    private func leave(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id && !$0.falling }) else { return }
        if isInInbox(id) { trashLater(item.url) }
        drop(id, quietly: true, falls: false)
    }

    private static let trashLaterKey = "trashLater"

    /// Kept across a quit: what is still waiting goes at the next launch.
    private func trashLater(_ url: URL) {
        var waiting = UserDefaults.standard.stringArray(forKey: Self.trashLaterKey) ?? []
        waiting.append(url.path)
        UserDefaults.standard.set(waiting, forKey: Self.trashLaterKey)
        let path = url.path
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated { self?.trashWaiting(only: path) }
        }
    }

    /// One file, or at launch every one still waiting. A file that hangs on
    /// the line again stays.
    private func trashWaiting(only path: String? = nil) {
        let waiting = UserDefaults.standard.stringArray(forKey: Self.trashLaterKey) ?? []
        guard !waiting.isEmpty else { return }
        let hanging = Set(items.filter { !$0.falling }.map(\.url.path))
        let due = waiting.filter { path == nil || $0 == path }
        for file in due where !hanging.contains(file) && FileManager.default.fileExists(atPath: file) {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: file), resultingItemURL: nil)
        }
        UserDefaults.standard.set(waiting.filter { !due.contains($0) }, forKey: Self.trashLaterKey)
    }

    /// Text, like a translation, straight into the app in front.
    func sendText(_ text: String) {
        Self.pasteText(text)
    }

    private static func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Paste.intoFrontApp()
    }

    /// A photo with a line of text after it, as it goes in a chat.
    func send(_ id: UUID, caption: String) {
        guard let item = items.first(where: { $0.id == id && !$0.falling }) else {
            sendText(caption)
            return
        }
        paste([item], then: caption)
    }

    // MARK: Translate and Describe

    /// Where a photo hangs on screen, for the card that shows what it says.
    var frameOfPhoto: ((UUID) -> CGRect?)?

    func translate(_ id: UUID, to language: Locale.Language) {
        showCard(.translation, for: id, target: language)
    }

    func describe(_ id: UUID) {
        showCard(.description, for: id, target: Languages.own)
    }

    private func showCard(_ kind: TextCardModel.Kind, for id: UUID, target: Locale.Language) {
        guard let item = items.first(where: { $0.id == id && !$0.falling }), !item.isRecording else { return }
        let model = TextCardModel(kind, photo: id, url: item.url, line: self, target: target)
        TextCard.shared.show(model, under: frameOfPhoto?(id))
        model.start()
    }

    /// Each photo goes on the clipboard as an item of its own, as Finder
    /// copies several files, so apps paste them all, in the order they hang.
    private func copy(_ photos: [Pegged]) {
        let entries = photos.map { item -> NSPasteboardItem in
            let entry = NSPasteboardItem()
            // With Hide private details on, a copy with them covered.
            let url = PrivateDetails.shareable(item.url)
            // A recording is copied as the file, which apps paste as the video.
            if !item.isRecording, let png = pngData(url) { entry.setData(png, forType: .png) }
            entry.setString(url.absoluteString, forType: .fileURL)
            return entry
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(entries)
        showCopied(Set(photos.map(\.id)))
    }

    /// "Copied" under each photo, for a moment.
    private func showCopied(_ ids: Set<UUID>) {
        copiedIDs = ids
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedIDs == ids { self?.copiedIDs = [] }
        }
    }

    /// Copy Text: the words in a photo, read on this Mac, as text to paste
    /// anywhere. Private details chosen in Settings are left out, as they
    /// are from everything else that leaves the line.
    func copyText(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isRecording else { return }
        let url = item.url
        let chosen = PrivateDetails.details
        let hand = PrivateDetails.hand(url)
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Finder.text(of: url, hiding: chosen, hand: hand)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !text.isEmpty else {
                        NSSound.beep()
                        return
                    }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    self.pickedIDs = []
                    self.showCopied([id])
                }
            }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    @discardableResult
    func trash(_ id: UUID, quietly: Bool = false) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            drop(id, quietly: true)
            return true
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !quietly { NSSound.beep() }
            return false
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Tendedero's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID, quietly: Bool = false) {
        // Already on its way down, from a second click on the tag's trash.
        guard items.contains(where: { $0.id == id && !$0.falling }) else { return }
        if isInInbox(id) { trash(id, quietly: quietly) } else { drop(id, quietly: quietly) }
    }

    /// The oldest photo falling off a full line. Like the cross, a file from
    /// Tendedero's folder goes to the Trash, or nothing would ever take it out
    /// of that folder. If the Trash refuses it, it still leaves the line.
    /// Moves along a line that holds more than fit, from a scroll gesture.
    func scroll(by delta: CGFloat) {
        let most = CGFloat(max(0, items.count - visibleCount)) * Layout.spacing
        let next = min(most, max(0, scroll + delta))
        if next != scroll { scroll = next }
    }

    /// After Keep on line is lowered, the oldest photos past it go the way
    /// of a full line.
    func trim() {
        while liveCount > maxItems, let oldest = items.first(where: { !$0.falling && !$0.pinned }) {
            letGo(oldest.id)
        }
        scroll = 0
    }

    private func letGo(_ id: UUID) {
        if isInInbox(id), trash(id, quietly: true) { return }
        drop(id, quietly: true)
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor. Markup does
    /// not edit video, so a recording opens in the trimming editor instead.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isRecording {
            Trim.shared.edit(item.url, size: item.thumb.size)
        } else {
            Markup.shared.edit(item.url)
        }
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
        PrivateDetails.prepare(url)
        TextIndex.read(url)
    }

    // MARK: Search

    /// Opens the search bar under the line, from the tag.
    var onSearch: (() -> Void)?
    /// The search bar under the line is open.
    @Published private(set) var isSearching = false
    /// While something is typed: the photos that say every word of it, each
    /// with where it says them, from 0 to 1 from the bottom left. Nil shows
    /// every photo as usual.
    @Published private(set) var found: [UUID: [CGRect]]?
    /// Photos not read yet, so the search may still find more.
    @Published private(set) var stillReading = 0
    private var query = ""

    func beginSearch() {
        isSearching = true
        refreshSearch()
    }

    func search(_ text: String) {
        query = text
        refreshSearch()
    }

    func endSearch() {
        isSearching = false
        query = ""
        found = nil
        stillReading = 0
    }

    /// Return in the search bar: what was found is picked, and copied, ready
    /// for the send or combine button.
    func pickFound() {
        guard let found, !found.isEmpty else { return }
        let picked = items.filter { found[$0.id] != nil && !$0.falling }
        pickedIDs = Set(picked.map(\.id))
        copy(picked)
    }

    private func refreshSearch() {
        guard isSearching else { return }
        let terms = TextIndex.fold(query).split(whereSeparator: \.isWhitespace).map { String($0) }
        var result: [UUID: [CGRect]] = [:]
        var waiting = 0
        for item in items where !item.falling && !item.isRecording {
            guard let rows = TextIndex.rows(for: item.url) else {
                waiting += 1
                TextIndex.read(item.url)
                continue
            }
            if !terms.isEmpty, let places = Self.places(of: terms, in: rows) { result[item.id] = places }
        }
        stillReading = waiting
        found = terms.isEmpty ? nil : result
        // A long line scrolls to the newest photo found.
        if let newest = items.lastIndex(where: { result[$0.id] != nil }) { scrollToShow(newest) }
    }

    /// Where each word is said, roughly, or nil when one of them is not.
    private static func places(of terms: [String], in rows: [TextIndex.Row]) -> [CGRect]? {
        var places: [CGRect] = []
        for term in terms {
            var said = false
            for row in rows {
                let text = row.folded
                let length = CGFloat(max(text.count, 1))
                var from = text.startIndex
                while from < text.endIndex, let match = text.range(of: term, range: from..<text.endIndex) {
                    said = true
                    let start = CGFloat(text.distance(from: text.startIndex, to: match.lowerBound))
                    let count = CGFloat(text.distance(from: match.lowerBound, to: match.upperBound))
                    places.append(CGRect(x: row.box.minX + row.box.width * start / length, y: row.box.minY,
                                         width: row.box.width * count / length, height: row.box.height))
                    from = match.upperBound
                }
            }
            if !said { return nil }
        }
        return places
    }

    /// On a line longer than the screen, brings a photo to the middle.
    private func scrollToShow(_ index: Int) {
        guard Line.keepOnLine != nil, items.count > visibleCount else { return }
        let most = CGFloat(items.count - visibleCount) * Layout.spacing
        let centred = CGFloat(items.count - 1 - index) * Layout.spacing - CGFloat(visibleCount - 1) * Layout.spacing / 2
        scroll = min(most, max(0, centred))
    }

    /// With Hide private details on, every photo is read ahead of time, so
    /// copying one stays instant. Off, they show as they are again, but for
    /// parts hidden by hand.
    func readPrivateDetails() {
        for item in items where !item.falling { cover(item.url) }
    }

    /// Hide Part: a box drawn over anything that should not leave the line.
    func hidePart(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isRecording else { return }
        let url = item.url
        HideEditor.shared.edit(url) { [weak self] in self?.cover(url) }
    }

    private func cover(_ url: URL) {
        if PrivateDetails.covers(url) {
            PrivateDetails.prepare(url)
        } else if items.contains(where: { $0.url == url && $0.covered }) {
            show(url, for: url)
        }
    }

    /// Quick Look on this photo, with the rest of the line a key press away.
    func quickLook(_ id: UUID) {
        let live = items.filter { !$0.falling }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        QuickLook.shared.show(live.map(\.url), at: index)
    }

    /// After a change of size, every photo is redrawn sharp at the new one.
    func reloadThumbnails() {
        for i in items.indices where !items[i].falling {
            let shown = PrivateDetails.shown(items[i].url) ?? items[i].url
            if let thumb = makeThumbnail(shown) { items[i].thumb = thumb }
            items[i].covered = shown != items[i].url
        }
    }

    /// Each photo hangs as it will leave the line: with its private details
    /// covered, or as it is when the latest choice leaves nothing to cover.
    private func show(_ shown: URL, for url: URL) {
        guard shown == url || PrivateDetails.covers(url),
              let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(shown) else { return }
        items[i].thumb = thumb
        items[i].covered = shown != url
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let live = items.filter { !$0.falling }
        let paths = live.map(\.url.path)
        UserDefaults.standard.set(paths, forKey: storeKey)
        UserDefaults.standard.set(live.filter(\.pinned).map(\.url.path), forKey: pinnedKey)
        PrivateDetails.keepHand(only: Set(paths))
        TextIndex.keep(only: Set(paths))
    }

    /// Everything comes back as it was. This runs before the line knows its
    /// screen, so the capacity is still the default one: hanging through
    /// `hang` would let photos fall off a wide screen's line at every launch.
    private func restore() {
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        let pinned = Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard !items.contains(where: { $0.url == url }), let thumb = makeThumbnail(url) else { continue }
            var item = Pegged(url: url, thumb: thumb)
            item.pinned = pinned.contains(path)
            items.append(item)
            TextIndex.read(url)
        }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Screen recordings, as macOS saves them.
func isRecording(_ url: URL) -> Bool {
    ["mov", "mp4"].contains(url.pathExtension.lowercased())
}

/// The default size covers a card at twice its size in points, as on a
/// Retina screen, and no more: every photo on the line keeps one in memory.
func makeThumbnail(_ url: URL, maxPixels: Int = Int(320 * Layout.size.scale)) -> NSImage? {
    if isRecording(url) { return firstFrame(url, maxPixels: maxPixels) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A recording shows its first frame.
private func firstFrame(_ url: URL, maxPixels: Int) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
