import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Records the screen from Snapfly itself: an area, a window or a whole
/// screen, chosen on the same still screens as a screenshot. A small capsule
/// above the Dock shows how long it has run, and a click on it stops. The
/// menu bar item and the shortcut stop it too. The recording hangs on the
/// line like one made with the Screenshot app, and Trim trims it.
///
/// Snapfly's own line and controls stay out of the recording. Sound is
/// what Settings › General chooses: none, the Mac's own, the microphone, or
/// both mixed into one track. The microphone is asked for only when chosen.
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
                let sound = await RecordingSound.usable()
                let recorder = try Recorder(filter: setup.filter, configuration: setup.config, url: file, sound: sound)
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
                Notice.show(L("Could not record the screen."), on: Capture.screen(of: region))
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
            var saved = await recorder.finish()
            // The Mac's sound and the voice, as one track every player and
            // chat plays. Should that fail, both tracks stay.
            if saved, recorder.hasTwoSoundTracks {
                let note = Notice.show(L("Saving the recording…"), working: true)
                if !(await SoundMix.mixDown(file)) { log.error("Could not mix the recording's sound into one track") }
                Notice.end(note)
                saved = FileManager.default.fileExists(atPath: file.path)
            }
            isRecording = false
            onChange()
            guard saved, let url = keep(file, from: frame) else {
                log.error("Could not save a screen recording")
                try? FileManager.default.removeItem(at: file)
                Notice.show(L("Could not save the recording."), on: nil)
                return
            }
            onFinish(url)
        }
    }

    /// A recording cut short by quitting is left half written. It goes at
    /// launch.
    static func cleanUp() {
        let fm = FileManager.default
        for folder in [Inbox.legacyFolder, Inbox.folder] {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix(".recording-") || file.lastPathComponent.hasPrefix(".mix-") {
                try? fm.removeItem(at: file)
            }
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

/// A short note in the same capsule above the Dock: what went wrong, for a
/// few seconds, or what is being made, until it is done. VoiceOver says it
/// too. A click puts it away. It is used instead of a beep wherever a beep
/// would leave the user guessing.
@MainActor
enum Notice {
    private static var badge: CaptureBadge?
    private static var hide: DispatchWorkItem?
    private static var current: UUID?

    /// Without a screen, on the one with the pointer. Returns which note it
    /// is, so the work that showed it ends only its own.
    /// - Parameters:
    ///   - done: something went as it should, like a file saved, rather
    ///     than wrong.
    ///   - seconds: how long it stays, unless it is working.
    ///   - onClick: what a click does before putting it away, like showing a
    ///     file just saved in Finder.
    @discardableResult
    static func show(_ text: String, on screen: NSScreen? = nil, working: Bool = false, done: Bool = false,
                     lasting seconds: TimeInterval = 4, onClick: (() -> Void)? = nil) -> UUID {
        hide?.cancel()
        badge?.orderOut(nil)
        let id = UUID()
        current = id
        let kind: CaptureBadgeModel.Kind = working ? .working(text) : (done ? .done(text) : .message(text))
        let badge = CaptureBadge(kind: kind, label: text) {
            onClick?()
            Notice.end(id)
        }
        badge.show(on: screen ?? pointerScreen)
        self.badge = badge
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        if !working {
            let work = DispatchWorkItem { MainActor.assumeIsolated { Notice.end(id) } }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        return id
    }

    /// A file written over, or moved, and where it is now, from the home
    /// folder down: "Saved to Pictures › Snapfly." A click shows it in Finder.
    static func saved(_ file: URL) {
        let place = Folders.placeName(file.deletingLastPathComponent())
        show(String(format: L("Saved to %@. Click to show it in Finder."), place), done: true, lasting: 6) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }

    /// A copy saved as a file of its own, its name and where it is.
    static func savedCopy(_ file: URL) {
        let place = Folders.placeName(file.deletingLastPathComponent())
        show(String(format: L("Saved as %1$@ in %2$@. Click to show it in Finder."), file.lastPathComponent, place),
             done: true, lasting: 6) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }

    /// Puts the note away, unless another one has taken its place.
    static func end(_ id: UUID) {
        guard current == id else { return }
        current = nil
        hide?.cancel()
        hide = nil
        badge?.orderOut(nil)
        badge = nil
    }

    private static var pointerScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
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
    /// The Mac's own sound and the microphone, each a track of its own while
    /// recording.
    private var macSound: AVAssetWriterInput?
    private var voice: AVAssetWriterInput?
    private var heardMac = false
    private var heardVoice = false
    private let queue = DispatchQueue(label: "de.ghazarian.Snapfly.recorder")
    private var sessionStarted = false
    private var sessionStart = CMTime.invalid
    private var finished = false
    private var lastTime = CMTime.invalid
    private var lastHostTime = CMTime.invalid

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, url: URL,
         sound: RecordingSound = .none) throws {
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
        if sound.hasMac {
            configuration.capturesAudio = true
            // Snapfly's own sounds, like the shutter, stay out.
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            let mac = Self.soundInput(channels: 2)
            if writer.canAdd(mac) {
                writer.add(mac)
                macSound = mac
            }
        }
        if sound.hasVoice, #available(macOS 15.0, *) {
            configuration.captureMicrophone = true
            let voice = Self.soundInput(channels: 1)
            if writer.canAdd(voice) {
                writer.add(voice)
                self.voice = voice
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if macSound != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if voice != nil, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        capture = stream
    }

    /// AAC at 48 kHz, as a movie's sound usually is.
    private static func soundInput(channels: Int) -> AVAssetWriterInput {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }

    /// Both the Mac's sound and the voice were heard, in two tracks to mix
    /// into one once written. Read once `finish` is done.
    var hasTwoSoundTracks: Bool { heardMac && heardVoice }

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
                self.macSound?.markAsFinished()
                self.voice?.markAsFinished()
                self.writer.finishWriting {
                    continuation.resume(returning: self.writer.status == .completed)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finished, sampleBuffer.isValid, writer.status == .writing else { return }
        if type == .audio {
            if append(sampleBuffer, to: macSound) { heardMac = true }
            return
        }
        if #available(macOS 15.0, *), type == .microphone {
            if append(sampleBuffer, to: voice) { heardVoice = true }
            return
        }
        guard type == .screen, Self.isComplete(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
            sessionStart = time
        }
        guard input.isReadyForMoreMediaData, input.append(sampleBuffer) else { return }
        lastTime = time
        lastHostTime = CMClockGetTime(CMClockGetHostTimeClock())
    }

    /// Sound from the first picture on; what came before it is left out.
    private func append(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput?) -> Bool {
        guard let input, sessionStarted, buffer.presentationTimeStamp >= sessionStart,
              input.isReadyForMoreMediaData else { return false }
        return input.append(buffer)
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
    enum Kind {
        case countdown, recording
        /// A guide being recorded: how many steps so far.
        case steps
        /// Something that went wrong.
        case message(String)
        /// Something that went as it should, like a file saved.
        case done(String)
        /// Something being made, like a GIF.
        case working(String)
    }

    let kind: Kind
    /// Left on the countdown, or recorded so far.
    @Published var seconds = 0
    /// The steps of a guide so far.
    @Published var steps = 0

    init(kind: Kind) { self.kind = kind }
}

/// A capsule above the Dock, over every app, that never takes the keyboard.
/// It is Snapfly's own window, so it is never in what is taken.
final class CaptureBadge: NSPanel {
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
/// stop button and the time so far. A guide: the stop button and its steps
/// so far.
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
            case .steps:
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.red, in: Circle())
                Text(model.steps == 0 ? L("Click through the steps") : String(format: L("Steps: %d"), model.steps))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: model.steps)
                    .padding(.trailing, 8)
            case let .message(text):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
            case let .done(text):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
            case let .working(text):
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 6)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
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

// MARK: - GIF

/// A recording turned into a looping GIF, which every chat plays inline:
/// at most 10 frames a second and 300 frames, at most 800 points wide.
/// It is saved next to the recording, in Snapfly's folder.
enum GIF {
    static let maxFrames = 300
    static let maxSide = 800

    /// How many frames a second, and how many in all, for a recording this
    /// long: 10 a second, fewer for a long one, so it stays within 300.
    static func plan(for seconds: Double) -> (fps: Double, count: Int) {
        let fps = min(10, Double(maxFrames) / max(seconds, 0.1))
        return (fps, min(maxFrames, max(1, Int(seconds * fps))))
    }

    static func make(from movie: URL) async -> URL? {
        let asset = AVURLAsset(url: movie)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
        let (fps, count) = plan(for: duration.seconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let base = movie.deletingPathExtension().lastPathComponent
        let target = Collage.newFile(base, "gif")
        // Hidden while it is written, so the folder watcher leaves it alone.
        let temp = target.deletingLastPathComponent().appendingPathComponent(".gif-\(UUID().uuidString).gif")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, UTType.gif.identifier as CFString,
                                                                count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frame = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1 / fps,
                kCGImagePropertyGIFUnclampedDelayTime: 1 / fps,
            ],
        ] as CFDictionary
        var added = 0
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(destination, image, frame)
            added += 1
        }
        let fm = FileManager.default
        guard added == count, CGImageDestinationFinalize(destination) else {
            try? fm.removeItem(at: temp)
            return nil
        }
        do {
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            return nil
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
}
