import AppKit

/// The Workspace, from Settings › Workspace: screenshots saved in a folder of
/// their own on the Desktop (or wherever it is put), with a folder for each
/// category inside. It is off until the owner turns it on, and turning it
/// off, or quitting, or uninstalling, never deletes a file.
///
/// Everything the system could make wait (the Desktop's consent question,
/// iCloud, a slow disk) is done off the main thread. Until the folder has
/// been checked, and whenever it can't be used, screenshots keep going to
/// Snapfly's own folder, so a capture is never lost to a missing folder.
///
/// The folder is followed where it goes: a bookmark finds it again when the
/// Finder renames or moves it, and the folder is only made again when it was
/// deleted. The direct edition only: the sandbox of the App Store edition
/// can't write to the Desktop.
@MainActor
final class Workspace: ObservableObject {
    static let shared = Workspace()

    enum Problem: Equatable {
        /// macOS didn't let Snapfly into the folder.
        case noAccess
        /// The disk has no room.
        case diskFull
        /// The place is one the workspace must not be in.
        case unsafe
        case cannotUse

        var message: String {
            switch self {
            case .noAccess:
                L("Snapfly can't open the workspace folder. Allow it under Files & Folders in System Settings › Privacy & Security.")
            case .diskFull:
                L("The disk is full. Free some space, then try again.")
            case .unsafe:
                L("The workspace can't be kept in this place. Choose another folder.")
            case .cannotUse:
                L("The workspace folder can't be used. Check that it is still there.")
            }
        }
    }

    /// Not offered in the App Store edition.
    nonisolated static var isAvailable: Bool { !Edition.appStore }

    @Published private(set) var config: WorkspaceConfig
    @Published private(set) var isOn: Bool
    /// The folder has been checked and is being used.
    @Published private(set) var isReady = false
    @Published private(set) var problem: Problem?
    @Published private(set) var tallies: [String: WorkspaceTally] = [:]
    @Published private(set) var busy = false

    /// The place screenshots go to changed: Snapfly points the Screenshot
    /// app there and watches it.
    var onChange: () -> Void = {}
    /// A photo's file moved, from the old place to the new one.
    var relocated: (URL, URL) -> Void = { _, _ in }
    /// A whole folder moved, with everything in it.
    var rebased: (URL, URL) -> Void = { _, _ in }
    /// Files went to the Trash, so the line forgets them.
    var removed: () -> Void = {}

    private let defaults = UserDefaults.standard
    private static let iconKey = "workspaceIconFor"
    private var watching: DispatchSourceFileSystemObject?
    private var settling: DispatchWorkItem?
    private var activation: NSObjectProtocol?

    private init() {
        config = WorkspaceStore.load() ?? Self.standardConfig()
        isOn = Self.isAvailable && WorkspaceStore.isEnabled()
    }

    static func standardConfig() -> WorkspaceConfig {
        .standard(orders: L("Orders"), customers: L("Customers"), projects: L("Projects"),
                  documents: L("Documents"), other: L("Other"), unsorted: L("Unsorted"))
    }

    // MARK: Where

    /// The user's real Desktop, wherever the system keeps it.
    static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    var root: URL { config.root(desktop: Self.desktop) }

    func folder(of category: WorkspaceCategory) -> URL { config.folder(of: category, root: root) }

    var landing: URL { folder(of: config.defaultCategory) }

    /// Folders the workspace must never be, or contain.
    nonisolated static var protectedPlaces: [URL] {
        let fm = FileManager.default
        var places = [fm.homeDirectoryForCurrentUser]
        for directory: FileManager.SearchPathDirectory in [.desktopDirectory, .documentDirectory, .downloadsDirectory,
                                                           .picturesDirectory, .moviesDirectory, .musicDirectory,
                                                           .libraryDirectory, .applicationDirectory] {
            places += fm.urls(for: directory, in: .userDomainMask)
        }
        return places
    }

    // MARK: Starting

    /// At launch: checks the folder in the background, and watches it.
    func start() {
        guard isOn else { return }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // A problem is tried again whenever Snapfly comes to the front,
            // after the owner has fixed it.
            MainActor.assumeIsolated { if self?.problem != nil { self?.settleSoon(after: 0) } }
        }
        settleSoon(after: 0)
        cleanPartials()
    }

    /// Tries the folder again, after the owner has fixed what was wrong.
    func retry() {
        guard isOn else { return }
        settleSoon(after: 0)
    }

    private func settleSoon(after delay: TimeInterval = 0.5) {
        settling?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { Workspace.shared.settle() } }
        settling = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// What checking the folder found.
    private struct Outcome: Sendable {
        var root: URL
        var adopted = false
        var bookmark: Data?
        var watch: Int32 = -1
        var problem: Problem?
        var needsIcon = false
    }

    /// Finds the folder, makes it and the folder new screenshots go to, writes
    /// the marker and a bookmark, and opens it to be watched. Off the main
    /// thread: the first time, macOS asks whether Snapfly may open the Desktop.
    private nonisolated static func prepare(_ config: WorkspaceConfig, expected: URL, bookmark: Data?,
                                            protected: [URL], iconFor: String?) -> Outcome {
        let fm = FileManager.default
        var root = expected
        var adopted = false
        // Where the folder is now, if the Finder renamed or moved it.
        if let bookmark {
            var stale = false
            if let found = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &stale) {
                var isDirectory: ObjCBool = false
                let there = found.standardizedFileURL
                if !WorkspaceGuard.isTrashed(there), fm.fileExists(atPath: there.path, isDirectory: &isDirectory),
                   isDirectory.boolValue, !WorkspaceGuard.isSymbolicLink(there),
                   WorkspaceMarker.read(in: there) != nil, there.path != expected.standardizedFileURL.path {
                    root = there
                    adopted = true
                }
            }
        }
        guard WorkspaceGuard.isSafeRoot(root, protected: protected) else {
            return Outcome(root: root, problem: .unsafe)
        }
        do {
            try fm.createDirectory(at: config.folder(of: config.defaultCategory, root: root),
                                   withIntermediateDirectories: true)
            try WorkspaceMarker.ensure(in: root)
            let data = try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let fd = open(root.path, O_EVTONLY)
            return Outcome(root: root, adopted: adopted, bookmark: data, watch: fd,
                           needsIcon: iconFor != root.standardizedFileURL.path)
        } catch {
            return Outcome(root: root, problem: problem(for: error))
        }
    }

    private nonisolated static func problem(for error: Error) -> Problem {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (ns.domain == NSPOSIXErrorDomain ? ns.code : nil)
        if ns.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return .noAccess }
        if posix == Int(EPERM) || posix == Int(EACCES) { return .noAccess }
        if posix == Int(ENOSPC) || ns.code == NSFileWriteOutOfSpaceError { return .diskFull }
        return .cannotUse
    }

    private func settle() {
        guard isOn else { return }
        let config = config, expected = root, protected = Self.protectedPlaces
        let bookmark = defaults.data(forKey: WorkspaceStore.bookmarkKey)
        let iconFor = defaults.string(forKey: Self.iconKey)
        Task { @MainActor in
            let outcome = await Task.detached(priority: .utility) {
                Self.prepare(config, expected: expected, bookmark: bookmark, protected: protected, iconFor: iconFor)
            }.value
            self.finish(outcome)
        }
    }

    private func finish(_ outcome: Outcome) {
        watching?.cancel()
        watching = nil
        guard isOn else {
            if outcome.watch >= 0 { close(outcome.watch) }
            return
        }
        if let found = outcome.problem {
            if outcome.watch >= 0 { close(outcome.watch) }
            let first = problem != found
            problem = found
            isReady = false
            // Until it can be used, screenshots keep going to Snapfly's own
            // folder.
            if publish() { onChange() }
            if first { Notice.show(found.message, lasting: 8) }
            return
        }
        problem = nil
        if outcome.adopted { adopt(outcome.root) }
        if let data = outcome.bookmark { defaults.set(data, forKey: WorkspaceStore.bookmarkKey) }
        if outcome.needsIcon {
            // Not applying it is not a problem: the folder is a folder.
            FolderIcon.apply(to: outcome.root)
            defaults.set(outcome.root.standardizedFileURL.path, forKey: Self.iconKey)
        }
        watch(outcome.watch)
        isReady = true
        if publish() { onChange() }
        refreshStats()
    }

    /// The Finder renamed or moved the folder: that is the new name and place.
    private func adopt(_ found: URL) {
        let parent = found.deletingLastPathComponent()
        let atDesktop = WorkspaceGuard.components(parent) == WorkspaceGuard.components(Self.desktop)
        var next = config
        next.name = WorkspaceNames.clean(found.lastPathComponent) ?? config.name
        next.parent = atDesktop ? nil : parent.standardizedFileURL.path
        update(next)
    }

    private func update(_ next: WorkspaceConfig) {
        config = next
        WorkspaceStore.save(next, defaults)
    }

    /// Where captures go, for every thread. Returns whether it changed.
    @discardableResult
    private func publish() -> Bool {
        let before = WorkspaceLocation.value?.landing.standardizedFileURL.path
        if isOn, isReady, problem == nil {
            WorkspaceLocation.set(root: root, landing: landing)
        } else {
            WorkspaceLocation.set(root: nil, landing: nil)
        }
        return before != WorkspaceLocation.value?.landing.standardizedFileURL.path
    }

    private func watch(_ fd: Int32) {
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.settleSoon() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watching = source
    }

    /// A write cut short leaves a hidden partial file behind; an hour old,
    /// it goes.
    private func cleanPartials() {
        let folder = landing
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [])) ?? []
            for file in files where file.lastPathComponent.hasPrefix(".") && file.pathExtension == "partial" {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let date, date.timeIntervalSinceNow < -3600 { try? fm.removeItem(at: file) }
            }
        }
    }

    // MARK: On and off

    func enable() {
        guard Self.isAvailable, !isOn else { return }
        isOn = true
        isReady = false
        problem = nil
        WorkspaceStore.setEnabled(true, defaults)
        if activation == nil { start() } else { settleSoon(after: 0) }
    }

    /// Stops saving into the workspace. Its folder and everything in it stay.
    func disable() {
        guard isOn else { return }
        let place = Folders.placeName(root)
        isOn = false
        isReady = false
        problem = nil
        WorkspaceStore.setEnabled(false, defaults)
        watching?.cancel()
        watching = nil
        settling?.cancel()
        if publish() { onChange() }
        Notice.show(String(format: L("The workspace is off. Your screenshots stay in %@."), place), done: true, lasting: 6)
    }

    // MARK: Looking

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([isOn ? root : landing])
    }

    func reveal(_ category: WorkspaceCategory) {
        let folder = folder(of: category)
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([root])
        }
    }

    /// How many screenshots and how much space each category holds.
    func refreshStats() {
        guard isOn, isReady else {
            tallies = [:]
            return
        }
        let config = config, root = root
        Task { @MainActor in
            let found = await Task.detached(priority: .utility) { WorkspaceStats.scan(config, root: root) }.value
            if self.isOn { self.tallies = found }
        }
    }

    // MARK: Categories

    func addCategory(_ name: String) {
        var next = config
        guard next.add(name) != nil else { return }
        update(next)
    }

    /// Renames a category and its folder. The Finder ignores case when it
    /// compares names, so a change of case goes by a temporary name.
    func renameCategory(_ id: String, to name: String) {
        var next = config
        guard let before = next.category(id), next.rename(id, to: name) != nil, let after = next.category(id) else {
            Notice.show(L("That name can't be used. Another folder may already have it."))
            objectWillChange.send()
            return
        }
        guard before.name != after.name else { return }
        let from = folder(of: before), to = config.folder(of: after, root: root)
        let fm = FileManager.default
        Task { @MainActor in
            do {
                if fm.fileExists(atPath: from.path) {
                    try await Task.detached { try Self.renameFolder(from, to: to) }.value
                }
                self.update(next)
                self.rebased(from, to)
                if self.publish() { self.onChange() }
            } catch {
                log.error("Could not rename a category folder: \(error.localizedDescription, privacy: .private)")
                Notice.show(L("Could not rename the folder."))
                self.objectWillChange.send()
            }
        }
    }

    private nonisolated static func renameFolder(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        if WorkspaceNames.same(from.lastPathComponent, to.lastPathComponent),
           from.deletingLastPathComponent().standardizedFileURL.path == to.deletingLastPathComponent().standardizedFileURL.path {
            let temporary = from.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
            try fm.moveItem(at: from, to: temporary)
            do { try fm.moveItem(at: temporary, to: to) } catch {
                try? fm.moveItem(at: temporary, to: from)
                throw error
            }
        } else {
            try fm.moveItem(at: from, to: to)
        }
    }

    /// Takes a category out. Its screenshots move to Unsorted first, nothing
    /// is deleted, and its folder goes to the Trash only when it is empty.
    func removeCategory(_ id: String) {
        var next = config
        guard let gone = next.remove(id), let unsorted = next.category(WorkspaceCategory.unsortedID) else { return }
        let from = folder(of: gone), to = config.folder(of: unsorted, root: root)
        Task { @MainActor in
            let moves: [(URL, URL)] = await Task.detached { () -> [(URL, URL)] in
                var done: [(URL, URL)] = []
                for item in WorkspaceFiles.items(in: from) {
                    if let target = try? WorkspaceFiles.move(item.url, into: to) { done.append((item.url, target)) }
                }
                if WorkspaceFiles.others(in: from).isEmpty, FileManager.default.fileExists(atPath: from.path) {
                    try? FileManager.default.trashItem(at: from, resultingItemURL: nil)
                }
                return done
            }.value
            for (old, new) in moves { self.relocated(old, new) }
            self.update(next)
            if self.publish() { self.onChange() }
            self.refreshStats()
            if !moves.isEmpty {
                Notice.show(String(format: L("%1$d screenshots moved to %2$@."), moves.count, unsorted.name), done: true)
            }
        }
    }

    func hideCategory(_ id: String, _ hidden: Bool) {
        var next = config
        next.setHidden(id, hidden)
        update(next)
    }

    func moveCategory(_ id: String, by offset: Int) {
        var next = config
        next.move(id, by: offset)
        update(next)
    }

    func setDefaultCategory(_ id: String) {
        var next = config
        next.setDefault(id)
        update(next)
        if publish() { onChange() }
    }

    /// Every category shown again, in the usual order, with Unsorted the one
    /// new screenshots go to. Names stay as they are, because the folders
    /// are named so.
    func restoreCategories() {
        var next = config
        let usual = Self.standardConfig().categories.map(\.id)
        let rank = { (id: String) -> Int in usual.firstIndex(of: id) ?? usual.count }
        next.categories = next.categories.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element.id), rank(b.element.id))
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
        for index in next.categories.indices { next.categories[index].hidden = false }
        next.defaultID = WorkspaceCategory.unsortedID
        update(next)
        if publish() { onChange() }
    }

    // MARK: Moving screenshots

    /// A screenshot, or several, into a category. Moves the files, never
    /// copies, and never replaces one with the same name. The line follows.
    func move(_ files: [URL], to id: String, completion: (() -> Void)? = nil) {
        guard isOn, let category = config.category(id) else { return }
        let folder = folder(of: category)
        Task { @MainActor in
            var moved = 0
            var failed = 0
            for file in files {
                let result: URL? = await Task.detached { () -> URL? in try? WorkspaceFiles.move(file, into: folder) }.value
                if let result {
                    if result != file { self.relocated(file, result); moved += 1 }
                } else {
                    failed += 1
                }
            }
            self.refreshStats()
            completion?()
            if failed > 0 {
                Notice.show(L("Could not move the screenshot."))
            } else if moved > 0 {
                Notice.show(String(format: L("Moved to %@."), category.name), done: true)
            }
        }
    }

    // MARK: Renaming and moving the workspace

    /// Renames the workspace's folder. Nothing is replaced: a folder of that
    /// name already there is a refusal.
    func rename(to raw: String) {
        guard isOn, let name = WorkspaceNames.clean(raw), name != config.name else { return }
        var next = config
        next.name = name
        let from = root, to = next.root(desktop: Self.desktop)
        let fm = FileManager.default
        if !WorkspaceNames.same(config.name, name), fm.fileExists(atPath: to.path) {
            Notice.show(String(format: L("A folder named “%@” is already there."), name))
            objectWillChange.send()
            return
        }
        Task { @MainActor in
            do {
                if fm.fileExists(atPath: from.path) {
                    try await Task.detached { try Self.renameFolder(from, to: to) }.value
                }
                self.update(next)
                self.rebased(from, to)
                if let data = try? to.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    self.defaults.set(data, forKey: WorkspaceStore.bookmarkKey)
                }
                if self.publish() { self.onChange() }
            } catch {
                log.error("Could not rename the workspace: \(error.localizedDescription, privacy: .private)")
                Notice.show(L("Could not rename the folder."))
                self.objectWillChange.send()
            }
        }
    }

    /// Asks where the workspace should be kept, then moves it there.
    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root.deletingLastPathComponent()
        panel.prompt = L("Choose")
        panel.message = String(format: L("Choose where to keep the workspace. The “%@” folder moves there."), config.name)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        move(to: parent)
    }

    /// Moves the whole folder to another place. Nothing already there is
    /// replaced, and nothing is changed if the move fails.
    func move(to parent: URL) {
        guard isOn else { return }
        var next = config
        let atDesktop = WorkspaceGuard.components(parent) == WorkspaceGuard.components(Self.desktop)
        next.parent = atDesktop ? nil : parent.standardizedFileURL.path
        let from = root, to = next.root(desktop: Self.desktop)
        guard WorkspaceGuard.components(from) != WorkspaceGuard.components(to) else { return }
        guard WorkspaceGuard.isSafeRoot(to, protected: Self.protectedPlaces),
              !WorkspaceGuard.isInside(to, of: from) else {
            Notice.show(Problem.unsafe.message)
            return
        }
        if FileManager.default.fileExists(atPath: to.path) {
            Notice.show(String(format: L("A folder named “%@” is already there."), next.name))
            return
        }
        busy = true
        Task { @MainActor in
            defer { self.busy = false }
            do {
                if FileManager.default.fileExists(atPath: from.path) {
                    try await Task.detached { try FileManager.default.moveItem(at: from, to: to) }.value
                }
                self.update(next)
                self.rebased(from, to)
                if let data = try? to.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    self.defaults.set(data, forKey: WorkspaceStore.bookmarkKey)
                }
                self.settleSoon(after: 0)
                Notice.show(String(format: L("The workspace is now in %@."), Folders.placeName(to)), done: true)
            } catch {
                log.error("Could not move the workspace: \(error.localizedDescription, privacy: .private)")
                Notice.show(L("Could not move the workspace. Nothing was changed."))
            }
        }
    }

    // MARK: Deleting the workspace

    /// Asks, naming what is affected, then moves the screenshots to the Trash
    /// one by one, so they can be put back. What is not Snapfly's, and the
    /// folders that hold it, stay. Then the workspace is off.
    func confirmDelete() {
        guard isOn else { return }
        let config = config, root = root, protected = Self.protectedPlaces
        Task { @MainActor in
            let plan: WorkspaceRemoval? = await Task.detached { () -> WorkspaceRemoval? in
                guard !WorkspaceGuard.isSymbolicLink(root), WorkspaceGuard.isSafeRoot(root, protected: protected),
                      WorkspaceMarker.read(in: root) != nil else { return nil }
                return WorkspaceRemoval.plan(config, root: root)
            }.value
            guard let plan else {
                Notice.show(L("This folder can't be deleted from Snapfly, because it isn't marked as its workspace."))
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Delete the workspace?")
            var lines: [String] = []
            if plan.files.isEmpty {
                lines.append(L("The workspace has no screenshots in it."))
            } else {
                lines.append(String(format: L("%1$d screenshots (%2$@) go to the Trash, so you can still put them back."),
                                    plan.files.count,
                                    ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file)))
            }
            if !plan.left.isEmpty {
                lines.append(String(format: L("%d other files or folders in it are not Snapfly's, so they stay, and so do the folders that hold them."),
                                    plan.left.count))
            }
            lines.append(L("The workspace is then turned off."))
            alert.informativeText = lines.joined(separator: " ")
            alert.addButton(withTitle: L("Move to Trash"))
            alert.addButton(withTitle: L("Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            if let icon = NSApp.applicationIconImage { alert.icon = icon }
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.delete(plan, root: root)
        }
    }

    private func delete(_ plan: WorkspaceRemoval, root: URL) {
        busy = true
        Task { @MainActor in
            defer { self.busy = false }
            let failed: Int = await Task.detached { () -> Int in
                let fm = FileManager.default
                var failed = 0
                for file in plan.files {
                    // Only what the plan found inside the folder, one file at a time.
                    guard WorkspaceGuard.isInside(file, of: root), !WorkspaceGuard.isSymbolicLink(file) else { failed += 1; continue }
                    do { try fm.trashItem(at: file, resultingItemURL: nil) } catch { failed += 1 }
                }
                // Folders last, and only while nothing but hidden files is in them.
                if failed == 0 {
                    for folder in plan.folders where fm.fileExists(atPath: folder.path) {
                        let visible = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
                        if visible.isEmpty { try? fm.trashItem(at: folder, resultingItemURL: nil) }
                    }
                }
                return failed
            }.value
            self.removed()
            self.disable()
            if failed > 0 {
                Notice.show(String(format: L("%d screenshots could not be moved to the Trash. They are still there."), failed))
            } else {
                Notice.show(L("The workspace was moved to the Trash."), done: true)
            }
        }
    }
}
