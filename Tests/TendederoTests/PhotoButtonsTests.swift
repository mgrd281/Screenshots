import XCTest
@testable import Tendedero

/// The buttons on a photo under the pointer: where ChatGPT and Claude fit
/// beside the paper plane, the pick circle opposite the cross, and the
/// websites each chat answers on.
final class PhotoButtonsTests: XCTestCase {
    func testAWidePhotoHoldsTheChatsInARow() {
        // A screenshot of a wide window at the medium size.
        let card = CGSize(width: 144, height: 93)
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 2, leadingRoom: 0), .row)
        // The lock and the paper plane of a photo sent before still leave room.
        let badges = PhotoButtons.leadingRoom(badges: 2, document: false)
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 2, leadingRoom: badges), .row)
        XCTAssertEqual(PhotoButtons.plane(card: card), CGRect(x: 118, y: 67, width: 22, height: 22))
        XCTAssertEqual(PhotoButtons.chats(card: card, count: 2, arrangement: .row),
                       [CGRect(x: 66, y: 67, width: 22, height: 22), CGRect(x: 92, y: 67, width: 22, height: 22)])
    }

    func testANarrowPhotoStacksThemAboveThePlane() {
        // A phone screenshot at the medium size.
        let card = CGSize(width: 56, height: 112)
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 2, leadingRoom: 0), .column)
        let frames = PhotoButtons.chats(card: card, count: 2, arrangement: .column)
        XCTAssertEqual(frames, [CGRect(x: 30, y: 34, width: 22, height: 22), CGRect(x: 30, y: 60, width: 22, height: 22)])
        // Clear of the pick circle above them.
        XCTAssertLessThanOrEqual(PhotoButtons.pick(card: card).maxY + PhotoButtons.gap, frames[0].minY)
    }

    func testATinyPhotoLeavesThemToTheMenu() {
        // A phone screenshot at the small size.
        let card = CGSize(width: 46, height: 91)
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 2, leadingRoom: 0), .none)
        XCTAssertTrue(PhotoButtons.chats(card: card, count: 2, arrangement: .none).isEmpty)
        // One chat still fits above the plane.
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 1, leadingRoom: 0), .column)
    }

    func testWithoutChatsOnlyThePlaneShows() {
        let card = CGSize(width: 144, height: 93)
        XCTAssertEqual(PhotoButtons.arrangement(card: card, chats: 0, leadingRoom: 0), .none)
        XCTAssertTrue(PhotoButtons.chats(card: card, count: 0, arrangement: .row).isEmpty)
    }

    func testAPDFsCapsuleKeepsTheRowAway() {
        let room = PhotoButtons.leadingRoom(badges: 0, document: true)
        XCTAssertEqual(PhotoButtons.arrangement(card: CGSize(width: 144, height: 112), chats: 2, leadingRoom: room), .column)
        XCTAssertEqual(PhotoButtons.leadingRoom(badges: 0, document: false), 0)
    }

    func testThePickCircleSitsOppositeTheCross() {
        XCTAssertEqual(PhotoButtons.pick(card: CGSize(width: 144, height: 93)), CGRect(x: 121, y: 3, width: 20, height: 20))
    }

    func testEachChatKnowsItsWebsites() {
        XCTAssertTrue(AIChat.chatGPT.owns(host: "chatgpt.com"))
        XCTAssertTrue(AIChat.chatGPT.owns(host: "CHAT.openai.com"))
        XCTAssertTrue(AIChat.claude.owns(host: "claude.ai."))
        XCTAssertFalse(AIChat.claude.owns(host: "notclaude.ai"))
        XCTAssertFalse(AIChat.chatGPT.owns(host: nil))
        XCTAssertEqual(AIChat.claude.newChat.absoluteString, "https://claude.ai/new")
        for chat in AIChat.allCases {
            // A new chat opens where the website starts one.
            XCTAssertTrue(ChatLayouts.isNewChat(chat.newChat), chat.name)
            XCTAssertTrue(chat.owns(host: chat.newChat.host), chat.name)
            // Both are AI chats, so what goes there is covered as in one.
            XCTAssertTrue(CoveringProfile.isAIChat(app: chat.appID, host: nil), chat.name)
            XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: chat.hosts[0]), chat.name)
        }
    }

    func testTheChoiceIsKept() {
        let key = "aiChatsOnPhotosOff"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(AIChat.onPhotos)
        AIChat.onPhotos = false
        XCTAssertFalse(AIChat.onPhotos)
    }
}
