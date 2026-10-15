import XCTest
@testable import Tendedero

/// The chat button finds its place over chats it knows from the page's
/// address: in the middle on a new chat, at the bottom once it has started.
final class ChatLayoutTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text)! }

    func testNewChatsByAddress() {
        XCTAssertTrue(ChatLayouts.isNewChat(url("https://chatgpt.com/")))
        XCTAssertTrue(ChatLayouts.isNewChat(url("https://chatgpt.com/?model=gpt-5")))
        XCTAssertFalse(ChatLayouts.isNewChat(url("https://chatgpt.com/c/68a1-22")))
        XCTAssertFalse(ChatLayouts.isNewChat(url("https://chatgpt.com/g/g-abc/c/68a1-22")))
        XCTAssertTrue(ChatLayouts.isNewChat(url("https://claude.ai/new")))
        XCTAssertFalse(ChatLayouts.isNewChat(url("https://claude.ai/chat/0f2c")))
        XCTAssertTrue(ChatLayouts.isNewChat(url("https://gemini.google.com/app")))
        XCTAssertFalse(ChatLayouts.isNewChat(url("https://gemini.google.com/app/5d1e")))
        XCTAssertTrue(ChatLayouts.isNewChat(url("https://www.perplexity.ai/")))
        XCTAssertFalse(ChatLayouts.isNewChat(url("https://www.perplexity.ai/search/abc")))
    }

    func testKnownSitesAndApps() {
        XCTAssertNotNil(ChatLayouts.layout(for: url("https://chatgpt.com/c/1")))
        XCTAssertNotNil(ChatLayouts.layout(for: url("https://www.claude.ai/new")))
        XCTAssertNotNil(ChatLayouts.layout(for: url("https://web.whatsapp.com/")))
        XCTAssertNil(ChatLayouts.layout(for: url("https://example.com/chat")))
        XCTAssertNotNil(ChatLayouts.layout(forApp: "net.whatsapp.WhatsApp"))
        XCTAssertNil(ChatLayouts.layout(forApp: "com.example.notes"))
    }

    /// The bug that started it: on ChatGPT's new chat page the button sat
    /// at the bottom, over the suggestions under the message box.
    func testNewChatSitsHigherThanAStartedOne() {
        let window = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let new = ChatLayouts.layout(for: url("https://chatgpt.com/"))!.corner(in: window)
        let started = ChatLayouts.layout(for: url("https://chatgpt.com/c/1"))!.corner(in: window)
        XCTAssertGreaterThan(new.y, window.height / 3)
        XCTAssertLessThan(started.y, 160)
        XCTAssertEqual(new.x, started.x)
    }

    func testCenteredBoxEndsWhereTheBoxEnds() {
        // Wide: a sidebar of 260 and a box of 768 centered in the rest.
        let wide = ChatLayout(across: .centered(width: 768, sidebar: 260), up: .bottom(100))
            .corner(in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(wide.x, 260 + (1180 + 768) / 2)
        XCTAssertEqual(wide.y, 100)
        // Narrow: no sidebar, and the box fills the window less its margins.
        let narrow = ChatLayout(across: .centered(width: 768, sidebar: 260), up: .bottom(100))
            .corner(in: CGRect(x: 100, y: 50, width: 700, height: 600))
        XCTAssertEqual(narrow.x, 100 + 700 - 16)
        XCTAssertEqual(narrow.y, 150)
    }

    func testTrailingAndMiddle() {
        let window = CGRect(x: 200, y: 100, width: 1000, height: 800)
        let corner = ChatLayout(across: .trailing(14), up: .middle(40), bar: 88).corner(in: window)
        XCTAssertEqual(corner.x, 1186)
        XCTAssertEqual(corner.y, 100 + (800 - 88) / 2 + 40)
    }
}
