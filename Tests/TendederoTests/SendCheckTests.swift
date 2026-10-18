import Foundation
import XCTest
@testable import Tendedero

/// Check Before Sending: when the card shows first, and what a photo sent
/// before says.
final class SendCheckTests: XCTestCase {
    private let chatApps: Set<String> = ["net.whatsapp.WhatsApp", "com.apple.mail", "com.openai.chat"]
    private let chatSites = ["web.whatsapp.com", "mail.google.com", "chatgpt.com"]
    private let safari = "com.apple.Safari"

    private func reason(_ when: SendCheck.When, app: String, host: String? = nil,
                        inBrowser: Bool = false) -> SendCheck.Reason? {
        SendCheck.reason(when, app: app, host: host, inBrowser: inBrowser, chatApps: chatApps, chatSites: chatSites)
    }

    func testAIChatsAndUnknownPlacesGetTheCardAtFirst() {
        XCTAssertEqual(reason(.aiAndUnknown, app: "com.openai.chat"), .aiChat)
        XCTAssertEqual(reason(.aiAndUnknown, app: safari, host: "chatgpt.com", inBrowser: true), .aiChat)
        XCTAssertEqual(reason(.aiAndUnknown, app: "com.apple.TextEdit"), .unknownPlace)
        XCTAssertEqual(reason(.aiAndUnknown, app: safari, host: "example.com", inBrowser: true), .unknownPlace)
        // A browser whose page can't be read is no known chat either.
        XCTAssertEqual(reason(.aiAndUnknown, app: safari, inBrowser: true), .unknownPlace)
    }

    func testKnownChatsGoAtOnce() {
        XCTAssertNil(reason(.aiAndUnknown, app: "net.whatsapp.WhatsApp"))
        XCTAssertNil(reason(.aiAndUnknown, app: safari, host: "web.whatsapp.com", inBrowser: true))
        XCTAssertNil(reason(.aiAndUnknown, app: safari, host: "Mail.Google.com", inBrowser: true))
        XCTAssertNil(reason(.aiAndUnknown, app: safari, host: "www.web.whatsapp.com", inBrowser: true))
    }

    func testEveryTimeAndNever() {
        XCTAssertEqual(reason(.always, app: "net.whatsapp.WhatsApp"), .everySend)
        XCTAssertEqual(reason(.always, app: "com.openai.chat"), .aiChat)
        XCTAssertEqual(reason(.always, app: "com.apple.TextEdit"), .unknownPlace)
        XCTAssertNil(reason(.never, app: "com.openai.chat"))
        XCTAssertNil(reason(.never, app: "com.apple.TextEdit"))
    }

    func testTheChoiceIsKept() {
        let key = "checkBeforeSending"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(SendCheck.when, .never)
        SendCheck.when = .aiAndUnknown
        XCTAssertEqual(SendCheck.when, .aiAndUnknown)
        UserDefaults.standard.set("gone", forKey: key)
        XCTAssertEqual(SendCheck.when, .never)
    }

    @MainActor
    func testASendBeforeSaysWhereToAndWhen() {
        let sent = SendLog.Sent(date: Date(timeIntervalSince1970: 1_792_234_567), name: "Rechnung.png",
                                to: "WhatsApp", covered: [], message: nil)
        let english = Locale(identifier: "en_US")
        let sentence = SendLog.sentence(sent, locale: english)
        let format = DateFormatter()
        format.locale = english
        format.dateStyle = .medium
        format.timeStyle = .short
        format.doesRelativeDateFormatting = true
        XCTAssertEqual(sentence, String(format: L("Sent to %@ · %@"), "WhatsApp", format.string(from: sent.date)))
    }

    @MainActor
    func testASendKeptBeforePrintsWereReadsBackWithout() throws {
        let old = #"[{"id":"7A2E3B0C-7C5D-4B5D-9C2E-3F7B2A1D9E10","date":0,"name":"Shot.png","to":"WhatsApp","covered":[]}]"#
        let read = try JSONDecoder().decode([SendLog.Sent].self, from: Data(old.utf8))
        XCTAssertEqual(read.first?.name, "Shot.png")
        XCTAssertNil(read.first?.textPrint)
    }
}
