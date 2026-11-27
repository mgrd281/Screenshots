import XCTest
@testable import Tendedero

/// The proof of time on the Mac: the fingerprint it asks about, what it
/// keeps with the file, and the page that goes with it to a lawyer.
final class TimeProofTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let english = Locale(identifier: "en_US")
    // November 27, 2026, 12:35:12 in UTC.
    private let signed = Date(timeIntervalSince1970: 1_795_782_912)

    private func record(qualified: Bool = true, began: Date? = nil, atomic: Bool = false,
                        duration: Double? = nil) -> TimeProof.Record {
        TimeProof.Record(fingerprint: "ab12", signed: signed, accuracy: 1, authority: "Sectigo (Europe) SL",
                         qualified: qualified, serial: "EA6B", response: Data([0x30, 0x00]), began: began,
                         atomic: atomic, duration: duration)
    }

    func testTheFingerprintIsTheFilesSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("proof-\(UUID().uuidString).mov")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let digest = try XCTUnwrap(TimeProof.sha256(of: file))
        XCTAssertEqual(TimeProof.hex(digest), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testTheRecordIsKeptWhole() throws {
        let kept = record(began: signed.addingTimeInterval(-60), atomic: true, duration: 55)
        let data = try JSONEncoder().encode(kept)
        XCTAssertEqual(try JSONDecoder().decode(TimeProof.Record.self, from: data), kept)
    }

    func testThePageSaysWhatWasSignedAndHowToCheckIt() {
        let page = TimeProof.page(record(), file: "Snapfly 2026-11-27.mov", locale: english, timeZone: utc)
        XCTAssertTrue(page.hasPrefix("Proof of Time\n"))
        XCTAssertTrue(page.contains("File: Snapfly 2026-11-27.mov"))
        XCTAssertTrue(page.contains("Fingerprint (SHA-256): ab12"))
        XCTAssertTrue(page.contains("2026-11-27 12:35:12 UTC"))
        XCTAssertTrue(page.contains("Accuracy: ± 1 s"))
        XCTAssertTrue(page.contains("Time stamping authority: Sectigo (Europe) SL"))
        XCTAssertTrue(page.contains("A qualified electronic time stamp"))
        XCTAssertTrue(page.contains("Serial number: EA6B"))
        XCTAssertTrue(page.contains(#"openssl ts -verify -in "Snapfly 2026-11-27.mov.tsr" -data "Snapfly 2026-11-27.mov""#))
        // Nothing about a beginning Snapfly did not see.
        XCTAssertFalse(page.contains("Recording began"))
    }

    func testOneNotQualifiedSaysSo() {
        let page = TimeProof.page(record(qualified: false), file: "a.png", locale: english, timeZone: utc)
        XCTAssertTrue(page.contains("not a qualified one"))
        XCTAssertFalse(page.contains("A qualified electronic time stamp"))
    }

    func testWhenTheRecordingBeganIsMarkedAsNotSigned() {
        let atomic = TimeProof.page(record(began: signed.addingTimeInterval(-600), atomic: true, duration: 595),
                                    file: "a.mov", locale: english, timeZone: utc)
        XCTAssertTrue(atomic.contains("Recording began:"))
        XCTAssertTrue(atomic.contains("by the PTB’s atomic clock"))
        XCTAssertTrue(atomic.contains("(not signed)"))
        XCTAssertTrue(atomic.contains("Length: 9 minutes"))
        let mac = TimeProof.page(record(began: signed.addingTimeInterval(-600)), file: "a.mov", locale: english,
                                 timeZone: utc)
        XCTAssertTrue(mac.contains("by the Mac’s clock (not signed)"))
    }
}
