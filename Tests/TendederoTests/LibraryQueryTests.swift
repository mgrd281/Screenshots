import Foundation
import XCTest
@testable import Tendedero

/// Finding screenshots in the iPhone's library by what they say, what they
/// hold and when they were taken.
final class LibraryQueryTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private lazy var items: [LibraryQuery.Item] = [
        .init(id: "order", created: Date(timeIntervalSince1970: 3 * day), text: "Bestellung Nr. 5166 Microsoft Office",
              kinds: ["orders", "names"], protected: true),
        .init(id: "chat", created: Date(timeIntervalSince1970: 5 * day), text: "Hallo Zoë, danke für Ihre Hilfe"),
        .init(id: "unread", created: Date(timeIntervalSince1970: 4 * day), text: nil),
        .init(id: "undated", created: nil, text: "Rechnung 2026", kinds: ["amounts"]),
    ]

    func testEveryWordSearchedForMustBeSaid() {
        var query = LibraryQuery(search: "bestellung office")
        XCTAssertEqual(query.apply(items).map(\.id), ["order"])
        // Case and accents do not matter.
        query.search = "ZOE FUR"
        XCTAssertEqual(query.apply(items).map(\.id), ["chat"])
        query.search = "office hilfe"
        XCTAssertTrue(query.apply(items).isEmpty)
    }

    func testAScreenshotNotReadYetIsFoundOnlyWithoutWords() {
        XCTAssertTrue(LibraryQuery(search: "x").apply(items).allSatisfy { $0.text != nil })
        XCTAssertTrue(LibraryQuery().apply(items).contains { $0.id == "unread" })
        XCTAssertFalse(LibraryQuery().narrows)
        XCTAssertTrue(LibraryQuery(search: "  ").words.isEmpty, "spaces alone search for nothing")
    }

    func testFilters() {
        XCTAssertEqual(LibraryQuery(filter: .privateDetails).apply(items).map(\.id), ["order", "undated"])
        XCTAssertEqual(LibraryQuery(filter: .protected).apply(items).map(\.id), ["order"])
        XCTAssertEqual(LibraryQuery(filter: .unprotected).apply(items).map(\.id), ["chat", "unread", "undated"])
        XCTAssertTrue(LibraryQuery(filter: .protected).narrows)
    }

    func testNewestOrOldestFirstWithTheUndatedLast() {
        XCTAssertEqual(LibraryQuery().apply(items).map(\.id), ["chat", "unread", "order", "undated"])
        XCTAssertEqual(LibraryQuery(order: .oldest).apply(items).map(\.id), ["order", "unread", "chat", "undated"])
    }
}
