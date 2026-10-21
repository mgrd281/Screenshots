import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture's covered copy, as it leaves the iPhone app and its share
/// extension: covered, read again and checked in its pixels, or nothing.
enum CoveredCopy {
    /// The picture with the chosen details covered and checked, and what
    /// was covered. Worked out on a queue of its own, where Apple
    /// Intelligence may be waited for without holding up anything else.
    /// Nil when the copy could not be made, Vision could not read the
    /// picture or the copy, or its covers did not all land, so a picture
    /// never leaves uncovered.
    static func make(_ image: CGImage, _ chosen: Set<PrivateDetail>, rules: [OwnRule] = OwnRules.all,
                     style: CoverStyle = .current, intelligence: Bool = true) async -> (image: CGImage, report: CoverReport)? {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                let failures = Finder.failures
                guard let made = Finder.protect(image, chosen, rules: rules, intelligence: intelligence, style: style) else {
                    return done.resume(returning: nil)
                }
                // Nothing found where nothing could be read is no proof that
                // nothing is there.
                guard Finder.failures == failures else { return done.resume(returning: nil) }
                let places = made.areas.map(\.rect)
                if Finder.coversHold(original: image, covered: made.image, areas: places) {
                    return done.resume(returning: (made.image, CoverReport(made.areas, places: places)))
                }
                // A look that let something through is made again in ink, the surest.
                guard let ink = Finder.cover(image, areas: made.areas, style: .ink),
                      Finder.coversHold(original: image, covered: ink, areas: places) else {
                    return done.resume(returning: nil)
                }
                done.resume(returning: (ink, CoverReport(made.areas, places: places)))
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

    /// As PNG, encoded afresh, so none of the original's details come along.
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
