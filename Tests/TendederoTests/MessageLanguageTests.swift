import Foundation
import XCTest
@testable import Tendedero

/// The language a message goes in: kept for each chat, and translated only
/// when it is written in another.
final class MessageLanguageTests: XCTestCase {
    func testTheLanguageIsKeptForEachChat() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MessageLanguageTests-\(UUID().uuidString)"))
        XCTAssertNil(MessageLanguage.language(for: "WhatsApp", in: defaults))
        MessageLanguage.remember("de", for: "WhatsApp", in: defaults)
        MessageLanguage.remember("en", for: "chatgpt.com", in: defaults)
        XCTAssertEqual(MessageLanguage.language(for: "WhatsApp", in: defaults), "de")
        XCTAssertEqual(MessageLanguage.language(for: "chatgpt.com", in: defaults), "en")
        // As typed again.
        MessageLanguage.remember(nil, for: "WhatsApp", in: defaults)
        XCTAssertNil(MessageLanguage.language(for: "WhatsApp", in: defaults))
        XCTAssertEqual(MessageLanguage.language(for: "chatgpt.com", in: defaults), "en")
        // Without a chat in front there is nothing to keep.
        MessageLanguage.remember("fr", for: nil, in: defaults)
        XCTAssertNil(MessageLanguage.language(for: nil, in: defaults))
    }

    func testOnlyAMessageInAnotherLanguageIsTranslated() {
        let german = Locale.Language(identifier: "de")
        let arabic = MessageLanguage.source(of: "شكراً لطلبك، سنرسله إليك اليوم مع رقم التتبع.", into: german)
        XCTAssertEqual(arabic?.languageCode?.identifier, "ar")
        XCTAssertNil(MessageLanguage.source(of: "Vielen Dank für deine Bestellung, sie geht heute raus.", into: german))
        // Numbers alone go as they are.
        XCTAssertNil(MessageLanguage.source(of: "1024 · 74,00 €", into: german))
        XCTAssertNil(MessageLanguage.source(of: "", into: german))
    }

    func testTheCodeOnTheBar() {
        XCTAssertEqual(MessageLanguage.code(Locale.Language(identifier: "de")), "DE")
        XCTAssertEqual(MessageLanguage.code(Locale.Language(identifier: "pt-BR")), "PT")
        XCTAssertEqual(MessageLanguage.code(Locale.Language(identifier: "zh-Hans")), "ZH")
    }
}
