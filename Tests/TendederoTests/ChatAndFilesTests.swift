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

    @MainActor
    func testMailAppsAndWebmailAreKnown() {
        let apps = ChatButton.standardApps.map(\.bundleID)
        XCTAssertTrue(apps.contains("com.apple.mail"))
        XCTAssertTrue(apps.contains("com.microsoft.Outlook"))
        let sites = ChatButton.standardSites.map(\.host)
        for host in ["mail.google.com", "outlook.live.com", "mail.yahoo.com", "email.t-online.de", "web.de", "gmx.net"] {
            XCTAssertTrue(sites.contains(host), host)
        }
        XCTAssertEqual(Set(sites).count, sites.count, "no website twice")
        XCTAssertEqual(Set(apps).count, apps.count, "no app twice")
    }

    /// A list saved before mail joined gets the new entries once, at the end;
    /// one removed after it was offered stays removed, and nothing doubles.
    @MainActor
    func testNewStandardEntriesJoinASavedListOnce() {
        let standard = ["a", "b", "mail"]
        let first = ChatButton.joining(standard, to: ["b", "mine"], offered: ["a", "b"], id: { $0 })
        XCTAssertEqual(first.list, ["b", "mine", "mail"])
        XCTAssertEqual(first.offered, ["a", "b", "mail"])
        // Mail removed afterwards: it does not come back.
        let again = ChatButton.joining(standard, to: ["b", "mine"], offered: first.offered, id: { $0 })
        XCTAssertEqual(again.list, ["b", "mine"])
        // Already there: not added twice.
        XCTAssertEqual(ChatButton.joining(standard, to: ["mail"], offered: [], id: { $0 }).list, ["mail", "a", "b"])
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
