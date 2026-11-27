import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A proof of when a file existed that holds up without Snapfly: a time
/// stamp from an independent time stamping authority, as RFC 3161 sets it
/// out. Only the file's SHA-256 fingerprint goes out, with a random number
/// that ties the answer to this question; the answer, signed by the
/// authority, binds that fingerprint to the time by the authority's clock.
/// Anyone can check it later against the file, with any program that reads
/// RFC 3161 time stamps.
///
/// The first authority gives qualified electronic time stamps under the
/// EU's eIDAS regulation, which courts across the EU take as accurate until
/// shown otherwise (Article 41). The others answer when it does not.
enum TrustedTime {
    struct Authority: Equatable, Sendable {
        var name: String
        var url: URL
    }

    /// Asked in turn until one answers. Only HTTPS: the answer is signed
    /// either way, and the Mac allows nothing else.
    static let authorities = [
        Authority(name: "Sectigo (Europe) SL", url: URL(string: "https://timestamp.sectigo.com/qualified")!),
        Authority(name: "Sectigo Limited", url: URL(string: "https://timestamp.sectigo.com")!),
        Authority(name: "Free TSA", url: URL(string: "https://freetsa.org/tsr")!),
    ]

    /// What an authority's answer says, once it is known to answer this
    /// question about this file.
    struct Stamp: Equatable, Sendable {
        /// By the authority's clock.
        var time: Date
        /// How far either way the authority vouches for its time, in
        /// seconds, when it says.
        var accuracy: Double?
        /// The authority's own number for this time stamp, in hexadecimal.
        var serial: String
        /// The rules the authority stamped by, as a dotted object identifier.
        var policy: String
        /// The authority marks the stamp as a qualified one under eIDAS.
        var qualified: Bool
        /// The whole answer as it came (a TimeStampResp, DER), which is what
        /// is kept and handed on.
        var response: Data
    }

    enum Failure: Error, Equatable {
        /// Not an answer that can be read.
        case malformed
        /// The authority said no, with its status.
        case refused(Int)
        /// The answer is about another fingerprint.
        case otherFile
        /// The answer is to another question.
        case otherQuestion
    }

    // MARK: Asking

    private static let session = URLSession(configuration: .ephemeral)

    /// Asks the authorities in turn for a stamp on this SHA-256 fingerprint;
    /// nil when none answered with one.
    static func stamp(sha256: Data) async -> (Stamp, Authority)? {
        for authority in authorities {
            if let stamp = await ask(authority, sha256: sha256) { return (stamp, authority) }
        }
        return nil
    }

    /// One question to one authority, given twenty seconds to answer.
    static func ask(_ authority: Authority, sha256: Data) async -> Stamp? {
        let nonce = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var request = URLRequest(url: authority.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        request.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")
        request.httpBody = query(sha256: sha256, nonce: nonce)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? stamp(from: data, sha256: sha256, nonce: nonce)
    }

    // MARK: The question

    /// The question for a time stamp (a TimeStampReq, DER): version 1, the
    /// SHA-256 fingerprint, the random number, and a request for the
    /// authority's certificate, so the answer can be checked on its own.
    static func query(sha256: Data, nonce: Data) -> Data {
        let imprint = der(0x30, sha256Algorithm + der(0x04, [UInt8](sha256)))
        let body = der(0x02, [1]) + imprint + der(0x02, positive([UInt8](nonce))) + der(0x01, [0xFF])
        return Data(der(0x30, body))
    }

    /// SHA-256 with no parameters, as an AlgorithmIdentifier.
    private static let sha256Algorithm = der(0x30, der(0x06, sha256OID) + der(0x05, []))
    private static let sha256OID: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    /// esi4-qtstStatement-1 (0.4.0.19422.1.1), with which an authority
    /// marks a time stamp as qualified under eIDAS (ETSI EN 319 422).
    private static let qualifiedOID: [UInt8] = [0x04, 0x00, 0x81, 0x97, 0x5E, 0x01, 0x01]

    /// One DER element: its tag, its length and its content.
    private static func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var length: [UInt8]
        if content.count < 0x80 {
            length = [UInt8(content.count)]
        } else {
            var n = content.count
            length = []
            while n > 0 {
                length.insert(UInt8(n & 0xFF), at: 0)
                n >>= 8
            }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return [tag] + length + content
    }

    /// A number's bytes as a positive INTEGER: no leading zeros, and one
    /// zero in front where the first bit would read as a minus.
    private static func positive(_ bytes: [UInt8]) -> [UInt8] {
        var bytes = Array(bytes.drop { $0 == 0 })
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return bytes
    }

    // MARK: The answer

    /// Reads an authority's answer and checks that it grants a stamp, on
    /// this fingerprint, in answer to this question.
    static func stamp(from response: Data, sha256: Data, nonce: Data?) throws -> Stamp {
        let bytes = [UInt8](response)
        let top = try element(bytes[...], tag: 0x30)
        let parts = try children(top)
        guard parts.count >= 1 else { throw Failure.malformed }
        let status = try children(parts[0].expecting(0x30))
        guard let first = status.first else { throw Failure.malformed }
        let code = try integer(first.expecting(0x02))
        guard code == 0 || code == 1 else { throw Failure.refused(code) }
        guard parts.count >= 2 else { throw Failure.malformed }

        // The token is CMS SignedData, whose content is the TSTInfo.
        let token = try children(parts[1].expecting(0x30))
        guard token.count >= 2 else { throw Failure.malformed }
        let signed = try children(token[1].expecting(0xA0))
        guard let signedData = signed.first else { throw Failure.malformed }
        let fields = try children(signedData.expecting(0x30))
        guard fields.count >= 3 else { throw Failure.malformed }
        let content = try children(fields[2].expecting(0x30))
        guard content.count >= 2 else { throw Failure.malformed }
        let wrapped = try children(content[1].expecting(0xA0))
        guard let octets = wrapped.first else { throw Failure.malformed }
        let info = try children(element(octets.expecting(0x04), tag: 0x30))
        guard info.count >= 5 else { throw Failure.malformed }

        let policy = try objectIdentifier(info[1].expecting(0x06))
        let imprint = try children(info[2].expecting(0x30))
        guard imprint.count == 2 else { throw Failure.malformed }
        let algorithm = try children(imprint[0].expecting(0x30))
        guard let oid = algorithm.first, try Array(oid.expecting(0x06)) == sha256OID else { throw Failure.otherFile }
        guard try Array(imprint[1].expecting(0x04)) == [UInt8](sha256) else { throw Failure.otherFile }
        let number = try info[3].expecting(0x02).drop { $0 == 0 }
        let serial = number.isEmpty ? "00" : hex(Array(number))
        guard let time = generalizedTime(try info[4].expecting(0x18)) else { throw Failure.malformed }

        var accuracy: Double?
        var answered: [UInt8]?
        var qualified = false
        for field in info.dropFirst(5) {
            switch field.tag {
            case 0x30: accuracy = try seconds(of: field.body)
            case 0x02: answered = Array(field.body)
            case 0xA1: qualified = contains(field.body, qualifiedOID)
            default: break
            }
        }
        if let nonce {
            guard let answered, positive(answered) == positive([UInt8](nonce)) else { throw Failure.otherQuestion }
        }
        return Stamp(time: time, accuracy: accuracy, serial: serial, policy: policy, qualified: qualified,
                     response: response)
    }

    // MARK: Reading DER

    struct Element {
        var tag: UInt8
        var body: ArraySlice<UInt8>

        func expecting(_ tag: UInt8) throws -> ArraySlice<UInt8> {
            guard self.tag == tag else { throw Failure.malformed }
            return body
        }
    }

    /// The first element in these bytes, and what follows it. Only definite
    /// lengths, as DER has them, and tags of one byte.
    private static func read(_ bytes: ArraySlice<UInt8>) throws -> (Element, ArraySlice<UInt8>) {
        var i = bytes.startIndex
        guard i < bytes.endIndex else { throw Failure.malformed }
        let tag = bytes[i]
        guard tag & 0x1F != 0x1F else { throw Failure.malformed }
        i += 1
        guard i < bytes.endIndex else { throw Failure.malformed }
        var length = Int(bytes[i])
        i += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), bytes.endIndex - i >= count else { throw Failure.malformed }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(bytes[i])
                i += 1
            }
        }
        guard bytes.endIndex - i >= length else { throw Failure.malformed }
        let body = bytes[i..<(i + length)]
        return (Element(tag: tag, body: body), bytes[(i + length)...])
    }

    /// The body of the first element, which must have this tag.
    private static func element(_ bytes: ArraySlice<UInt8>, tag: UInt8) throws -> ArraySlice<UInt8> {
        try read(bytes).0.expecting(tag)
    }

    /// The elements one after another in a body.
    private static func children(_ body: ArraySlice<UInt8>) throws -> [Element] {
        var rest = body
        var found: [Element] = []
        while !rest.isEmpty {
            let (next, after) = try read(rest)
            found.append(next)
            rest = after
        }
        return found
    }

    /// A small INTEGER's value.
    private static func integer(_ body: ArraySlice<UInt8>) throws -> Int {
        guard (1...4).contains(body.count) else { throw Failure.malformed }
        var value = body.first! & 0x80 != 0 ? -1 : 0
        for byte in body { value = value << 8 | Int(byte) }
        return value
    }

    /// An OBJECT IDENTIFIER, dotted.
    private static func objectIdentifier(_ body: ArraySlice<UInt8>) throws -> String {
        var numbers: [Int] = []
        var value = 0
        for byte in body {
            value = value << 7 | Int(byte & 0x7F)
            guard value < Int(Int32.max) else { throw Failure.malformed }
            if byte & 0x80 == 0 {
                if numbers.isEmpty {
                    let first = min(value / 40, 2)
                    numbers = [first, value - first * 40]
                } else {
                    numbers.append(value)
                }
                value = 0
            }
        }
        guard !numbers.isEmpty else { throw Failure.malformed }
        return numbers.map(String.init).joined(separator: ".")
    }

    /// A GeneralizedTime in UTC, as RFC 3161 has it: "20261127122852Z",
    /// with a fraction of a second where the authority gives one.
    static func generalizedTime(_ body: ArraySlice<UInt8>) -> Date? {
        guard let text = String(bytes: body, encoding: .ascii), text.hasSuffix("Z") else { return nil }
        let digits = Array(text.dropLast())
        guard digits.count >= 14, digits[0..<14].allSatisfy(\.isNumber) else { return nil }
        func number(_ range: Range<Int>) -> Int { Int(String(digits[range]))! }
        var parts = DateComponents()
        parts.year = number(0..<4)
        parts.month = number(4..<6)
        parts.day = number(6..<8)
        parts.hour = number(8..<10)
        parts.minute = number(10..<12)
        parts.second = number(12..<14)
        var fraction = 0.0
        if digits.count > 14 {
            let rest = digits[14...]
            guard rest.first == ".", rest.count > 1, rest.dropFirst().allSatisfy(\.isNumber),
                  let value = Double("0" + String(rest)) else { return nil }
            fraction = value
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: parts)?.addingTimeInterval(fraction)
    }

    /// An Accuracy's seconds, milliseconds and microseconds, together.
    private static func seconds(of body: ArraySlice<UInt8>) throws -> Double {
        var total = 0.0
        for part in try children(body) {
            switch part.tag {
            case 0x02: total += Double(try integer(part.body))
            case 0x80: total += Double(try integer(part.body)) / 1_000
            case 0x81: total += Double(try integer(part.body)) / 1_000_000
            default: break
            }
        }
        return total
    }

    private static func contains(_ bytes: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
        let haystack = Array(bytes)
        guard haystack.count >= needle.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
