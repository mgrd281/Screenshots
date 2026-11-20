import XCTest
@testable import Tendedero

/// The AI chats beside the line's tag: those shown in Settings, AI ones
/// only, at most three, in their order, with room made for them only while
/// any shows.
final class LineTagAITests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var kept: [String: Any?] = [:]

    private var keys: [String] {
        ChatTarget.allCases.map { "aiChatOff.\($0.rawValue)" } + ["aiChatsOnPhotosOff", "chatOrder"]
    }

    override func setUp() {
        for key in keys { kept[key] = defaults.object(forKey: key) }
    }

    override func tearDown() {
        for (key, value) in kept {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    private func show(_ chats: Set<ChatTarget>) {
        for chat in ChatTarget.allCases { ChatTarget.setShows(chats.contains(chat), chat) }
    }

    func testOnlyTheAIChatsShownGoBesideTheTagInTheirOrder() {
        show([.claude, .chatGPT, .whatsApp])
        ChatTarget.setOrder([.whatsApp, .claude, .chatGPT])
        XCTAssertEqual(Layout.aiChats, [.claude, .chatGPT])
        XCTAssertEqual(Layout.aiRoom, Layout.tagWidth + Layout.aiGap)
    }

    func testAtMostThree() {
        show([.chatGPT, .claude, .perplexity, .grok, .deepSeek])
        XCTAssertEqual(Layout.aiChats.count, 3)
        XCTAssertTrue(Layout.aiChats.allSatisfy(\.isAI))
    }

    func testNoRoomIsMadeWhenNoneIsShown() {
        show([.whatsApp, .gmail])
        XCTAssertEqual(Layout.aiChats, [])
        XCTAssertEqual(Layout.aiRoom, 0)
    }
}
