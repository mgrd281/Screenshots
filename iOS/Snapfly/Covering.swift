import ImageIO
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
    /// The picture with the chosen details covered and checked, and what
    /// was covered. Worked out on a queue of its own, where Apple
    /// Intelligence may be waited for without holding up anything else.
    /// Nil when the copy could not be made, or its covers did not all land,
    /// so a screenshot never leaves uncovered.
    static func cover(_ image: CGImage, _ chosen: Set<PrivateDetail>) async -> (image: CGImage, report: CoverReport)? {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let made = Finder.protect(image, chosen) else { return done.resume(returning: nil) }
                let places = made.areas.map(\.rect)
                if Finder.coversHold(original: image, covered: made.image, areas: places) {
                    return done.resume(returning: (made.image, CoverReport(made.areas)))
                }
                // A look that let something through is made again in ink, the surest.
                guard let ink = Finder.cover(image, areas: made.areas, style: .ink),
                      Finder.coversHold(original: image, covered: ink, areas: places) else {
                    return done.resume(returning: nil)
                }
                done.resume(returning: (ink, CoverReport(made.areas)))
            }
        }
    }

    /// A picture's data as it is seen: a photo taken sideways turned the
    /// right way up, and one larger than `longest` pixels made smaller.
    /// A screenshot is read as it is.
    static func upright(_ data: Data, longest: Int = 4096) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        if orientation == 1, max(width, height) <= longest {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
