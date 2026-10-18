import Foundation

/// The Workspace: a folder of its own for screenshots, on the Desktop or
/// wherever the owner chooses, with a folder for each category inside. All
/// of it is plain Finder folders and files; Snapfly only decides where a new
/// file goes and moves what it is told to.
///
/// Only Foundation here, so the rules (what a folder may be called, what is
/// safe to touch, what deleting would affect) are checked without a screen.

// MARK: Categories and settings

struct WorkspaceCategory: Codable, Equatable, Identifiable, Sendable {
    /// Stays the same when the category is renamed.
    var id: String
    /// Also the name of its folder.
    var name: String
    /// Left out of the menus and the choices; its folder stays where it is.
    var hidden = false

    static let unsortedID = "unsorted"

    /// Where files go that have no reliable place, and what a removed
    /// category's files move to. It can be renamed or hidden, never removed.
    var isUnsorted: Bool { id == Self.unsortedID }
}

struct WorkspaceConfig: Codable, Equatable, Sendable {
    /// The folder's name.
    var name: String
    /// The folder it sits in; nil is the Desktop.
    var parent: String?
    /// In the order they are shown.
    var categories: [WorkspaceCategory]
    /// Where new screenshots go.
    var defaultID: String

    static let defaultName = "Snapfly"

    /// The categories at first, in their usual order, Unsorted last. The
    /// names are the user's language's, chosen by the caller.
    static func standard(name: String = defaultName, orders: String, customers: String, projects: String,
                         documents: String, other: String, unsorted: String) -> WorkspaceConfig {
        WorkspaceConfig(name: name, parent: nil, categories: [
            WorkspaceCategory(id: "orders", name: orders),
            WorkspaceCategory(id: "customers", name: customers),
            WorkspaceCategory(id: "projects", name: projects),
            WorkspaceCategory(id: "documents", name: documents),
            WorkspaceCategory(id: "other", name: other),
            WorkspaceCategory(id: WorkspaceCategory.unsortedID, name: unsorted),
        ], defaultID: WorkspaceCategory.unsortedID)
    }

    func category(_ id: String) -> WorkspaceCategory? {
        categories.first { $0.id == id }
    }

    /// The category new screenshots go to; Unsorted if the saved one is gone.
    var defaultCategory: WorkspaceCategory {
        category(defaultID) ?? category(WorkspaceCategory.unsortedID) ?? categories[0]
    }

    /// What the menus and choices offer.
    var visible: [WorkspaceCategory] { categories.filter { !$0.hidden } }

    // MARK: Changing it

    /// Adds a category at the end, named as asked, or with a number if the
    /// name is taken. Nil when there is no usable name.
    @discardableResult
    mutating func add(_ raw: String) -> WorkspaceCategory? {
        guard let name = WorkspaceNames.clean(raw) else { return nil }
        let category = WorkspaceCategory(id: WorkspaceNames.newID(),
                                         name: WorkspaceNames.unique(name, among: categories.map(\.name)))
        categories.append(category)
        return category
    }

    /// Renames a category. Nil when the name is not usable or another
    /// category has it; otherwise the old name, for the folder to follow.
    mutating func rename(_ id: String, to raw: String) -> String? {
        guard let index = categories.firstIndex(where: { $0.id == id }),
              let name = WorkspaceNames.clean(raw),
              WorkspaceNames.isFree(name, among: categories, except: id) else { return nil }
        let old = categories[index].name
        categories[index].name = name
        return old
    }

    /// Takes a category out; its files are the caller's to move first. The
    /// default falls back to Unsorted. Unsorted stays.
    @discardableResult
    mutating func remove(_ id: String) -> WorkspaceCategory? {
        guard let index = categories.firstIndex(where: { $0.id == id }), !categories[index].isUnsorted else { return nil }
        if defaultID == id { defaultID = WorkspaceCategory.unsortedID }
        return categories.remove(at: index)
    }

    /// Hides or shows a category. The one new screenshots go to stays shown.
    mutating func setHidden(_ id: String, _ hidden: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }), id != defaultID || !hidden else { return }
        categories[index].hidden = hidden
    }

    /// Moves a category up or down the list.
    mutating func move(_ id: String, by offset: Int) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard categories.indices.contains(target) else { return }
        categories.swapAt(index, target)
    }

    /// Makes a category the one new screenshots go to, and shows it.
    mutating func setDefault(_ id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].hidden = false
        defaultID = id
    }

    // MARK: Where things are

    /// The folder itself, on the Desktop unless a parent was chosen.
    func root(desktop: URL) -> URL {
        let base = parent.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? desktop
        return base.appendingPathComponent(name, isDirectory: true)
    }

    func folder(of category: WorkspaceCategory, root: URL) -> URL {
        root.appendingPathComponent(category.name, isDirectory: true)
    }

    /// The category a file sits in, by the folder directly under the
    /// workspace; nil for a file elsewhere.
    func category(containing url: URL, root: URL) -> WorkspaceCategory? {
        let below = WorkspaceGuard.components(url)
        let top = WorkspaceGuard.components(root)
        guard below.count > top.count + 1, Array(below.prefix(top.count)) == top else { return nil }
        let name = below[top.count]
        return categories.first { WorkspaceNames.same($0.name, name) }
    }
}

// MARK: Names

enum WorkspaceNames {
    /// A folder name stays short enough for any volume.
    static let longest = 60

    /// A name a folder can have and a person can read: no slash or colon
    /// (the Finder shows one as the other), no control characters, no
    /// leading dot that would hide it, spaces tidied. Nil when nothing is
    /// left.
    static func clean(_ raw: String) -> String? {
        var text = ""
        for character in raw {
            if character == "/" || character == ":" {
                text.append("-")
            } else if character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                text.append(" ")
            } else if character.isNewline {
                text.append(" ")
            } else {
                text.append(character)
            }
        }
        var words = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while words.first == "." { words.removeFirst() }
        words = words.trimmingCharacters(in: .whitespaces)
        if words.count > longest {
            words = String(words.prefix(longest)).trimmingCharacters(in: .whitespaces)
        }
        return words.isEmpty ? nil : words
    }

    /// Two names are one for a folder: the usual volume ignores case and
    /// accents' form.
    static func same(_ a: String, _ b: String) -> Bool {
        fold(a) == fold(b)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether no other category has the name.
    static func isFree(_ name: String, among categories: [WorkspaceCategory], except id: String? = nil) -> Bool {
        !categories.contains { $0.id != id && same($0.name, name) }
    }

    /// The name, or with a number after it when taken: "Orders 2".
    static func unique(_ name: String, among taken: [String]) -> String {
        var candidate = name
        var n = 2
        while taken.contains(where: { same($0, candidate) }) {
            candidate = "\(name) \(n)"
            n += 1
        }
        return candidate
    }

    static func newID() -> String {
        "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
}

// MARK: What is safe to touch

enum WorkspaceGuard {
    /// A path's parts with links followed, so a symbolic link can't lead
    /// out of the folder it sits in.
    static func components(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }

    /// Strictly inside the folder, not the folder itself.
    static func isInside(_ url: URL, of root: URL) -> Bool {
        let below = components(url), top = components(root)
        return below.count > top.count && Array(below.prefix(top.count)) == top
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// In the Trash, where a bookmark follows a folder that was deleted.
    static func isTrashed(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    /// A folder that may be a workspace root: not a link, not the top of a
    /// disk, and not the home folder, the Desktop or any other folder the
    /// system or the user keeps things in, nor above one of them.
    static func isSafeRoot(_ root: URL, protected: [URL]) -> Bool {
        guard !isSymbolicLink(root) else { return false }
        let parts = components(root)
        // "/", "Users", "name", at least one more.
        guard parts.count >= 4 else { return false }
        for place in protected {
            let held = components(place)
            if parts.count <= held.count, Array(held.prefix(parts.count)) == parts { return false }
        }
        return true
    }
}

// MARK: The marker

/// A small hidden file that says a folder is a workspace and which one, so
/// it is found again after a restart or an update, and so deleting never
/// touches a folder that is not one.
struct WorkspaceMarker: Codable, Equatable, Sendable {
    var id: UUID
    var created: Date

    static let fileName = ".snapfly-workspace"

    static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    static func read(in root: URL) -> WorkspaceMarker? {
        guard let data = try? Data(contentsOf: url(in: root)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkspaceMarker.self, from: data)
    }

    /// Writes the marker, keeping the one that is there.
    @discardableResult
    static func ensure(in root: URL, now: Date = Date()) throws -> WorkspaceMarker {
        if let known = read(in: root) { return known }
        let marker = WorkspaceMarker(id: UUID(), created: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: url(in: root), options: .atomic)
        return marker
    }
}

// MARK: Files

struct WorkspaceItem: Identifiable, Equatable, Sendable {
    var url: URL
    var size: Int64
    var date: Date
    var id: String { url.path }
}

enum WorkspaceFiles {
    /// What counts as a screenshot in a category folder: pictures, PDFs and
    /// screen recordings. Anything else in there is somebody's own.
    static let kinds: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "svg", "pdf", "mov", "mp4"]

    static func isManaged(_ url: URL) -> Bool {
        !url.lastPathComponent.hasPrefix(".") && kinds.contains(url.pathExtension.lowercased())
    }

    /// A name not taken in the folder: "name 2.png" when "name.png" is there.
    /// Nothing is ever overwritten.
    static func unique(_ name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var url = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// The screenshots directly in a folder, newest first.
    static func items(in folder: URL) -> [WorkspaceItem] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> WorkspaceItem? in
            guard isManaged(url), let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { return nil }
            return WorkspaceItem(url: url, size: Int64(values.fileSize ?? 0),
                                 date: values.creationDate ?? values.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    /// Everything else directly in a folder that a person would see: not
    /// ours to touch.
    static func others(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.filter { !isManaged($0) }
    }

    /// Where a file goes in another folder: its own name there, or
    /// numbered. Nil when it is already in that folder.
    static func destination(of file: URL, into folder: URL) -> URL? {
        if WorkspaceGuard.components(file.deletingLastPathComponent()) == WorkspaceGuard.components(folder) { return nil }
        return unique(file.lastPathComponent, in: folder)
    }

    /// Moves a file into a folder under a free name, and says where it
    /// went. A move, not a copy, so nothing is left behind and nothing is
    /// replaced.
    static func move(_ file: URL, into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let target = destination(of: file, into: folder) else { return file }
        try FileManager.default.moveItem(at: file, to: target)
        return target
    }
}

// MARK: Counting and removing

struct WorkspaceTally: Equatable, Sendable {
    var count = 0
    var bytes: Int64 = 0
}

enum WorkspaceStats {
    /// How many screenshots and how many bytes each category holds, by id.
    static func scan(_ config: WorkspaceConfig, root: URL) -> [String: WorkspaceTally] {
        var tallies: [String: WorkspaceTally] = [:]
        for category in config.categories {
            let items = WorkspaceFiles.items(in: config.folder(of: category, root: root))
            tallies[category.id] = WorkspaceTally(count: items.count, bytes: items.reduce(0) { $0 + $1.size })
        }
        return tallies
    }

    static func total(_ tallies: [String: WorkspaceTally]) -> WorkspaceTally {
        tallies.values.reduce(WorkspaceTally()) { WorkspaceTally(count: $0.count + $1.count, bytes: $0.bytes + $1.bytes) }
    }
}

/// What deleting a whole workspace would touch, worked out before anything
/// is: the screenshots to go to the Trash one by one, the empty folders to
/// follow, and what is left because it is not Snapfly's.
struct WorkspaceRemoval: Equatable, Sendable {
    var files: [URL] = []
    /// Category folders, then the workspace folder, each only once empty.
    var folders: [URL] = []
    /// Somebody's own files and folders inside; their presence keeps the
    /// folders they sit in.
    var left: [URL] = []

    var bytes: Int64 = 0

    static func plan(_ config: WorkspaceConfig, root: URL) -> WorkspaceRemoval {
        var plan = WorkspaceRemoval()
        let fm = FileManager.default
        let known = Set(config.categories.map { WorkspaceNames.fold($0.name) })
        for category in config.categories {
            let folder = config.folder(of: category, root: root)
            guard fm.fileExists(atPath: folder.path) else { continue }
            let items = WorkspaceFiles.items(in: folder)
            plan.files += items.map(\.url)
            plan.bytes += items.reduce(0) { $0 + $1.size }
            let others = WorkspaceFiles.others(in: folder)
            plan.left += others
            if others.isEmpty { plan.folders.append(folder) }
        }
        // What else sits in the workspace folder itself.
        let inRoot = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles])) ?? []
        let strangers = inRoot.filter { !known.contains(WorkspaceNames.fold($0.lastPathComponent)) }
        plan.left += strangers
        if plan.left.isEmpty { plan.folders.append(root) }
        return plan
    }
}

// MARK: Keeping the settings

enum WorkspaceStore {
    static let configKey = "workspaceConfig"
    static let enabledKey = "workspaceEnabled"
    static let bookmarkKey = "workspaceBookmark"

    static func load(_ defaults: UserDefaults = .standard) -> WorkspaceConfig? {
        guard let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(WorkspaceConfig.self, from: data),
              !config.categories.isEmpty else { return nil }
        return config
    }

    static func save(_ config: WorkspaceConfig, _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(config), forKey: configKey)
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: enabledKey)
    }
}

// MARK: Where the workspace is, for any thread

/// The folders Snapfly saves into, set by the workspace manager on the main
/// thread and read from any, because files are written off it.
enum WorkspaceLocation {
    private static let lock = NSLock()
    private static var current: (root: URL, landing: URL)?

    /// The workspace folder and the category folder new screenshots go to;
    /// nil while the workspace is off.
    static var value: (root: URL, landing: URL)? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    static func set(root: URL?, landing: URL?) {
        lock.lock()
        defer { lock.unlock() }
        current = root.flatMap { root in landing.map { (root, $0) } }
    }
}
