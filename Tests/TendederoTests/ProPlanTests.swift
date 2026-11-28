#if canImport(AppKit)
import AppKit
#endif
import Foundation
import XCTest
@testable import Tendedero

/// What the Pro screen says and shows, without a screen or the App Store:
/// when Pro has begun, which features it lists, the words around a price,
/// what each state of the store shows, where the links lead, and that a
/// locked feature opens the whole screen only once a day.
final class ProPlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)
    private let day: TimeInterval = 86_400

    /// A way to pay as the App Store would hand it on, priced in euros.
    private func offer(_ period: ProOffer.Period, _ price: String, perMonth: String? = nil,
                       trial: String? = nil) -> ProOffer {
        let id: String
        switch period {
        case .year: id = ProProducts.yearly
        case .month: id = ProProducts.monthly
        case .week: id = "test.weekly"
        case .other(let words): id = "test." + words
        }
        return ProOffer(id: id, period: period, price: Decimal(string: price)!, displayPrice: "€" + price,
                        perMonth: perMonth, trial: trial)
    }

    // MARK: When Pro begins

    func testProHasNotBegunWithoutADay() {
        XCTAssertFalse(Plan.hasBegun(now: start, proStarts: nil))
        XCTAssertFalse(Plan.hasBegun())
    }

    func testProBeginsOnItsDay() {
        XCTAssertFalse(Plan.hasBegun(now: start.addingTimeInterval(-day), proStarts: start))
        XCTAssertFalse(Plan.hasBegun(now: start.addingTimeInterval(-1), proStarts: start))
        XCTAssertTrue(Plan.hasBegun(now: start, proStarts: start))
        XCTAssertTrue(Plan.hasBegun(now: start.addingTimeInterval(30 * day), proStarts: start))
    }

    func testWhoeverCameBeforeKeepsEverything() {
        let monthLater = start.addingTimeInterval(30 * day)
        let founder = start.addingTimeInterval(-200 * day)
        XCTAssertTrue(Plan.keepsEverything(now: monthLater, proStarts: start, firstLaunch: founder))
        // Arriving on the day itself, or after it, is not before.
        XCTAssertFalse(Plan.keepsEverything(now: monthLater, proStarts: start, firstLaunch: start))
        XCTAssertFalse(Plan.keepsEverything(now: monthLater, proStarts: start,
                                            firstLaunch: start.addingTimeInterval(day)))
        XCTAssertFalse(Plan.keepsEverything(now: monthLater, proStarts: start, firstLaunch: nil))
    }

    func testNothingIsKeptBeforeProBegins() {
        let founder = start.addingTimeInterval(-200 * day)
        XCTAssertFalse(Plan.keepsEverything(now: start, proStarts: nil, firstLaunch: founder))
        XCTAssertFalse(Plan.keepsEverything(now: start.addingTimeInterval(-day), proStarts: start,
                                            firstLaunch: founder))
    }

    func testEachAnswerIsKeptUnderItsOwnName() {
        XCTAssertEqual(Set([Plan.subscribedKey, Plan.firstLaunchKey, ProNudge.key]).count, 3)
    }

    // MARK: The features

    func testTheCatalogListsEveryFeatureOnce() {
        XCTAssertEqual(ProCatalog.all.count, Plan.ProFeature.allCases.count)
        XCTAssertEqual(Set(ProCatalog.all), Set(Plan.ProFeature.allCases))
        let groups = ProCatalog.Group.allCases
        for group in groups {
            XCTAssertFalse(group.features.isEmpty, "\(group)")
            XCTAssertFalse(group.title.isEmpty, "\(group)")
        }
        XCTAssertEqual(Set(groups.map(\.title)).count, groups.count)
    }

    func testEveryFeatureHasANameALineAndItsOwnSymbol() {
        let features = Plan.ProFeature.allCases
        for feature in features {
            XCTAssertFalse(feature.title.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.detail.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.symbol.isEmpty, feature.rawValue)
        }
        XCTAssertEqual(Set(features.map(\.symbol)).count, features.count)
        XCTAssertEqual(Set(features.map(\.title)).count, features.count)
    }

    #if canImport(AppKit)
    func testEverySymbolIsOneTheMacHas() {
        for feature in Plan.ProFeature.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: feature.symbol, accessibilityDescription: nil), feature.symbol)
        }
    }
    #endif

    func testTheNoteNamesTheLockedFeature() {
        XCTAssertEqual(ProNudge.note(for: .studio), "Studio is part of Snapfly Pro.")
        for feature in Plan.ProFeature.allCases {
            XCTAssertTrue(ProNudge.note(for: feature).contains(feature.title), feature.rawValue)
        }
    }

    // MARK: The ways to pay

    func testTheYearComesFirstThenTheMonthTheWeekAndAnyOther() {
        let other = offer(.other("3 months"), "9.99"), week = offer(.week, "1.49")
        let month = offer(.month, "3.99"), year = offer(.year, "39.99")
        let expected: [ProOffer.Period] = [.year, .month, .week, .other("3 months")]
        XCTAssertEqual(ProOffers.sorted([other, week, month, year]).map(\.period), expected)
        XCTAssertEqual(ProOffers.sorted([month, other, year, week]).map(\.period), expected)
        XCTAssertTrue(ProOffers.sorted([]).isEmpty)
    }

    func testTheYearIsChosenAtFirst() {
        let week = offer(.week, "1.49"), month = offer(.month, "3.99"), year = offer(.year, "39.99")
        XCTAssertEqual(ProOffers.preferred(in: [month, year]), year)
        XCTAssertEqual(ProOffers.preferred(in: [week, month, year])?.id, ProProducts.yearly)
        XCTAssertEqual(ProOffers.preferred(in: [week, month]), month)
        XCTAssertNil(ProOffers.preferred(in: []))
    }

    func testTheProductsAreTheYearAndTheMonth() {
        XCTAssertEqual(ProProducts.ids, [ProProducts.yearly, ProProducts.monthly])
        XCTAssertNotEqual(ProProducts.yearly, ProProducts.monthly)
    }

    func testAYearSavesWhatTwelveMonthsWouldCostMore() {
        XCTAssertEqual(ProOffers.savings(in: [offer(.year, "39.99"), offer(.month, "3.99")]), 16)
        XCTAssertEqual(ProOffers.savings(in: [offer(.month, "3.99"), offer(.year, "39.99")]), 16)
        // Exactly 5% is said; a share is rounded down, never up.
        XCTAssertEqual(ProOffers.savings(in: [offer(.year, "114"), offer(.month, "10")]), 5)
        XCTAssertEqual(ProOffers.savings(in: [offer(.year, "59.99"), offer(.month, "9.99")]), 49)
    }

    func testNoSavingsAreClaimedWithoutGrounds() {
        // A year that costs as much as twelve months, or more.
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "47.88"), offer(.month, "3.99")]))
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "50"), offer(.month, "3.99")]))
        // Under 5%.
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "115"), offer(.month, "10")]))
        // Without both, or with a month that costs nothing.
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "39.99")]))
        XCTAssertNil(ProOffers.savings(in: [offer(.month, "3.99")]))
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "39.99"), offer(.week, "0.99")]))
        XCTAssertNil(ProOffers.savings(in: [offer(.year, "39.99"), offer(.month, "0")]))
        XCTAssertNil(ProOffers.savings(in: []))
    }

    func testEveryPeriodHasItsOwnNameAndUnit() {
        let periods: [ProOffer.Period] = [.year, .month, .week, .other("3 months")]
        for period in periods {
            XCTAssertFalse(ProOffers.name(of: period).isEmpty, "\(period)")
            XCTAssertFalse(ProOffers.unit(of: period).isEmpty, "\(period)")
        }
        XCTAssertEqual(Set(periods.map { ProOffers.name(of: $0) }).count, periods.count)
        XCTAssertEqual(Set(periods.map { ProOffers.unit(of: $0) }).count, periods.count)
        XCTAssertEqual(ProOffers.name(of: .year), "Yearly")
        XCTAssertEqual(ProOffers.unit(of: .year), "a year")
        // Any other length is named in the App Store's own words.
        XCTAssertEqual(ProOffers.name(of: .other("3 months")), "3 months")
        XCTAssertTrue(ProOffers.unit(of: .other("3 months")).contains("3 months"))
    }

    func testWhatIsBilledNamesThePriceAndThePeriod() {
        let offers = [offer(.year, "39.99"), offer(.month, "3.99"), offer(.week, "1.49"),
                      offer(.other("3 months"), "9.99")]
        for item in offers {
            XCTAssertTrue(ProOffers.billing(item).contains(item.displayPrice), ProOffers.billing(item))
        }
        XCTAssertEqual(Set(offers.map { ProOffers.billing($0) }).count, offers.count)
        XCTAssertEqual(ProOffers.billing(offers[0]), "€39.99 a year")
        XCTAssertEqual(ProOffers.billing(offers[1]), "€3.99 a month")
        XCTAssertTrue(ProOffers.billing(offers[3]).contains("3 months"))
    }

    func testTheLinesUnderAPrice() {
        let year = offer(.year, "39.99", perMonth: "€3.33", trial: "1 week")
        let month = offer(.month, "3.99")
        XCTAssertEqual(ProOffers.perMonthLine(year), "€3.33 a month")
        XCTAssertNil(ProOffers.perMonthLine(month))
        XCTAssertEqual(ProOffers.trialLine(year), "1 week free")
        XCTAssertNil(ProOffers.trialLine(month))
        XCTAssertEqual(ProOffers.savingsLine(16), "Saves 16%")
    }

    func testTheRenewalIsSaidBeforeSubscribing() {
        let yearWithTrial = offer(.year, "39.99", trial: "1 week")
        let withTrial = ProOffers.renewal(yearWithTrial)
        XCTAssertTrue(withTrial.contains(ProOffers.billing(yearWithTrial)), withTrial)
        XCTAssertTrue(withTrial.contains("1 week"), withTrial)

        let plain = offer(.year, "39.99")
        let withoutTrial = ProOffers.renewal(plain)
        XCTAssertTrue(withoutTrial.contains(ProOffers.billing(plain)), withoutTrial)
        XCTAssertNotEqual(withTrial, withoutTrial)

        let month = offer(.month, "3.99")
        XCTAssertTrue(ProOffers.renewal(month).contains(ProOffers.billing(month)))
        XCTAssertFalse(ProOffers.cancelling.isEmpty)
        XCTAssertFalse(ProOffers.seller.isEmpty)
    }

    // MARK: What the screen shows

    func testTheSubscriptionSaysWhatHappensWhenItsPeriodEnds() {
        let ends = start
        let date = ends.formatted(date: .long, time: .omitted)
        func line(_ renews: Bool?) -> String? {
            ProSubscription(productID: ProProducts.yearly, transactionID: 7, ends: ends, renews: renews).line
        }
        XCTAssertEqual(line(true), "Renews on \(date).")
        XCTAssertEqual(line(false), "Ends on \(date).")
        XCTAssertEqual(line(nil), "Paid until \(date).")
        XCTAssertNil(ProSubscription(productID: ProProducts.yearly, transactionID: 7, ends: nil, renews: true).line)
    }

    /// The screen's state, with every flag off unless named.
    private func phase(canBuy: Bool = true, keeps: Bool = false, subscribed: Bool = false, justBought: Bool = false,
                       pending: Bool = false, buying: Bool = false, loading: Bool = false,
                       hasOffers: Bool = false) -> ProPhase {
        ProPhase.of(canBuy: canBuy, keeps: keeps, subscribed: subscribed, justBought: justBought, pending: pending,
                    buying: buying, loading: loading, hasOffers: hasOffers)
    }

    func testEachStateWinsOverThoseAfterIt() {
        XCTAssertEqual(phase(canBuy: false, keeps: true, subscribed: true, justBought: true, pending: true,
                             buying: true, loading: true, hasOffers: true), .welcome)
        XCTAssertEqual(phase(canBuy: false, keeps: true, subscribed: true, pending: true, buying: true,
                             loading: true, hasOffers: true), .subscribed)
        XCTAssertEqual(phase(canBuy: false, keeps: true, justBought: true, pending: true, buying: true,
                             loading: true, hasOffers: true), .keeps)
        XCTAssertEqual(phase(canBuy: false, pending: true, buying: true, loading: true, hasOffers: true), .elsewhere)
        XCTAssertEqual(phase(pending: true, buying: true, loading: true, hasOffers: true), .pending)
        XCTAssertEqual(phase(buying: true, loading: true, hasOffers: true), .buying)
        XCTAssertEqual(phase(loading: true, hasOffers: true), .offers)
        XCTAssertEqual(phase(loading: true), .loading)
        XCTAssertEqual(phase(), .unavailable)
        // Just bought means nothing until the App Store says Pro is on.
        XCTAssertEqual(phase(justBought: true, hasOffers: true), .offers)
    }

    func testOnlyThePricesCanBeSubscribedTo() {
        let withPrices: Set<ProPhase> = [.loading, .offers, .unavailable, .buying, .pending]
        for state in ProPhase.allCases {
            XCTAssertEqual(state.canSubscribe, state == .offers, state.rawValue)
            XCTAssertEqual(state.showsOffers, withPrices.contains(state), state.rawValue)
        }
    }

    func testTheCapturesNameRealStatesAndFeatures() {
        for name in ["offers", "subscribed", "welcome", "unavailable", "keeps", "elsewhere"] {
            XCTAssertNotNil(ProPhase(rawValue: name), name)
        }
        XCTAssertEqual(Plan.ProFeature(rawValue: "orderCard"), Plan.ProFeature.orderCard)
    }

    #if DEBUG
    func testTheSamplePricesAreAYearAndAMonth() {
        let offers = ProSample.offers
        XCTAssertEqual(ProOffers.preferred(in: offers)?.id, ProProducts.yearly)
        XCTAssertEqual(ProOffers.savings(in: offers), 16)
        XCTAssertNotNil(ProOffers.preferred(in: offers)?.perMonth)
    }
    #endif

    // MARK: Links

    func testGermanAndArabicHaveTheirOwnFolder() {
        XCTAssertEqual(ProLinks.folder(for: "de"), "de/")
        XCTAssertEqual(ProLinks.folder(for: "de-DE"), "de/")
        XCTAssertEqual(ProLinks.folder(for: "ar"), "ar/")
        XCTAssertEqual(ProLinks.folder(for: "en"), "")
        XCTAssertEqual(ProLinks.folder(for: "fr"), "")
        XCTAssertEqual(ProLinks.folder(for: "pt-BR"), "")
    }

    func testTheTermsOpenInTheLanguageShown() {
        XCTAssertTrue(ProLinks.terms(language: "de").absoluteString.hasSuffix("de/terms.html"))
        XCTAssertTrue(ProLinks.privacy(language: "de").absoluteString.hasSuffix("de/privacy.html"))
        XCTAssertTrue(ProLinks.withdrawal(language: "de").absoluteString.hasSuffix("de/withdrawal.html"))
        XCTAssertEqual(ProLinks.terms(language: "de").absoluteString, ProLinks.site + "de/terms.html")
        XCTAssertEqual(ProLinks.withdrawal(language: "ar").absoluteString, ProLinks.site + "ar/withdrawal.html")
        // English is the site's own folder.
        XCTAssertEqual(ProLinks.terms(language: "en").absoluteString, ProLinks.site + "terms.html")
        XCTAssertEqual(ProLinks.privacy(language: "en").absoluteString, ProLinks.site + "privacy.html")
        XCTAssertEqual(ProLinks.withdrawal(language: "en").absoluteString, ProLinks.site + "withdrawal.html")
    }

    func testApplesOwnPagesForTheContract() {
        XCTAssertEqual(ProLinks.appleWithdrawal.scheme, "https")
        XCTAssertEqual(ProLinks.appleWithdrawal.host, "reportaproblem.apple.com")
        XCTAssertEqual(ProLinks.appleSubscriptions.scheme, "https")
        XCTAssertEqual(ProLinks.appleSubscriptions.host, "apps.apple.com")
    }

    // MARK: How often

    /// Days as they fall in one time zone, so that the test holds anywhere.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func november(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTheScreenOpensTheFirstTimeADay() {
        XCTAssertTrue(ProNudge.opensScreen(lastShown: nil, now: november(28, 12), calendar: utc))
        XCTAssertFalse(ProNudge.opensScreen(lastShown: november(28, 0, 30), now: november(28, 23, 30), calendar: utc))
        XCTAssertTrue(ProNudge.opensScreen(lastShown: november(27, 23, 30), now: november(28, 0, 30), calendar: utc))
    }

    func testTheDayIsNotedOnce() throws {
        let suite = "ProPlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(ProNudge.takeScreen(now: start, defaults: defaults))
        XCTAssertEqual(defaults.object(forKey: ProNudge.key) as? Date, start)
        // A minute later, the same day: a note instead, and the day stays as it was.
        XCTAssertFalse(ProNudge.takeScreen(now: start.addingTimeInterval(60), defaults: defaults))
        XCTAssertEqual(defaults.object(forKey: ProNudge.key) as? Date, start)
        let later = start.addingTimeInterval(2 * day)
        XCTAssertTrue(ProNudge.takeScreen(now: later, defaults: defaults))
        XCTAssertEqual(defaults.object(forKey: ProNudge.key) as? Date, later)
    }
}
