import XCTest
@testable import Tendedero

/// The apps a covered picture goes to, as the Mac and the iPhone share them:
/// which the iPhone offers, which it shows at first, the order and choice
/// made in Settings, and where a tap on the iPhone goes.
final class ChatsTests: XCTestCase {
    /// Settings as on a new iPhone.
    private func fresh() -> UserDefaults {
        let name = "ChatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testTheIPhoneOffersEveryAppButTheEditors() {
        XCTAssertEqual(ChatTarget.allCases.filter { !$0.onPhone }, [.vsCode, .antigravity])
        XCTAssertEqual(ChatTarget.phoneChoices(in: fresh()).count, ChatTarget.allCases.count - 2)
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

    func testATapTriesTheAppThenItsWebsite() {
        XCTAssertEqual(ChatTarget.whatsApp.phoneLinks.map(\.absoluteString), ["whatsapp://app", "https://web.whatsapp.com/"])
        XCTAssertEqual(ChatTarget.gmail.phoneLinks.first?.scheme, "googlegmail")
        // An AI chat's website opens its app when the app claims it.
        XCTAssertEqual(ChatTarget.claude.phoneLinks, [URL(string: "https://claude.ai/new")!])
        for chat in ChatTarget.allCases where chat.onPhone {
            // The website is always there, last.
            XCTAssertEqual(chat.phoneLinks.last, chat.newChat, chat.name)
            XCTAssertTrue(chat.owns(host: chat.phoneLinks.last?.host), chat.name)
            // Before it, only an app's own address.
            XCTAssertTrue(chat.phoneLinks.dropLast().allSatisfy { !["http", "https"].contains($0.scheme) }, chat.name)
        }
    }
}
