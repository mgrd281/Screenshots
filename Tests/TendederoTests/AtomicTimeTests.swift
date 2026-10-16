import XCTest
@testable import Tendedero

/// Asking the PTB's atomic clock for the time: the packets, and the offset
/// worked out from an answer.
final class AtomicTimeTests: XCTestCase {
    private let sent = Date(timeIntervalSince1970: 1_792_193_400.25)

    func testTimestampRoundTrip() {
        let back = AtomicTime.date(fromTimestamp: AtomicTime.timestamp(sent))
        XCTAssertEqual(back.timeIntervalSince1970, sent.timeIntervalSince1970, accuracy: 0.000_001)
    }

    func testRequestIsAClientQuestion() {
        let request = AtomicTime.request(at: sent)
        XCTAssertEqual(request.count, 48)
        XCTAssertEqual(request[0], 0x23)
    }

    /// The server's clock is 10.5 seconds ahead, and the trip takes 2 ms.
    private func answer(to request: Data, mode: UInt8 = 4, stratum: UInt8 = 1) -> Data {
        var answer = Data(count: 48)
        answer[0] = 0x20 | mode
        answer[1] = stratum
        answer.replaceSubrange(24..<32, with: request[40..<48])
        put(sent.addingTimeInterval(10.501), in: &answer, at: 32)
        put(sent.addingTimeInterval(10.5015), in: &answer, at: 40)
        return answer
    }

    private func put(_ date: Date, in data: inout Data, at offset: Int) {
        let value = AtomicTime.timestamp(date)
        for i in 0..<8 { data[offset + i] = UInt8(truncatingIfNeeded: value >> (56 - 8 * UInt64(i))) }
    }

    func testOffsetFromAnAnswer() throws {
        let request = AtomicTime.request(at: sent)
        let offset = try XCTUnwrap(AtomicTime.offset(response: answer(to: request), request: request,
                                                     received: sent.addingTimeInterval(0.002)))
        XCTAssertEqual(offset, 10.50025, accuracy: 0.0001)
    }

    func testAnswerToAnotherQuestionIsIgnored() {
        let request = AtomicTime.request(at: sent)
        let other = AtomicTime.request(at: sent.addingTimeInterval(1))
        XCTAssertNil(AtomicTime.offset(response: answer(to: other), request: request, received: sent))
    }

    func testUnsynchronisedServerIsIgnored() {
        let request = AtomicTime.request(at: sent)
        XCTAssertNil(AtomicTime.offset(response: answer(to: request, stratum: 0), request: request, received: sent))
        XCTAssertNil(AtomicTime.offset(response: answer(to: request, mode: 3), request: request, received: sent))
        XCTAssertNil(AtomicTime.offset(response: Data(count: 12), request: request, received: sent))
    }
}
