import Photos
import UIKit
import UniformTypeIdentifiers

/// What to cover: the recommended kinds, until Settings says otherwise. The
/// same choice, under the same name, as on the Mac.
enum Choice {
    /// The saved choice, brought up to date once before it is first read: a
    /// recommended kind added since starts on.
    private static let upToDate: Void = PrivateDetail.bringUpToDate(["hiddenDetails"])

    static var details: Set<PrivateDetail> {
        get {
            _ = upToDate
            guard let raw = UserDefaults.standard.stringArray(forKey: "hiddenDetails") else {
                return PrivateDetail.recommended
            }
            return Set(raw.compactMap(PrivateDetail.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenDetails") }
    }
}

/// A screenshot with its private details covered, and the ways it leaves.
enum Covering {
    /// The picture with the chosen details covered, and what was.
    static func cover(_ image: CGImage, _ chosen: Set<PrivateDetail>) -> (image: CGImage, report: CoverReport) {
        let areas = Finder.coveredAreas(in: image, chosen)
        return (Finder.cover(image, areas: areas) ?? image, CoverReport(areas))
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
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
