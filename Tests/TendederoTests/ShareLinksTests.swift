import Foundation
import XCTest
@testable import Tendedero

/// Copy Link: what may go, the requests to the share service, reading its
/// answers, and the links kept with their delete tokens.
final class ShareLinksTests: XCTestCase {
    private let service = URL(string: "https://snapfly-share.example.workers.dev/")!
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ShareLinksTests-\(UUID().uuidString)")
    }

    private func link(_ id: String, source: String = "/a.png", fingerprint: String = "f", expires: Date) -> ShareLinks.Link {
        ShareLinks.Link(id: id, url: service.appendingPathComponent(id), deleteToken: "t-\(id)", expires: expires,
                        source: source, fingerprint: fingerprint)
    }

    func testOnlyPicturesFilmsAndPDFsGo() {
        XCTAssertEqual(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/A.PNG")), "image/png")
        XCTAssertEqual(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/a.jpeg")), "image/jpeg")
        XCTAssertEqual(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/a.mov")), "video/quicktime")
        XCTAssertEqual(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/a.pdf")), "application/pdf")
        XCTAssertNil(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/a.svg")))
        XCTAssertNil(ShareLinks.contentType(for: URL(fileURLWithPath: "/x/a.html")))
        XCTAssertThrowsError(try ShareLinks.uploadRequest(for: URL(fileURLWithPath: "/x/a.svg"), to: service))
    }

    func testTheRequests() throws {
        let upload = try ShareLinks.uploadRequest(for: URL(fileURLWithPath: "/x/a.png"), to: service)
        XCTAssertEqual(upload.url?.absoluteString, "https://snapfly-share.example.workers.dev/api/files")
        XCTAssertEqual(upload.httpMethod, "POST")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Content-Type"), "image/png")
        let delete = ShareLinks.deleteRequest(for: link("abc", expires: Date()), to: service)
        XCTAssertEqual(delete.url?.absoluteString, "https://snapfly-share.example.workers.dev/api/files/abc")
        XCTAssertEqual(delete.httpMethod, "DELETE")
        XCTAssertEqual(delete.value(forHTTPHeaderField: "Authorization"), "Bearer t-abc")
    }

    func testTheLinkIsReadFromTheAnswer() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "AbCdEfGhIjKlMnOpQrStUv", "url": "https://snapfly-share.example.workers.dev/AbCdEfGhIjKlMnOpQrStUv",
            "deleteToken": "secret", "expires": "2026-10-26T09:41:00.123Z",
        ])
        let made = try ShareLinks.link(status: 201, data: data, source: "/a.png", fingerprint: "f")
        XCTAssertEqual(made.id, "AbCdEfGhIjKlMnOpQrStUv")
        XCTAssertEqual(made.deleteToken, "secret")
        XCTAssertEqual(made.expires.timeIntervalSince1970, 1_793_007_660.123, accuracy: 0.01)
        XCTAssertEqual(ShareLinks.daysLeft(made, now: made.expires.addingTimeInterval(-6.5 * 86_400)), 7)
    }

    func testEachFailureSaysWhatHappened() {
        func failure(_ status: Int) -> ShareLinks.Failure? {
            do {
                _ = try ShareLinks.link(status: status, data: Data(), source: "", fingerprint: "")
                return nil
            } catch {
                return error as? ShareLinks.Failure
            }
        }
        XCTAssertEqual(failure(413), .tooLarge)
        XCTAssertEqual(failure(415), .kind)
        XCTAssertEqual(failure(429), .busy)
        XCTAssertEqual(failure(500), .failed)
        XCTAssertEqual(failure(201), .failed)
    }

    func testTheSameVersionKeepsItsLink() {
        let now = Date()
        ShareLinks.add(link("old", expires: now.addingTimeInterval(-60)), in: defaults, now: now)
        ShareLinks.add(link("soon", expires: now.addingTimeInterval(3_600)), in: defaults, now: now)
        ShareLinks.add(link("week", expires: now.addingTimeInterval(6 * 86_400)), in: defaults, now: now)
        ShareLinks.add(link("other", fingerprint: "g", expires: now.addingTimeInterval(6 * 86_400)), in: defaults, now: now)
        // Run out ones are forgotten; one with less than a day left is not copied again.
        XCTAssertEqual(ShareLinks.kept(in: defaults, now: now).map(\.id), ["soon", "week", "other"])
        XCTAssertEqual(ShareLinks.reusable(source: "/a.png", fingerprint: "f", in: defaults, now: now)?.id, "week")
        XCTAssertNil(ShareLinks.reusable(source: "/b.png", fingerprint: "f", in: defaults, now: now))
        XCTAssertEqual(ShareLinks.links(for: "/a.png", in: defaults, now: now).count, 3)
        ShareLinks.remove(link("week", expires: now), in: defaults)
        XCTAssertNil(ShareLinks.reusable(source: "/a.png", fingerprint: "f", in: defaults, now: now))
    }

    func testAFileIsKnownByWhatIsInIt() throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).png")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try Data([1, 2, 3]).write(to: a)
        try Data([1, 2, 3]).write(to: b)
        XCTAssertEqual(ShareLinks.fingerprint(of: a), ShareLinks.fingerprint(of: b))
        try Data([1, 2, 4]).write(to: b)
        XCTAssertNotEqual(ShareLinks.fingerprint(of: a), ShareLinks.fingerprint(of: b))
    }
}
