import CoreGraphics
import Foundation

/// How Save Video writes the video: how large, and as which kind of file.
/// Kept as last chosen, the same for every recording.
struct StudioOutput: Codable, Equatable, Sendable {
    /// How large, by the picture's shorter side, as video sites name it.
    enum Quality: String, Codable, CaseIterable, Sendable {
        /// As large as the recording, within 4K.
        case original
        case uhd, fullHD, hd

        /// The shorter side in pixels; nil to follow the recording.
        var side: Int? {
            switch self {
            case .original: nil
            case .uhd: 2160
            case .fullHD: 1080
            case .hd: 720
            }
        }
    }

    /// The kind of file: a movie as Macs and iPhones play it, one every
    /// player and website takes, or a GIF that plays in any chat.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case mov, mp4, gif
    }

    var quality = Quality.original
    var kind = Kind.mov

    init() {}

    init(quality: Quality, kind: Kind) {
        self.quality = quality
        self.kind = kind
    }

    // What cannot be read, as from a newer Snapfly, is left as it starts.
    init(from decoder: Decoder) throws {
        let kept = try decoder.container(keyedBy: CodingKeys.self)
        quality = (try? kept.decodeIfPresent(Quality.self, forKey: .quality)) ?? .original
        kind = (try? kept.decodeIfPresent(Kind.self, forKey: .kind)) ?? .mov
    }

    /// The size the video is made at: a GIF is small whatever is chosen.
    var size: Quality {
        kind == .gif ? .hd : quality
    }
}

/// Where the recording sits in the saved video, in the video's own pixels
/// from the bottom left: the whole picture's size, the recording's place on
/// it, how round its corners are and its shadow. Without a background the
/// recording fills the picture. The preview lays itself out by the same
/// measures, so what is seen is what is saved.
struct StudioFraming: Equatable, Sendable {
    /// The whole picture, even on both sides as video wants, within 4K.
    var canvas: CGSize
    var video: CGRect
    var radius: CGFloat = 0
    /// The shadow's blur and how far down it falls; nothing without one.
    var blur: CGFloat = 0
    var drop: CGFloat = 0
    /// The colour round the recording; nil without a background.
    var fill: Backdrop.Fill?

    init(pixels: CGSize, backdrop: Backdrop?, quality: StudioOutput.Quality = .original) {
        let width = max(2, Double(pixels.width).rounded()), height = max(2, Double(pixels.height).rounded())
        // The background's own measures, at the recording's size, as a photo's.
        var whole = CGSize(width: width, height: height)
        var picture = CGRect(x: 0, y: 0, width: width, height: height)
        if let backdrop {
            let layout = backdrop.layout(width: Int(width), height: Int(height))
            whole = layout.canvas
            picture = layout.picture
            radius = layout.radius
            blur = layout.blur
            drop = layout.drop
        }
        // Then all of it made the size chosen.
        let wanted = quality.side.map { Double($0) / max(1, min(whole.width, whole.height)) } ?? 1
        let (canvasWidth, canvasHeight) = Capture.videoSize(whole.width * wanted, whole.height * wanted)
        canvas = CGSize(width: canvasWidth, height: canvasHeight)
        fill = backdrop?.fill
        guard backdrop != nil else {
            video = CGRect(origin: .zero, size: canvas)
            return
        }
        let scale = min(canvasWidth / whole.width, canvasHeight / whole.height)
        let size = CGSize(width: (picture.width * scale).rounded(), height: (picture.height * scale).rounded())
        video = CGRect(x: ((canvasWidth - size.width) / 2).rounded(.down), y: ((canvasHeight - size.height) / 2).rounded(.down),
                       width: size.width, height: size.height)
        radius = min((radius * scale).rounded(), min(size.width, size.height) / 2)
        blur = (blur * scale).rounded()
        drop = (drop * scale).rounded()
    }

    /// Whether anything shows round the recording.
    var isFramed: Bool { fill != nil }
}
