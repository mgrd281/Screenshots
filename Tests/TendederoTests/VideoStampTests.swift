#if os(macOS)
import AppKit
import AVFoundation
import XCTest
@testable import Tendedero

/// The time stamp on a recording: the page in front at each moment, the
/// record kept with the file, what the band says as the video runs, its one
/// even height, and the band drawn above a made-up recording's picture.
final class VideoStampTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let german = Locale(identifier: "de_DE")
    // October 16, 2026, 23:30 in UTC, on the second.
    private let began = Date(timeIntervalSince1970: 1_792_193_400)

    private func made(_ pages: [VideoStamp.Page], atomic: Bool = true) -> VideoStamp.Record {
        VideoStamp.Record(began: began, atomic: atomic, pages: pages)
    }

    private func stamp(_ pages: [VideoStamp.Page], text: String = "Officehauss") -> VideoStamp.Stamp {
        VideoStamp.Stamp(record: made(pages), text: text, rightToLeft: false, locale: german, timeZone: utc)
    }

    // MARK: The pages

    func testThePageInFrontIsTheLastToComeBeforeTheMoment() {
        let shop = "https://www.kaufland.de/product/42/"
        let review = "https://example.com/reviews?filter=1"
        let kept = made([VideoStamp.Page(at: 0, address: shop), VideoStamp.Page(at: 3.5, address: nil),
                         VideoStamp.Page(at: 7, address: review)])
        XCTAssertEqual(VideoStamp.page(at: 0, in: kept), shop)
        XCTAssertEqual(VideoStamp.page(at: 3.49, in: kept), shop)
        XCTAssertNil(VideoStamp.page(at: 3.5, in: kept))
        XCTAssertNil(VideoStamp.page(at: 6.9, in: kept))
        XCTAssertEqual(VideoStamp.page(at: 7, in: kept), review)
        XCTAssertEqual(VideoStamp.page(at: 600, in: kept), review)
        XCTAssertNil(VideoStamp.page(at: 2, in: made([])))
    }

    func testWhatWasInFrontAsItBeganCountsFromTheStart() {
        // On the host clock: two pages before the first picture, at 100,
        // then none twice, then another.
        let seen: [(t: Double, address: String?)] = [
            (t: 99, address: "https://a.example/"), (t: 99.5, address: "https://b.example/"),
            (t: 104, address: nil), (t: 104.5, address: nil), (t: 106, address: "https://c.example/"),
        ]
        XCTAssertEqual(VideoStamp.pages(seen, since: 100), [
            VideoStamp.Page(at: 0, address: "https://b.example/"), VideoStamp.Page(at: 4, address: nil),
            VideoStamp.Page(at: 6, address: "https://c.example/"),
        ])
        // Noted a moment after the first picture, it still shows from the start.
        let late: [(t: Double, address: String?)] = [(t: 100.2, address: "https://a.example/")]
        XCTAssertEqual(VideoStamp.pages(late, since: 100), [VideoStamp.Page(at: 0, address: "https://a.example/")])
        XCTAssertEqual(VideoStamp.pages([], since: 100), [])
    }

    func testTrimmingMovesTheRecordToTheNewStart() {
        let kept = made([VideoStamp.Page(at: 0, address: "https://a.example/"), VideoStamp.Page(at: 3, address: nil),
                         VideoStamp.Page(at: 8, address: "https://b.example/")])
        let trimmed = VideoStamp.trimmed(kept, from: 5)
        XCTAssertEqual(trimmed.began, began.addingTimeInterval(5))
        XCTAssertEqual(trimmed.pages, [VideoStamp.Page(at: 0, address: nil), VideoStamp.Page(at: 3, address: "https://b.example/")])
        XCTAssertEqual(VideoStamp.trimmed(kept, from: 0), kept)
    }

    // MARK: Kept with the file

    func testTheRecordSurvivesTheRoundTripAndStaysWithTheFile() throws {
        let kept = made([VideoStamp.Page(at: 0, address: "https://example.com/a"), VideoStamp.Page(at: 2.5, address: nil)])
        let data = try JSONEncoder().encode(kept)
        XCTAssertEqual(try JSONDecoder().decode(VideoStamp.Record.self, from: data), kept)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-stamp-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(VideoStamp.record(of: url))
        XCTAssertFalse(VideoStamp.isDrawnIn(url))
        XCTAssertTrue(VideoStamp.keep(kept, with: url))
        XCTAssertEqual(VideoStamp.record(of: url), kept)
        VideoStamp.drawnIn(stamp(kept.pages), into: url)
        XCTAssertTrue(VideoStamp.isDrawnIn(url))
        XCTAssertEqual(VideoStamp.record(of: url), kept)
    }

    // MARK: The band

    func testTheBandRunsSecondBySecondAndFollowsThePage() {
        let page = "https://example.com/review/42"
        let shown = stamp([VideoStamp.Page(at: 0, address: nil), VideoStamp.Page(at: 2, address: page)])
        let start = VideoStamp.mark(at: 0.4, of: shown)
        XCTAssertEqual(start.rows[0].text, TimeStamp.label(text: "Officehauss", date: began.addingTimeInterval(0.4),
                                                           locale: german, timeZone: utc))
        XCTAssertTrue(start.rows[0].text.contains("23:30:00"), start.rows[0].text)
        XCTAssertTrue(start.rows[1].text.contains("PTB"))
        XCTAssertEqual(start.rows.count, 2)
        let later = VideoStamp.mark(at: 2.7, of: shown)
        XCTAssertTrue(later.rows[0].text.contains("23:30:02"), later.rows[0].text)
        XCTAssertEqual(later.rows.count, 3)
        XCTAssertEqual(later.rows[2].kind, .link)
        XCTAssertEqual(later.rows[2].url, URL(string: page))
        // No fingerprint: a video cannot hold its own.
        XCTAssertFalse(later.rows.contains { $0.kind == .code })
    }

    func testTheMacsClockIsSaidWhenTheAtomicClockDidNotAnswer() {
        let mac = VideoStamp.Stamp(record: made([], atomic: false), text: "", rightToLeft: false, locale: german,
                                   timeZone: utc)
        XCTAssertFalse(VideoStamp.mark(at: 1, of: mac).rows[1].text.contains("PTB"))
    }

    func testTheBandKeepsOneEvenHeightForTheTallestMoment() {
        let long = "https://example.com/" + String(repeating: "a", count: 900)
        let shown = stamp([VideoStamp.Page(at: 0, address: "https://example.com/a"), VideoStamp.Page(at: 4, address: nil),
                           VideoStamp.Page(at: 9, address: long)])
        for width in [320, 1280, 1512, 2880, 3024, 3456, 3840] {
            let height = VideoStamp.bandHeight(shown, width: width)
            XCTAssertEqual(height % 2, 0, "at \(width)")
            let tallest = [0.0, 4, 9].map { TimeStamp.bandHeight(VideoStamp.mark(at: $0, of: shown), width: width) }.max() ?? 0
            XCTAssertTrue(height == tallest || height == tallest + 1, "at \(width): \(height) for \(tallest)")
        }
        XCTAssertEqual(VideoStamp.even(61), 62)
        XCTAssertEqual(VideoStamp.even(62), 62)
    }

    func testEachMomentsBandIsAsTallAndDrawnAgainOnlyWhenItChanges() throws {
        let shown = stamp([VideoStamp.Page(at: 0, address: nil),
                           VideoStamp.Page(at: 1.5, address: "https://example.com/" + String(repeating: "a", count: 300))])
        let banner = try XCTUnwrap(VideoStamp.Banner(shown, width: 1280))
        XCTAssertEqual(banner.height, VideoStamp.bandHeight(shown, width: 1280))
        let first = try XCTUnwrap(banner.image(at: 0.1))
        XCTAssertEqual(first.width, 1280)
        XCTAssertEqual(first.height, banner.height)
        // The same second, the same picture; the next second, a new one.
        let same = try XCTUnwrap(banner.image(at: 0.9))
        XCTAssertTrue(first === same)
        let next = try XCTUnwrap(banner.image(at: 1.2))
        XCTAssertFalse(first === next)
        // Another page, the same height.
        let paged = try XCTUnwrap(banner.image(at: 1.6))
        XCTAssertFalse(next === paged)
        XCTAssertEqual(paged.height, banner.height)
    }

    // MARK: The video

    func testTheBandIsDrawnAboveTheRecordingsPicture() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("video-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("red.mov")
        try writeRedMovie(to: source, width: 320, height: 180, seconds: 2)
        let shown = stamp([VideoStamp.Page(at: 0, address: "https://example.com/a")])
        let look = StudioLook(project: StudioProject(), events: nil, duration: 2, pixels: CGSize(width: 320, height: 180))
        let target = folder.appendingPathComponent("stamped.mov")
        try await StudioExport.run(source, look: look, rate: 30, stamp: shown, to: target,
                                   stop: StudioExport.Stop()) { _ in }
        let band = VideoStamp.bandHeight(shown, width: 320)
        let asset = AVURLAsset(url: target)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180 + band))
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        let frame = try await image(of: target, at: 1)
        // The band's own colour at its top right, where no words reach.
        let ground = pixel(frame, x: 316, y: 3)
        XCTAssertTrue(ground.r > 225 && ground.g > 225 && ground.b > 225, "\(ground)")
        // The picture below it, whole.
        let picture = pixel(frame, x: 160, y: band + 90)
        XCTAssertTrue(picture.r > 180 && picture.g < 80 && picture.b < 80, "\(picture)")
        let foot = pixel(frame, x: 160, y: band + 176)
        XCTAssertTrue(foot.r > 180 && foot.g < 80 && foot.b < 80, "\(foot)")
    }

    // MARK: A made-up recording

    /// All red, thirty frames a second.
    private func writeRedMovie(to url: URL, width: Int, height: Int, seconds: Double) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? StudioExport.Failure.cannotWrite }
        writer.startSession(atSourceTime: .zero)
        let fps = 30
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData {
                // A writer that failed is never ready again.
                guard writer.status == .writing else { throw writer.error ?? StudioExport.Failure.cannotWrite }
                Thread.sleep(forTimeInterval: 0.002)
            }
            var made: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let buffer = made
            else { throw StudioExport.Failure.cannotWrite }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? StudioExport.Failure.cannotWrite }
    }

    private func image(of url: URL, at t: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    /// A pixel's colour, counted in pixels from the top left.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let i = (min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))) * 4
        return (r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }
}
#endif
