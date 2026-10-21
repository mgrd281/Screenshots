import AppKit
import AVFoundation
import CoreImage

/// Everything Studio puts on a recording, fixed for a look at the preview or
/// for one export: the camera's path, the marks and when they show, and
/// the clicks to ring.
struct StudioLook: Sendable {
    let camera: StudioCamera
    let marks: [StudioProject.Mark]
    let numbers: [UUID: Int]
    let clicks: [StudioEvents.Click]
    /// The recording's own pixels, which the marks' sizes are measured in.
    let pixels: CGSize

    /// - Parameter camera: the camera worked out before for the same zooms,
    ///   so a change to the marks alone doesn't work it out again.
    init(project: StudioProject, events: StudioEvents?, duration: Double, pixels: CGSize, camera: StudioCamera? = nil) {
        self.camera = camera ?? StudioCamera(zooms: project.zooms, events: events, duration: duration)
        marks = project.marks.sorted { $0.start < $1.start }
        numbers = project.numbers
        clicks = project.showsClicks ? (events?.clicks ?? []).filter { StudioEvents.isInside($0.x, $0.y) } : []
        self.pixels = pixels
    }

    /// The unit the marks are measured in, for the recording shown `size`
    /// large, so they keep their size from the preview to the video.
    func unit(for size: CGSize) -> CGFloat {
        guard pixels.width > 0 else { return Drawing.unit(width: size.width, height: size.height) }
        return Drawing.unit(width: pixels.width, height: pixels.height) * size.width / pixels.width
    }

    /// Whether anything is drawn over the picture at a time.
    func draws(at t: Double) -> Bool {
        marks.contains { t >= $0.start && t < $0.end }
            || clicks.contains { t >= $0.t && t < $0.t + StudioFade.ripple }
    }
}

/// How Studio draws: a frame of the recording through the camera, and the
/// marks and clicks over it. The preview and the video are drawn by the
/// same code, so what you see is what is saved.
enum StudioDraw {
    /// The marks and clicks at a time, in a context whose origin is the
    /// view's bottom left, `size` large, seen through the camera's `rect`.
    /// - Parameter still: Reduce Motion, in the preview: marks only fade.
    static func overlay(_ look: StudioLook, at t: Double, rect: CGRect, in context: CGContext, size: CGSize,
                        still: Bool = false) {
        let unit = look.unit(for: size)
        let place = { (point: CGPoint) in StudioCamera.shown(point, through: rect) }
        for click in look.clicks {
            guard let ring = StudioFade.ripple(at: t, click: click.t) else { continue }
            let at = Drawing.point(place(CGPoint(x: click.x, y: click.y)), in: size)
            drawRing(at: at, size: ring.size, opacity: ring.opacity, unit: unit, in: context)
        }
        for item in look.marks {
            guard let presence = StudioFade.presence(at: t, start: item.start, end: item.end, still: still) else { continue }
            var mark = item.mark
            mark.from = place(mark.from)
            mark.to = place(mark.to)
            context.saveGState()
            context.setAlpha(CGFloat(presence.opacity))
            let drawn = CGFloat(presence.drawn)
            switch mark.kind {
            case .arrow:
                // Drawn from its tail to its tip.
                mark.to = CGPoint(x: mark.from.x + (mark.to.x - mark.from.x) * drawn,
                                  y: mark.from.y + (mark.to.y - mark.from.y) * drawn)
            case .step, .text:
                grow(context, about: Drawing.point(mark.from, in: size), by: 0.6 + 0.4 * drawn)
            case .box, .circle, .highlight:
                let box = Drawing.rect(mark.rect, in: size)
                grow(context, about: CGPoint(x: box.midX, y: box.midY), by: 0.92 + 0.08 * drawn)
            }
            Drawing.draw([mark], in: context, size: size, unit: unit, numbered: look.numbers)
            context.restoreGState()
        }
    }

    private static func grow(_ context: CGContext, about center: CGPoint, by scale: CGFloat) {
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -center.x, y: -center.y)
    }

    /// A click's ring: white, with a soft dark edge, so it shows on light
    /// and dark pages alike.
    private static func drawRing(at center: CGPoint, size: Double, opacity: Double, unit: CGFloat, in context: CGContext) {
        let across = unit * 0.034 * CGFloat(size)
        let width = max(1.5, unit * 0.0035)
        let ring = CGRect(x: center.x - across / 2, y: center.y - across / 2, width: across, height: across)
        let shown = CGFloat(opacity)
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 0.18 * shown))
        context.fillEllipse(in: ring)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.28 * shown))
        context.setLineWidth(width + 2)
        context.strokeEllipse(in: ring)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95 * shown))
        context.setLineWidth(width)
        context.strokeEllipse(in: ring)
        context.restoreGState()
    }

    /// A frame of the video: the recording's picture through the camera at
    /// that time, at the recording's own size, then what is drawn over it.
    static func frame(_ source: CVPixelBuffer, into output: CVPixelBuffer, look: StudioLook, at t: Double,
                      context: CIContext) {
        let width = CVPixelBufferGetWidth(output), height = CVPixelBufferGetHeight(output)
        let size = CGSize(width: width, height: height)
        let rect = look.camera.rect(at: t)
        let picture = CIImage(cvPixelBuffer: source)
        let extent = picture.extent
        let crop = CGRect(x: extent.minX + rect.minX * extent.width, y: extent.minY + rect.minY * extent.height,
                          width: rect.width * extent.width, height: rect.height * extent.height)
        let move = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
            .concatenating(CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
        let seen = picture.clampedToExtent().cropped(to: crop).transformed(by: move)
            .cropped(to: CGRect(origin: .zero, size: size))
        context.render(seen, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
        guard look.draws(at: t) else { return }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let base = CVPixelBufferGetBaseAddress(output), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let drawing = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(output), space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        overlay(look, at: t, rect: rect, in: drawing, size: size)
    }
}

/// Writes the recording as Studio shows it: sixty frames a second, each
/// through the camera with the marks and clicks drawn on, at the
/// recording's own size, and its sound as it was.
enum StudioExport {
    enum Failure: Error {
        case noPicture, cannotRead, cannotWrite, cancelled
    }

    /// Set from the window to stop an export under way.
    final class Stop: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func set() {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    /// Something that happened on one of the inputs' queues, read once they
    /// are all done.
    private typealias Flag = Stop

    /// Where the pictures are up to, used on their queue alone.
    private final class PictureState: @unchecked Sendable {
        var index = 0
        var current: CVPixelBuffer?
        var next: CMSampleBuffer?
        var done = false
        /// The last share of the work told, in hundredths.
        var told = -1

        init(next: CMSampleBuffer?) {
            self.next = next
        }
    }

    static let rate: Int32 = 60

    /// Writes `source` as Studio shows it to `target`, by way of a hidden
    /// file beside it so the folder watcher ignores it until it is done.
    static func run(_ source: URL, look: StudioLook, to target: URL, stop: Stop,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noPicture
        }
        let natural = try await track.load(.naturalSize)
        let sounds = try await asset.loadTracks(withMediaType: .audio)
        var found: [CMFormatDescription?] = []
        for sound in sounds { found.append(try await sound.load(.formatDescriptions).first) }
        let hints = found
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".studio-\(UUID().uuidString)").appendingPathExtension("mov")
        do {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try write(asset: asset, track: track, size: natural, sounds: sounds, hints: hints,
                                  duration: duration, look: look, to: temp, stop: stop, progress: progress)
                        done.resume()
                    } catch {
                        done.resume(throwing: error)
                    }
                }
            }
            let fm = FileManager.default
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: temp, to: target)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    // The reader and writer are kept to this one queue's work and the
    // inputs' own queues, so they are never used from two places at once.
    private static func write(asset: AVAsset, track: AVAssetTrack, size natural: CGSize, sounds: [AVAssetTrack],
                              hints: [CMFormatDescription?], duration: Double, look: StudioLook, to temp: URL,
                              stop: Stop, progress: @escaping @Sendable (Double) -> Void) throws {
        let reader = try AVAssetReader(asset: asset)
        let pictures = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        pictures.alwaysCopiesSampleData = false
        guard reader.canAdd(pictures) else { throw Failure.cannotRead }
        reader.add(pictures)

        let width = max(2, Int((natural.width / 2).rounded()) * 2)
        let height = max(2, Int((natural.height / 2).rounded()) * 2)
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mov)
        // About as sharp as the recording, for text that stays crisp when
        // zoomed in on.
        let bitRate = min(80_000_000, max(6_000_000, Int(Double(width * height) * Double(rate) * 0.08)))
        let picture = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(rate),
                AVVideoMaxKeyFrameIntervalKey: Int(rate) * 2,
            ],
        ])
        picture.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: picture, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
        ])
        guard writer.canAdd(picture) else { throw Failure.cannotWrite }
        writer.add(picture)

        // The sound is copied as it is, track by track.
        var copies: [(from: AVAssetReaderTrackOutput, to: AVAssetWriterInput)] = []
        for (i, sound) in sounds.enumerated() {
            let from = AVAssetReaderTrackOutput(track: sound, outputSettings: nil)
            let to = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hints[i])
            to.expectsMediaDataInRealTime = false
            guard reader.canAdd(from), writer.canAdd(to) else { continue }
            reader.add(from)
            writer.add(to)
            copies.append((from, to))
        }

        guard reader.startReading() else { throw reader.error ?? Failure.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? Failure.cannotWrite
        }
        let next = pictures.copyNextSampleBuffer()
        let start = next?.presentationTimeStamp ?? .zero
        writer.startSession(atSourceTime: start)

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                          .cacheIntermediates: false])
        let total = max(1, Int((duration * Double(rate)).rounded(.down)))
        let group = DispatchGroup()
        let failed = Flag()

        // Each input's work stays on its own queue, its state with it.
        group.enter()
        let state = PictureState(next: next)
        let pictureQueue = DispatchQueue(label: "de.ghazarian.Snapfly.studio.picture")
        picture.requestMediaDataWhenReady(on: pictureQueue) {
            func finish(_ failure: Bool) {
                guard !state.done else { return }
                state.done = true
                if failure { failed.set() }
                picture.markAsFinished()
                group.leave()
            }
            while picture.isReadyForMoreMediaData {
                guard !stop.isSet, state.index < total else { return finish(false) }
                let t = Double(state.index) / Double(rate)
                // The newest picture by then: the screen sends one only
                // when something changed.
                while let sample = state.next, (sample.presentationTimeStamp - start).seconds <= t + 0.0005 {
                    if let buffer = CMSampleBufferGetImageBuffer(sample) { state.current = buffer }
                    state.next = pictures.copyNextSampleBuffer()
                }
                guard let source = state.current else {
                    state.index += 1
                    continue
                }
                var made: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let output = made
                else { return finish(true) }
                StudioDraw.frame(source, into: output, look: look, at: t, context: context)
                let time = CMTimeAdd(start, CMTime(value: CMTimeValue(state.index), timescale: rate))
                guard adaptor.append(output, withPresentationTime: time) else { return finish(true) }
                state.index += 1
                // A hundred steps at most, so the window keeps up.
                let share = Int(min(1, t / duration) * 100)
                if share != state.told {
                    state.told = share
                    progress(Double(share) / 100)
                }
            }
        }

        for (n, copy) in copies.enumerated() {
            group.enter()
            let soundDone = Flag()
            let queue = DispatchQueue(label: "de.ghazarian.Snapfly.studio.sound.\(n)")
            copy.to.requestMediaDataWhenReady(on: queue) {
                while copy.to.isReadyForMoreMediaData {
                    guard !soundDone.isSet else { return }
                    if !stop.isSet, let sample = copy.from.copyNextSampleBuffer() {
                        if copy.to.append(sample) { continue }
                        // The writer has failed: it asks for nothing more.
                        failed.set()
                    }
                    soundDone.set()
                    copy.to.markAsFinished()
                    group.leave()
                    return
                }
            }
        }

        // Should the writer or the reader fail while an input waits, it is
        // never asked for more: the wait ends then too.
        while group.wait(timeout: .now() + .milliseconds(250)) == .timedOut {
            if writer.status == .failed || reader.status == .failed {
                failed.set()
                break
            }
        }
        if stop.isSet {
            reader.cancelReading()
            writer.cancelWriting()
            throw Failure.cancelled
        }
        if failed.isSet || reader.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            throw writer.error ?? reader.error ?? Failure.cannotWrite
        }
        writer.endSession(atSourceTime: CMTimeAdd(start, CMTime(seconds: duration, preferredTimescale: 600)))
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else { throw writer.error ?? Failure.cannotWrite }
        progress(1)
    }
}

/// What the timeline shows of the recording: little pictures along it and
/// its sound's loudness. Read in the background as the window opens.
enum StudioMedia {
    /// `count` pictures spread along the recording, `height` points tall.
    static func strip(of url: URL, count: Int, height: CGFloat) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        guard count > 0, let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 4, height: height * 2)
        let tolerance = CMTime(seconds: duration / Double(count) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var images: [CGImage] = []
        for i in 0..<count {
            let time = CMTime(seconds: duration * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            images.append(image)
        }
        return images
    }

    /// The sound's loudness in `count` parts, from 0 to 1; empty without
    /// sound.
    static func wave(of url: URL, count: Int) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        return await withCheckedContinuation { (done: CheckedContinuation<[Float], Never>) in
            DispatchQueue.global(qos: .utility).async {
                done.resume(returning: read(asset: asset, tracks: tracks, count: count, duration: duration))
            }
        }
    }

    private static let soundRate = 8000.0

    private static func read(asset: AVAsset, tracks: [AVAssetTrack], count: Int, duration: Double) -> [Float] {
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: soundRate,
            AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var folding = StudioWave.Folding(count: count, expected: Int(duration * soundRate))
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let floats = length / MemoryLayout<Float>.size
            guard floats > 0 else { continue }
            var chunk = [Float](repeating: 0, count: floats)
            let bytes = floats * MemoryLayout<Float>.size
            let status = chunk.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: buffer.baseAddress!)
            }
            if status == kCMBlockBufferNoErr { folding.add(chunk) }
        }
        return folding.peaks
    }
}
