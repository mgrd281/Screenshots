import AppIntents
import Photos
import UniformTypeIdentifiers

/// A problem to say in Shortcuts, in the user's words.
struct Problem: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

/// Covers the newest screenshot and puts it on the clipboard, without
/// opening Snapfly. Chosen for a double tap on the back of the iPhone, it
/// makes a screenshot ready to paste in two taps.
struct CoverLatestScreenshot: AppIntent {
    static let title: LocalizedStringResource = "Cover the Latest Screenshot"
    static let description = IntentDescription("Covers the private details in your newest screenshot and copies it, ready to paste.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else {
            throw Problem(text: L("Snapfly may not see your screenshots yet. Open Snapfly once and allow it."))
        }
        guard let asset = Library.screenshots(limit: 1).first else {
            throw Problem(text: L("There is no screenshot yet."))
        }
        guard let image = await Library.image(of: asset) else {
            throw Problem(text: L("The picture could not be read."))
        }
        let chosen = Choice.details
        let covered = await Task.detached(priority: .userInitiated) { Covering.cover(image, chosen) }.value
        guard let png = Covering.png(covered.image) else {
            throw Problem(text: L("The picture could not be read."))
        }
        Covering.copy(png)
        return .result(value: IntentFile(data: png, filename: "Snapfly.png", type: .png),
                       dialog: IntentDialog(stringLiteral: L("Covered and copied, ready to paste.")))
    }
}

/// Covers the private details in any picture handed to it, for a shortcut
/// of one's own, or from the Share sheet through one.
struct CoverPicture: AppIntent {
    static let title: LocalizedStringResource = "Cover Private Details"
    static let description = IntentDescription("Covers names, addresses, emails, phone numbers and bank details in a picture.")
    static let openAppWhenRun = false

    @Parameter(title: "Picture", supportedContentTypes: [.image])
    var picture: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let source = CGImageSourceCreateWithData(picture.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Problem(text: L("The picture could not be read."))
        }
        let covered = Covering.cover(image, Choice.details)
        guard let png = Covering.png(covered.image) else {
            throw Problem(text: L("The picture could not be read."))
        }
        return .result(value: IntentFile(data: png, filename: "Snapfly.png", type: .png))
    }
}

/// Ready in Shortcuts and for Back Tap as soon as Snapfly is installed.
struct SnapflyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CoverLatestScreenshot(),
                    phrases: ["Cover my latest screenshot with \(.applicationName)",
                              "\(.applicationName), cover my screenshot"],
                    shortTitle: "Cover Screenshot",
                    systemImageName: "eye.slash")
    }
}
