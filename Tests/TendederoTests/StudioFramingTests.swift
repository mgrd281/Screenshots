import XCTest
@testable import Tendedero

/// Studio's background, sizes and saving: where the recording sits in the
/// saved video, how large it is made, and work kept before they came.
final class StudioFramingTests: XCTestCase {
    private let retina = CGSize(width: 2880, height: 1800)

    func testWithoutABackgroundTheRecordingFillsTheVideoAtItsOwnSize() {
        let framing = StudioFraming(pixels: CGSize(width: 1511, height: 981), backdrop: nil)
        XCTAssertEqual(framing.canvas, CGSize(width: 1512, height: 982))
        XCTAssertEqual(framing.video, CGRect(origin: .zero, size: framing.canvas))
        XCTAssertFalse(framing.isFramed)
        XCTAssertEqual(framing.radius, 0)
    }

    func testABackgroundLeavesRoomRoundTheRecording() {
        var backdrop = Backdrop()
        backdrop.padding = 0.1
        let framing = StudioFraming(pixels: CGSize(width: 1280, height: 800), backdrop: backdrop)
        XCTAssertTrue(framing.isFramed)
        XCTAssertGreaterThan(framing.canvas.width, framing.video.width)
        XCTAssertGreaterThan(framing.canvas.height, framing.video.height)
        // In the middle, at the recording's own shape.
        XCTAssertEqual(framing.video.midX, framing.canvas.width / 2, accuracy: 1)
        XCTAssertEqual(framing.video.midY, framing.canvas.height / 2, accuracy: 1)
        XCTAssertEqual(framing.video.width / framing.video.height, 1.6, accuracy: 0.01)
        XCTAssertGreaterThan(framing.radius, 0)
        XCTAssertGreaterThan(framing.blur, 0)
    }

    func testPostsShapesAreMadeAtTheSizesTheyAskFor() {
        var backdrop = Backdrop()
        let sizes: [(Backdrop.Ratio, StudioOutput.Quality, CGSize)] = [
            (.story, .fullHD, CGSize(width: 1080, height: 1920)),
            (.square, .fullHD, CGSize(width: 1080, height: 1080)),
            (.portrait, .fullHD, CGSize(width: 1080, height: 1350)),
            (.wide, .fullHD, CGSize(width: 1920, height: 1080)),
            (.wide, .uhd, CGSize(width: 3840, height: 2160)),
            (.story, .uhd, CGSize(width: 2160, height: 3840)),
            (.wide, .hd, CGSize(width: 1280, height: 720)),
        ]
        for (ratio, quality, wanted) in sizes {
            backdrop.ratio = ratio
            let framing = StudioFraming(pixels: retina, backdrop: backdrop, quality: quality)
            XCTAssertEqual(framing.canvas, wanted, "\(ratio) at \(quality)")
            // The recording stays whole on it, with room to spare.
            XCTAssertTrue(CGRect(origin: .zero, size: framing.canvas).contains(framing.video), "\(ratio) at \(quality)")
            XCTAssertEqual(framing.video.width / framing.video.height, 1.6, accuracy: 0.01)
        }
    }

    func testTheQualityChosenSetsTheShorterSide() {
        XCTAssertEqual(StudioFraming(pixels: retina, backdrop: nil, quality: .fullHD).canvas, CGSize(width: 1728, height: 1080))
        XCTAssertEqual(StudioFraming(pixels: retina, backdrop: nil, quality: .hd).canvas, CGSize(width: 1152, height: 720))
        XCTAssertEqual(StudioFraming(pixels: retina, backdrop: nil, quality: .original).canvas, retina)
    }

    func testNothingIsMadeLargerThan4K() {
        let large = StudioFraming(pixels: CGSize(width: 5120, height: 2880), backdrop: nil)
        XCTAssertEqual(large.canvas, CGSize(width: 3840, height: 2160))
        var backdrop = Backdrop()
        backdrop.ratio = .story
        let tall = StudioFraming(pixels: retina, backdrop: backdrop)
        XCTAssertLessThanOrEqual(max(tall.canvas.width, tall.canvas.height), 3840)
        XCTAssertLessThanOrEqual(tall.canvas.width * tall.canvas.height, 3840 * 2160)
    }

    func testTheVideoIsEvenOnBothSides() {
        var backdrop = Backdrop()
        for ratio in Backdrop.Ratio.allCases {
            for quality in StudioOutput.Quality.allCases {
                backdrop.ratio = ratio
                for pixels in [CGSize(width: 1511, height: 981), CGSize(width: 333, height: 777), retina] {
                    let canvas = StudioFraming(pixels: pixels, backdrop: backdrop, quality: quality).canvas
                    XCTAssertEqual(Int(canvas.width) % 2, 0, "\(pixels) \(ratio) \(quality)")
                    XCTAssertEqual(Int(canvas.height) % 2, 0, "\(pixels) \(ratio) \(quality)")
                }
            }
        }
    }

    func testAGIFIsMadeSmallWhateverIsChosen() {
        XCTAssertEqual(StudioOutput(quality: .uhd, kind: .gif).size, .hd)
        XCTAssertEqual(StudioOutput(quality: .uhd, kind: .mp4).size, .uhd)
    }

    // MARK: The work kept

    func testWorkKeptBeforeTheBackgroundStillOpens() throws {
        let before = #"{"zooms":[],"marks":[],"autoZoom":false,"showsClicks":false}"#
        let project = try JSONDecoder().decode(StudioProject.self, from: Data(before.utf8))
        XCTAssertFalse(project.autoZoom)
        XCTAssertFalse(project.showsClicks)
        XCTAssertNil(project.backdrop)
        // Older still, with fewer fields.
        let oldest = try JSONDecoder().decode(StudioProject.self, from: Data(#"{"zooms":[]}"#.utf8))
        XCTAssertTrue(oldest.autoZoom)
        XCTAssertTrue(oldest.showsClicks)
    }

    func testTheBackgroundIsKeptWithTheWork() throws {
        var project = StudioProject()
        var backdrop = Backdrop()
        backdrop.fill = .ocean
        backdrop.ratio = .story
        project.backdrop = backdrop
        let read = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(read, project)
        XCTAssertEqual(read.backdrop?.ratio, .story)
    }

    func testSavingAsWhatANewerSnapflyChoseFallsBackToAMovie() throws {
        let output = try JSONDecoder().decode(StudioOutput.self, from: Data(#"{"quality":"8k","kind":"webm"}"#.utf8))
        XCTAssertEqual(output, StudioOutput())
        let kept = StudioOutput(quality: .fullHD, kind: .mp4)
        XCTAssertEqual(try JSONDecoder().decode(StudioOutput.self, from: JSONEncoder().encode(kept)), kept)
    }
}
