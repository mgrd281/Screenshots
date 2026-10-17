import Foundation
import XCTest
@testable import Tendedero

/// Writing for help from Settings › Support: the mail link and the details
/// that go with it.
final class SupportTests: XCTestCase {
    func testTheMailLinkCarriesTheSubjectAndTheBody() throws {
        let url = try XCTUnwrap(Support.mail(to: "help@example.com", subject: "Snapfly: Report a Problem",
                                             body: "Line one\nLine two"))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:help@example.com?"), url.absoluteString)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["subject"], "Snapfly: Report a Problem")
        XCTAssertEqual(items["body"], "Line one\nLine two")
        // A new line travels encoded, never raw.
        XCTAssertFalse(url.absoluteString.contains("\n"))
    }

    func testTheDetailsNameTheAppTheMacAndThePermissions() {
        let text = Support.details(version: "1.0.0", build: "135", appStore: true, system: "macOS Version 26.0.1 (Build 25A362)",
                                   model: "Mac16,1 · Apple silicon", language: "de_DE",
                                   permissions: [("Screen Recording", "Allowed"), ("Accessibility", "Not asked yet")])
        XCTAssertEqual(text, """
        Snapfly 1.0.0 (135) · App Store
        macOS Version 26.0.1 (Build 25A362) · Mac16,1 · Apple silicon
        de_DE
        Screen Recording: Allowed
        Accessibility: Not asked yet
        """)
        let direct = Support.details(version: "1.0.0", build: "135", appStore: false, system: "macOS 26",
                                     model: "Mac16,1 · Apple silicon", language: "en", permissions: [])
        XCTAssertTrue(direct.hasPrefix("Snapfly 1.0.0 (135)\n"))
        XCTAssertFalse(direct.contains("App Store"))
    }

    func testTheMacNamesItself() {
        XCTAssertFalse(Support.model.isEmpty)
        XCTAssertTrue(Support.model.contains("Apple silicon") || Support.model.contains("Intel"))
    }
}
