import AVFoundation
import CoreImage
import CoreMotion
import os
import SwiftUI
import UIKit
import Vision

/// Snapfly's own camera for pages, a test for now, switched on in More ›
/// Detection (`isOn`); the system's document camera otherwise. It takes the
/// page at the camera's full resolution (up to 24 MP) with the close-focus lens the
/// iPhone switches to by itself, focus and exposure on the page's middle and
/// the white balance kept once the paper fills the view. Ten times a second
/// it tells from the preview whether the page can be taken (`ScanReadiness`):
/// when the print is sharp, the phone still and the smallest letters large
/// enough, it takes the page by itself; otherwise one short hint says what
/// to do. Where the camera's photos are no larger than 12 MP it takes four
/// frames and merges them (`ScanBurst`); larger, one photo of the best
/// quality, which the iPhone already makes of several. The frames stay in
/// memory only. `done` gets the pages, whole photos whose page is still to
/// be found, or none when it was closed. With `closeUp`, it takes one
/// close-up of a page's small print (`ScanDetail`): no whole page in view,
/// the letters larger, and it closes once it is taken.
struct PageCamera: View {
    /// Whether Snapfly's own camera takes pages instead of the system's.
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static let key = "snapfly.scan.ownCamera"

    let closeUp: Bool
    let done: ([CGImage]) -> Void
    @StateObject private var camera: PageCameraModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(closeUp: Bool = false, done: @escaping ([CGImage]) -> Void) {
        self.closeUp = closeUp
        self.done = done
        _camera = StateObject(wrappedValue: PageCameraModel(closeUp: closeUp))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PageCameraPreview(session: camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                top
                if closeUp { card }
                Spacer(minLength: 16)
                hint
                    .padding(.bottom, 20)
                bottom
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if camera.taking {
                Color.white.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .light), trigger: camera.readyCount)
        .sensoryFeedback(.success, trigger: camera.pages.count)
        .onAppear { camera.start() }
        // A close-up is one picture: the camera closes once it is taken.
        .onChange(of: camera.pages.count) { _, count in
            guard closeUp, count > 0 else { return }
            camera.stop()
            done(camera.pages)
        }
        .onDisappear { camera.stop() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: camera.taking)
    }

    /// Close on the leading side, the light on the trailing side once more is asked for.
    private var top: some View {
        HStack {
            Button {
                camera.stop()
                done([])
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .editorGlass(in: Circle())
            }
            .accessibilityLabel(L("Cancel"))
            Spacer()
            if camera.hasTorch {
                Button { camera.toggleTorch() } label: {
                    Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .editorGlass(in: Circle())
                }
                .accessibilityLabel(L("Torch"))
                .accessibilityValue(camera.torchOn ? L("On") : L("Off"))
            }
        }
        .foregroundStyle(.white)
    }

    /// What a close-up is for, on glass under the buttons.
    private var card: some View {
        VStack(spacing: 4) {
            Text(L("Take Small Print Closer"))
                .font(.headline)
            Text(L("Hold the iPhone close over the small print."))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .editorGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The one hint, calm on glass; or what to point at, while no page is seen.
    @ViewBuilder private var hint: some View {
        let words = camera.message
        Text(words ?? " ")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .editorGlass(in: Capsule())
            .opacity(words == nil ? 0 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: words)
            .accessibilityHidden(words == nil)
    }

    /// The pages taken so far, the shutter, and Done.
    private var bottom: some View {
        ZStack {
            HStack {
                if let last = camera.thumbnail {
                    Image(uiImage: last)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Text("\(camera.pages.count)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(SnapflyTokens.protect, in: Capsule())
                                .offset(x: 8, y: -8)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(String(format: L("Page %d"), camera.pages.count))
                }
                Spacer()
                Button(L("Done")) {
                    camera.stop()
                    done(camera.pages)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(SnapflyTokens.protect, in: Capsule())
                .opacity(camera.pages.isEmpty ? 0 : 1)
                .disabled(camera.pages.isEmpty)
            }
            Button { camera.take() } label: {
                Circle()
                    .fill(.white)
                    .padding(5)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2.5))
                    .frame(width: 68, height: 68)
            }
            .disabled(camera.taking)
            .accessibilityLabel(L("Take Page"))
        }
    }
}

/// The camera's picture, filling the screen.
private struct PageCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Shown: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Shown {
        let view = Shown()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: Shown, context: Context) {}
}

/// The camera behind `PageCamera`: the session, what the preview tells, the
/// pages taken.
@MainActor
final class PageCameraModel: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var hint: ScanReadiness.Hint?
    /// No page seen yet, for the words that ask for one.
    @Published private(set) var seesPage = false
    @Published private(set) var pages: [CGImage] = []
    /// The last page small, for its corner.
    @Published private(set) var thumbnail: UIImage?
    @Published private(set) var taking = false
    @Published private(set) var torchOn = false
    @Published private(set) var hasTorch = false
    /// The camera was not allowed.
    @Published private(set) var denied = false
    /// Each time the page becomes ready, for the light tap.
    @Published private(set) var readyCount = 0

    private let queue = DispatchQueue(label: "snapfly.page-camera")
    private let analyzer: PageAnalyzer
    private let closeUp: Bool
    private let photos = AVCapturePhotoOutput()
    private let frames = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var dimensions = CMVideoDimensions(width: 0, height: 0)
    private var configured = false
    /// Taken by itself once, it waits for the page to change before it takes another.
    private var armed = true
    private var wasReady = false
    /// A hint is shown once it has held for a moment, so it does not flicker.
    private var pending: (hint: ScanReadiness.Hint?, since: Date)?
    private var lastPoint: CGPoint?
    private var lastPointAt = Date.distantPast
    private var whiteKept = false
    /// Where the page lay when it was taken by itself.
    private var takenAt: CGRect?
    private var lastPage: CGRect?
    nonisolated private static let log = Logger(subsystem: "app.snapfly", category: "PageCamera")

    init(closeUp: Bool = false) {
        self.closeUp = closeUp
        analyzer = PageAnalyzer(tuning: closeUp ? .closeUp : .init())
    }

    /// The hint's words, or what to point at while no page is seen.
    var message: String? {
        if denied { return L("Snapfly may not use the camera. Allow it in Settings.") }
        guard let hint else {
            if seesPage || taking { return nil }
            return closeUp ? L("Point the camera at the small print") : L("Point the camera at a page")
        }
        return hint.message
    }

    func start() {
        analyzer.onLook = { [weak self] state, page in
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.saw(state, page: page) } }
        }
        analyzer.startMotion()
        Task {
            // Asked once; what was said before is kept.
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                denied = true
                return
            }
            configure()
            let session = self.session
            queue.async { session.startRunning() }
        }
    }

    func stop() {
        analyzer.stopMotion()
        let session = self.session
        queue.async { session.stopRunning() }
    }

    /// The best camera for a page close up: the one that switches lenses by
    /// itself, else the wide one; photos at its largest size, of the best quality.
    private func configure() {
        guard !configured else { return }
        configured = true
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back).devices.first
        guard let device = found, let input = try? AVCaptureDeviceInput(device: device) else {
            Self.log.error("No camera for pages")
            return
        }
        self.device = device
        hasTorch = device.hasTorch
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photos) { session.addOutput(photos) }
        frames.alwaysDiscardsLateVideoFrames = true
        frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        frames.setSampleBufferDelegate(analyzer, queue: analyzer.queue)
        if session.canAddOutput(frames) { session.addOutput(frames) }
        photos.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()
        // The format the photo preset chose, at its largest size up to 24 MP:
        // 48 MP pages would take four times the memory and time to make.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        let fitting = sizes.filter { Int($0.width) * Int($0.height) <= 25_000_000 }
        let largest = (fitting.isEmpty ? sizes : fitting).max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        if let largest {
            photos.maxPhotoDimensions = largest
            dimensions = largest
        }
        analyzer.photoHeight = Int(max(dimensions.width, dimensions.height))
        let said = "Camera \(device.localizedName), photos \(dimensions.width)×\(dimensions.height), "
            + "closest focus \(device.minimumFocusDistance) mm"
        Self.log.info("\(said, privacy: .public)")
    }

    /// What the preview told: the hint, once it held; the page taken once it is ready.
    private func saw(_ state: ScanReadiness.State, page: CGRect?) {
        seesPage = page != nil
        // Another page, or this one laid elsewhere, is taken by itself again.
        if !armed, page.map({ seen in takenAt.map { Self.apart(seen, $0) } ?? true }) ?? true { armed = true }
        lastPage = page
        if state.ready && !wasReady { readyCount += 1 }
        wasReady = state.ready
        let now = Date.now
        if pending?.hint != state.hint { pending = (state.hint, now) }
        if let pending, pending.hint != hint, now.timeIntervalSince(pending.since) >= 0.4 || pending.hint == nil {
            hint = pending.hint
            if let words = pending.hint?.message, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: words)
            }
        }
        if let page { aim(at: page, steady: state.hint != .steady) }
        if state.ready, armed, !taking { take() }
    }

    /// Whether two places of the page are far apart: its middle moved by a
    /// tenth of the view or more, or its size by a third.
    private static func apart(_ a: CGRect, _ b: CGRect) -> Bool {
        let moved = hypot(a.midX - b.midX, a.midY - b.midY)
        let sizes = (a.width * a.height) / max(0.001, b.width * b.height)
        return moved > 0.1 || sizes > 1.33 || sizes < 0.75
    }

    /// Focus and exposure on the page's middle; the white balance kept once
    /// the paper fills the view and the phone is still.
    private func aim(at page: CGRect, steady: Bool) {
        guard let device else { return }
        // Vision's point, upright from the bottom left, as the camera's own, turned from the top left.
        let point = CGPoint(x: 1 - page.midY, y: 1 - page.midX)
        let now = Date.now
        let moved = lastPoint.map { hypot($0.x - point.x, $0.y - point.y) > 0.05 } ?? true
        let keepWhite = steady && !whiteKept && page.width * page.height > 0.35
        guard moved && now.timeIntervalSince(lastPointAt) > 0.5 || keepWhite else { return }
        lastPoint = point
        lastPointAt = now
        if keepWhite { whiteKept = true }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            if keepWhite, device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        }
    }

    /// The torch at a low level, never the flash.
    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        let on = !torchOn
        torchOn = on
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if on { try? device.setTorchModeOn(level: 0.15) } else { device.torchMode = .off }
            device.unlockForConfiguration()
        }
    }

    /// The page taken: four frames merged where photos are 12 MP, else one of the best quality.
    func take() {
        guard !taking, session.isRunning else { return }
        taking = true
        armed = false
        takenAt = lastPage
        let started = Date.now
        let large = Int(dimensions.width) * Int(dimensions.height) > 12_500_000
        let settings: AVCapturePhotoSettings
        if !large, photos.maxBracketedCapturePhotoCount >= 4 {
            let frame = AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 0)
            settings = AVCapturePhotoBracketSettings(rawPixelFormatType: 0,
                                                     processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg],
                                                     bracketedSettings: Array(repeating: frame, count: 4))
            settings.photoQualityPrioritization = .speed
        } else {
            settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
        }
        if dimensions.width > 0 { settings.maxPhotoDimensions = dimensions }
        settings.flashMode = .off
        let taker = PhotoTaker { [weak self] data in
            let shot = Date.now
            Task.detached(priority: .userInitiated) { [weak self] in
                let page = PageCameraModel.page(from: data)
                let made = Date.now
                let small = page.flatMap { ScanCleaner.smaller($0, longest: 160) }.map { UIImage(cgImage: $0) }
                let said = String(format: "Page from %d frames: taken in %.2f s, made in %.2f s", data.count,
                                  shot.timeIntervalSince(started), made.timeIntervalSince(shot))
                PageCameraModel.log.info("\(said, privacy: .public)")
                await self?.took(page, small: small)
            }
        }
        analyzer.taker = taker
        photos.capturePhoto(with: settings, delegate: taker)
    }

    private func took(_ page: CGImage?, small: UIImage?) {
        taking = false
        guard let page else { return }
        pages.append(page)
        thumbnail = small
    }

    /// The frames as one page, upright: merged where there are several.
    nonisolated private static func page(from data: [Data]) -> CGImage? {
        let pictures = data.compactMap { Covering.upright($0, longest: 8192) }
        guard pictures.count > 1 else { return pictures.first }
        let bitmaps = pictures.compactMap(ScanCleaner.bitmap)
        guard let merged = ScanBurst.merged(bitmaps) else { return pictures.first }
        log.info("Frames used \(merged.used.count) of \(bitmaps.count)")
        return ScanCleaner.image(merged.page, gray: false) ?? pictures.first
    }
}

/// Takes a photo, or a burst of them, and hands their data over once all came.
private final class PhotoTaker: NSObject, AVCapturePhotoCaptureDelegate {
    private var data: [Data] = []
    private let done: ([Data]) -> Void

    init(done: @escaping ([Data]) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil, let file = photo.fileDataRepresentation() { data.append(file) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        done(data)
    }
}

/// Reads the preview ten times a second: where the page and its lines of
/// text are (Vision), its brightness made small and upright, and how long
/// the phone has been still (Core Motion); tells `ScanReadiness`.
private final class PageAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "snapfly.page-camera.frames")
    let tuning: ScanReadiness.Tuning

    init(tuning: ScanReadiness.Tuning) {
        self.tuning = tuning
        super.init()
    }

    /// What the preview told, and where the page is; for a close-up, where its print is.
    var onLook: ((ScanReadiness.State, CGRect?) -> Void)?
    /// Kept while its photos are taken.
    var taker: AnyObject?
    var photoHeight = 4032
    private let motion = CMMotionManager()
    private let lock = NSLock()
    private var stillSince = Date.now
    private var lastLook = Date.distantPast
    private var lastSmudge = Date.distantPast
    private var smudged = false
    private let context = CIContext()

    func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] reading, _ in
            guard let self, let reading else { return }
            let r = reading.rotationRate, a = reading.userAcceleration
            let turning = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            let moving = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if turning > 0.12 || moving > 0.04 {
                self.lock.lock()
                self.stillSince = Date.now
                self.lock.unlock()
            }
        }
    }

    func stopMotion() { motion.stopDeviceMotionUpdates() }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date.now
        guard now.timeIntervalSince(lastLook) >= 0.1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastLook = now
        let pageRequest = VNDetectDocumentSegmentationRequest()
        let textRequest = VNDetectTextRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
        try? handler.perform([pageRequest, textRequest])
        let page = pageRequest.results?.first.flatMap { $0.confidence >= 0.5 ? $0.boundingBox : nil }
        let lines = (textRequest.results ?? []).map(\.boundingBox)
        guard let small = Self.plane(buffer) else { return }
        lock.lock()
        let still = now.timeIntervalSince(motion.isDeviceMotionActive ? stillSince : now.addingTimeInterval(-1))
        lock.unlock()
        // A smudged lens is asked about every two seconds, as Vision tells it slowly.
        if now.timeIntervalSince(lastSmudge) >= 2 {
            lastSmudge = now
            if let picture = context.createCGImage(CIImage(cvPixelBuffer: buffer).oriented(.right),
                                                   from: CIImage(cvPixelBuffer: buffer).oriented(.right).extent) {
                Task { [weak self] in
                    let found = await ScanCleaner.smudged(picture)
                    self?.queue.async { [weak self] in self?.smudged = found }
                }
            }
        }
        let look = ScanReadiness.Look(plane: small.plane, width: small.width, height: small.height, page: page, lines: lines,
                                      photoHeight: photoHeight, still: still, smudged: smudged)
        let aimed = tuning.needsPage ? page : lines.dropFirst().reduce(lines.first) { $0?.union($1) }
        onLook?(ScanReadiness.state(of: look, tuning: tuning), aimed)
    }

    /// The preview's brightness, upright and no wider than about 640 pixels,
    /// rows from the top. The camera's frames lie on their side: their top
    /// is the upright picture's right.
    static func plane(_ buffer: CVPixelBuffer) -> (plane: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let step = max(1, max(w, h) / 640)
        let width = h / step, height = w / step
        guard width > 8, height > 8 else { return nil }
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var plane = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let bx = y * step
            for x in 0..<width {
                let by = h - 1 - x * step
                plane[y * width + x] = luma[by * row + bx]
            }
        }
        return (plane, width, height)
    }
}
