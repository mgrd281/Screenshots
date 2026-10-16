import Foundation
import Network

/// The exact time from the atomic clocks of the PTB, Germany's national
/// metrology institute, asked the way clocks set themselves (NTP). Only the
/// question for the time goes out: nothing about the Mac, its user or its
/// screenshots. Asked only while the time stamp is on.
enum AtomicTime {
    static let servers = ["ptbtime1.ptb.de", "ptbtime2.ptb.de", "ptbtime3.ptb.de"]

    /// Seconds between 1900, where NTP counts from, and 1970.
    private static let since1900: TimeInterval = 2_208_988_800

    /// The last answer, kept for a few minutes: a Mac's clock drifts far
    /// less than a second in that time, and a burst of screenshots asks once.
    private static var last: (offset: TimeInterval, at: Date)?
    private static let lock = NSLock()

    /// How far the PTB's time is ahead of the Mac's clock, in seconds, or
    /// nil when no server answered in time. Calls back on the main thread.
    static func offset(completion: @escaping @Sendable (TimeInterval?) -> Void) {
        lock.lock()
        let cached = last
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 300 {
            DispatchQueue.main.async { completion(cached.offset) }
            return
        }
        ask(servers[...]) { offset in
            if let offset {
                lock.lock()
                last = (offset, Date())
                lock.unlock()
            }
            DispatchQueue.main.async { completion(offset) }
        }
    }

    /// Tries each server in turn until one answers.
    private static func ask(_ servers: ArraySlice<String>, completion: @escaping @Sendable (TimeInterval?) -> Void) {
        guard let server = servers.first else { return completion(nil) }
        Query(server: server).run { offset in
            if let offset { completion(offset) } else { ask(servers.dropFirst(), completion: completion) }
        }
    }

    /// One question to one server, given two seconds to answer.
    private final class Query: @unchecked Sendable {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "Snapfly.AtomicTime")
        private var done: ((TimeInterval?) -> Void)?

        init(server: String) {
            connection = NWConnection(host: NWEndpoint.Host(server), port: 123, using: .udp)
        }

        func run(_ completion: @escaping @Sendable (TimeInterval?) -> Void) {
            done = completion
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready: send()
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { [self] in finish(nil) }
        }

        private func send() {
            let sent = Date()
            let request = AtomicTime.request(at: sent)
            connection.send(content: request, completion: .contentProcessed { [self] error in
                if error != nil { return finish(nil) }
                connection.receiveMessage { [self] data, _, _, _ in
                    let received = Date()
                    finish(data.flatMap { AtomicTime.offset(response: $0, request: request, received: received) })
                }
            })
        }

        /// Runs on the query's own queue, so only the first outcome counts.
        private func finish(_ offset: TimeInterval?) {
            guard let done else { return }
            self.done = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            done(offset)
        }
    }

    // MARK: The packets

    /// A question for the time: version 4, from a client, sent at the given
    /// moment by the Mac's clock.
    static func request(at sent: Date) -> Data {
        var packet = Data(count: 48)
        packet[0] = 0x23
        put(timestamp(sent), in: &packet, at: 40)
        return packet
    }

    /// The offset from a server's answer: the middle of what the server's
    /// clock read on the way in and out, against the Mac's. Nil for an
    /// answer that is not to this question, or from a server that is not
    /// synchronised.
    static func offset(response: Data, request: Data, received: Date) -> TimeInterval? {
        let bytes = [UInt8](response)
        guard bytes.count >= 48, bytes[0] & 0x07 == 4, (1...15).contains(bytes[1]),
              bytes[24..<32].elementsEqual([UInt8](request)[40..<48]) else { return nil }
        let sent = date(fromTimestamp: read(bytes, at: 24))
        let serverIn = date(fromTimestamp: read(bytes, at: 32))
        let serverOut = date(fromTimestamp: read(bytes, at: 40))
        return (serverIn.timeIntervalSince(sent) + serverOut.timeIntervalSince(received)) / 2
    }

    /// A moment as NTP writes it: seconds since 1900, then the fraction.
    static func timestamp(_ date: Date) -> UInt64 {
        let seconds = date.timeIntervalSince1970 + since1900
        let whole = UInt64(seconds)
        let fraction = UInt64((seconds - Double(whole)) * 4_294_967_296)
        return whole << 32 | fraction
    }

    static func date(fromTimestamp value: UInt64) -> Date {
        let seconds = Double(value >> 32) + Double(value & 0xFFFF_FFFF) / 4_294_967_296
        return Date(timeIntervalSince1970: seconds - since1900)
    }

    private static func put(_ value: UInt64, in packet: inout Data, at offset: Int) {
        for i in 0..<8 { packet[offset + i] = UInt8(truncatingIfNeeded: value >> (56 - 8 * UInt64(i))) }
    }

    private static func read(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 { value = value << 8 | UInt64(bytes[offset + i]) }
        return value
    }
}
