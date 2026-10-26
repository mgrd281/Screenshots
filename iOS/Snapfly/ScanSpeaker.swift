import AVFoundation
import Combine
import NaturalLanguage
import UIKit

/// Reads the scanned pages' text aloud, a paragraph or a table's row at a
/// time (`ScanReading.utterances`), with the system's own voice for the
/// text's language, on this iPhone: the best voice installed for it, a
/// piece's own language where it is long and sure enough. It can pause,
/// skip to the next piece or the one before, and speak slower or faster;
/// which piece and which word is being said is published, to follow in the
/// text. A cover is said as a word and what it hides is not in the text at
/// all. Other sound is turned down while it speaks.
@MainActor
final class ScanSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State {
        case idle, speaking, paused
    }

    @Published private(set) var state = State.idle
    /// The piece being said.
    @Published private(set) var index: Int?
    /// The stretch of that piece's shown text being said.
    @Published private(set) var shownRange: NSRange?
    /// How fast, from slow to fast: 1 is the voice's own pace.
    @Published private(set) var speed: Double

    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]
    private static let speedKey = "snapfly.scan.speechSpeed"

    private let synthesizer = AVSpeechSynthesizer()
    private var pieces: [ScanReading.Utterance] = []
    private var current: ObjectIdentifier?
    /// The language the whole text is mostly in.
    private var language: String?

    override init() {
        let kept = UserDefaults.standard.double(forKey: Self.speedKey)
        speed = Self.speeds.contains(kept) ? kept : 1
        super.init()
        synthesizer.delegate = self
    }

    var speaking: Bool { state != .idle }

    /// The piece being said, with how it is shown and said.
    var piece: ScanReading.Utterance? {
        guard let index, pieces.indices.contains(index) else { return nil }
        return pieces[index]
    }

    // MARK: Playing

    /// Starts at a piece. False when no voice for the text's language is on
    /// this iPhone, so nothing is said in another's.
    @discardableResult
    func start(_ pieces: [ScanReading.Utterance], at first: Int = 0) -> Bool {
        halt()
        end()
        self.pieces = pieces
        guard pieces.indices.contains(first) else { return false }
        language = Self.language(of: pieces.map(\.spoken).joined(separator: " "))
        if let language, Self.best(for: language) == nil { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        // The screen stays on while it reads, so the iPhone locking does not cut it off.
        UIApplication.shared.isIdleTimerDisabled = true
        say(first)
        return true
    }

    func pause() {
        guard state == .speaking else { return }
        if synthesizer.pauseSpeaking(at: .word) { state = .paused }
    }

    func resume() {
        guard state == .paused else { return }
        if synthesizer.continueSpeaking() { state = .speaking }
    }

    func stop() {
        halt()
        end()
    }

    /// The next piece, or the one before; the first again at the start.
    func skip(_ steps: Int) {
        guard let index else { return }
        let target = index + steps
        halt()
        if pieces.indices.contains(target) { say(target) } else if target < 0 { say(0) } else { end() }
    }

    func setSpeed(_ speed: Double) {
        guard speed != self.speed else { return }
        self.speed = speed
        UserDefaults.standard.set(speed, forKey: Self.speedKey)
        // The piece in hand goes on at the new pace from its start.
        if let index, state != .idle {
            halt()
            say(index)
        }
    }

    private func say(_ index: Int) {
        guard pieces.indices.contains(index) else { return end() }
        let piece = pieces[index]
        let utterance = AVSpeechUtterance(string: piece.spoken)
        utterance.voice = Self.voice(for: piece.spoken, fallback: language)
        utterance.rate = Self.rate(for: speed)
        // A pause after a paragraph, a shorter one after a row.
        utterance.postUtteranceDelay = piece.row == nil ? 0.3 : 0.12
        current = ObjectIdentifier(utterance)
        self.index = index
        shownRange = nil
        state = .speaking
        synthesizer.speak(utterance)
    }

    /// What is being said is stopped, and what it would still call is ignored.
    private func halt() {
        current = nil
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func end() {
        guard state != .idle || index != nil else { return }
        state = .idle
        index = nil
        shownRange = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: The delegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.spoke(characterRange, of: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    private func spoke(_ range: NSRange, of id: ObjectIdentifier) {
        guard id == current, let index, pieces.indices.contains(index) else { return }
        shownRange = pieces[index].shownRange(range)
    }

    private func finished(_ id: ObjectIdentifier) {
        guard id == current, let index else { return }
        shownRange = nil
        if index + 1 < pieces.count { say(index + 1) } else { end() }
    }

    // MARK: Voices

    /// The language a text is mostly in, as a code like "de" or "zh-Hans".
    static func language(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    /// The voice for a piece: its own language where it has enough words and
    /// the recognizer is sure of it, else the text's.
    static func voice(for text: String, fallback: String?) -> AVSpeechSynthesisVoice? {
        var code = fallback
        if text.count >= 24 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let top = recognizer.languageHypotheses(withMaximum: 1).first, top.value >= 0.8 { code = top.key.rawValue }
        }
        return code.flatMap(best(for:))
    }

    /// The best voice installed for a language: a premium or enhanced one
    /// before the standard, the one of this iPhone's region before another.
    static func best(for code: String) -> AVSpeechSynthesisVoice? {
        let base = (code.split(separator: "-").first.map(String.init) ?? code).lowercased()
        let region = Locale.current.region?.identifier
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(base) }
        let best = voices.max { score($0, code: code, region: region) < score($1, code: code, region: region) }
        return best ?? AVSpeechSynthesisVoice(language: code)
    }

    private static func score(_ voice: AVSpeechSynthesisVoice, code: String, region: String?) -> Int {
        var score = 0
        if voice.quality == .premium { score += 20 } else if voice.quality == .enhanced { score += 10 }
        if let region, voice.language.hasSuffix("-" + region) { score += 5 }
        // Simplified Chinese is the mainland's, traditional the island's.
        if code == "zh-Hans", voice.language == "zh-CN" { score += 8 }
        if code == "zh-Hant", voice.language == "zh-TW" { score += 8 }
        return score
    }

    /// The utterance rate for a pace: the voice's own at 1, slower under it,
    /// faster over it by a gentle slope, as the scale is not even.
    static func rate(for speed: Double) -> Float {
        let own = Double(AVSpeechUtteranceDefaultSpeechRate)
        let rate = speed <= 1 ? own * speed : own + 0.18 * (speed - 1)
        return Float(min(max(rate, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }
}
