import XCTest
@testable import Tendedero

/// Websites typed in Settings, the kinds of files on the line, the words
/// search compares, and the shortcuts' defaults.
final class ChatAndFilesTests: XCTestCase {
    @MainActor
    func testHostFromWhatIsTyped() {
        XCTAssertEqual(ChatButton.host(from: "https://www.chatgpt.com/c/123"), "chatgpt.com")
        XCTAssertEqual(ChatButton.host(from: "claude.ai"), "claude.ai")
        XCTAssertEqual(ChatButton.host(from: "  Web.WhatsApp.com  "), "web.whatsapp.com")
        XCTAssertNil(ChatButton.host(from: "not a site"))
        XCTAssertNil(ChatButton.host(from: ""))
    }

    func testKindsOfFiles() {
        let movie = URL(fileURLWithPath: "/tmp/Snapfly 1.mov")
        let pdf = URL(fileURLWithPath: "/tmp/Order.pdf")
        let gif = URL(fileURLWithPath: "/tmp/Snapfly 1.gif")
        let png = URL(fileURLWithPath: "/tmp/Snapfly 1.PNG")
        XCTAssertTrue(isRecording(movie))
        XCTAssertTrue(isRecording(URL(fileURLWithPath: "/tmp/a.MP4")))
        XCTAssertTrue(isDocument(pdf))
        XCTAssertTrue(isImage(gif))
        XCTAssertTrue(isImage(png))
        XCTAssertFalse(isImage(movie))
        XCTAssertFalse(isImage(pdf))
    }

    func testFoldIgnoresCaseAndAccents() {
        XCTAssertEqual(TextIndex.fold("Café RECHNUNG"), TextIndex.fold("cafe rechnung"))
    }

    func testShortcutDefaultsDiffer() {
        let keys = Shortcut.Role.allCases.map(\.standard.keyCode)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
