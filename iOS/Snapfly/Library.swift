import ImageIO
import Photos
import UIKit

/// The screenshots in Photos, newest first.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var shots: [PHAsset] = []

    var mayRead: Bool { access == .authorized || access == .limited }

    func ask() {
        Task {
            access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            load()
        }
    }

    func load() {
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        shots = mayRead ? Self.screenshots(limit: 90) : []
    }

    /// The newest screenshots, from the album Photos keeps of them.
    nonisolated static func screenshots(limit: Int) -> [PHAsset] {
        guard let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots,
                                                                  options: nil).firstObject else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(in: album, options: options)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    nonisolated static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Whether a picture chosen in the picker is a screenshot: as Photos
    /// says, where Snapfly may see it there; else as the note iOS writes
    /// into a screenshot says.
    nonisolated static func isScreenshot(_ id: String?, data: Data) -> Bool {
        if let id, let asset = asset(id) { return asset.mediaSubtypes.contains(.photoScreenshot) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let comment = exif[kCGImagePropertyExifUserComment] as? String else { return false }
        return comment.localizedCaseInsensitiveContains("screenshot")
    }

    /// One screenshot at full size, as it was taken, the right way up.
    nonisolated static func image(of asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data.flatMap { Covering.upright($0) })
            }
        }
    }

    /// The screenshots with these identifiers, in that order, those still in Photos.
    nonisolated static func assets(_ ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var found: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }
        return ids.compactMap { found[$0] }
    }

    /// A small picture of one screenshot, for the grid: never the whole
    /// picture decoded, and a changed screenshot made again.
    nonisolated static func thumbnail(of asset: PHAsset, width: CGFloat) async -> UIImage? {
        let key = Thumbnails.key(asset, width: width)
        if let kept = Thumbnails.kept.object(forKey: key) { return kept }
        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One answer, not a blurry one first and a sharp one after.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let size = CGSize(width: width, height: width * 2.2)
            Thumbnails.images.requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                           options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image {
            let pixels = image.size.width * image.scale * image.size.height * image.scale
            Thumbnails.kept.setObject(image, forKey: key, cost: Int(pixels) * 4)
        }
        return image
    }

    /// The small picture made of a screenshot lately, if it is still kept,
    /// so a card made again shows it at once rather than blank for a moment.
    nonisolated static func keptThumbnail(of asset: PHAsset, width: CGFloat) -> UIImage? {
        Thumbnails.kept.object(forKey: Thumbnails.key(asset, width: width))
    }
}

/// The small pictures made lately, kept while the app runs, so going back
/// to the grid or scrolling up shows them at once.
private enum Thumbnails {
    static let kept: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // About fifty screenshots' worth, less when iOS needs the memory.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static let images = PHCachingImageManager()

    /// A screenshot's small picture at this width, as it is now: one changed
    /// since is made again.
    static func key(_ asset: PHAsset, width: CGFloat) -> NSString {
        let stamp = asset.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(asset.localIdentifier)|\(Int(width))|\(stamp)" as NSString
    }
}
