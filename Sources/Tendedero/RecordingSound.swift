import AVFoundation
import Foundation

/// What a screen recording hears, from Settings › General: nothing, the
/// Mac's own sound, the microphone, or both. The Mac's sound needs nothing
/// more than Screen Recording; the microphone is asked for the first time
/// it is used, and needs macOS 15.
enum RecordingSound: String, CaseIterable, Sendable {
    case none, mac, microphone, both

    var hasMac: Bool { self == .mac || self == .both }
    var hasVoice: Bool { self == .microphone || self == .both }

    private static let key = "recordingSound"

    /// None until chosen, so nobody is recorded by surprise.
    static var current: RecordingSound {
        get { UserDefaults.standard.string(forKey: key).flatMap(RecordingSound.init(rawValue:)) ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Recording the microphone with the screen needs macOS 15.
    static var microphoneAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// The sound to record now: the microphone only where macOS has it and
    /// it is allowed, asked for the first time. Without it, a note says why
    /// and the rest is recorded.
    @MainActor
    static func usable() async -> RecordingSound {
        let chosen = current
        guard chosen.hasVoice else { return chosen }
        let withoutVoice: RecordingSound = chosen == .both ? .mac : .none
        guard microphoneAvailable else { return withoutVoice }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return chosen
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return chosen }
        default:
            break
        }
        Notice.show(L("Recording without the microphone: Snapfly isn’t allowed to use it. Allow it in System Settings › Privacy & Security › Microphone."),
                    lasting: 8) { Permissions.open("Privacy_Microphone") }
        return withoutVoice
    }

    var title: String {
        switch self {
        case .none: return L("No Sound")
        case .mac: return L("Mac’s Sound")
        case .microphone: return L("Microphone")
        case .both: return L("Mac’s Sound and Microphone")
        }
    }
}

/// A recording's sound tracks mixed into one, the picture copied as it is,
/// so every player and every chat plays both the Mac's sound and the voice.
enum SoundMix {
    /// Replaces the movie with the mixed one. False, with the movie left as
    /// it was, when it cannot be done.
    static func mixDown(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: mix(url))
            }
        }
    }

    private static func mix(_ url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        let audio = asset.tracks(withMediaType: .audio)
        guard audio.count > 1 else { return true }
        guard let video = asset.tracks(withMediaType: .video).first else { return false }
        let out = url.deletingLastPathComponent().appendingPathComponent(".mix-\(UUID().uuidString).mov")
        let fm = FileManager.default
        do {
            let reader = try AVAssetReader(asset: asset)
            let pictures = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            pictures.alwaysCopiesSampleData = false
            let sound = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(pictures), reader.canAdd(sound) else { return false }
            reader.add(pictures)
            reader.add(sound)

            let writer = try AVAssetWriter(outputURL: out, fileType: .mov)
            let hint = video.formatDescriptions.first.map { $0 as! CMFormatDescription }
            let picturesIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
            picturesIn.transform = video.preferredTransform
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            let soundIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
                AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
            ])
            guard writer.canAdd(picturesIn), writer.canAdd(soundIn) else { return false }
            writer.add(picturesIn)
            writer.add(soundIn)

            guard reader.startReading(), writer.startWriting() else {
                reader.cancelReading()
                writer.cancelWriting()
                try? fm.removeItem(at: out)
                return false
            }
            // The movie's timeline, from its first picture.
            guard let first = pictures.copyNextSampleBuffer() else {
                reader.cancelReading()
                writer.cancelWriting()
                try? fm.removeItem(at: out)
                return false
            }
            writer.startSession(atSourceTime: first.presentationTimeStamp)
            let group = DispatchGroup()
            let endings = [Ending(), Ending()]
            copy(from: pictures, to: picturesIn, first: first, label: "pictures", group: group, ending: endings[0])
            copy(from: sound, to: soundIn, first: nil, label: "sound", group: group, ending: endings[1])
            // Should the writer or the reader fail while an input waits, it is
            // never asked for more: the wait ends then too, as Studio's does,
            // and so it does once mixing takes a minute longer than the movie
            // lasts. Each input not ended yet is ended here, once, so the
            // group is left as often as it was entered.
            let deadline = Date().addingTimeInterval(60 + max(0, CMTimeGetSeconds(asset.duration)))
            var failed = false
            while group.wait(timeout: .now() + .milliseconds(250)) == .timedOut {
                guard writer.status == .failed || reader.status == .failed || Date() > deadline else { continue }
                failed = true
                for ending in endings {
                    if ending.end() { group.leave() }
                }
            }

            guard !failed, reader.status == .completed else {
                reader.cancelReading()
                writer.cancelWriting()
                try? fm.removeItem(at: out)
                return false
            }
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()
            guard writer.status == .completed else {
                try? fm.removeItem(at: out)
                return false
            }
            _ = try fm.replaceItemAt(url, withItemAt: out)
            return true
        } catch {
            try? fm.removeItem(at: out)
            return false
        }
    }

    /// Copies one output into one input as fast as the input takes it.
    private static func copy(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, first: CMSampleBuffer?,
                             label: String, group: DispatchGroup, ending: Ending) {
        group.enter()
        let queue = DispatchQueue(label: "de.ghazarian.Snapfly.mix.\(label)")
        var pending = first
        input.requestMediaDataWhenReady(on: queue) {
            guard !ending.isSet else { return }
            while input.isReadyForMoreMediaData {
                let buffer = pending ?? output.copyNextSampleBuffer()
                pending = nil
                guard let buffer, input.append(buffer) else {
                    if ending.end() {
                        input.markAsFinished()
                        group.leave()
                    }
                    return
                }
            }
        }
    }

    /// Whether an input's copying has ended: once, on its own queue, or in
    /// the wait when the writer or the reader has failed.
    private final class Ending: @unchecked Sendable {
        private let lock = NSLock()
        private var ended = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return ended
        }

        /// True for the one that ends it, false once it has ended.
        func end() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !ended else { return false }
            ended = true
            return true
        }
    }
}
