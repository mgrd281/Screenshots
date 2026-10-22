import Foundation

/// A PDF being put together from pages of other files: PDFs, photos, scans
/// and screenshots, in the order the owner gives them. Nothing of those
/// files is ever changed: each is copied in once as it came, and a page only
/// says which file and which of its pages it shows, and how far it is turned.
/// The project is kept on this iPhone, so it opens again where it was left,
/// and becomes a PDF only when it is saved or shared.
struct PDFProject: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let created: Date
    var modified: Date
    /// The files the pages come from, as they were copied in.
    var files: [ProjectFile]
    var pages: [ProjectPage]
    /// The page open in the editor when the project was left; nil while
    /// only the pages' overview was open.
    var openPage: UUID?
    /// How pictures sit on their pages in the PDF.
    var paper: PaperSize
    var quality: ExportQuality
    /// What kind of paper a picture shows, by its file, as its words told
    /// once it was added; kept apart from the pages, so undoing never forgets it.
    var kinds: [String: PaperKind]

    init(id: UUID = UUID(), name: String, created: Date = Date(), files: [ProjectFile] = [], pages: [ProjectPage] = []) {
        self.id = id
        self.name = name
        self.created = created
        modified = created
        self.files = files
        self.pages = pages
        openPage = nil
        paper = .original
        quality = .medium
        kinds = [:]
    }

    // A project written before a setting was added opens with its default.
    private enum CodingKeys: String, CodingKey {
        case id, name, created, modified, files, pages, openPage, paper, quality, kinds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        created = try values.decode(Date.self, forKey: .created)
        modified = try values.decodeIfPresent(Date.self, forKey: .modified) ?? created
        files = try values.decodeIfPresent([ProjectFile].self, forKey: .files) ?? []
        pages = try values.decodeIfPresent([ProjectPage].self, forKey: .pages) ?? []
        openPage = try values.decodeIfPresent(UUID.self, forKey: .openPage)
        paper = try values.decodeIfPresent(PaperSize.self, forKey: .paper) ?? .original
        quality = try values.decodeIfPresent(ExportQuality.self, forKey: .quality) ?? .medium
        kinds = try values.decodeIfPresent([String: PaperKind].self, forKey: .kinds) ?? [:]
    }

    func file(_ id: UUID) -> ProjectFile? { files.first { $0.id == id } }

    func index(of page: UUID) -> Int? { pages.firstIndex { $0.id == page } }

    /// Whether any page is a picture, so the PDF asks how pictures sit on their pages.
    var hasPictures: Bool {
        pages.contains { page in
            if case .picture = page.source { return true }
            return false
        }
    }

    /// Under a page in the overview: where it comes from, "Rechnung.pdf · S. 1",
    /// "Foto · Beleg", "Scan · Brief" or "Leere Seite".
    func label(of page: ProjectPage) -> String {
        switch page.source {
        case .pdf(let id, let index):
            let name = file(id)?.name ?? "PDF"
            return String(format: L("%@ · p. %d"), name, index + 1)
        case .picture(let id, let origin, let kind):
            let from: String
            switch origin {
            case .photo: from = L("Photo")
            case .scan: from = L("Scanned")
            case .screenshot: from = L("Screenshot")
            case .file: from = file(id)?.name ?? L("Picture")
            }
            guard let kind = kind ?? kinds[id.uuidString] else { return from }
            return from + " · " + kind.title
        case .blank:
            return L("Blank Page")
        }
    }

    // MARK: The pages

    /// Pages added, after the page at `index` or at the end.
    mutating func insert(_ new: [ProjectPage], at index: Int? = nil) {
        pages.insert(contentsOf: new, at: min(max(index ?? pages.count, 0), pages.count))
    }

    /// One page moved to another place, the others closing up round it.
    mutating func move(from: Int, to place: Int) {
        pages = ScanOrder.moving(pages, from: from, to: place)
    }

    /// Pages moved together, in their order, so the first of them stands at
    /// `place` among the pages that stay.
    mutating func move(_ ids: Set<UUID>, to place: Int) {
        let moving = pages.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        var staying = pages.filter { !ids.contains($0.id) }
        staying.insert(contentsOf: moving, at: min(max(place, 0), staying.count))
        pages = staying
    }

    /// Pages turned a quarter clockwise, or `quarters` of them; turned back
    /// with a negative number.
    mutating func turn(_ ids: Set<UUID>, by quarters: Int = 1) {
        for index in pages.indices where ids.contains(pages[index].id) {
            pages[index].turns = ((pages[index].turns + quarters) % 4 + 4) % 4
        }
    }

    /// A copy of each page right after it, turned as it is; the copies' ids.
    @discardableResult
    mutating func duplicate(_ ids: Set<UUID>) -> [UUID] {
        var made: [UUID] = []
        var result: [ProjectPage] = []
        for page in pages {
            result.append(page)
            guard ids.contains(page.id) else { continue }
            let copy = ProjectPage(source: page.source, turns: page.turns)
            result.append(copy)
            made.append(copy.id)
        }
        pages = result
        return made
    }

    mutating func remove(_ ids: Set<UUID>) {
        pages.removeAll { ids.contains($0.id) }
        if let open = openPage, ids.contains(open) { openPage = nil }
    }

    /// An empty page at `index`; its id.
    @discardableResult
    mutating func insertBlank(at index: Int, size: CGSize) -> UUID {
        let page = ProjectPage(source: .blank(width: Double(size.width), height: Double(size.height)))
        insert([page], at: index)
        return page.id
    }

    /// Only these pages, in the project's order, as for a PDF of the pages
    /// chosen; the files stay, so nothing is copied again.
    func only(_ ids: Set<UUID>) -> PDFProject {
        var part = self
        part.pages = pages.filter { ids.contains($0.id) }
        return part
    }

    /// The files no page shows any more.
    var unused: [ProjectFile] {
        let shown = Set(pages.compactMap(\.source.file))
        return files.filter { !shown.contains($0.id) }
    }
}

/// A file copied into a project as it came, which its pages show.
struct ProjectFile: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case pdf, picture
    }

    let id: UUID
    let kind: Kind
    /// The name it came with, as it shows under its pages: "Rechnung.pdf".
    let name: String
    /// Its copy's name in the project's folder.
    let stored: String
    /// How many pages it has: a picture has one.
    let pageCount: Int
    /// Its SHA-256 as it came, in hex, so it can be shown the copy was never changed.
    let digest: String

    init(id: UUID = UUID(), kind: Kind, name: String, stored: String, pageCount: Int, digest: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.stored = stored
        self.pageCount = pageCount
        self.digest = digest
    }

    /// The pages of a file, in their order, each upright.
    func pages(origin: PictureOrigin, kind paper: PaperKind? = nil) -> [ProjectPage] {
        switch kind {
        case .pdf: (0..<pageCount).map { ProjectPage(source: .pdf(file: id, index: $0)) }
        case .picture: [ProjectPage(source: .picture(file: id, origin: origin, kind: paper))]
        }
    }
}

/// A page of a project: which page of which file it shows, and how far it
/// is turned. Two pages may show the same page of the same file.
struct ProjectPage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var source: PageSource
    /// Quarter turns clockwise, from 0 to 3.
    var turns: Int

    init(id: UUID = UUID(), source: PageSource, turns: Int = 0) {
        self.id = id
        self.source = source
        self.turns = turns
    }
}

/// What a page shows.
enum PageSource: Codable, Equatable, Hashable, Sendable {
    /// A page of a PDF, counted from 0.
    case pdf(file: UUID, index: Int)
    /// A picture: where it came from, and what kind of paper it shows where that is known.
    case picture(file: UUID, origin: PictureOrigin, kind: PaperKind?)
    /// An empty white page of this size, in points.
    case blank(width: Double, height: Double)

    var file: UUID? {
        switch self {
        case .pdf(let file, _), .picture(let file, _, _): file
        case .blank: nil
        }
    }
}

/// Where a picture in a project came from, for the words under it.
enum PictureOrigin: String, Codable, Sendable {
    case photo, file, scan, screenshot
}

extension PaperKind: Codable {}

// MARK: Undo

/// The project's pages before each change, to go back to, and after each
/// change gone back from, to go forward to again. A new change forgets what
/// could be gone forward to.
struct ProjectHistory: Equatable, Sendable {
    private(set) var back: [[ProjectPage]] = []
    private(set) var forward: [[ProjectPage]] = []
    /// How many changes are kept to go back over.
    static let limit = 200

    var canUndo: Bool { !back.isEmpty }
    var canRedo: Bool { !forward.isEmpty }

    /// The pages as they were before a change.
    mutating func record(_ before: [ProjectPage]) {
        back.append(before)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward = []
    }

    /// The pages before the last change, given the pages now; nil with nothing to undo.
    mutating func undo(_ now: [ProjectPage]) -> [ProjectPage]? {
        guard let before = back.popLast() else { return nil }
        forward.append(now)
        return before
    }

    /// The pages after the change last undone; nil with nothing to redo.
    mutating func redo(_ now: [ProjectPage]) -> [ProjectPage]? {
        guard let after = forward.popLast() else { return nil }
        back.append(now)
        return after
    }

    mutating func clear() {
        back = []
        forward = []
    }
}

// MARK: Paper

/// How a picture sits on its page in the PDF: on a page of its own shape,
/// or on A4 or US Letter, turned as the picture is, with 10 mm round it.
/// It is never stretched and never cut.
enum PaperSize: String, Codable, CaseIterable, Sendable {
    case original, a4, letter

    static let a4Size = CGSize(width: 595.28, height: 841.89)
    static let letterSize = CGSize(width: 612, height: 792)
    /// 10 mm, in points.
    static let margin: CGFloat = 28.35

    var title: String {
        switch self {
        case .original: L("Original")
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    /// The page for a picture of this many pixels, and where on it the
    /// picture goes, in points from the bottom left. A page of the
    /// picture's own shape is as long as A4 on its longer side.
    func layout(width: Int, height: Int) -> (page: CGSize, picture: CGRect) {
        let across = CGFloat(max(width, 1)), down = CGFloat(max(height, 1))
        let lying = across > down
        switch self {
        case .original:
            let long = Self.a4Size.height
            let scale = long / max(across, down)
            let size = CGSize(width: across * scale, height: down * scale)
            return (size, CGRect(origin: .zero, size: size))
        case .a4, .letter:
            let upright = self == .a4 ? Self.a4Size : Self.letterSize
            let page = lying ? CGSize(width: upright.height, height: upright.width) : upright
            let room = CGRect(origin: .zero, size: page).insetBy(dx: Self.margin, dy: Self.margin)
            let scale = min(room.width / across, room.height / down)
            let shown = CGSize(width: across * scale, height: down * scale)
            let origin = CGPoint(x: room.midX - shown.width / 2, y: room.midY - shown.height / 2)
            return (page, CGRect(origin: origin, size: shown))
        }
    }

    /// The paper an empty page is made of where the owner lives: US Letter
    /// in the Americas that use it, A4 everywhere else.
    static func blank(region: String?) -> CGSize {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "GT", "CR", "PA", "DO", "PR"]
        if let region, letterRegions.contains(region.uppercased()) { return letterSize }
        return a4Size
    }
}

// MARK: Quality

/// How sharp the pages are drawn into the PDF, and so how large it is.
enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case high, medium, small

    var title: String {
        switch self {
        case .high: L("High")
        case .medium: L("Medium")
        case .small: L("Small")
        }
    }

    /// Dots an inch a page drawn as a picture has at most.
    var dpi: Double {
        switch self {
        case .high: 300
        case .medium: 200
        case .small: 150
        }
    }

    /// How finely a JPEG is kept.
    var jpeg: Double {
        switch self {
        case .high: 0.9
        case .medium: 0.75
        case .small: 0.6
        }
    }

    /// The pixels a picture of this many pixels is drawn with, to fill this
    /// many points at this quality: never more than it has, so nothing is
    /// made up, and never stretched.
    func pixels(width: Int, height: Int, filling points: CGSize) -> (width: Int, height: Int) {
        let wanted = Double(max(points.width, points.height)) / 72 * dpi
        let has = Double(max(width, height, 1))
        let scale = min(1, wanted / has)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// The pixels a page of this many points is drawn with at this quality.
    func pixels(for points: CGSize) -> (width: Int, height: Int) {
        let scale = dpi / 72
        return (max(1, Int((Double(points.width) * scale).rounded())), max(1, Int((Double(points.height) * scale).rounded())))
    }
}

// MARK: Its name and size

enum ProjectNaming {
    /// A new project's name: the first PDF's name without ".pdf", else the
    /// kind of the first page where it is known, else "Dokument" and the day.
    static func name(files: [ProjectFile], pages: [ProjectPage], at date: Date, calendar: Calendar = .current) -> String {
        if let first = files.first(where: { $0.kind == .pdf }) {
            let base = (first.name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty { return base }
        }
        if let first = pages.first, case .picture(_, _, let kind?) = first.source { return kind.title }
        let day = calendar.dateComponents([.day, .month, .year], from: date)
        let text = String(format: "%02d.%02d.%04d", day.day ?? 1, day.month ?? 1, day.year ?? 2026)
        return String(format: L("Document %@"), text)
    }

    /// "1 page", "6 pages".
    static func pages(_ count: Int) -> String {
        count == 1 ? L("1 page") : String(format: L("%d pages"), count)
    }
}

/// How large a PDF will be, from pages already made: what they hold on
/// average, for every page, plus what the file needs round them.
enum SizeEstimate {
    /// Bytes a PDF needs beyond its pages: its catalogue, its table, a font.
    static let overhead = 4_000

    /// From the bytes of some pages made, of `count` pages in all. Nil
    /// without any page made.
    static func bytes(sampled: [Int], count: Int) -> Int? {
        guard !sampled.isEmpty, count > 0 else { return nil }
        let average = Double(sampled.reduce(0, +)) / Double(sampled.count)
        return Int(average * Double(count)) + overhead
    }

    /// Which pages to make for the estimate: the first, the last and a few
    /// between, at most `most`.
    static func sample(count: Int, most: Int = 4) -> [Int] {
        guard count > 0 else { return [] }
        guard count > most else { return Array(0..<count) }
        let step = Double(count - 1) / Double(most - 1)
        return Array(Set((0..<most).map { Int((Double($0) * step).rounded()) })).sorted()
    }
}
