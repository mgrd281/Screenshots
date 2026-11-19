import AVFoundation
import Foundation
import Speech

/// A line of what is said in a recording, shown at the foot of the video
/// while it is said, on the recording's own time.
struct StudioCaption: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var start: Double
    var end: Double

    func contains(_ t: Double) -> Bool { t >= start && t < end }

    init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Captions made from the words heard, with their times: lines short
/// enough to read at a glance, broken where the speaker pauses or a
/// sentence ends.
enum StudioCaptions {
    /// A word heard, and from when to when.
    struct Word: Equatable {
        var text: String
        var start: Double
        var end: Double
    }

    /// The most letters a line holds.
    static let longest = 42
    /// A pause this long starts a new line.
    static let pause = 0.7
    /// The longest a line stays, in seconds.
    static let longestTime = 4.5
    /// The shortest a line stays, so it can be read.
    static let shortestTime = 0.8

    /// - Parameter spaced: false for languages written without spaces
    ///   between words, like Chinese and Japanese.
    static func lines(_ words: [Word], spaced: Bool = true) -> [StudioCaption] {
        let separator = spaced ? " " : ""
        var lines: [StudioCaption] = []
        var current: [Word] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: separator).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append(StudioCaption(text: text, start: first.start, end: max(last.end, first.start))) }
            current = []
        }
        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let first = current.first, let last = current.last {
                let length = current.map(\.text.count).reduce(0, +) + separator.count * current.count + word.text.count
                if word.start - last.end > pause || length > longest || word.end - first.start > longestTime {
                    flush()
                }
            }
            current.append(word)
            // A sentence's end ends the line, once it holds a few words.
            let said = current.map(\.text).joined(separator: separator)
            if let mark = word.text.last, ".?!؟。？！".contains(mark), said.count >= 12 { flush() }
        }
        flush()
        // Each stays long enough to read, and goes before the next comes.
        for i in lines.indices {
            let next = i + 1 < lines.count ? lines[i + 1].start : .infinity
            lines[i].end = min(next, max(lines[i].end, lines[i].start + shortestTime))
        }
        return lines
    }

    /// Whether a language is written without spaces between its words.
    static func isSpaced(_ locale: Locale) -> Bool {
        !["zh", "ja", "th", "lo", "km", "my"].contains(locale.language.languageCode?.identifier ?? "")
    }

    /// The captions after the recording's first `offset` seconds were
    /// trimmed off and `duration` kept.
    static func trimmed(_ captions: [StudioCaption], from offset: Double, keeping duration: Double) -> [StudioCaption] {
        captions.compactMap { caption in
            var caption = caption
            caption.start = max(0, caption.start - offset)
            caption.end = min(duration, caption.end - offset)
            return caption.end - caption.start >= 0.2 ? caption : nil
        }
    }
}

/// Hears what is said in a recording, on this Mac alone, with the speech
/// recognition macOS has for the language chosen; nothing is sent.
enum StudioListener {
    enum Failure: Error {
        case notAllowed, noSound, notOnThisMac, nothingHeard
    }

    /// The languages that can be heard on this Mac, by their names in the
    /// language Snapfly speaks, the Mac's own first.
    static func languages() -> [Locale] {
        let all = SFSpeechRecognizer.supportedLocales().filter {
            SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true
        }
        let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        return all.sorted { a, b in
            let mine = (a.identifier.replacingOccurrences(of: "_", with: "-") == current,
                        b.identifier.replacingOccurrences(of: "_", with: "-") == current)
            if mine.0 != mine.1 { return mine.0 }
            return name(of: a).localizedStandardCompare(name(of: b)) == .orderedAscending
        }
    }

    /// The language Snapfly would hear first: the Mac's own where it can.
    static func preferred(among languages: [Locale]) -> Locale? {
        let current = Locale.current
        return languages.first { $0.identifier == current.identifier }
            ?? languages.first { $0.language.languageCode == current.language.languageCode }
            ?? languages.first { $0.language.languageCode?.identifier == "en" }
            ?? languages.first
    }

    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Asks once, as macOS wants, before anything is heard.
    static func allowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { status in done.resume(returning: status == .authorized) }
            }
        @unknown default: return false
        }
    }

    /// The captions for what is said in a recording.
    static func captions(for movie: URL, in locale: Locale) async throws -> [StudioCaption] {
        guard await allowed() else { throw Failure.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw Failure.notOnThisMac
        }
        let sound = try await soundOnly(of: movie)
        defer { try? FileManager.default.removeItem(at: sound) }
        let request = SFSpeechURLRecognitionRequest(url: sound)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        // Answered once, by the final words or by what went wrong.
        let once = StudioExport.Stop()
        let words: [StudioCaptions.Word] = try await withCheckedThrowingContinuation { done in
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard once.setFirst() else { return }
                    done.resume(returning: result.bestTranscription.segments.map {
                        StudioCaptions.Word(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                    })
                } else if let error {
                    guard once.setFirst() else { return }
                    done.resume(throwing: error)
                }
            }
        }
        guard !words.isEmpty else { throw Failure.nothingHeard }
        return StudioCaptions.lines(words, spaced: StudioCaptions.isSpaced(locale))
    }

    /// The recording's sound alone, in a file of its own out of sight.
    private static func soundOnly(of movie: URL) async throws -> URL {
        let asset = AVURLAsset(url: movie)
        let sounds = try await asset.loadTracks(withMediaType: .audio)
        guard !sounds.isEmpty,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noSound
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snapfly-Sound-\(UUID().uuidString)").appendingPathExtension("m4a")
        session.outputURL = target
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: target)
            throw session.error ?? Failure.noSound
        }
        return target
    }
}
