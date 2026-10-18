import Foundation

/// Step-by-step guides, recorded from the clicks themselves: each click is a
/// step, with a screenshot of the moment, where the click went and what it
/// went on, and a sentence saying what to do. A guide is kept in Snapfly's
/// own folder while it is worked on, and whatever leaves it is covered like
/// any screenshot.
///
/// Only Foundation here: what a step says, which part of the screen it shows
/// and how steps share pages are worked out without a screen.
struct HowToGuide: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var created = Date()
    var steps: [HowToStep] = []
}

struct HowToStep: Codable, Equatable, Identifiable {
    enum Click: String, Codable, Sendable {
        case single, double, right
    }

    var id = UUID()
    /// What to do, in a sentence; it can be written again.
    var text: String
    var click = Click.single
    /// The screenshot, a file in the guide's folder.
    var file: String
    /// Its size in pixels.
    var width: Int
    var height: Int
    /// Where the click went, from 0 to 1 from the screenshot's top left.
    var point: CGPoint
    /// What it went on, the same way; nil when the app didn't say.
    var target: CGRect?
    /// The app it was in.
    var app: String?
    /// Shows the part around the click; off, the whole screen.
    var focused = true
}

// MARK: What a step says

enum HowToWording {
    /// What was clicked, as Accessibility names it.
    struct Element: Equatable, Sendable {
        var role: String?
        var subrole: String?
        var name: String?
    }

    /// The things a click goes on, each said its own way.
    enum Kind: Equatable {
        case control, menuItem, menuBarItem, link, field, tab, dockItem, content
    }

    static func kind(role: String?, subrole: String?) -> Kind {
        if subrole == "AXTabButton" { return .tab }
        if subrole == "AXSearchField" || subrole == "AXSecureTextField" { return .field }
        switch role {
        case "AXMenuItem": return .menuItem
        case "AXMenuBarItem", "AXMenuExtra": return .menuBarItem
        case "AXLink": return .link
        case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField": return .field
        case "AXDockItem": return .dockItem
        case "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle",
             "AXSlider", "AXIncrementor", "AXColorWell", "AXSegmentedControl":
            return .control
        default: return .content
        }
    }

    /// Longer names are cut, at a word, so a sentence stays a sentence.
    static let longestName = 48

    /// The name to put in the sentence, or nil to leave it out: nothing
    /// private, as `isPrivate` judges, and for what a page shows rather
    /// than a control, nothing with three digits or more, like an amount or
    /// an order's number.
    static func usableName(_ name: String?, kind: Kind, isPrivate: (String) -> Bool) -> String? {
        guard let name else { return nil }
        let words = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var said = words.joined(separator: " ")
        guard !said.isEmpty else { return nil }
        if said.count > longestName {
            var cut = ""
            for word in words {
                let next = cut.isEmpty ? String(word) : cut + " " + word
                if next.count > longestName - 1 { break }
                cut = next
            }
            guard !cut.isEmpty else { return nil }
            said = cut + "…"
        }
        if kind == .content || kind == .link, said.filter(\.isNumber).count >= 3 { return nil }
        return isPrivate(said) ? nil : said
    }

    /// The sentence for a click, from what it went on.
    static func sentence(_ click: HowToStep.Click, on element: Element?, isPrivate: (String) -> Bool) -> String {
        let kind = kind(role: element?.role, subrole: element?.subrole)
        let name = usableName(element?.name, kind: kind, isPrivate: isPrivate)
        switch click {
        case .double:
            return name.map { String(format: L("Double-click “%@”."), $0) } ?? L("Double-click here.")
        case .right:
            return name.map { String(format: L("Right-click “%@”."), $0) } ?? L("Right-click here.")
        case .single:
            break
        }
        guard let name else {
            switch kind {
            case .field: return L("Click the field.")
            case .link: return L("Click the link.")
            default: return L("Click here.")
            }
        }
        switch kind {
        case .menuItem: return String(format: L("Choose “%@”."), name)
        case .menuBarItem: return String(format: L("Open the “%@” menu."), name)
        case .link: return String(format: L("Click the “%@” link."), name)
        case .field: return String(format: L("Click the “%@” field."), name)
        case .tab: return String(format: L("Open the “%@” tab."), name)
        case .dockItem: return String(format: L("Open “%@” in the Dock."), name)
        case .control, .content: return String(format: L("Click “%@”."), name)
        }
    }
}

// MARK: What a step shows

enum HowToFrame {
    /// The whole picture, from 0 to 1.
    static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// How much of the screen's width a step shows around its click, at least.
    static let focusShare: CGFloat = 0.6
    /// Wide like a screen.
    static let focusAspect: CGFloat = 1.6

    /// What was clicked, when it is worth marking: holding the click, and
    /// smaller than a quarter of the screen, so a whole page or window is
    /// left out.
    static func target(of step: HowToStep) -> CGRect? {
        guard let target = step.target, target.width > 0, target.height > 0,
              target.width * target.height < 0.25,
              target.insetBy(dx: -0.01, dy: -0.01).contains(step.point) else { return nil }
        return target
    }

    /// The part of the screenshot a step shows, from 0 to 1 from the top
    /// left: around what was clicked, with room round it and never past the
    /// picture's edges; all of it when that is nearly all of it anyway.
    static func focus(of step: HowToStep) -> CGRect {
        guard step.focused, step.width > 0, step.height > 0 else { return whole }
        let width = CGFloat(step.width), height = CGFloat(step.height)
        let thing = target(of: step).map {
            CGRect(x: $0.minX * width, y: $0.minY * height, width: $0.width * width, height: $0.height * height)
        }
        var across = width * focusShare
        if let thing {
            across = max(across, thing.width + 0.12 * width, (thing.height + 0.12 * height) * focusAspect)
        }
        let down = across / focusAspect
        guard across < width * 0.92, down < height * 0.92 else { return whole }
        let middle = thing.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: step.point.x * width, y: step.point.y * height)
        let x = min(max(0, middle.x - across / 2), width - across)
        let y = min(max(0, middle.y - down / 2), height - down)
        return CGRect(x: x / width, y: y / height, width: across / width, height: down / height)
    }

    /// What a step marks in its picture.
    enum Mark: Equatable {
        /// A box around what was clicked.
        case box(CGRect)
        /// A ring where the click went.
        case ring(center: CGPoint, radius: CGFloat)
    }

    /// What a step marks, in the pixels of the part it shows, from that
    /// part's top left. Sized from the whole screenshot, so every step's mark
    /// weighs the same.
    static func mark(of step: HowToStep, in part: CGRect) -> Mark {
        let width = CGFloat(step.width), height = CGFloat(step.height)
        let unit = max((width * height).squareRoot(), 640)
        let origin = CGPoint(x: part.minX * width, y: part.minY * height)
        if let target = target(of: step) {
            let pad = unit * 0.006
            return .box(CGRect(x: target.minX * width - origin.x - pad, y: target.minY * height - origin.y - pad,
                               width: target.width * width + 2 * pad, height: target.height * height + 2 * pad))
        }
        return .ring(center: CGPoint(x: step.point.x * width - origin.x, y: step.point.y * height - origin.y),
                     radius: unit * 0.024)
    }
}

// MARK: Pages

enum HowToPages {
    /// Steps laid out on pages, by their heights: in order, each step whole
    /// on one page, and a new page when the next one doesn't fit. The first
    /// page has less room, under the title. A step alone on a page that is
    /// still too tall for it is drawn smaller to fit.
    static func paginate(heights: [CGFloat], firstRoom: CGFloat, room: CGFloat, gap: CGFloat) -> [[Int]] {
        var pages: [[Int]] = []
        var page: [Int] = []
        var left = firstRoom
        for (index, height) in heights.enumerated() {
            if !page.isEmpty, gap + height > left {
                pages.append(page)
                page = []
                left = room
            }
            left -= page.isEmpty ? height : gap + height
            page.append(index)
        }
        if !page.isEmpty || pages.isEmpty { pages.append(page) }
        return pages
    }
}

// MARK: Where guides are kept

enum HowToStore {
    /// Snapfly's own folder, inside the sandbox for the App Store edition.
    static let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snapfly", isDirectory: true)
        .appendingPathComponent("Guides", isDirectory: true)
    /// How many guides are kept; the oldest go first.
    static let kept = 20

    static func folder(of id: UUID, in base: URL = folder) -> URL {
        base.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func file(_ name: String, of id: UUID, in base: URL = folder) -> URL {
        folder(of: id, in: base).appendingPathComponent(name)
    }

    /// A step's screenshot with its private details covered, beside it.
    static func coveredName(of step: HowToStep) -> String {
        (step.file as NSString).deletingPathExtension + "-covered.png"
    }

    /// Readable only by the owner, like the screenshots.
    static func save(_ guide: HowToGuide, in base: URL = folder) throws {
        let folder = folder(of: guide.id, in: base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(guide)
        let url = folder.appendingPathComponent("Guide.json")
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(_ id: UUID, in base: URL = folder) -> HowToGuide? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file("Guide.json", of: id, in: base)) else { return nil }
        return try? decoder.decode(HowToGuide.self, from: data)
    }

    /// The guides kept, newest first; those with no steps are left out.
    static func recent(in base: URL = folder) -> [HowToGuide] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { UUID(uuidString: $0.lastPathComponent).flatMap { load($0, in: base) } }
            .filter { !$0.steps.isEmpty }
            .sorted { $0.created > $1.created }
    }

    static func delete(_ id: UUID, in base: URL = folder) {
        try? FileManager.default.removeItem(at: folder(of: id, in: base))
    }

    /// Lets the oldest go, past `kept`, and any left without steps, but
    /// never the one being worked on.
    static func prune(keeping count: Int = kept, sparing current: UUID? = nil, in base: URL = folder) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        var guides: [HowToGuide] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), id != current else { continue }
            if let guide = load(id, in: base), !guide.steps.isEmpty {
                guides.append(guide)
            } else {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        let room = max(0, count - (current == nil ? 0 : 1))
        for guide in guides.sorted(by: { $0.created > $1.created }).dropFirst(room) {
            delete(guide.id, in: base)
        }
    }
}
