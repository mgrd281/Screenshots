import XCTest
@testable import Tendedero

final class CoverBatchTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CoverBatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func make(_ path: String) -> URL {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data([1]))
        return url
    }

    func testKinds() {
        XCTAssertEqual(CoverBatch.kind(of: URL(fileURLWithPath: "/a/B.PDF")), .document)
        XCTAssertEqual(CoverBatch.kind(of: URL(fileURLWithPath: "/a/b.HEIC")), .picture)
        XCTAssertNil(CoverBatch.kind(of: URL(fileURLWithPath: "/a/b.docx")))
        XCTAssertNil(CoverBatch.kind(of: URL(fileURLWithPath: "/a/b")))
    }

    func testAFolderIsOpenedAllTheWayDown() {
        _ = make("Invoices/2026/b.pdf")
        _ = make("Invoices/a.pdf")
        _ = make("Invoices/photo.JPG")
        _ = make("Invoices/notes.docx")
        _ = make("Invoices/.hidden.pdf")
        let scan = CoverBatch.scan([root.appendingPathComponent("Invoices")])
        XCTAssertEqual(scan.items.map(\.relative), ["Invoices/2026/b.pdf", "Invoices/a.pdf", "Invoices/photo.JPG"])
        XCTAssertEqual(scan.items.map(\.kind), [.document, .document, .picture])
        XCTAssertEqual(scan.unsupported.map(\.lastPathComponent), ["notes.docx"])
    }

    func testAFileBroughtTwiceCountsOnce() {
        let file = make("one.pdf")
        let scan = CoverBatch.scan([file, file, root])
        XCTAssertEqual(scan.items.count, 1)
        XCTAssertEqual(scan.items.first?.relative, "one.pdf")
    }

    func testTheLimitHolds() {
        for n in 0..<5 { _ = make("Many/\(n).png") }
        XCTAssertEqual(CoverBatch.scan([root.appendingPathComponent("Many")], limit: 3).items.count, 3)
    }

    func testOutputsKeepFoldersAndNeverRepeat() {
        let items = [
            CoverBatch.Item(url: URL(fileURLWithPath: "/x/a.pdf"), relative: "a.pdf", kind: .document),
            CoverBatch.Item(url: URL(fileURLWithPath: "/y/a.pdf"), relative: "a.pdf", kind: .document),
            CoverBatch.Item(url: URL(fileURLWithPath: "/x/a.jpg"), relative: "A.jpg", kind: .picture),
            CoverBatch.Item(url: URL(fileURLWithPath: "/x/a.png"), relative: "a.png", kind: .picture),
            CoverBatch.Item(url: URL(fileURLWithPath: "/f/s/c.heic"), relative: "f/s/c.heic", kind: .picture),
        ]
        XCTAssertEqual(CoverBatch.outputs(for: items), ["a.pdf", "a 2.pdf", "A.png", "a 2.png", "f/s/c.png"])
    }

    func testFolderName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_792_397_700) // 2026-10-19 08:15 UTC
        XCTAssertEqual(CoverBatch.folderName(at: date, calendar: calendar, prefix: "Covered"), "Covered 2026-10-19 08.15")
    }

    func testRemaining() {
        XCTAssertNil(CoverBatch.remaining(done: 2, total: 10, elapsed: 4))
        XCTAssertEqual(CoverBatch.remaining(done: 4, total: 10, elapsed: 8), 12)
        XCTAssertNil(CoverBatch.remaining(done: 10, total: 10, elapsed: 8))
    }
}
