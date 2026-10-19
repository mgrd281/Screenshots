import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Where a ledger syncs: the owner's own iCloud, with their devices signed
/// in to the same Apple account, or the zones a Mac on another Apple account
/// shares with this device once they were paired with a code (SYNC.md,
/// "Pairing with a code").
enum SyncSpace: Hashable, Sendable {
    case own
    /// Shared by the account with this user record name.
    case shared(owner: String)

    var owner: String? {
        if case .shared(let owner) = self { return owner }
        return nil
    }

    /// Its own folder for the ledger and the pictures, inside Snapfly's sync
    /// folder, so leaving a shared space takes only what came with it.
    func folder(in root: URL) -> URL {
        switch self {
        case .own:
            return root
        case .shared(let owner):
            let name = String(owner.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" })
            return root.appendingPathComponent("Shared", isDirectory: true)
                .appendingPathComponent(name.isEmpty ? "owner" : name, isDirectory: true)
        }
    }
}

/// The code a Mac shows so a device on another Apple account can join it:
/// six digits, a new one every 30 seconds. Each is drawn at random, never
/// worked out from the time or the one before.
struct PairingCode: Equatable, Sendable {
    static let digits = 6
    static let period: TimeInterval = 30
    /// A code still counts this much longer, for one typed just as it changed.
    static let grace: TimeInterval = 15

    let value: String
    /// When it first showed.
    let shown: Date

    var expires: Date { shown.addingTimeInterval(Self.period) }

    /// Shown with the code, counting down to the next one.
    func secondsLeft(now: Date = Date()) -> Int {
        max(0, Int(expires.timeIntervalSince(now).rounded(.up)))
    }

    /// Whether a device may still join with it.
    func accepts(at now: Date) -> Bool {
        now < expires.addingTimeInterval(Self.grace)
    }

    /// "042 917", easier to read off a screen and type in.
    var spaced: String {
        String(value.prefix(3)) + " " + String(value.dropFirst(3))
    }

    static func make<Generator: RandomNumberGenerator>(at now: Date = Date(), using generator: inout Generator) -> PairingCode {
        PairingCode(value: text(Int.random(in: 0..<1_000_000, using: &generator)), shown: now)
    }

    /// A number as six digits, with its leading zeros.
    static func text(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, Self.digits - digits.count)) + digits
    }

    static func make(at now: Date = Date()) -> PairingCode {
        var generator = SystemRandomNumberGenerator()
        return make(at: now, using: &generator)
    }

    /// What was typed, as six plain digits, or nil. Spaces and dashes are
    /// left out, and digits of any script count, like Arabic-Indic ones.
    static func normalize(_ text: String) -> String? {
        var out = ""
        for character in text {
            if character.isWhitespace || character == "-" { continue }
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
            out += String(digit)
        }
        return out.count == digits ? out : nil
    }
}

/// The codes a Mac listens for while it shows them: the one showing, and the
/// one before it for a few seconds more.
struct PairingSchedule: Sendable {
    private(set) var current: PairingCode
    private(set) var previous: PairingCode?

    init(now: Date = Date()) {
        current = PairingCode.make(at: now)
    }

    init<Generator: RandomNumberGenerator>(now: Date, using generator: inout Generator) {
        current = PairingCode.make(at: now, using: &generator)
    }

    /// A new code once the one showing has run out; true when there is one.
    mutating func advance(now: Date = Date()) -> Bool {
        var generator = SystemRandomNumberGenerator()
        return advance(now: now, using: &generator)
    }

    mutating func advance<Generator: RandomNumberGenerator>(now: Date, using generator: inout Generator) -> Bool {
        guard now >= current.expires else {
            if let previous, !previous.accepts(at: now) { self.previous = nil }
            return false
        }
        var next = PairingCode.make(at: now, using: &generator)
        // Never the same digits twice in a row, so the change shows.
        while next.value == current.value { next = PairingCode.make(at: now, using: &generator) }
        previous = current.accepts(at: now) ? current : nil
        current = next
        return true
    }

    /// The codes a device may join with now.
    func listening(at now: Date = Date()) -> [PairingCode] {
        [current, previous].compactMap { $0 }.filter { $0.accepts(at: now) }
    }
}

/// What a Mac and a device on another Apple account tell each other while
/// pairing, through iCloud's public database, each sealed with the code.
enum PairingMessage {
    /// The Mac, showing a code.
    struct Offer: Codable, Equatable, Sendable {
        var version = 1
        var name: String
        var platform: SyncPlatform
    }

    /// The device that typed the code, asking to join.
    struct Request: Codable, Equatable, Sendable {
        var version = 1
        /// Its iCloud account, as CloudKit names it in Snapfly's container.
        var user: String
        var device: SyncDevice
    }

    /// The Mac's answer, once the person at the Mac chose.
    struct Answer: Codable, Equatable, Sendable {
        enum Outcome: String, Codable, Sendable {
            /// Shared: the device joins with these links. Each lets in only
            /// the account the Mac added, so a link alone opens nothing.
            case joined
            /// The same Apple account: plain syncing does it.
            case sameAccount
            case declined
            /// The Mac could not share, like before iCloud was ready.
            case failed
        }

        var version = 1
        var outcome: Outcome
        var shares: [URL] = []
        var name: String
        var owner: String?
    }

    enum Kind: String, CaseIterable, Sendable {
        case offer, request, answer
    }

    /// The public record a message goes in, named from the code. The name
    /// shows nothing: what is in it is sealed with the code itself.
    static func recordName(_ kind: Kind, code: String) -> String? {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data("snapfly-pair-v1|\(code)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(kind.rawValue)-\(hex.prefix(40))"
        #else
        return nil
        #endif
    }

    #if canImport(CryptoKit)
    private static func key(_ code: String, _ kind: Kind) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(code.utf8)),
                               salt: Data("snapfly-pair-v1".utf8), info: Data(kind.rawValue.utf8),
                               outputByteCount: 32)
    }

    static func seal<Value: Encodable>(_ value: Value, _ kind: Kind, code: String) throws -> Data {
        let plain = try SyncCoding.encoder.encode(value)
        guard let sealed = try AES.GCM.seal(plain, using: key(code, kind)).combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return sealed
    }

    /// Nil for anything not sealed with this code for this kind of message.
    static func open<Value: Decodable>(_ data: Data, as type: Value.Type, _ kind: Kind, code: String) -> Value? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key(code, kind)) else { return nil }
        return try? SyncCoding.decoder.decode(type, from: plain)
    }
    #endif
}

/// Tries on a device that types codes: after a few wrong ones in a row it
/// waits, so codes cannot be guessed one after another.
struct PairingAttempts: Codable, Equatable, Sendable {
    static let allowed = 5
    static let pause: TimeInterval = 60

    private(set) var wrong = 0
    private(set) var waitUntil: Date?

    func mayTry(at now: Date = Date()) -> Bool {
        guard let waitUntil else { return true }
        return now >= waitUntil
    }

    /// Seconds still to wait, for the message.
    func wait(at now: Date = Date()) -> Int {
        guard let waitUntil else { return 0 }
        return max(0, Int(waitUntil.timeIntervalSince(now).rounded(.up)))
    }

    mutating func failed(at now: Date = Date()) {
        if let waitUntil, now >= waitUntil {
            wrong = 0
            self.waitUntil = nil
        }
        wrong += 1
        if wrong >= Self.allowed { waitUntil = now.addingTimeInterval(Self.pause) }
    }

    mutating func succeeded() {
        wrong = 0
        waitUntil = nil
    }
}
