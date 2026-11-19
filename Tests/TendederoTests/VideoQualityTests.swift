import AVFoundation
import XCTest
@testable import Tendedero

/// How Snapfly's videos are compressed: HEVC at a bit rate that follows the
/// picture, H.264 a little higher where HEVC cannot be written.
final class VideoQualityTests: XCTestCase {
    func testTheBitRateFollowsThePicture() {
        // A Retina screen at thirty frames a second.
        let screen = VideoQuality.bitRate(width: 2880, height: 1800, frameRate: 30,
                                          bitsPerPixel: VideoQuality.recording, hevc: true)
        XCTAssertEqual(screen, 9_331_200)
        // H.264 needs more for the same sharpness.
        let older = VideoQuality.bitRate(width: 2880, height: 1800, frameRate: 30,
                                         bitsPerPixel: VideoQuality.recording, hevc: false)
        XCTAssertEqual(older, 14_929_920)
    }

    func testTheBitRateStaysWithinBounds() {
        XCTAssertEqual(VideoQuality.bitRate(width: 320, height: 200, frameRate: 30,
                                            bitsPerPixel: VideoQuality.recording, hevc: true), 2_000_000)
        XCTAssertEqual(VideoQuality.bitRate(width: 3840, height: 2160, frameRate: 60,
                                            bitsPerPixel: 0.2, hevc: false), 60_000_000)
    }

    func testHEVCIsAskedForWithItsBitRate() throws {
        let settings = VideoQuality.settings(width: 1920, height: 1080, frameRate: 60,
                                             bitsPerPixel: VideoQuality.studio, hevc: true)
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
        XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 1920)
        XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 1080)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 6_220_800)
        XCTAssertEqual(compression[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
        XCTAssertEqual(compression[AVVideoMaxKeyFrameIntervalKey] as? Int, 120)
        XCTAssertNil(compression[AVVideoProfileLevelKey])
    }

    func testH264TakesItsBestProfile() throws {
        let settings = VideoQuality.settings(width: 1920, height: 1080, frameRate: 30,
                                             bitsPerPixel: VideoQuality.recording, hevc: false)
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoProfileLevelKey] as? String, AVVideoProfileLevelH264HighAutoLevel)
        XCTAssertEqual(compression[AVVideoH264EntropyModeKey] as? String, AVVideoH264EntropyModeCABAC)
    }

    func testAWriterOnThisMacTakesTheSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quality-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings = VideoQuality.settings(for: writer, width: 1280, height: 800, frameRate: 30,
                                             bitsPerPixel: VideoQuality.recording)
        XCTAssertTrue(writer.canApply(outputSettings: settings, forMediaType: .video))
    }
}
