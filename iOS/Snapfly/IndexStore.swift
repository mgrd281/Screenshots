import CryptoKit
import Foundation

/// Where the photos prepared ahead of time are kept: in the app's own
/// folder on this iPhone, left out of backups, each photo's lines in a file
/// of its own that iOS keeps locked while the iPhone is, once it is closed.
/// A list without the text says what is there, so what is left to do is
/// known without opening a photo's file. Deleted whole when the owner asks.
actor IndexStore {
    static let shared = IndexStore()

    private let folder: URL
    private var manifest: IndexManifest?

    init(folder: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? base.appendingPathComponent("Prepared", isDirectory: true)
    }

    // MARK: Reading

    /// What the index holds, without the text.
    func list() -> IndexManifest {
        if let manifest { return manifest }
        let read = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(IndexManifest.self, from: $0) }
        manifest = read ?? IndexManifest()
        return manifest!
    }

    /// A photo as it was prepared, if it was; nil while the iPhone is locked.
    func photo(_ id: String) -> IndexedPhoto? {
        guard list().entries[id]?.status == .ready, let data = try? Data(contentsOf: url(of: id)) else { return nil }
        return try? JSONDecoder().decode(IndexedPhoto.self, from: data)
    }

    /// Those of these photos that were prepared, by their identifier, asked
    /// for at once, as See All does for every screenshot.
    func photos(_ ids: [String]) -> [String: IndexedPhoto] {
        var found: [String: IndexedPhoto] = [:]
        for id in ids {
            if let photo = photo(id) { found[id] = photo }
        }
        return found
    }

    // MARK: Writing

    /// Keeps a photo as prepared. Written even while the iPhone is locked;
    /// readable again only once it is unlocked.
    func keep(_ photo: IndexedPhoto) throws {
        try makeFolder()
        var bytes = 0
        if photo.status == .ready {
            let data = try JSONEncoder().encode(photo)
            try data.write(to: url(of: photo.id), options: [.atomic, .completeFileProtectionUnlessOpen])
            bytes = data.count
        } else {
            try? FileManager.default.removeItem(at: url(of: photo.id))
        }
        var manifest = list()
        manifest.note(photo, bytes: bytes)
        try save(manifest)
    }

    /// Forgets these photos.
    func forget(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var manifest = list()
        for id in ids {
            try? FileManager.default.removeItem(at: url(of: id))
            manifest.entries[id] = nil
        }
        try? save(manifest)
    }

    /// Deletes everything prepared, and the folder with it.
    func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
        manifest = IndexManifest()
    }

    // MARK: Files

    private var manifestURL: URL { folder.appendingPathComponent("list.json") }

    /// A photo's file, named by a hash of its identifier.
    private func url(of id: String) -> URL {
        let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name + ".json")
    }

    private func save(_ manifest: IndexManifest) throws {
        self.manifest = manifest
        try makeFolder()
        try JSONEncoder().encode(manifest).write(to: manifestURL,
                                                 options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func makeFolder() throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try excluded.setResourceValues(values)
    }
}
