import Foundation

/// Pictures read a few at a time, the newest asked first, so a line full of
/// them, read again after a change in Settings or at launch, never reads all
/// of them at once: each reading holds its picture whole, and may wait a
/// while for Apple Intelligence. A screenshot just taken goes before the
/// older ones still waiting.
final class ReadingQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [@Sendable () -> Void] = []
    private var running = 0
    /// How many readings go on at the same time.
    let width: Int
    private let quality: DispatchQoS.QoSClass

    init(width: Int, quality: DispatchQoS.QoSClass = .utility) {
        self.width = max(1, width)
        self.quality = quality
    }

    /// Reads it once a place is free, before the readings asked earlier
    /// that still wait.
    func add(_ job: @escaping @Sendable () -> Void) {
        lock.lock()
        waiting.append(job)
        lock.unlock()
        startNext()
    }

    /// How many wait for a place, for the tests.
    var waitingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiting.count
    }

    private func startNext() {
        lock.lock()
        guard running < width, let job = waiting.popLast() else {
            lock.unlock()
            return
        }
        running += 1
        lock.unlock()
        DispatchQueue.global(qos: quality).async {
            job()
            self.lock.lock()
            self.running -= 1
            self.lock.unlock()
            self.startNext()
        }
    }
}
