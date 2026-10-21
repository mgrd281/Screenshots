#if os(macOS)
import AppKit
import AVFoundation
import CoreText
import SwiftUI
import XCTest
@testable import Tendedero

/// Studio's video, made from made-up recordings: it is zoomed in where the
/// camera looks, the marks are drawn into it, and it keeps its length and
/// size. With STUDIO_CAPTURES set to a folder, it also keeps pictures of a
/// made-up screen recording as Studio saves it, and of Studio's window, for
/// review (the Studio Checks workflow).
final class StudioRenderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: The video

    func testTheVideoIsZoomedInWhereTheCameraLooks() async throws {
        let source = folder.appendingPathComponent("quarters.mov")
        try StudioSample.writeMovie(to: source, width: 320, height: 180, seconds: 2, draw: StudioSample.quarters)
        var project = StudioProject()
        project.zooms = [StudioZoom(start: 0, end: 2, scale: 2, focus: .point(x: 0.25, y: 0.75))]
        let made = try await export(source, project)
        // At the start the whole picture shows; settled, only its top left quarter.
        let first = try await StudioSample.frame(of: made, at: 0)
        XCTAssertTrue(StudioSample.pixel(first, x: 0.75, y: 0.25).isGreen)
        let settled = try await StudioSample.frame(of: made, at: 1.8)
        for (x, y) in [(0.1, 0.1), (0.5, 0.5), (0.9, 0.9), (0.1, 0.9), (0.9, 0.1)] {
            XCTAssertTrue(StudioSample.pixel(settled, x: x, y: y).isBlue, "at \(x), \(y)")
        }
    }

    func testMarksAreDrawnIntoTheVideoWhileTheyShow() async throws {
        let source = folder.appendingPathComponent("quarters.mov")
        try StudioSample.writeMovie(to: source, width: 320, height: 180, seconds: 2, draw: StudioSample.quarters)
        var project = StudioProject()
        project.showsClicks = false
        let step = Drawing.Mark(kind: .step, from: CGPoint(x: 0.75, y: 0.25), to: CGPoint(x: 0.75, y: 0.25),
                                ink: .blue, size: .thick)
        project.marks = [StudioProject.Mark(mark: step, start: 0.5, end: 2)]
        let made = try await export(source, project)
        // Beside the digit, inside the step's circle.
        let x = 0.75 + 7.0 / 320
        let before = try await StudioSample.frame(of: made, at: 0.3)
        XCTAssertTrue(StudioSample.pixel(before, x: x, y: 0.25).isGreen)
        let shown = try await StudioSample.frame(of: made, at: 1.2)
        XCTAssertTrue(StudioSample.pixel(shown, x: x, y: 0.25).isBlue)
    }

    func testTheVideoKeepsItsLengthAndSizeAtSixtyFramesASecond() async throws {
        let source = folder.appendingPathComponent("quarters.mov")
        try StudioSample.writeMovie(to: source, width: 320, height: 180, seconds: 2, draw: StudioSample.quarters)
        let made = try await export(source, StudioProject())
        let asset = AVURLAsset(url: made)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
        let rate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(Double(rate), 60, accuracy: 1.5)
    }

    func testStoppingLeavesNoVideo() async throws {
        let source = folder.appendingPathComponent("quarters.mov")
        try StudioSample.writeMovie(to: source, width: 320, height: 180, seconds: 2, draw: StudioSample.quarters)
        let target = folder.appendingPathComponent("stopped.mov")
        let stop = StudioExport.Stop()
        stop.set()
        let look = StudioLook(project: StudioProject(), events: nil, duration: 2, pixels: CGSize(width: 320, height: 180))
        do {
            try await StudioExport.run(source, look: look, to: target, stop: stop) { _ in }
            XCTFail("A stopped export should not finish")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".studio-") }
        XCTAssertEqual(left, [])
    }

    private func export(_ source: URL, _ project: StudioProject, events: StudioEvents? = nil) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let look = StudioLook(project: project, events: events, duration: duration, pixels: size)
        let target = folder.appendingPathComponent("made-\(UUID().uuidString).mov")
        try await StudioExport.run(source, look: look, to: target, stop: StudioExport.Stop()) { _ in }
        return target
    }

    // MARK: The work kept

    func testTrimmingMovesTheWorkToTheNewStart() {
        var project = StudioProject()
        project.zooms = [StudioZoom(start: 1, end: 4, scale: 2), StudioZoom(start: 8, end: 9.5, scale: 2)]
        let arrow = Drawing.Mark(kind: .arrow, from: .zero, to: CGPoint(x: 0.5, y: 0.5), ink: .red, size: .medium)
        let late = Drawing.Mark(kind: .box, from: .zero, to: CGPoint(x: 0.5, y: 0.5), ink: .red, size: .medium)
        project.marks = [StudioProject.Mark(mark: arrow, start: 2, end: 5), StudioProject.Mark(mark: late, start: 9, end: 10)]
        let trimmed = project.trimmed(from: 2, keeping: 5)
        XCTAssertEqual(trimmed.zooms.count, 1)
        XCTAssertEqual(trimmed.zooms[0].start, 0)
        XCTAssertEqual(trimmed.zooms[0].end, 2)
        XCTAssertEqual(trimmed.marks.map(\.id), [arrow.id])
        XCTAssertEqual(trimmed.marks[0].start, 0)
        XCTAssertEqual(trimmed.marks[0].end, 3)
    }

    func testStepsAreNumberedInTheOrderTheyShow() {
        var project = StudioProject()
        let first = Drawing.Mark(kind: .step, from: .zero, to: .zero, ink: .red, size: .medium)
        let second = Drawing.Mark(kind: .step, from: .zero, to: .zero, ink: .red, size: .medium)
        project.marks = [StudioProject.Mark(mark: second, start: 4, end: 6), StudioProject.Mark(mark: first, start: 1, end: 3)]
        XCTAssertEqual(project.numbers[first.id], 1)
        XCTAssertEqual(project.numbers[second.id], 2)
    }

    func testAFirstProjectZoomsInOnWhatWasDone() {
        let events = StudioEvents(width: 1512, height: 982, clicks: [StudioEvents.Click(t: 3, x: 0.4, y: 0.6)])
        let project = StudioProject.first(events: events, duration: 10)
        XCTAssertEqual(project.zooms.count, 1)
        XCTAssertTrue(project.autoZoom)
        XCTAssertTrue(project.showsClicks)
        XCTAssertTrue(StudioProject.first(events: nil, duration: 10).zooms.isEmpty)
    }

    func testTheStoreKeepsWorkUnderANameThatSaysNothingAndMovesIt() {
        let old = folder.appendingPathComponent("Snapfly 2026-10-21 at 10.00.00.mov")
        let new = folder.appendingPathComponent("Moved.mov")
        let key = StudioStore.key(old)
        XCTAssertEqual(key.count, 32)
        XCTAssertFalse(key.contains("Snapfly"))
        XCTAssertEqual(key, StudioStore.key(old))
        XCTAssertNotEqual(key, StudioStore.key(new))
        var project = StudioProject()
        project.showsClicks = false
        StudioStore.setProject(project, for: old)
        defer {
            // Only what this test wrote goes.
            for url in [old, new] {
                try? FileManager.default.removeItem(at: StudioStore.folder
                    .appendingPathComponent("\(StudioStore.key(url)).project.json"))
            }
        }
        XCTAssertEqual(StudioStore.project(for: old), project)
        StudioStore.move(from: old, to: new)
        XCTAssertNil(StudioStore.project(for: old))
        XCTAssertEqual(StudioStore.project(for: new), project)
    }

    // MARK: Pictures for review

    /// A made-up screen recording as Studio saves it, frame by frame.
    func testCaptureTheVideo() async throws {
        guard let out = Self.captures else { throw XCTSkip("STUDIO_CAPTURES is not set") }
        let source = folder.appendingPathComponent("demo.mov")
        try StudioSample.writeMovie(to: source, width: 1280, height: 800, seconds: StudioSample.length,
                                    draw: StudioSample.screen)
        let events = StudioSample.events
        var project = StudioProject.first(events: events, duration: StudioSample.length)
        project.marks = StudioSample.marks
        let made = try await export(source, project, events: events)
        let fm = FileManager.default
        try? fm.removeItem(at: out.appendingPathComponent("studio-demo.mov"))
        try fm.copyItem(at: made, to: out.appendingPathComponent("studio-demo.mov"))
        try? fm.removeItem(at: out.appendingPathComponent("studio-source.mov"))
        try fm.copyItem(at: source, to: out.appendingPathComponent("studio-source.mov"))
        for t in [0.5, 1.4, 2.0, 2.4, 3.0, 3.6, 4.4, 5.3, 5.9] {
            let image = try await StudioSample.frame(of: made, at: t)
            try StudioSample.png(image, to: out.appendingPathComponent(String(format: "frame-%04.1f.png", t)))
        }
        let zooms = project.zooms.map { String(format: "%.2f–%.2f ×%.1f", $0.start, $0.end, $0.scale) }
        try zooms.joined(separator: "\n").write(to: out.appendingPathComponent("zooms.txt"), atomically: true, encoding: .utf8)
    }

    /// Studio's window, light and dark, with a mark and with a zoom chosen.
    @MainActor
    func testCaptureTheWindow() throws {
        guard let out = Self.captures else { throw XCTSkip("STUDIO_CAPTURES is not set") }
        let source = folder.appendingPathComponent("demo.mov")
        try StudioSample.writeMovie(to: source, width: 1280, height: 800, seconds: StudioSample.length,
                                    draw: StudioSample.screen)
        let events = StudioSample.events
        var project = StudioProject.first(events: events, duration: StudioSample.length)
        project.marks = StudioSample.marks
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for chosen in ["mark", "zoom"] {
                let model = StudioModel(url: source, duration: StudioSample.length, pixels: CGSize(width: 1280, height: 800),
                                        events: events, project: project)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 860),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                let hosting = NSHostingView(rootView: StudioEditorView(model: model, title: "Sample", finish: { _ in },
                                                                       stop: {}))
                window.contentView = hosting
                window.orderFrontRegardless()
                model.load()
                let t = chosen == "mark" ? 3.0 : 2.4
                model.seek(to: t)
                model.poster = StudioSample.image(at: t, width: 1280, height: 800, draw: StudioSample.screen)
                if chosen == "mark", let step = project.marks.first(where: { $0.mark.kind == .step }) {
                    model.tool = .select
                    model.choose(.mark(step.id))
                } else if let zoom = project.zooms.first(where: { $0.contains(t) }) {
                    model.choose(.zoom(zoom.id))
                }
                Self.spin(4)
                let bounds = hosting.bounds
                if let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) {
                    hosting.cacheDisplay(in: bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?
                        .write(to: out.appendingPathComponent("window-\(chosen)-\(name).png"))
                }
                window.orderOut(nil)
                model.close()
            }
        }
    }

    private static var captures: URL? {
        guard let path = ProcessInfo.processInfo.environment["STUDIO_CAPTURES"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Lets the window draw and the timeline's pictures load.
    @MainActor
    private static func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
}

/// Made-up recordings for Studio's tests: four coloured quarters, or a
/// screen with a form being filled in, its pointer drawn on as a recording
/// has it. No real names or details.
private enum StudioSample {
    typealias Draw = (CGContext, CGSize, Double) -> Void

    static let length = 6.4

    static func writeMovie(to url: URL, width: Int, height: Int, seconds: Double, draw: Draw) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
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
                draw(context, CGSize(width: width, height: height), Double(i) / Double(fps))
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

    static func image(at t: Double, width: Int, height: Int, draw: Draw) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context, CGSize(width: width, height: height), t)
        return context.makeImage()
    }

    /// Red, green, blue and yellow quarters: bottom left, bottom right, top
    /// left, top right.
    static func quarters(_ context: CGContext, _ size: CGSize, _ t: Double) {
        let w = size.width / 2, h = size.height / 2
        let colors: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: 0, width: w, height: h), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: w, y: 0, width: w, height: h), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: h, width: w, height: h), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: w, y: h, width: w, height: h), CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)),
        ]
        for (rect, color) in colors {
            context.setFillColor(color)
            context.fill(rect)
        }
    }

    // MARK: A form being filled in

    /// Where things are on the made-up screen, from 0 to 1 from the bottom left.
    static let field = CGPoint(x: 0.42, y: 0.56)
    static let send = CGPoint(x: 0.66, y: 0.33)
    static let help = CGPoint(x: 0.83, y: 0.81)
    static let typed = "INV-2026-0042"

    /// Where the pointer is: resting, then over the field, typing, over
    /// Send, then up to Help.
    static func pointer(at t: Double) -> CGPoint {
        let path: [(Double, CGPoint)] = [
            (0, CGPoint(x: 0.2, y: 0.78)), (0.9, CGPoint(x: 0.2, y: 0.78)), (1.8, field), (3.6, field),
            (4.3, send), (5.0, send), (5.6, help), (length, help),
        ]
        for (a, b) in zip(path, path.dropFirst()) where t >= a.0 && t <= b.0 {
            let f = b.0 > a.0 ? (t - a.0) / (b.0 - a.0) : 0
            let e = f * f * (3 - 2 * f)
            return CGPoint(x: a.1.x + (b.1.x - a.1.x) * e, y: a.1.y + (b.1.y - a.1.y) * e)
        }
        return help
    }

    static let clicks: [(Double, CGPoint)] = [(1.95, field), (4.45, send), (5.75, help)]
    static let keys: [Double] = stride(from: 2.3, through: 3.5, by: 0.1).map { $0 }

    static var events: StudioEvents {
        var events = StudioEvents(width: 1280, height: 800)
        events.pointer = stride(from: 0.0, through: length, by: 1.0 / 30).map {
            let p = pointer(at: $0)
            return StudioEvents.Point(t: $0, x: Double(p.x), y: Double(p.y))
        }
        events.clicks = clicks.map { StudioEvents.Click(t: $0.0, x: Double($0.1.x), y: Double($0.1.y)) }
        events.keys = keys
        return events
    }

    static var marks: [StudioProject.Mark] {
        let step = Drawing.Mark(kind: .step, from: CGPoint(x: field.x - 0.17, y: field.y), to: CGPoint(x: field.x - 0.17, y: field.y),
                                ink: .red, size: .medium)
        let arrow = Drawing.Mark(kind: .arrow, from: CGPoint(x: send.x - 0.16, y: send.y - 0.12),
                                 to: CGPoint(x: send.x - 0.05, y: send.y - 0.03), ink: .red, size: .medium)
        var words = Drawing.Mark(kind: .text, from: CGPoint(x: send.x - 0.2, y: send.y - 0.15),
                                 to: CGPoint(x: send.x - 0.2, y: send.y - 0.15), ink: .yellow, size: .medium)
        words.text = "Then send it"
        return [StudioProject.Mark(mark: step, start: 1.9, end: 3.8), StudioProject.Mark(mark: arrow, start: 3.9, end: 5.2),
                StudioProject.Mark(mark: words, start: 4.0, end: 5.2)]
    }

    /// A window with a form, filled in as the pointer goes, and the pointer.
    static func screen(_ context: CGContext, _ size: CGSize, _ t: Double) {
        let W = size.width, H = size.height
        context.setFillColor(CGColor(srgbRed: 0.36, green: 0.42, blue: 0.55, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let window = CGRect(x: W * 0.12, y: H * 0.1, width: W * 0.76, height: H * 0.8)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: window, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.94, alpha: 1))
        context.fill(CGRect(x: window.minX, y: window.maxY - 44, width: window.width, height: 32))
        for (i, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: window.minX + 18 + CGFloat(i) * 20, y: window.maxY - 26, width: 12, height: 12))
        }
        text("New Invoice", at: CGPoint(x: window.minX + W * 0.06, y: H * 0.75), size: 30, weight: .bold, in: context)
        text("Invoice number", at: CGPoint(x: W * field.x - W * 0.12, y: H * field.y + 30), size: 17, in: context)
        let box = CGRect(x: W * field.x - W * 0.12, y: H * field.y - 22, width: W * 0.3, height: 44)
        context.setStrokeColor(CGColor(gray: t >= clicks[0].0 && t < 3.8 ? 0.2 : 0.7, alpha: 1))
        context.setLineWidth(2)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()
        let count = keys.filter { $0 <= t }.count
        text(String(typed.prefix(count)), at: CGPoint(x: box.minX + 14, y: box.minY + 13), size: 19, in: context)
        for row in 0..<3 {
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: window.minX + W * 0.06, y: H * (0.42 - Double(row) * 0.06), width: W * 0.28, height: 12))
        }
        let pressed = t >= clicks[1].0 && t < clicks[1].0 + 0.25
        let button = CGRect(x: W * send.x - 70, y: H * send.y - 24, width: 140, height: 48)
        context.setFillColor(CGColor(srgbRed: 0, green: pressed ? 0.36 : 0.48, blue: pressed ? 0.8 : 1, alpha: 1))
        context.addPath(CGPath(roundedRect: button, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
        text("Send", at: CGPoint(x: button.minX + 46, y: button.minY + 15), size: 19, weight: .semibold,
             color: CGColor(gray: 1, alpha: 1), in: context)
        text("Help", at: CGPoint(x: W * help.x - 20, y: H * help.y - 8), size: 17,
             color: CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1), in: context)
        if t >= 4.6 {
            text("Sent", at: CGPoint(x: button.maxX + 20, y: button.minY + 15), size: 17,
                 color: CGColor(srgbRed: 0.16, green: 0.6, blue: 0.3, alpha: 1), in: context)
        }
        // The pointer, as a recording shows it.
        let p = pointer(at: t)
        let tip = CGPoint(x: W * p.x, y: H * p.y)
        let arrow = CGMutablePath()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x, y: tip.y - 26))
        arrow.addLine(to: CGPoint(x: tip.x + 7, y: tip.y - 20))
        arrow.addLine(to: CGPoint(x: tip.x + 12, y: tip.y - 30))
        arrow.addLine(to: CGPoint(x: tip.x + 16, y: tip.y - 28))
        arrow.addLine(to: CGPoint(x: tip.x + 11, y: tip.y - 18))
        arrow.addLine(to: CGPoint(x: tip.x + 19, y: tip.y - 18))
        arrow.closeSubpath()
        context.addPath(arrow)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.5)
        context.drawPath(using: .fillStroke)
    }

    private static func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
                             color: CGColor = CGColor(gray: 0.1, alpha: 1), in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): NSFont.systemFont(ofSize: size, weight: weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
    }

    // MARK: Reading the video back

    static func frame(of url: URL, at t: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    struct Pixel {
        var r: Int
        var g: Int
        var b: Int

        var isBlue: Bool { b > 170 && r < 110 && g < 170 }
        var isGreen: Bool { g > 170 && r < 110 && b < 110 }
    }

    /// A pixel's colour, at a place from 0 to 1 from the bottom left.
    static func pixel(_ image: CGImage, x: Double, y: Double) -> Pixel {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let column = min(width - 1, max(0, Int(x * Double(width))))
        let row = min(height - 1, max(0, Int((1 - y) * Double(height))))
        let i = (row * width + column) * 4
        return Pixel(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }

    static func png(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
