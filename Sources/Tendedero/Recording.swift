import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Records the screen from Snapfly itself: an area, a window or a whole
/// screen, chosen on the same still screens as a screenshot. A small capsule
/// above the Dock shows how long it has run, and a click on it stops. The
/// menu bar item and the shortcut stop it too. The recording hangs on the
/// line like one made with the Screenshot app, and Trim trims it.
///
/// Snapfly's own line and controls stay out of the recording. There is no
/// sound, so no microphone permission is asked for.
@MainActor
final class Recording {
    static let shared = Recording()

    /// Called with each recording once it is saved.
    var onFinish: (URL) -> Void = { _ in }
    /// Called when a recording starts or ends, for the menu bar item.
    var onChange: () -> Void = {}

    /// From the choice until the file is written.
    private(set) var isRecording = false

    private var recorder: Recorder?
    private var file: URL?
    private var frame = CGRect.zero
    private var started = Date()
    private var tick: Timer?
    private var badge: CaptureBadge?
    private var edge: RecordingEdge?

    func start(_ region: Capture.Region) {
        guard !isRecording else { return }
        isRecording = true
        onChange()
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let setup = Capture.setup(region, in: content, forVideo: true) else {
                    throw RecorderError.nothingToRecord
                }
                try FileManager.default.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
                // Hidden while it is written, so the folder watcher leaves it alone.
                let file = Inbox.folder.appendingPathComponent(".recording-\(UUID().uuidString).mov")
                let recorder = try Recorder(filter: setup.filter, configuration: setup.config, url: file)
                recorder.onFailure = {
                    DispatchQueue.main.async { MainActor.assumeIsolated { Recording.shared.stop() } }
                }
                try await recorder.start()
                self.recorder = recorder
                self.file = file
                self.frame = setup.frame
                showControls(for: region, frame: setup.frame)
            } catch {
                log.error("Could not record the screen: \(error.localizedDescription, privacy: .public)")
                isRecording = false
                onChange()
                NSSound.beep()
            }
        }
    }

    func stop() {
        guard let recorder, let file else { return }
        self.recorder = nil
        self.file = nil
        hideControls()
        let frame = frame
        Task { @MainActor in
            let saved = await recorder.finish()
            isRecording = false
            onChange()
            guard saved, let url = keep(file, from: frame) else {
                log.error("Could not save a screen recording")
                try? FileManager.default.removeItem(at: file)
                NSSound.beep()
                return
            }
            onFinish(url)
        }
    }

    /// Named like a screenshot, readable only by the user, and tagged with
    /// the area it came from, so it flies from there to the line.
    private func keep(_ file: URL, from rect: CGRect) -> URL? {
        let fm = FileManager.default
        var url = Inbox.folder.appendingPathComponent("Snapfly \(Capture.stamp()).mov")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = Inbox.folder.appendingPathComponent("Snapfly \(Capture.stamp()) \(n).mov")
            n += 1
        }
        do {
            try fm.moveItem(at: file, to: url)
        } catch {
            return nil
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let area = [rect.minX, top - rect.maxY, rect.width, rect.height].map { Double($0) }
        Capture.tag(url, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", area)
        return url
    }

    // MARK: Controls

    private func showControls(for region: Capture.Region, frame: CGRect) {
        let screen = Capture.screen(of: region) ?? NSScreen.main
        if case .area = region {
            let edge = RecordingEdge(around: frame)
            edge.orderFrontRegardless()
            self.edge = edge
        }
        started = Date()
        let badge = CaptureBadge(kind: .recording, label: L("Stop Recording")) { Recording.shared.stop() }
        badge.show(on: screen)
        self.badge = badge
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Recording.shared.update() }
        }
    }

    private func update() {
        badge?.model.seconds = Int(Date().timeIntervalSince(started))
    }

    private func hideControls() {
        tick?.invalidate()
        tick = nil
        badge?.orderOut(nil)
        badge = nil
        edge?.orderOut(nil)
        edge = nil
    }
}

/// The countdown before a timed screenshot, in the same capsule above the
/// Dock. A click on it cancels.
@MainActor
final class Countdown {
    static let shared = Countdown()

    private(set) var isRunning = false
    private var deadline = Date()
    private var tick: Timer?
    private var badge: CaptureBadge?
    private var then: () -> Void = {}

    func run(_ seconds: Int, on screen: NSScreen?, then: @escaping () -> Void) {
        end()
        isRunning = true
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        self.then = then
        let badge = CaptureBadge(kind: .countdown, label: L("Cancel the timer")) { Countdown.shared.end() }
        badge.model.seconds = seconds
        badge.show(on: screen)
        self.badge = badge
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Countdown.shared.update() }
        }
    }

    private func update() {
        let left = Int(deadline.timeIntervalSinceNow.rounded())
        if left > 0 {
            badge?.model.seconds = left
        } else {
            let then = then
            end()
            then()
        }
    }

    func end() {
        tick?.invalidate()
        tick = nil
        badge?.orderOut(nil)
        badge = nil
        then = {}
        isRunning = false
    }
}

enum RecorderError: Error {
    case nothingToRecord
    case cannotWrite
}

/// Writes the frames of a screen stream into a movie, off the main thread.
/// The screen only sends a frame when something changes, so the last one
/// is held until the recording stops.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// The system stopped the stream, for example because the window closed.
    var onFailure: () -> Void = {}

    private var capture: SCStream?
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "de.ghazarian.Snapfly.recorder")
    private var sessionStarted = false
    private var finished = false
    private var lastTime = CMTime.invalid
    private var lastHostTime = CMTime.invalid

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, url: URL) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
        ])
        input.expectsMediaDataInRealTime = true
        super.init()
        guard writer.canAdd(input) else { throw RecorderError.cannotWrite }
        writer.add(input)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        capture = stream
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }
        do {
            try await capture?.startCapture()
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    /// Returns whether a movie was written.
    func finish() async -> Bool {
        try? await capture?.stopCapture()
        return await withCheckedContinuation { continuation in
            queue.async {
                self.finished = true
                guard self.sessionStarted, self.lastTime.isValid, self.writer.status == .writing else {
                    self.writer.cancelWriting()
                    continuation.resume(returning: false)
                    return
                }
                // Up to now, even when the screen kept still since the last frame.
                let still = CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), self.lastHostTime)
                self.writer.endSession(atSourceTime: CMTimeAdd(self.lastTime, CMTimeMaximum(still, .zero)))
                self.input.markAsFinished()
                self.writer.finishWriting {
                    continuation.resume(returning: self.writer.status == .completed)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finished, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              writer.status == .writing else { return }
        let time = sampleBuffer.presentationTimeStamp
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        guard input.isReadyForMoreMediaData, input.append(sampleBuffer) else { return }
        lastTime = time
        lastHostTime = CMClockGetTime(CMClockGetHostTimeClock())
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("The screen recording stopped: \(error.localizedDescription, privacy: .public)")
        onFailure()
    }

    /// Frames that carry a new picture, not the ones that say nothing changed.
    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

// MARK: - The capsule

@MainActor
final class CaptureBadgeModel: ObservableObject {
    enum Kind { case countdown, recording }

    let kind: Kind
    /// Left on the countdown, or recorded so far.
    @Published var seconds = 0

    init(kind: Kind) { self.kind = kind }
}

/// A capsule above the Dock, over every app, that never takes the keyboard.
/// It is Snapfly's own window, so it is never in what is taken.
private final class CaptureBadge: NSPanel {
    static let margin: CGFloat = 16

    let model: CaptureBadgeModel
    private let content: CaptureBadgeView
    private var screenFrame = CGRect.zero

    init(kind: CaptureBadgeModel.Kind, label: String, action: @escaping () -> Void) {
        let model = CaptureBadgeModel(kind: kind)
        self.model = model
        content = CaptureBadgeView(model: model, label: label, margin: Self.margin, action: action)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = content
        content.onResize = { [weak self] size in self?.place(size) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        screenFrame = screen.frame
        // Above the Dock, where there is one on this screen.
        screenFrame.origin.y = screen.visibleFrame.minY
        content.layoutSubtreeIfNeeded()
        place(content.fittingSize)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    /// Centered, so it stays put as the numbers change.
    private func place(_ size: CGSize) {
        guard !screenFrame.isEmpty, frame.size != size else { return }
        setFrame(CGRect(x: (screenFrame.midX - size.width / 2).rounded(),
                        y: screenFrame.minY + 16 - Self.margin,
                        width: size.width, height: size.height), display: true)
    }
}

/// Takes the click itself, as the chat button does: the panel never becomes
/// key, so only a view of its own takes the first click.
private final class CaptureBadgeView: NSView {
    var onResize: (CGSize) -> Void = { _ in }

    private let host: NSHostingView<CaptureBadgeLabel>
    private let margin: CGFloat
    private let action: () -> Void

    init(model: CaptureBadgeModel, label: String, margin: CGFloat, action: @escaping () -> Void) {
        self.margin = margin
        self.action = action
        host = NSHostingView(rootView: CaptureBadgeLabel(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            host.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        toolTip = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = CGSize(width: host.intrinsicContentSize.width + 2 * margin,
                          height: host.intrinsicContentSize.height + 2 * margin)
        if size.width > 2 * margin { onResize(size) }
    }

    /// Only the capsule takes the pointer; the shadow's margin lets it through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return host.frame.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard host.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }
}

/// The countdown: a timer, the seconds left and a cross. The recording: a
/// stop button and the time so far.
private struct CaptureBadgeLabel: View {
    @ObservedObject var model: CaptureBadgeModel

    private static let time: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            switch model.kind {
            case .countdown:
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Text(model.seconds, format: .number)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: model.seconds)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.08), in: Circle())
            case .recording:
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.red, in: Circle())
                Text(Self.time.string(from: TimeInterval(model.seconds)) ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.trailing, 8)
            }
        }
        .padding(4)
        .fixedSize()
        .controlGlass(capsule: true)
        .shadow(color: .black.opacity(hasLiquidGlass ? 0.14 : 0.25), radius: 14, y: 6)
    }
}

/// A thin edge around the area being recorded, just outside it.
private final class RecordingEdge: NSPanel {
    init(around area: CGRect) {
        super.init(contentRect: area.insetBy(dx: -2, dy: -2), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        isReleasedWhenClosed = false
        contentView = RecordingEdgeView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RecordingEdgeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // White on dark screens, with a dark line beside it for light ones.
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let outer = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 1
        outer.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        inner.lineWidth = 1
        inner.stroke()
    }
}
