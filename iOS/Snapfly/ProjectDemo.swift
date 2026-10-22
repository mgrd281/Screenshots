import Foundation

/// A made-up PDF project for pictures made in CI (`scripts/pdf-checks.sh`)
/// and the UI tests, as `-SnapflyProject` asks: a three-page invoice with
/// real text and two photos, a narrow receipt and a page lying sideways
/// (overview); with two pages chosen (select); a page just deleted, with
/// Undo (deleted); its first page in the editor (editor); Save and Share
/// (export), without covers (uncovered); 300 pages (long); a PDF locked
/// with a password (locked); a signed PDF (signed); nothing added yet
/// (empty); or the Scan tab with the project among the recent ones (tab).
/// Everything on them is made up (`PDFFixtures`). Nothing of it is in a
/// release build.
enum ProjectDemo {
    #if DEBUG
    static let state: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SnapflyProject"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var requested: Bool { state != nil }
    static var showsTab: Bool { state == "tab" }
    static var selects: Bool { state == "select" }
    static var opensExport: Bool { state == "export" || state == "uncovered" }
    static var uncovered: Bool { state == "uncovered" }

    /// The made-up files written where the app keeps what is temporary, then added as a file from Files would be.
    @MainActor static func start(_ store: ProjectStore) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Made-up files", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func file(_ data: Data, _ name: String) -> URL {
            let url = folder.appendingPathComponent(name)
            try? data.write(to: url)
            return url
        }
        store.start()
        Task {
            switch state {
            case "empty":
                return
            case "long":
                await store.add(.files([file(PDFFixtures.long(), "Protokoll.pdf")]))
            case "locked":
                await store.add(.files([file(PDFFixtures.locked(), "Kontoauszug.pdf")]))
            case "signed":
                await store.add(.files([file(PDFFixtures.signed(), "Mietvertrag.pdf")]))
            default:
                await store.add(.files([file(PDFFixtures.invoice(), "Rechnung.pdf")]))
                let photos = [PDFFixtures.receipt(), PDFFixtures.sideways()].compactMap { $0 }
                await store.add(.pictures(photos, origin: .photo))
            }
            store.rename(state == "long" ? "Protokoll" : state == "signed" ? "Mietvertrag" : "Rechnung März")
            let pages = store.project?.pages ?? []
            switch state {
            case "deleted":
                if pages.count > 1 { store.delete([pages[1].id]) }
            case "editor":
                store.setOpenPage(pages.first?.id)
            case "tab":
                store.close()
            default:
                break
            }
        }
    }
    #else
    static let requested = false
    static let showsTab = false
    static let selects = false
    static let opensExport = false
    static let uncovered = false
    @MainActor static func start(_ store: ProjectStore) {}
    #endif
}
