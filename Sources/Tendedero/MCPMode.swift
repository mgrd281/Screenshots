import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Snapfly for AI apps on this Mac, like Claude: started by the AI app as
/// `Snapfly --mcp`, it answers over its standard input and output
/// (`MCPServer`) instead of hanging a line. The AI app may ask for the
/// newest screenshot, a list of what hangs on the line, any photo or PDF
/// there, or text to cover; whatever it gets has the private details
/// covered as Settings › Privacy says, and everything in AI chats when that
/// is on. Nothing leaves this Mac but what the AI app itself sends on.
///
/// The owner turns it on in Settings › AI Assistant; while it is off, every
/// tool says so and gives nothing.
@MainActor
enum MCPMode {
    nonisolated static let argument = "--mcp"

    /// Whether Snapfly was started by an AI app, to answer it.
    nonisolated static var isRequested: Bool { CommandLine.arguments.contains(argument) }

    /// Whether AI apps may ask Snapfly, from Settings. Off unless turned on.
    nonisolated static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "aiAppsMayAsk") }
        set { UserDefaults.standard.set(newValue, forKey: "aiAppsMayAsk") }
    }

    /// How many pages of a PDF one answer holds at most.
    static let mostPages = 10
    /// The longest side of a picture given, in pixels: as large as AI apps
    /// read pictures, small enough to go quickly.
    static let largestSide = 1568

    /// Answers the AI app until it closes the connection. Snapfly's line,
    /// menu and windows stay out of it; another Snapfly may run meanwhile.
    static func run() -> Never {
        Notice.isSilent = true
        // The folders the App Store edition was let into, and the photos
        // brought in from elsewhere, opened as the line opens them.
        _ = AppDelegate.extraFolders
        Outside.reopen()
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let server = MCPServer(name: "snapfly", title: "Snapfly", version: version, instructions: instructions,
                               tools: tools) { name, arguments in
            MainActor.assumeIsolated { MCPMode.call(name, arguments) }
        }
        Thread.detachNewThread {
            let input = FileHandle.standardInput
            let output = FileHandle.standardOutput
            var buffer = Data()
            while true {
                let chunk = input.availableData
                // The AI app closed the connection: done.
                if chunk.isEmpty { exit(0) }
                buffer.append(chunk)
                while let end = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...end)
                    let reply = DispatchQueue.main.sync { server.respond(to: line) }
                    if let reply { output.write(Data((reply + "\n").utf8)) }
                }
            }
        }
        app.run()
        exit(0)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: The tools

    private static let instructions = """
        Snapfly holds the user's screenshots on a line on their Mac. Everything it gives you already has \
        the user's private details covered, as they chose in Snapfly: covered parts of a picture are \
        blacked out or blurred, and in text each detail stands as a tag like [NAME 1] or [EMAIL 2], the \
        same tag wherever the same detail comes again. Never guess what a tag or a covered part hides; \
        use the tags as they are in what you write, so the user can put the details back.
        """

    private static let tools: [MCPServer.Tool] = [
        MCPServer.Tool(name: "latest_screenshot", title: "Newest Screenshot",
                       description: "The newest screenshot on the user's Snapfly line, as a picture, with its private details covered."),
        MCPServer.Tool(name: "list_items", title: "What Hangs on the Line",
                       description: "Lists the screenshots, photos and PDFs on the user's Snapfly line, newest first, each with its number for get_item, its name and when it was made."),
        MCPServer.Tool(name: "get_item", title: "A Screenshot, Photo or PDF",
                       description: "One screenshot, photo or PDF from the user's Snapfly line, by its number from list_items (1 is the newest), with its private details covered. A PDF comes as a picture of each page, up to ten.",
                       properties: ["number": ["type": "integer", "minimum": 1,
                                               "description": "Its number from list_items; 1 is the newest."]],
                       required: ["number"]),
        MCPServer.Tool(name: "cover_text", title: "Cover Private Details in Text",
                       description: "Gives back the text with its private details, like names, addresses, email addresses, phone numbers and bank details, replaced by tags like [NAME 1], as the user chose in Snapfly. Use it on text the user gives you before you work with it.",
                       properties: ["text": ["type": "string", "description": "The text to cover."]],
                       required: ["text"]),
    ]

    /// What the owner chose to cover, and every kind with Cover Everything
    /// in AI Chats on: an AI app is an AI chat.
    private static var chosen: Set<PrivateDetail> {
        CoveringProfile.details(PrivateDetails.details, inAIChat: true, coversAll: CoveringProfile.coversAllInAIChats)
    }

    static func call(_ name: String, _ arguments: [String: Any]) -> MCPServer.Result {
        guard isOn else {
            return .failure("Snapfly is not letting AI apps read the line. The user can turn on “Let AI apps use Snapfly” in Snapfly’s Settings › AI Assistant.")
        }
        switch name {
        case "latest_screenshot":
            guard let newest = items.first else { return .failure("Nothing hangs on the user's Snapfly line yet.") }
            return give(newest, number: 1)
        case "list_items":
            let all = items
            guard !all.isEmpty else { return MCPServer.Result(content: [.text("Nothing hangs on the line yet.")]) }
            let list = all.enumerated().map { n, url in "\(n + 1). \(url.lastPathComponent) — \(kind(of: url)), \(when(url))" }
            return MCPServer.Result(content: [.text(list.joined(separator: "\n"))])
        case "get_item":
            let all = items
            let number = (arguments["number"] as? NSNumber)?.intValue ?? Int(arguments["number"] as? String ?? "") ?? 0
            guard all.indices.contains(number - 1) else {
                return .failure("There is no item \(number); the line holds \(all.count). Use list_items to see them.")
            }
            return give(all[number - 1], number: number)
        case "cover_text":
            guard let text = arguments["text"] as? String else { return .failure("No text was given.") }
            let covered = TextCover.covered(text, chosen, rules: OwnRules.all)
            return MCPServer.Result(content: [.text(covered.text)])
        default:
            return .failure("Snapfly has no tool called \(name).")
        }
    }

    // MARK: The line

    /// What hangs on the line that can be given, newest first: pictures and
    /// PDFs, never recordings.
    private static var items: [URL] {
        Line.savedPaths.reversed().map { URL(fileURLWithPath: $0) }.filter { url in
            FileManager.default.fileExists(atPath: url.path) && (Tendedero.isImage(url) || Tendedero.isDocument(url))
        }
    }

    private static func kind(of url: URL) -> String {
        Tendedero.isDocument(url) ? "PDF" : "picture"
    }

    private static func when(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        guard let date = values?.creationDate ?? values?.contentModificationDate else { return "date unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// A photo or PDF as it leaves the line for an AI chat, covered, as
    /// pictures the AI app reads.
    private static func give(_ url: URL, number: Int) -> MCPServer.Result {
        let covered = PrivateDetails.shareable(url, covering: chosen)
        let pictures: [Data]
        if Tendedero.isDocument(url) {
            pictures = pages(of: covered)
        } else {
            pictures = picture(at: covered).map { [$0] } ?? []
        }
        guard !pictures.isEmpty else { return .failure("Snapfly could not open \(url.lastPathComponent).") }
        var content: [MCPServer.Content] = [.text(
            "Item \(number): \(url.lastPathComponent), \(when(url)). Private details are covered as the user chose in Snapfly.")]
        content += pictures.map { MCPServer.Content.image($0, mimeType: "image/jpeg") }
        return MCPServer.Result(content: content)
    }

    /// A picture file as a JPEG no larger than `largestSide`.
    private static func picture(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: largestSide]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image)
    }

    /// The first pages of a PDF, each a picture.
    private static func pages(of url: URL) -> [Data] {
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<min(document.pageCount, mostPages)).compactMap { i in
            guard let page = document.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = Double(largestSide) / Double(max(bounds.width, bounds.height, 1))
            let size = NSSize(width: Double(bounds.width) * scale, height: Double(bounds.height) * scale)
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return jpeg(image)
        }
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
