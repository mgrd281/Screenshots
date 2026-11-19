import Foundation

/// A screenshot handed from the Mac to the iPhone nearby, with Handoff: the
/// Mac offers its newest photo, the iPhone shows Snapfly at the bottom of
/// its app switcher, and a tap there opens the photo on the iPhone. The
/// photo itself goes straight from one device to the other when the iPhone
/// asks for it, over Handoff's own streams: the Mac writes its length, then
/// its bytes, and the iPhone reads them back. Both must be signed in to the
/// same Apple account, with Bluetooth and Wi-Fi on.
///
/// What goes is what leaves the line, covered as Settings says.
enum PhotoHandoff {
    /// The kind of activity, as both apps' Info.plist lists it under
    /// NSUserActivityTypes.
    static let activityType = "de.ghazarian.Snapfly.photo"
    /// The photo's file name, in the activity's user info.
    static let nameKey = "name"
    /// Larger than this, a photo is not sent: no screenshot is, and a
    /// length read wrong must not ask for more memory than an iPhone has.
    static let largest = 64 * 1024 * 1024

    /// The length before the bytes: eight bytes, the largest first.
    static func header(for count: Int) -> Data {
        var length = UInt64(count).bigEndian
        return Data(bytes: &length, count: 8)
    }

    /// The length a header says, or nil when it is not one, or says
    /// nothing, or more than `largest`.
    static func length(of header: Data) -> Int? {
        guard header.count == 8 else { return nil }
        let value = header.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard value > 0, value <= UInt64(largest) else { return nil }
        return Int(value)
    }

    /// The photo, its length first, into a stream, which is then closed.
    /// Blocks until all is written: call it away from the main thread.
    /// Whether it all went.
    @discardableResult
    static func send(_ data: Data, to stream: OutputStream) -> Bool {
        stream.open()
        defer { stream.close() }
        return framed(data, into: stream)
    }

    /// The photo, its length first, into a stream already open.
    static func framed(_ data: Data, into stream: OutputStream) -> Bool {
        guard !data.isEmpty, data.count <= largest else { return false }
        return write(header(for: data.count), to: stream) && write(data, to: stream)
    }

    /// A photo from a stream, its length first, which is then closed.
    /// Blocks until all is read: call it away from the main thread. Nil
    /// when the stream ends early or fails.
    static func receive(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        guard let header = read(8, from: stream), let count = length(of: header) else { return nil }
        return read(count, from: stream)
    }

    private static func write(_ data: Data, to stream: OutputStream) -> Bool {
        var sent = 0
        while sent < data.count {
            let wrote = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return stream.write(base + sent, maxLength: min(64 * 1024, data.count - sent))
            }
            guard wrote > 0 else { return false }
            sent += wrote
        }
        return true
    }

    private static func read(_ count: Int, from stream: InputStream) -> Data? {
        var data = Data(capacity: count)
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < count {
            let got = stream.read(&chunk, maxLength: min(chunk.count, count - data.count))
            guard got > 0 else { return nil }
            data.append(chunk, count: got)
        }
        return data
    }
}
