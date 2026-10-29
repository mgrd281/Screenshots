import Foundation

/// The keys pressed in another app's file dialog, its Open window, to
/// choose the photos sent to it: Go to Folder, the place typed in, then
/// Open. One photo is gone to by its own path; several by their folder,
/// and all of them picked there.
enum OpenPanelPlan {
    enum Step: Equatable {
        /// ⇧⌘G, Go to Folder.
        case goTo
        /// The words typed into the field Go to Folder shows.
        case type(String)
        /// Return: go there, or open what is chosen.
        case confirm
        /// ⌘A, every file in the folder.
        case selectAll
        /// A moment for the dialog to follow, in seconds.
        case wait(Double)
    }

    /// - Parameters:
    ///   - files: the full paths of the photos' copies.
    ///   - folder: the folder that holds them all.
    static func steps(for files: [String], in folder: String) -> [Step] {
        guard let first = files.first else { return [] }
        if files.count == 1 {
            return [.goTo, .wait(0.4), .type(first), .wait(0.2), .confirm, .wait(0.6), .confirm]
        }
        return [.goTo, .wait(0.4), .type(folder), .wait(0.2), .confirm, .wait(0.7), .selectAll, .wait(0.2), .confirm]
    }

    /// The copies' names in their folder, each once: a second "Bildschirmfoto.png"
    /// becomes "Bildschirmfoto 2.png".
    static func names(_ names: [String]) -> [String] {
        var taken = Set<String>()
        return names.map { name in
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var candidate = name
            var n = 2
            while taken.contains(candidate.lowercased()) {
                candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                n += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }

    /// Text as the key presses that type it: a few characters each, as
    /// macOS takes them, never splitting a character.
    static func chunks(of text: String, size: Int = 16) -> [[UInt16]] {
        var chunks: [[UInt16]] = [], current: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > size {
                chunks.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
