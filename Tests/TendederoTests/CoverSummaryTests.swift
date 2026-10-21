import XCTest
@testable import Tendedero

/// The More tab's counts, presets and groups: the presets write exactly
/// what Check All, Recommended and Uncheck All wrote, the counts, the meter
/// and the badge follow the switches, the protection reads as off with
/// nothing chosen, and Always Hide is counted as its rows show.
final class CoverSummaryTests: XCTestCase {
    func testThePresetsWriteWhatTheOldButtonsWrote() {
        // SettingsView's buttons of before: Set(PrivateDetail.allCases), PrivateDetail.recommended, [].
        XCTAssertEqual(CoverPreset.all.kinds, Set(PrivateDetail.allCases))
        XCTAssertEqual(CoverPreset.recommended.kinds, PrivateDetail.recommended)
        XCTAssertEqual(CoverPreset.none.kinds, [])
        XCTAssertEqual(CoverSummary.total, 22)
        XCTAssertEqual(CoverPreset.recommended.kinds.count, 13)
        XCTAssertEqual(CoverPreset.recommended.kinds,
                       [.names, .patientNames, .otherPeople, .addresses, .birthDates, .emails, .phones, .bank, .health,
                        .ids, .codes, .keys, .barcodes])
    }

    func testAPresetIsNamedOnlyWhenTheChoiceIsExactlyIt() {
        XCTAssertEqual(CoverSummary(PrivateDetail.recommended).preset, .recommended)
        XCTAssertEqual(CoverSummary(Set(PrivateDetail.allCases)).preset, .all)
        XCTAssertEqual(CoverSummary([]).preset, CoverPreset.none)
        let own = CoverSummary(PrivateDetail.recommended.subtracting([.codes]))
        XCTAssertNil(own.preset)
        XCTAssertEqual(own.presetTitle, "Your Choice")
        XCTAssertEqual(CoverSummary(PrivateDetail.recommended.union([.amounts])).presetTitle, "Your Choice")
        XCTAssertEqual(CoverSummary(PrivateDetail.recommended).presetTitle, "Recommended")
        XCTAssertEqual(CoverSummary([]).presetTitle, "None")
    }

    func testTheFiveGroupsHoldEveryKindOnce() {
        let kinds = CoverGroup.allCases.flatMap(\.kinds)
        XCTAssertEqual(kinds.count, PrivateDetail.allCases.count)
        XCTAssertEqual(Set(kinds), Set(PrivateDetail.allCases))
        for kind in PrivateDetail.allCases {
            XCTAssertTrue(CoverGroup.of(kind).kinds.contains(kind), "\(kind)")
        }
        XCTAssertEqual(CoverGroup.allCases.map { $0.kinds.count }, [10, 2, 1, 6, 3])
        XCTAssertEqual(CoverGroup.people.kinds.last, .organizations, "the companies beside the people")
        XCTAssertEqual(CoverGroup.people.kinds.first, .names)
    }

    func testCountsTheMeterAndTheBadgeFollowTheSwitches() {
        var summary = CoverSummary(PrivateDetail.recommended)
        XCTAssertEqual(summary.count, 13)
        XCTAssertEqual(summary.share, 13.0 / 22.0, accuracy: 0.0001)
        XCTAssertEqual(CoverGroup.allCases.map(summary.count(in:)), [7, 1, 1, 2, 2])
        XCTAssertFalse(summary.isOff)

        summary = CoverSummary(summary.toggling(.amounts))
        XCTAssertEqual(summary.count, 14)
        XCTAssertEqual(summary.count(in: .money), 2)
        XCTAssertTrue(summary.isWhole(.money))
        XCTAssertNil(summary.preset)

        summary = CoverSummary(summary.toggling(.amounts))
        XCTAssertEqual(summary.count, 13)
        XCTAssertEqual(summary.preset, .recommended, "back to the preset, the badge says it again")
    }

    func testAGroupTurnsOnAndOffAndTheOthersStay() {
        let summary = CoverSummary(PrivateDetail.recommended)
        let on = summary.setting(.documents, on: true)
        XCTAssertTrue(on.isSuperset(of: CoverGroup.documents.kinds))
        XCTAssertEqual(on.subtracting(CoverGroup.documents.kinds), summary.chosen.subtracting(CoverGroup.documents.kinds))
        let off = summary.setting(.people, on: false)
        XCTAssertTrue(off.isDisjoint(with: CoverGroup.people.kinds))
        XCTAssertEqual(off, summary.chosen.subtracting(CoverGroup.people.kinds))
        XCTAssertEqual(CoverSummary(off).count(in: .people), 0)
        XCTAssertEqual(CoverSummary(off).count(in: .money), 1)
    }

    func testTheProtectionIsOffWithNothingChosen() {
        XCTAssertTrue(CoverSummary([]).isOff)
        XCTAssertEqual(CoverSummary([]).count, 0)
        XCTAssertEqual(CoverSummary([]).share, 0)
        XCTAssertFalse(CoverSummary([.names]).isOff)
        // Uncheck All of before, now None, turns it off.
        XCTAssertTrue(CoverSummary(CoverPreset.none.kinds).isOff)
    }

    func testAChangeRunsDownTheKindsInThePagesOrder() {
        let changed = CoverSummary.changed(from: PrivateDetail.recommended, to: Set(PrivateDetail.allCases))
        XCTAssertEqual(Set(changed), Set(PrivateDetail.allCases).subtracting(PrivateDetail.recommended))
        XCTAssertEqual(changed, CoverGroup.allCases.flatMap(\.kinds).filter { !PrivateDetail.recommended.contains($0) })
        XCTAssertEqual(changed.first, .usernames)
        XCTAssertEqual(CoverSummary.changed(from: [.names], to: [.names]), [])
    }

    func testAlwaysHideIsCountedAsItsRowsShow() {
        let name = OwnRule(text: OwnDetails.nameText(given: "Max", surname: "Mustermann"), kind: .name)
        let card = OwnRule(text: "4242424242424242", kind: .card)
        let rules = [OwnRule(text: "Musterfirma", kind: .word),
                     OwnRule(text: "Kundennummer", kind: .label),
                     OwnRule(text: "Aktenzeichen", kind: .label, isEnabled: false),
                     OwnRule(text: "   ", kind: .word)]
        let summary = OwnSummary([name, card] + rules)
        XCTAssertEqual(summary.details, 2)
        XCTAssertEqual(summary.rules, 3, "an empty rule is no rule")
        XCTAssertEqual(summary.activeRules, 2)
        XCTAssertEqual(summary.initials, "MM")
        XCTAssertEqual(summary.line, "2 details · 2 rules")
        XCTAssertEqual(OwnSummary([name, rules[0]]).line, "1 detail · 1 rule")
        XCTAssertNil(OwnSummary(rules).initials, "no name, no initials")
        XCTAssertEqual(OwnSummary([]).line, "0 details · 0 rules")
    }

    func testInitialsAreTheGivenNameAndTheSurname() {
        XCTAssertEqual(OwnSummary.initials(of: "Mustermann, Max"), "MM")
        XCTAssertEqual(OwnSummary.initials(of: "Max van Berg"), "MB")
        XCTAssertEqual(OwnSummary.initials(of: "erika musterfrau"), "EM")
        XCTAssertEqual(OwnSummary.initials(of: "Cher"), "C")
        XCTAssertNil(OwnSummary.initials(of: "  "))
    }
}
