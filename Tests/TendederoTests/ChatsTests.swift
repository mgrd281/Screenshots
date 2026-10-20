import XCTest
@testable import Tendedero

/// The apps a covered picture goes to, as the Mac and the iPhone share them:
/// which the iPhone offers, which it shows at first, the order and choice
/// made in Settings, and how a picture reaches each app on the iPhone.
final class ChatsTests: XCTestCase {
    /// Settings as on a new iPhone.
    private func fresh() -> UserDefaults {
        let name = "ChatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testTheIPhoneOffersEveryAppThatTakesAPicture() {
        XCTAssertEqual(ChatTarget.allCases.filter { !$0.onPhone }, [.airbnb, .vsCode, .antigravity])
        XCTAssertEqual(ChatTarget.phoneChoices(in: fresh()).count, ChatTarget.allCases.count - 3)
    }

    func testAtFirstTheIPhoneShowsTheSameSixAsTheMac() {
        XCTAssertEqual(ChatTarget.onPhoneNow(in: fresh()), [.chatGPT, .claude, .whatsApp, .gmail, .gmx, .webDe])
        XCTAssertEqual(ChatTarget.onPhoneNow(in: fresh()), ChatTarget.ordered(in: fresh()).filter(\.isStandard))
    }

    func testTheIPhoneKeepsTheChoiceAndOrderMadeInSettings() {
        let defaults = fresh()
        ChatTarget.setShows(true, .perplexity, in: defaults)
        ChatTarget.setShows(false, .gmx, in: defaults)
        // An editor turned on stays off the iPhone, which has no app for it.
        ChatTarget.setShows(true, .vsCode, in: defaults)
        ChatTarget.setOrder(ChatTarget.moving(.whatsApp, to: .chatGPT, in: ChatTarget.ordered(in: defaults)), in: defaults)
        XCTAssertEqual(ChatTarget.onPhoneNow(in: defaults), [.whatsApp, .chatGPT, .claude, .perplexity, .gmail, .webDe])
        XCTAssertEqual(ChatTarget.phoneChoices(in: defaults).first, .whatsApp)
    }

    func testWhatsAppTakesOnePictureItselfAndTheRestGoThroughTheShareSheet() {
        XCTAssertEqual(ChatTarget.whatsApp.phoneHandoff(pictures: 1), .direct)
        // Several pages: the share sheet, which takes them all.
        XCTAssertEqual(ChatTarget.whatsApp.phoneHandoff(pictures: 3), .shareSheet)
        XCTAssertEqual(ChatTarget.chatGPT.phoneHandoff(pictures: 3), .shareSheet)
        for chat in ChatTarget.allCases where chat.onPhone && chat != .whatsApp {
            // An AI chat opens at once, with the picture to paste.
            XCTAssertEqual(chat.phoneHandoff(pictures: 1), chat.isAI ? .openApp : .shareSheet, chat.name)
        }
    }

    /// An AI chat opens by its own address, then by its website's link,
    /// which the iPhone opens only as the app's: never a browser.
    func testAnAIChatOpensItsAppByItsOwnLinks() {
        for chat in ChatTarget.allCases where chat.isAI {
            let links = chat.phoneAppLinks
            XCTAssertEqual(links.last, chat.newChat, chat.name)
            XCTAssertTrue(links.dropLast().allSatisfy { $0.scheme != "https" && $0.scheme != "http" }, chat.name)
        }
        XCTAssertEqual(ChatTarget.chatGPT.phoneAppLinks.first?.scheme, "chatgpt")
        XCTAssertEqual(ChatTarget.claude.phoneAppLinks.first?.scheme, "claude")
    }
}
