import ImageIO
import SwiftUI

/// A screenshot handed from the Mac nearby (`PhotoHandoff`): Snapfly at the
/// bottom of the app switcher opens it here, in the editor, to cover, save
/// or send. It comes straight from the Mac, as it leaves the Mac's line,
/// and is kept only while the app runs, as a photo chosen is.
@MainActor
final class MacHandoff: ObservableObject {
    static let shared = MacHandoff()
    /// The picture that came, until the Photos tab opens it.
    @Published var arrived: CGImage?

    func receive(_ activity: NSUserActivity) {
        guard activity.activityType == PhotoHandoff.activityType else { return }
        QuickCoverer.shared.show(L("Getting the screenshot from your Mac…"), for: 30)
        Self.fetch(activity)
    }

    /// Asks the Mac for the picture, and reads it away from the main thread.
    nonisolated private static func fetch(_ activity: NSUserActivity) {
        activity.getContinuationStreams { input, output, error in
            guard let input, error == nil else {
                DispatchQueue.main.async { MainActor.assumeIsolated { MacHandoff.shared.failed() } }
                return
            }
            // Read away from the main thread: it waits for every byte.
            DispatchQueue.global(qos: .userInitiated).async {
                let data = PhotoHandoff.receive(from: input)
                output?.open()
                output?.close()
                let image = data.flatMap(Self.picture)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let image {
                            QuickCoverer.shared.note = nil
                            MacHandoff.shared.arrived = image
                        } else {
                            MacHandoff.shared.failed()
                        }
                    }
                }
            }
        }
    }

    private func failed() {
        QuickCoverer.shared.show(L("The screenshot from your Mac could not be received."), for: 4)
    }

    /// The picture in the bytes, as it stands.
    nonisolated private static func picture(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 8192]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
