import XCTest
@testable import Tendedero

/// The buttons on a photo under the pointer: where the chats fit beside the
/// paper plane, the pick circle opposite the cross, and the websites each
/// answers on.
final class PhotoButtonsTests: XCTestCase {
    func testAWidePhotoHoldsTheChatsInARow() {
        // A screenshot of a wide window at the medium size.
        let card = CGSize(width: 144, height: 93)
        XCTAssertEqual(PhotoButtons.layout(card: card, chats: 2, leadingRoom: 0).arrangement, .row)
        // The lock and the paper plane of a photo sent before still leave room.
        let badges = PhotoButtons.leadingRoom(badges: 2, document: false)
        XCTAssertEqual(PhotoButtons.layout(card: card, chats: 2, leadingRoom: badges).arrangement, .row)
        XCTAssertEqual(PhotoButtons.plane(card: card), CGRect(x: 118, y: 67, width: 22, height: 22))
        XCTAssertEqual(PhotoButtons.chats(card: card, count: 2, arrangement: .row),
                       [CGRect(x: 66, y: 67, width: 22, height: 22), CGRect(x: 92, y: 67, width: 22, height: 22)])
    }

    func testANarrowPhotoStacksThemAboveThePlane() {
        // A phone screenshot at the medium size.
        let card = CGSize(width: 56, height: 112)
        XCTAssertEqual(PhotoButtons.layout(card: card, chats: 2, leadingRoom: 0).arrangement, .column)
        let frames = PhotoButtons.chats(card: card, count: 2, arrangement: .column)
        XCTAssertEqual(frames, [CGRect(x: 30, y: 34, width: 22, height: 22), CGRect(x: 30, y: 60, width: 22, height: 22)])
        // Clear of the pick circle above them.
        XCTAssertLessThanOrEqual(PhotoButtons.pick(card: card).maxY + PhotoButtons.gap, frames[0].minY)
    }

    func testATinyPhotoHoldsWhatFitsAndLeavesTheRestToTheMenu() {
        // A phone screenshot at the small size holds one above the plane.
        let card = CGSize(width: 46, height: 91)
        let two = PhotoButtons.layout(card: card, chats: 2, leadingRoom: 0)
        XCTAssertEqual(two.arrangement, .column)
        XCTAssertEqual(two.count, 1)
        XCTAssertEqual(PhotoButtons.chats(card: card, count: two.count, arrangement: two.arrangement).count, 1)
        XCTAssertEqual(PhotoButtons.layout(card: card, chats: 1, leadingRoom: 0).arrangement, .column)
        // Too small for even one.
        let none = PhotoButtons.layout(card: CGSize(width: 40, height: 50), chats: 3, leadingRoom: 0)
        XCTAssertEqual(none.arrangement, .none)
        XCTAssertEqual(none.count, 0)
    }

    func testFourChatsAreCutShortRatherThanDroppedAll() {
        // A medium screenshot with its lock holds three of four across.
        let card = CGSize(width: 144, height: 93)
        let lock = PhotoButtons.leadingRoom(badges: 1, document: false)
        let fit = PhotoButtons.layout(card: card, chats: 4, leadingRoom: lock)
        XCTAssertEqual(fit.arrangement, .row)
        XCTAssertEqual(fit.count, 3)
        // A wider card holds all four.
        XCTAssertEqual(PhotoButtons.layout(card: CGSize(width: 200, height: 120), chats: 4, leadingRoom: lock).count, 4)
    }

    func testWithoutChatsOnlyThePlaneShows() {
        let card = CGSize(width: 144, height: 93)
        XCTAssertEqual(PhotoButtons.layout(card: card, chats: 0, leadingRoom: 0).arrangement, .none)
        XCTAssertTrue(PhotoButtons.chats(card: card, count: 0, arrangement: .row).isEmpty)
    }

    func testAPDFsCapsuleKeepsTheRowAway() {
        let room = PhotoButtons.leadingRoom(badges: 0, document: true)
        XCTAssertEqual(PhotoButtons.layout(card: CGSize(width: 144, height: 112), chats: 2, leadingRoom: room).arrangement, .column)
        XCTAssertEqual(PhotoButtons.leadingRoom(badges: 0, document: false), 0)
    }

    func testThePickCircleSitsOppositeTheCross() {
        XCTAssertEqual(PhotoButtons.pick(card: CGSize(width: 144, height: 93)), CGRect(x: 121, y: 3, width: 20, height: 20))
    }

    func testEachChatKnowsItsWebsites() {
        XCTAssertTrue(ChatTarget.chatGPT.owns(host: "chatgpt.com"))
        XCTAssertTrue(ChatTarget.chatGPT.owns(host: "CHAT.openai.com"))
        XCTAssertTrue(ChatTarget.claude.owns(host: "claude.ai."))
        XCTAssertFalse(ChatTarget.claude.owns(host: "notclaude.ai"))
        XCTAssertFalse(ChatTarget.chatGPT.owns(host: nil))
        XCTAssertEqual(ChatTarget.claude.newChat.absoluteString, "https://claude.ai/new")
        XCTAssertTrue(ChatTarget.whatsApp.owns(host: "web.whatsapp.com"))
        XCTAssertTrue(ChatTarget.gmail.owns(host: "mail.google.com"))
        XCTAssertFalse(ChatTarget.gmail.owns(host: "google.com"))
        for chat in ChatTarget.allCases {
            XCTAssertTrue(chat.owns(host: chat.newChat.host), chat.name)
            XCTAssertEqual(chat.isAI, ["ChatGPT", "Claude"].contains(chat.name), chat.name)
            if chat.isAI {
                // A new chat opens where the website starts one, and what goes
                // there is covered as in an AI chat.
                XCTAssertTrue(ChatLayouts.isNewChat(chat.newChat), chat.name)
                XCTAssertTrue(CoveringProfile.isAIChat(app: chat.appID, host: nil), chat.name)
                XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: chat.hosts[0]), chat.name)
            } else {
                XCTAssertFalse(CoveringProfile.isAIChat(app: chat.appID, host: chat.hosts[0]), chat.name)
            }
        }
        // WhatsApp's app goes by two IDs; Gmail has none of its own.
        XCTAssertEqual(ChatTarget.whatsApp.appIDs.count, 2)
        XCTAssertNil(ChatTarget.gmail.appID)
        XCTAssertTrue(ChatTarget.gmail.startsFresh)
        XCTAssertFalse(ChatTarget.claude.startsFresh)
    }

    func testEachIconIsTurnedOffOnItsOwn() throws {
        let suite = "PhotoButtonsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for chat in ChatTarget.allCases { XCTAssertTrue(ChatTarget.shows(chat, in: defaults), "on at first: \(chat.name)") }
        XCTAssertEqual(ChatTarget.allCases.count, 4)
        ChatTarget.setShows(false, .claude, in: defaults)
        XCTAssertFalse(ChatTarget.shows(.claude, in: defaults))
        XCTAssertTrue(ChatTarget.shows(.chatGPT, in: defaults), "the other stays")
        ChatTarget.setShows(true, .claude, in: defaults)
        XCTAssertTrue(ChatTarget.shows(.claude, in: defaults))
    }

    func testTheSingleSwitchOfBeforeKeepsTheAIChatsOffUntilChosenAgain() throws {
        let suite = "PhotoButtonsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "aiChatsOnPhotosOff")
        XCTAssertFalse(ChatTarget.shows(.chatGPT, in: defaults))
        XCTAssertFalse(ChatTarget.shows(.claude, in: defaults))
        // WhatsApp and Gmail came after it, and are on.
        XCTAssertTrue(ChatTarget.shows(.whatsApp, in: defaults))
        XCTAssertTrue(ChatTarget.shows(.gmail, in: defaults))
        ChatTarget.setShows(true, .chatGPT, in: defaults)
        XCTAssertTrue(ChatTarget.shows(.chatGPT, in: defaults))
        XCTAssertFalse(ChatTarget.shows(.claude, in: defaults))
    }

    func testChatsOpenInTheBrowserUntilTheAppIsChosen() {
        let key = "aiChatsOpenInApp"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(ChatTarget.opensInApp)
        ChatTarget.opensInApp = true
        XCTAssertTrue(ChatTarget.opensInApp)
        // The marks differ, and are plain letters.
        XCTAssertEqual(Set(ChatTarget.allCases.map(\.mark)).count, ChatTarget.allCases.count)
    }
}
