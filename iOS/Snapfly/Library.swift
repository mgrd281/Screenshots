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

    /// One screenshot at full size, as it was taken.
    nonisolated static func image(of asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                let image = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                    .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
                continuation.resume(returning: image)
            }
        }
    }

    /// A small picture of one screenshot, for the grid.
    nonisolated static func thumbnail(of asset: PHAsset, width: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One answer, not a blurry one first and a sharp one after.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let size = CGSize(width: width, height: width * 2.2)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
