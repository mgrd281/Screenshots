import Foundation
import XCTest
@testable import Tendedero

/// Pairing with a code without iCloud: the codes and when they count, what
/// is typed, the records they name, the sealed messages, and the pause after
/// wrong codes.
final class PairingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// The same numbers each run, so the tests do not depend on chance.
    private struct Fixed: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testACodeIsSixDigitsAndCountsDownFromThirty() {
        var generator = Fixed(state: 7)
        let code = PairingCode.make(at: start, using: &generator)
        XCTAssertEqual(code.value.count, 6)
        XCTAssertTrue(code.value.allSatisfy(\.isNumber))
        XCTAssertEqual(code.secondsLeft(now: at(0)), 30)
        XCTAssertEqual(code.secondsLeft(now: at(29.2)), 1)
        XCTAssertEqual(code.secondsLeft(now: at(31)), 0)
        XCTAssertTrue(code.accepts(at: at(40)), "one typed just as it changed still counts")
        XCTAssertFalse(code.accepts(at: at(45)))
        XCTAssertEqual(code.spaced.count, 7)
    }

    func testSmallNumbersKeepTheirLeadingZeros() {
        XCTAssertEqual(PairingCode.text(0), "000000")
        XCTAssertEqual(PairingCode.text(42), "000042")
        XCTAssertEqual(PairingCode.text(999_999), "999999")
        XCTAssertEqual(PairingCode(value: PairingCode.text(42), shown: start).spaced, "000 042")
    }

    func testANewCodeEveryThirtySecondsAndTheOldOneBrieflyToo() {
        var generator = Fixed(state: 42)
        var schedule = PairingSchedule(now: start, using: &generator)
        let first = schedule.current
        XCTAssertFalse(schedule.advance(now: at(10), using: &generator))
        XCTAssertEqual(schedule.listening(at: at(10)).map(\.value), [first.value])
        XCTAssertTrue(schedule.advance(now: at(30), using: &generator))
        XCTAssertNotEqual(schedule.current.value, first.value, "the change shows")
        XCTAssertEqual(schedule.listening(at: at(31)).map(\.value), [schedule.current.value, first.value])
        XCTAssertFalse(schedule.advance(now: at(46), using: &generator))
        XCTAssertEqual(schedule.listening(at: at(46)).map(\.value), [schedule.current.value])
        XCTAssertNil(schedule.previous)
    }

    func testCodesAreNotWorkedOutFromTheTime() {
        var one = Fixed(state: 1), two = Fixed(state: 2)
        XCTAssertNotEqual(PairingCode.make(at: start, using: &one).value, PairingCode.make(at: start, using: &two).value)
        let drawn = Set((0..<50).map { _ in PairingCode.make(at: start).value })
        XCTAssertGreaterThan(drawn.count, 45, "drawn at random each time")
    }

    func testWhatIsTypedCountsInAnyDigitsAndSpacing() {
        XCTAssertEqual(PairingCode.normalize("042917"), "042917")
        XCTAssertEqual(PairingCode.normalize(" 042 917 "), "042917")
        XCTAssertEqual(PairingCode.normalize("042-917"), "042917")
        XCTAssertEqual(PairingCode.normalize("٠٤٢٩١٧"), "042917", "Arabic-Indic digits")
        XCTAssertEqual(PairingCode.normalize("۰۴۲۹۱۷"), "042917", "Persian digits")
        XCTAssertNil(PairingCode.normalize("04291"))
        XCTAssertNil(PairingCode.normalize("0429170"))
        XCTAssertNil(PairingCode.normalize("04a917"))
        XCTAssertNil(PairingCode.normalize(""))
    }

    func testWrongCodesInARowMeanAPause() {
        var attempts = PairingAttempts()
        for second in 0..<(PairingAttempts.allowed - 1) {
            attempts.failed(at: at(TimeInterval(second)))
            XCTAssertTrue(attempts.mayTry(at: at(TimeInterval(second))))
        }
        attempts.failed(at: at(10))
        XCTAssertFalse(attempts.mayTry(at: at(10)))
        XCTAssertEqual(attempts.wait(at: at(10)), Int(PairingAttempts.pause))
        XCTAssertTrue(attempts.mayTry(at: at(10 + PairingAttempts.pause)))
        attempts.failed(at: at(10 + PairingAttempts.pause))
        XCTAssertTrue(attempts.mayTry(at: at(11 + PairingAttempts.pause)), "after the pause, counting starts again")
        attempts.succeeded()
        XCTAssertEqual(attempts, PairingAttempts())
    }

    func testEachSharedSpaceHasAFolderOfItsOwn() {
        let root = URL(fileURLWithPath: "/tmp/Snapfly/Sync", isDirectory: true)
        XCTAssertEqual(SyncSpace.own.folder(in: root), root)
        let shared = SyncSpace.shared(owner: "_8d3f0c2a").folder(in: root)
        XCTAssertEqual(shared.path, "/tmp/Snapfly/Sync/Shared/_8d3f0c2a")
        XCTAssertEqual(SyncSpace.shared(owner: "../../etc").folder(in: root).path, "/tmp/Snapfly/Sync/Shared/etc",
                       "an owner's name never leaves the folder")
        XCTAssertNil(SyncSpace.own.owner)
        XCTAssertEqual(SyncSpace.shared(owner: "_a").owner, "_a")
    }

    func testDisconnectingAnotherAccountTakesItsDevicesOffAndKeepsWhatTheySent() {
        var mac = SyncLedger(device: "MAC")
        let phone = SyncDevice(id: "PHONE", name: "iPhone", platform: .iPhone, model: "iPhone16,1", registered: start,
                               lastSeen: start, lastSync: nil, appVersion: "1.1.0", schema: SyncSchema.current,
                               account: "_other")
        let own = SyncDevice(id: "PAD", name: "iPad", platform: .iPad, model: "iPad14,1", registered: start,
                             lastSeen: start, lastSync: nil, appVersion: "1.1.0", schema: SyncSchema.current,
                             account: "_me")
        mac.apply(.device(phone), now: at(0))
        mac.apply(.device(own), now: at(0))
        XCTAssertEqual(mac.forgetDevices(of: "_other", now: at(5)), ["PHONE"])
        XCTAssertNil(mac.devices["PHONE"])
        XCTAssertNotNil(mac.devices["PAD"], "devices of the Mac's own account stay")
        XCTAssertEqual(mac.journal.map(\.key), [SyncKey(.device, "PHONE")])
        XCTAssertEqual(mac.journal.first?.kind, .purge)
        var settings = SyncSettings()
        settings.on = true
        XCTAssertTrue(SyncPolicy.allows(mac.journal[0], in: mac, settings: settings), "its record may leave iCloud")
    }

    func testADeviceSaysWhenItsAccountChanges() {
        var ledger = SyncLedger(device: "MAC")
        var device = SyncDevice(id: "MAC", name: "Mac", platform: .mac, model: "Mac15,3", registered: start,
                                lastSeen: start, lastSync: nil, appVersion: "1.1.0", schema: SyncSchema.current)
        ledger.register(device, now: at(0))
        ledger.markDone(SyncKey(.device, "MAC"))
        device.account = "_me"
        ledger.register(device, now: at(60))
        XCTAssertEqual(ledger.journal.map(\.key), [SyncKey(.device, "MAC")])
        XCTAssertEqual(ledger.devices["MAC"]?.account, "_me")
    }

    func testAnOlderDeviceRecordWithoutAnAccountStillReads() throws {
        let old = #"{"id":"A","name":"Mac","platform":"mac","model":"Mac15,3","registered":1800000000000,"lastSeen":1800000000000,"appVersion":"1.1.0","schema":1}"#
        let device = try SyncCoding.decoder.decode(SyncDevice.self, from: Data(old.utf8))
        XCTAssertNil(device.account)
        XCTAssertEqual(device.name, "Mac")
    }

    #if canImport(CryptoKit)
    func testRecordsAreNamedFromTheCodeAndShowNothingOfIt() throws {
        let offer = try XCTUnwrap(PairingMessage.recordName(.offer, code: "042917"))
        XCTAssertEqual(offer, PairingMessage.recordName(.offer, code: "042917"))
        XCTAssertNotEqual(offer, PairingMessage.recordName(.offer, code: "042918"))
        XCTAssertNotEqual(offer, PairingMessage.recordName(.request, code: "042917"))
        XCTAssertNotEqual(offer, PairingMessage.recordName(.answer, code: "042917"))
        XCTAssertTrue(offer.hasPrefix("offer-"))
        XCTAssertFalse(offer.contains("042917"))
        XCTAssertLessThanOrEqual(offer.count, 255)
    }

    func testMessagesOpenOnlyWithTheirCodeAndKind() throws {
        let device = SyncDevice(id: "PHONE", name: "iPhone", platform: .iPhone, model: "iPhone16,1", registered: start,
                                lastSeen: start, lastSync: nil, appVersion: "1.1.0", schema: SyncSchema.current,
                                account: "_b")
        let request = PairingMessage.Request(user: "_b", device: device)
        let sealed = try PairingMessage.seal(request, .request, code: "042917")
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains("iPhone"), "sealed, not readable")
        XCTAssertEqual(PairingMessage.open(sealed, as: PairingMessage.Request.self, .request, code: "042917"), request)
        XCTAssertNil(PairingMessage.open(sealed, as: PairingMessage.Request.self, .request, code: "042918"))
        XCTAssertNil(PairingMessage.open(sealed, as: PairingMessage.Request.self, .answer, code: "042917"),
                     "an answer cannot be made from a request")
        var tampered = sealed
        tampered[tampered.startIndex + tampered.count / 2] ^= 0x01
        XCTAssertNil(PairingMessage.open(tampered, as: PairingMessage.Request.self, .request, code: "042917"))

        let answer = PairingMessage.Answer(outcome: .joined, shares: [URL(string: "https://www.icloud.com/share/0abc")!],
                                           name: "Studio", owner: "_a")
        let box = try PairingMessage.seal(answer, .answer, code: "042917")
        XCTAssertEqual(PairingMessage.open(box, as: PairingMessage.Answer.self, .answer, code: "042917"), answer)
        XCTAssertNotEqual(try PairingMessage.seal(answer, .answer, code: "042917"), box, "a fresh seal each time")
    }
    #endif
}
