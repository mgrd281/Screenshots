import XCTest
@testable import Tendedero

/// Capture and Ask AI: the chats offered and the one chosen first, and the
/// question that goes, kept or typed.
@MainActor
final class AskPanelTests: XCTestCase {
    func testTheChatsAreTheAIOnesShownInTheirOrder() {
        let order: [ChatTarget] = [.whatsApp, .claude, .gmail, .chatGPT, .perplexity]
        XCTAssertEqual(AskPanel.chats(shown: { $0 != .perplexity }, order: order), [.claude, .chatGPT])
        // None shown under photos: every AI chat, so there is one to ask.
        XCTAssertEqual(AskPanel.chats(shown: { _ in false }, order: order), [.claude, .chatGPT, .perplexity])
    }

    func testTheChatAskedLastComesFirst() {
        let chats: [ChatTarget] = [.chatGPT, .claude]
        XCTAssertEqual(AskPanel.preferredChat(among: chats, last: "claude", captureChat: .chatGPT), .claude)
        XCTAssertEqual(AskPanel.preferredChat(among: chats, last: nil, captureChat: .claude), .claude)
        XCTAssertEqual(AskPanel.preferredChat(among: chats, last: "grok", captureChat: .perplexity), .chatGPT)
        XCTAssertNil(AskPanel.preferredChat(among: [], last: nil, captureChat: nil))
    }

    func testAKeptQuestionGoesByItsNumberAndReturnSendsWhatIsTyped() {
        let model = AskModel(chats: [.claude], chat: .claude, questions: ["One?", "Two?"], thumb: nil)
        var asked: [String?] = []
        model.ask = { asked.append($0) }
        model.askKept(2)
        model.askKept(5)
        model.typed = "  "
        model.askTyped()
        model.typed = " Why is this red? "
        model.askTyped()
        XCTAssertEqual(asked, ["Two?", nil, "Why is this red?"])
    }

    func testItHasAShortcutOfItsOwn() {
        XCTAssertEqual(Shortcut.Role.ask.standard.display, "⌃⌥A")
        XCTAssertTrue(ShortcutTap.roles.contains(.ask))
    }
}
