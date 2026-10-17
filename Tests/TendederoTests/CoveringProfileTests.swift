import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// Cover Everything in AI Chats: which chats count, and that it only ever
/// covers more than Settings.
final class CoveringProfileTests: XCTestCase {
    func testAIChatAppsAndSitesAreKnown() {
        XCTAssertTrue(CoveringProfile.isAIChat(app: "com.openai.chat", host: nil))
        XCTAssertTrue(CoveringProfile.isAIChat(app: "com.anthropic.claudefordesktop", host: nil))
        XCTAssertTrue(CoveringProfile.isAIChat(app: "ai.perplexity.mac", host: nil))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "chatgpt.com"))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "www.chatgpt.com"))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "Claude.AI"))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "gemini.google.com"))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "www.perplexity.ai"))
        XCTAssertTrue(CoveringProfile.isAIChat(app: nil, host: "claude.ai."))
    }

    func testOtherChatsAreNot() {
        XCTAssertFalse(CoveringProfile.isAIChat(app: "net.whatsapp.WhatsApp", host: nil))
        XCTAssertFalse(CoveringProfile.isAIChat(app: "com.apple.Safari", host: "web.whatsapp.com"))
        XCTAssertFalse(CoveringProfile.isAIChat(app: nil, host: "mail.google.com"))
        XCTAssertFalse(CoveringProfile.isAIChat(app: nil, host: "google.com"))
        // A name that only looks like one is not the website.
        XCTAssertFalse(CoveringProfile.isAIChat(app: nil, host: "notchatgpt.com"))
        XCTAssertFalse(CoveringProfile.isAIChat(app: nil, host: "chatgpt.com.example.net"))
        XCTAssertFalse(CoveringProfile.isAIChat(app: nil, host: nil))
    }

    /// The send button shows over every AI chat from the start, so its lock
    /// can say so there.
    @MainActor
    func testTheSendButtonKnowsEveryAIChat() {
        let apps = Set(ChatButton.standardApps.map(\.bundleID))
        XCTAssertTrue(CoveringProfile.aiApps.isSubset(of: apps))
        let sites = ChatButton.standardSites.map(\.host)
        for site in CoveringProfile.aiSites where site != "chat.openai.com" {
            XCTAssertTrue(sites.contains(site), site)
        }
    }

    func testItOnlyEverCoversMore() {
        let chosen: Set<PrivateDetail> = [.names, .emails]
        let everything = Set(PrivateDetail.allCases)
        XCTAssertEqual(CoveringProfile.everything, everything)
        XCTAssertEqual(CoveringProfile.details(chosen, inAIChat: false, coversAll: true), chosen)
        XCTAssertEqual(CoveringProfile.details(chosen, inAIChat: true, coversAll: false), chosen)
        XCTAssertEqual(CoveringProfile.details(chosen, inAIChat: true, coversAll: true), everything)
        XCTAssertEqual(CoveringProfile.details([], inAIChat: true, coversAll: true), everything)
        let choices: [Set<PrivateDetail>] = [[], PrivateDetail.recommended, chosen, everything]
        for checked in choices {
            for inAIChat in [false, true] {
                for coversAll in [false, true] {
                    let covered = CoveringProfile.details(checked, inAIChat: inAIChat, coversAll: coversAll)
                    XCTAssertTrue(covered.isSuperset(of: checked))
                }
            }
        }
    }

    /// A receipt sent into an AI chat: the total and the date, which the
    /// recommended kinds leave, are covered too.
    func testEverythingCoversWhatTheRecommendedLeave() throws {
        let url = try receipt(["Gesamt 74,00 €", "Datum 17.10.2026", "lena.hoffmann@example.com"])
        let recommended = try XCTUnwrap(Cover.covering(url, PrivateDetail.recommended))
        let everything = try XCTUnwrap(Cover.covering(url, CoveringProfile.everything))
        XCTAssertNotNil(recommended.report.kinds[.emails])
        XCTAssertNil(recommended.report.kinds[.amounts])
        XCTAssertNil(recommended.report.kinds[.dates])
        XCTAssertNotNil(everything.report.kinds[.emails])
        XCTAssertNotNil(everything.report.kinds[.amounts], "\(everything.report.kinds)")
        XCTAssertNotNil(everything.report.kinds[.dates], "\(everything.report.kinds)")
        XCTAssertGreaterThan(everything.report.total, recommended.report.total)
    }

    // MARK: Helpers

    /// Lines of large black text on white, saved as a PNG.
    private func receipt(_ lines: [String]) throws -> URL {
        let width = 1400, height = 120 * lines.count + 80
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 100 - 120 * i))
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Receipt.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
