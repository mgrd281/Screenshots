import Photos
import UIKit
import UniformTypeIdentifiers

/// What to cover: every kind, until some are turned off in Settings. The
/// same choice, under the same name, as on the Mac.
enum Choice {
    static var details: Set<PrivateDetail> {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: "hiddenDetails") else {
                return Set(PrivateDetail.allCases)
            }
            return Set(raw.compactMap(PrivateDetail.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenDetails") }
    }
}

/// A screenshot with its private details covered, and the ways it leaves.
enum Covering {
    /// The picture with the chosen details covered, and how many places were.
    static func cover(_ image: CGImage, _ chosen: Set<PrivateDetail>) -> (image: CGImage, count: Int) {
        let areas = Finder.areas(in: image, chosen)
        return (Finder.cover(image, areas) ?? image, areas.count)
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
