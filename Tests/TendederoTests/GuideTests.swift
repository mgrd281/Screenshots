import AppKit
import SwiftUI
import XCTest
@testable import Tendedero

/// The introduction: its steps in order, skipping what is not there; where
/// it was ended, kept to go on from; the card placed beside what it points
/// at, never off the screen; and words that name the real shortcuts.
final class GuideTests: XCTestCase {
    private let ids = ["menuBar", "screenshot", "photo", "covered", "chats", "menu", "tag"]

    func testStepsSkipWhatIsNotThere() {
        // Nothing covered: the lock's step is left out, both ways.
        let shows: (String) -> Bool = { $0 != "covered" }
        XCTAssertEqual(GuideFlow.step(after: nil, in: ids, shows: shows), "menuBar")
        XCTAssertEqual(GuideFlow.step(after: "photo", in: ids, shows: shows), "chats")
        XCTAssertEqual(GuideFlow.step(before: "chats", in: ids, shows: shows), "photo")
        XCTAssertNil(GuideFlow.step(after: "tag", in: ids, shows: shows))
        XCTAssertNil(GuideFlow.step(before: "menuBar", in: ids, shows: shows))
        // It counts only the steps that show.
        XCTAssertEqual(GuideFlow.place(of: "chats", in: ids, shows: shows)?.number, 4)
        XCTAssertEqual(GuideFlow.place(of: "chats", in: ids, shows: shows)?.count, 6)
        XCTAssertNil(GuideFlow.place(of: "nowhere", in: ids, shows: shows))
    }

    func testItGoesOnFromWhereItWasEnded() {
        let all: (String) -> Bool = { _ in true }
        XCTAssertEqual(GuideFlow.resume(from: "menu", in: ids, shows: all), "menu")
        XCTAssertEqual(GuideFlow.resume(from: nil, in: ids, shows: all), "menuBar")
        XCTAssertEqual(GuideFlow.resume(from: "gone", in: ids, shows: all), "menuBar")
        // Ended at the lock, and nothing is covered now: the step after it.
        XCTAssertEqual(GuideFlow.resume(from: "covered", in: ids, shows: { $0 != "covered" }), "chats")
    }

    func testProgressIsKeptAndOfferedOncePerVersion() throws {
        let suite = "GuideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var progress = GuideProgress.load(from: defaults)
        XCTAssertTrue(progress.offers(version: 1))
        XCTAssertFalse(progress.canContinue)
        progress.version = 1
        progress.see("menuBar")
        progress.see("menuBar")
        progress.stoppedAt = "photo"
        progress.save(to: defaults)

        var loaded = GuideProgress.load(from: defaults)
        XCTAssertEqual(loaded, progress)
        XCTAssertEqual(loaded.seen, ["menuBar"])
        XCTAssertFalse(loaded.offers(version: 1))
        // A newer introduction is offered once more.
        XCTAssertTrue(loaded.offers(version: 2))
        XCTAssertTrue(loaded.canContinue)

        loaded.finished = true
        loaded.stoppedAt = nil
        XCTAssertFalse(loaded.canContinue)
        // Started again, what was seen stays seen.
        loaded.restart()
        XCTAssertFalse(loaded.finished)
        XCTAssertEqual(loaded.seen, ["menuBar"])
    }

    func testTheCardSitsBesideWhatItPointsAtAndOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let card = CGSize(width: 340, height: 150)

        // A photo near the top: the card below it, the arrow under its middle.
        let photo = CGRect(x: 600, y: 40, width: 158, height: 120)
        let below = GuidePlacement.place(card, at: photo, in: screen, gap: 14, margin: 12)
        XCTAssertEqual(below.side, .below)
        XCTAssertEqual(below.frame.minY, photo.maxY + 14)
        XCTAssertEqual(below.frame.minX + below.arrow, photo.midX, accuracy: 0.001)

        // Near the bottom: above it.
        let low = CGRect(x: 600, y: 800, width: 158, height: 60)
        let above = GuidePlacement.place(card, at: low, in: screen, gap: 14, margin: 12)
        XCTAssertEqual(above.side, .above)
        XCTAssertEqual(above.frame.maxY, low.minY - 14)

        // The menu bar icon at the far right: kept on the screen, the arrow
        // moved along the edge to still point at it, short of the corner.
        let icon = CGRect(x: 1400, y: 0, width: 28, height: 24)
        let edge = GuidePlacement.place(card, at: icon, in: screen, gap: 14, margin: 12)
        XCTAssertEqual(edge.frame.maxX, screen.maxX - 12)
        XCTAssertLessThanOrEqual(edge.arrow, card.width - GuidePlacement.arrowInset)
        XCTAssertGreaterThan(edge.arrow, card.width / 2)

        // As tall as the screen: beside it.
        let tall = CGRect(x: 100, y: 0, width: 200, height: 875)
        XCTAssertEqual(GuidePlacement.place(card, at: tall, in: screen, gap: 14, margin: 12).side, .right)

        // Pointing at nothing: across the middle, this far down.
        let free = GuidePlacement.place(card, at: nil, in: screen, gap: 14, margin: 12, top: 200)
        XCTAssertEqual(free.side, .none)
        XCTAssertEqual(free.frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(free.frame.minY, 212)
        for placed in [below, above, edge, free] {
            XCTAssertTrue(screen.insetBy(dx: 12, dy: 12).contains(placed.frame), "\(placed)")
        }
    }

    func testTheHoleFollowsTheCornersOfWhatItShows() {
        let hole = GuidePlacement.hole(around: CGRect(x: 10, y: 10, width: 100, height: 20), room: 6, corner: 16)
        XCTAssertEqual(hole.rect, CGRect(x: 4, y: 4, width: 112, height: 32))
        // Never rounder than a capsule.
        XCTAssertEqual(hole.corner, 16)
        XCTAssertEqual(GuidePlacement.hole(around: CGRect(x: 0, y: 0, width: 80, height: 80), room: 6, corner: 16).corner, 22)
    }

    func testTheStepsNameTheRealShortcutsAndSymbols() {
        let steps = GuideStep.introduction(capture: "⌃⌥S", appStore: false)
        XCTAssertEqual(steps.map(\.id), ids)
        for step in steps {
            XCTAssertNotNil(NSImage(systemSymbolName: step.symbol, accessibilityDescription: nil), step.symbol)
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.text.contains("%@"), step.text)
        }
        let screenshot = steps[1]
        XCTAssertTrue(screenshot.text.contains("⇧⌘4") && screenshot.text.contains("⌃⌥S"), screenshot.text)
        XCTAssertFalse(screenshot.dims, "the picture stays as it is")
        XCTAssertEqual(screenshot.action?.kind, .takeScreenshot)
        // The App Store edition sees only its own screenshots.
        let store = GuideStep.introduction(capture: "⌃⌥S", appStore: true)[1].text
        XCTAssertFalse(store.contains("⇧⌘4"), store)
        XCTAssertTrue(store.contains("⌃⌥S"), store)
        let none = GuideStep.introduction(capture: nil, appStore: true)[1].text
        XCTAssertTrue(none.contains(L("Take Screenshot")), none)
        // Each step waits for the real thing, or for Next.
        XCTAssertTrue(steps[0].waits)
        XCTAssertFalse(steps[6].waits)
    }

    func testLessonsAndTipsNameStepsThatExist() {
        let steps = Set(ids)
        for lesson in GuideLesson.allCases {
            XCTAssertFalse(lesson.title.isEmpty)
            XCTAssertTrue(Set(lesson.steps).isSubset(of: steps), lesson.rawValue)
        }
        for tip in GuideTip.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: tip.symbol, accessibilityDescription: nil), tip.symbol)
            if let step = tip.taughtBy { XCTAssertTrue(steps.contains(step), step) }
        }
    }

    func testTheArrowReachesOutOfTheCardTowardsWhatItPointsAt() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 150)
        // The tip is rounded, so it ends a little short of its full length.
        let up = GuideCardShape(side: .below, arrow: 100).path(in: rect).boundingRect
        XCTAssertEqual(up.minY, -GuideCardShape.arrowLength, accuracy: 1)
        XCTAssertEqual(up.maxY, rect.maxY, accuracy: 0.5)
        let down = GuideCardShape(side: .above, arrow: 100).path(in: rect).boundingRect
        XCTAssertEqual(down.maxY, rect.maxY + GuideCardShape.arrowLength, accuracy: 1)
        XCTAssertEqual(down.minY, rect.minY, accuracy: 0.5)
        let plain = GuideCardShape(side: .none, arrow: 0).path(in: rect).boundingRect
        XCTAssertEqual(plain.minY, rect.minY, accuracy: 0.5)
        XCTAssertEqual(plain.maxY, rect.maxY, accuracy: 0.5)
    }
}
