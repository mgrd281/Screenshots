import XCTest
@testable import Tendedero

/// What Is Covered as a live preview: every kind is in a sample, a group
/// and a kind open on the right one, the tiles' rings and words for none,
/// some and all, the presets as the old buttons wrote them, and the sweep
/// down a document.
final class CoverStudioTests: XCTestCase {
    // MARK: The samples

    func testEveryKindIsInASample() {
        let shown = Set(CoverStudioSample.allCases.flatMap(\.kinds))
        XCTAssertEqual(shown, Set(PrivateDetail.allCases))
    }

    func testTheSamplesHaveTheBriefsFields() {
        XCTAssertEqual(CoverStudioSample.bill.fields.count, 13)
        XCTAssertEqual(CoverStudioSample.chat.fields.count, 6)
        XCTAssertEqual(CoverStudioSample.note.fields.count, 5)
        // Each field once.
        let ids = CoverStudioSample.allCases.flatMap(\.fields).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAGroupOpensOnTheSampleWithMostOfIt() {
        XCTAssertEqual(CoverStudioSample.showing(.people), .bill)
        XCTAssertEqual(CoverStudioSample.showing(.money), .bill)
        XCTAssertEqual(CoverStudioSample.showing(.health), .bill)
        XCTAssertEqual(CoverStudioSample.showing(.documents), .bill)
        XCTAssertEqual(CoverStudioSample.showing(.access), .note)
    }

    func testAKindTurnedIsShownWhereItIs() {
        // Shown already: it stays.
        XCTAssertEqual(CoverStudioSample.showing(.phones, from: .chat), .chat)
        XCTAssertEqual(CoverStudioSample.showing(.emails, from: .note), .note)
        // Elsewhere: the first sample that has it.
        XCTAssertEqual(CoverStudioSample.showing(.faces, from: .bill), .chat)
        XCTAssertEqual(CoverStudioSample.showing(.keys, from: .bill), .note)
        XCTAssertEqual(CoverStudioSample.showing(.health, from: .note), .bill)
        for kind in PrivateDetail.allCases {
            for sample in CoverStudioSample.allCases {
                XCTAssertTrue(CoverStudioSample.showing(kind, from: sample).shows(kind), "\(kind) from \(sample)")
            }
        }
    }

    func testASampleCountsWhatIsCovered() {
        XCTAssertEqual(CoverStudioSample.bill.covered(by: PrivateDetail.recommended), 9)
        XCTAssertEqual(CoverStudioSample.bill.covered(by: []), 0)
        XCTAssertEqual(CoverStudioSample.note.covered(by: Set(PrivateDetail.allCases)), 5)
    }

    // MARK: The groups

    func testTheSheetsHoldEveryKindOfTheirGroupOnce() {
        for group in CoverGroup.allCases {
            let kinds = group.sections.flatMap(\.kinds)
            XCTAssertEqual(kinds.count, Set(kinds).count, "\(group)")
            XCTAssertEqual(Set(kinds), Set(group.kinds), "\(group)")
        }
        XCTAssertEqual(CoverGroup.people.sections.map(\.id), ["names", "contact", "more"])
        XCTAssertNotNil(CoverGroup.people.sections[0].footer)
        XCTAssertEqual(CoverGroup.access.sections.count, 1)
    }

    func testTheTilesForNoneSomeAndAll() {
        for group in CoverGroup.allCases {
            let none = CoverSummary([])
            XCTAssertEqual(none.state(of: group), .none)
            XCTAssertEqual(none.share(of: group), 0)
            let all = CoverSummary(Set(group.kinds))
            XCTAssertEqual(all.state(of: group), .all)
            XCTAssertEqual(all.share(of: group), 1)
            guard group.kinds.count > 1 else { continue }
            let some = CoverSummary([group.kinds[0]])
            XCTAssertEqual(some.state(of: group), .some(1, of: group.kinds.count))
            XCTAssertEqual(some.share(of: group), 1 / Double(group.kinds.count), accuracy: 0.0001)
        }
        let recommended = CoverSummary(PrivateDetail.recommended)
        XCTAssertEqual(recommended.state(of: .people), .some(7, of: 10))
        XCTAssertEqual(recommended.state(of: .money), .some(1, of: 2))
        XCTAssertEqual(recommended.state(of: .health), .all)
        XCTAssertEqual(recommended.state(of: .access), .some(2, of: 3))
    }

    func testTurningAGroupOnChangesOnlyThatGroup() {
        let before = CoverSummary(PrivateDetail.recommended)
        let after = before.setting(.money, on: true)
        XCTAssertEqual(after.subtracting(CoverGroup.money.kinds), before.chosen.subtracting(CoverGroup.money.kinds))
        XCTAssertTrue(Set(CoverGroup.money.kinds).isSubset(of: after))
        let off = before.setting(.people, on: false)
        XCTAssertTrue(off.isDisjoint(with: CoverGroup.people.kinds))
        XCTAssertEqual(off, before.chosen.subtracting(CoverGroup.people.kinds))
    }

    // MARK: The menu

    /// What Check All, Recommended and Uncheck All wrote before, recorded
    /// from the old page.
    private static let oldButtons: [String: [String]] = [
        "recommended": ["addresses", "bank", "barcodes", "birthDates", "codes", "emails", "health", "ids", "keys",
                        "names", "otherPeople", "patientNames", "phones"],
        "all": ["addresses", "amounts", "bank", "barcodes", "birthDates", "codes", "dates", "emails", "faces",
                "health", "ids", "ipAddresses", "keys", "links", "names", "orders", "organizations", "otherPeople",
                "patientNames", "phones", "tracking", "usernames"],
        "none": [],
    ]

    func testTheMenuWritesWhatTheOldButtonsWrote() {
        for preset in CoverPreset.allCases {
            XCTAssertEqual(preset.kinds.map(\.rawValue).sorted(), Self.oldButtons[preset.rawValue], preset.rawValue)
        }
    }

    func testTheBadgeTellsThePreset() {
        XCTAssertEqual(CoverSummary(PrivateDetail.recommended).preset, .recommended)
        XCTAssertEqual(CoverSummary(Set(PrivateDetail.allCases)).preset, .all)
        XCTAssertEqual(CoverSummary([]).preset, CoverPreset.none)
        XCTAssertNil(CoverSummary(PrivateDetail.recommended.union([.amounts])).preset)
        XCTAssertNil(CoverSummary([.faces]).preset)
    }

    // MARK: The sweep

    func testASweepRunsDownTheDocumentInReadingOrder() {
        let changed: [PrivateDetail] = [.links, .faces, .otherPeople, .amounts]
        let delays = CoverSummary.sweep(changed, on: .bill)
        XCTAssertEqual(delays[.otherPeople], 0)
        XCTAssertEqual(delays[.amounts] ?? -1, 0.025, accuracy: 0.0001)
        XCTAssertEqual(delays[.links] ?? -1, 0.05, accuracy: 0.0001)
        // Not on this document: at once.
        XCTAssertEqual(delays[.faces], 0)
    }

    func testASweepStartsWithinFourTenthsOfASecond() {
        let delays = CoverSummary.sweep(PrivateDetail.allCases, on: .bill)
        XCTAssertLessThanOrEqual(delays.values.max() ?? 0, 0.4 + 0.0001)
        XCTAssertEqual(delays.count, PrivateDetail.allCases.count)
    }
}
