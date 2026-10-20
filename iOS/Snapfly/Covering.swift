import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// What to cover: the recommended kinds, until Settings says otherwise. The
/// same choice, under the same name, as on the Mac.
enum Choice {
    /// The saved choice, brought up to date once before it is first read: a
    /// recommended kind added since starts on. The owner's name, saved as a
    /// word before there were details, becomes the name detail then too, so
    /// it is covered however it is written, whichever names are chosen.
    private static let upToDate: Void = {
        PrivateDetail.bringUpToDate(["hiddenDetails"])
        OwnRules.adoptName()
    }()

    static var details: Set<PrivateDetail> {
        get {
            _ = upToDate
            guard let raw = UserDefaults.standard.stringArray(forKey: "hiddenDetails") else {
                return PrivateDetail.recommended
            }
            return Set(raw.compactMap(PrivateDetail.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenDetails")
            share()
        }
    }

    /// The choice, the look and the owner's own rules, kept where the share
    /// extension can read them (`SharedChoice`).
    static func share() {
        let choice = SharedChoice(details: details, look: .current, rules: OwnRules.all)
        if SharedChoice.kept != choice { SharedChoice.keep(choice) }
    }
}

/// A screenshot with its private details covered, and the ways it leaves.
enum Covering {
    /// The picture with the chosen details covered and checked, and what
    /// was covered; nil when the copy could not be made (`CoveredCopy`).
    static func cover(_ image: CGImage, _ chosen: Set<PrivateDetail>) async -> (image: CGImage, report: CoverReport)? {
        await CoveredCopy.make(image, chosen)
    }

    static func upright(_ data: Data, longest: Int = 4096) -> CGImage? {
        CoveredCopy.upright(data, longest: longest)
    }

    static func png(_ image: CGImage) -> Data? {
        CoveredCopy.png(image)
    }

    /// On the clipboard, ready to paste into a chat.
    static func copy(_ png: Data) {
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
    }

    /// Into Photos, as a new picture next to the screenshot, which stays as
    /// it was.
    static func save(_ png: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
        }
    }
}
