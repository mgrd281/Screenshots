import Foundation
import XCTest
@testable import Tendedero

/// Pictures are read a few at a time, the newest asked first. Pure, so it
/// runs anywhere, Linux too.
final class ReadingQueueTests: XCTestCase {
    /// What the readings saw, written from their threads under a lock.
    private final class Seen: @unchecked Sendable {
        let lock = NSLock()
        var now = 0
        var most = 0
        var order: [Int] = []
    }

    func testNoMoreThanItsWidthReadAtOnce() {
        let queue = ReadingQueue(width: 2)
        let seen = Seen()
        let done = DispatchGroup()
        for _ in 0..<12 {
            done.enter()
            queue.add {
                seen.lock.lock()
                seen.now += 1
                seen.most = max(seen.most, seen.now)
                seen.lock.unlock()
                Thread.sleep(forTimeInterval: 0.02)
                seen.lock.lock()
                seen.now -= 1
                seen.lock.unlock()
                done.leave()
            }
        }
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(seen.most, 2)
        XCTAssertEqual(queue.waitingCount, 0)
    }

    /// While one is read, the one asked last goes next: a screenshot just
    /// taken before the older ones still waiting.
    func testTheNewestWaitingGoesFirst() {
        let queue = ReadingQueue(width: 1)
        let seen = Seen()
        let first = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        done.enter()
        queue.add {
            first.wait()
            done.leave()
        }
        for n in 1...3 {
            done.enter()
            queue.add {
                seen.lock.lock()
                seen.order.append(n)
                seen.lock.unlock()
                done.leave()
            }
        }
        XCTAssertEqual(queue.waitingCount, 3)
        first.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(seen.order, [3, 2, 1])
    }
}
