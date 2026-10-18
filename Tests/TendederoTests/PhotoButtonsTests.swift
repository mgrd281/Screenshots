import XCTest
@testable import Tendedero

/// The buttons on a photo under the pointer: the chats' icons in a row under
/// the card, the paper plane and the pick circle on it, and the websites each
/// chat answers on.
final class PhotoButtonsTests: XCTestCase {
    func testTheChatsStandInARowInTheMiddleUnderTheCard() {
        // A screenshot of a wide window at the medium size.
        let card = CGSize(width: 144, height: 93)
        let row = PhotoButtons.chats(card: card, count: 4)
        XCTAssertEqual(row.count, 4)
        XCTAssertEqual(row, [CGRect(x: 26, y: 99, width: 20, height: 20), CGRect(x: 50, y: 99, width: 20, height: 20),
                             CGRect(x: 74, y: 99, width: 20, height: 20), CGRect(x: 98, y: 99, width: 20, height: 20)])
        // Centered, and under the card, never on it.
        XCTAssertEqual(row[0].minX, card.width - row[3].maxX)
        XCTAssertTrue(row.allSatisfy { $0.minY > card.height })
        // The room below the card holds the row and a gap each side of it.
        XCTAssertEqual(PhotoButtons.stripHeight, 30)
        XCTAssertLessThanOrEqual(row[0].maxY, card.height + PhotoButtons.stripHeight)
    }

    func testANarrowPhotoStillHasItsRowCentered() {
        // A phone screenshot: the row is wider than the card, evenly on both sides.
        let card = CGSize(width: 56, height: 112)
        let row = PhotoButtons.chats(card: card, count: 4)
        XCTAssertEqual(row[0].minX, card.width - row[3].maxX)
        XCTAssertLessThan(row[0].minX, 0)
        // One chat sits right in the middle.
        XCTAssertEqual(PhotoButtons.chats(card: card, count: 1), [CGRect(x: 18, y: 118, width: 20, height: 20)])
    }

    func testWithoutChatsThereIsNoRow() {
        XCTAssertTrue(PhotoButtons.chats(card: CGSize(width: 144, height: 93), count: 0).isEmpty)
    }

    func testThePaperPlaneStaysInTheCornerOfTheCard() {
        XCTAssertEqual(PhotoButtons.plane(card: CGSize(width: 144, height: 93)), CGRect(x: 118, y: 67, width: 22, height: 22))
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
