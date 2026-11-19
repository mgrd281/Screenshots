import AVFoundation

/// How Snapfly compresses the videos it makes, recordings and Studio's:
/// HEVC, which keeps a screen as sharp as H.264 does in about half the
/// room, and which every Mac Snapfly runs on writes in hardware; H.264, a
/// little larger, where a Mac cannot. The bit rate follows the picture's
/// size and frame rate, generous enough that small text stays crisp.
enum VideoQuality {
    /// Bits for each pixel of each frame, on average, in HEVC: a recording
    /// of the screen, where most of it keeps still.
    static let recording = 0.06
    /// Studio's video, with its zooms and pans, at sixty frames a second.
    static let studio = 0.05
    /// H.264 needs about this much more for the same sharpness.
    static let h264Factor = 1.6

    /// The average bit rate for a picture this large at this frame rate,
    /// kept between 2 and 60 megabits a second.
    static func bitRate(width: Int, height: Int, frameRate: Double, bitsPerPixel: Double, hevc: Bool) -> Int {
        let bits = Double(width * height) * frameRate * bitsPerPixel * (hevc ? 1 : h264Factor)
        return min(60_000_000, max(2_000_000, Int(bits.rounded())))
    }

    /// What a writer is given for a picture this large: HEVC, or H.264 with
    /// its best profile, a key frame every two seconds, and the bit rate.
    static func settings(width: Int, height: Int, frameRate: Double, bitsPerPixel: Double,
                         hevc: Bool) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate(width: width, height: height, frameRate: frameRate,
                                              bitsPerPixel: bitsPerPixel, hevc: hevc),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalKey: Int((frameRate * 2).rounded()),
        ]
        if !hevc {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }
        return [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    /// HEVC when this writer can take it, else H.264.
    static func settings(for writer: AVAssetWriter, width: Int, height: Int, frameRate: Double,
                         bitsPerPixel: Double) -> [String: Any] {
        let hevc = settings(width: width, height: height, frameRate: frameRate, bitsPerPixel: bitsPerPixel, hevc: true)
        if writer.canApply(outputSettings: hevc, forMediaType: .video) { return hevc }
        return settings(width: width, height: height, frameRate: frameRate, bitsPerPixel: bitsPerPixel, hevc: false)
    }
}
