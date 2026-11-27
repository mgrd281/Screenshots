import Foundation

// What Snapfly Pro offers and says, the same on the Mac and the iPhone: the
// features it adds, the ways to pay as the App Store gives them, the words
// around a price, the links to the terms, and when a locked feature may open
// the Pro screen. Nothing here talks to the App Store; each app's ProStore
// does, and hands its answers to these types.

extension Plan {
    /// Whether Pro has begun, so that a feature can be locked at all.
    static func hasBegun(now: Date = Date(), proStarts: Date? = Plan.proStarts) -> Bool {
        guard let proStarts else { return false }
        return now >= proStarts
    }

    /// Whether this Mac or iPhone keeps every feature without Pro, because
    /// Snapfly was used on it before Pro began.
    static func keepsEverything(now: Date = Date(), proStarts: Date? = Plan.proStarts,
                                firstLaunch: Date? = Plan.firstLaunch) -> Bool {
        guard hasBegun(now: now, proStarts: proStarts), let proStarts, let firstLaunch else { return false }
        return firstLaunch < proStarts
    }

    /// Where the App Store's last answer is kept, so that what runs without a
    /// window, like the AI apps' server, knows it too.
    static let subscribedKey = "proSubscribed"

    /// Whether the App Store last said that Pro is on here.
    static var subscribedLately: Bool {
        UserDefaults.standard.bool(forKey: subscribedKey)
    }
}

// MARK: The features

extension Plan.ProFeature {
    /// The SF Symbol it is shown with on the Pro screen.
    var symbol: String {
        switch self {
        case .orderBinder: "tray.full"
        case .sendLog: "paperplane"
        case .orderCard: "list.bullet.rectangle"
        case .coveringProfiles: "person.crop.rectangle.stack"
        case .savedMessages: "bookmark"
        case .bookkeeping: "folder.badge.plus"
        case .shopHeader: "storefront"
        case .folderCover: "folder.badge.gearshape"
        case .markup: "pencil.tip.crop.circle"
        case .guides: "list.number"
        case .backgrounds: "photo.artframe"
        case .shareLinks: "link"
        case .studio: "wand.and.stars"
        case .aiApps: "sparkles"
        }
    }

    /// Its name.
    var title: String {
        switch self {
        case .orderBinder: L("Order Binder")
        case .sendLog: L("Send Log")
        case .orderCard: L("Order Details")
        case .coveringProfiles: L("Covering Profiles")
        case .savedMessages: L("Saved Messages")
        case .bookkeeping: L("Bookkeeping")
        case .shopHeader: L("Shop Header")
        case .folderCover: L("Cover a Folder")
        case .markup: L("Draw and Crop")
        case .guides: L("Step-by-Step Guides")
        case .backgrounds: L("Backgrounds")
        case .shareLinks: L("Copy Link")
        case .studio: L("Studio")
        case .aiApps: L("AI Apps")
        }
    }

    /// What it does, in one line.
    var detail: String {
        switch self {
        case .orderBinder: L("Screenshots kept together by order number.")
        case .sendLog: L("What was sent, when and into which chat, to look up or export.")
        case .orderCard: L("An order’s details read off a screenshot, ready to copy.")
        case .coveringProfiles: L("How much to cover, chosen for each chat, and everything in AI chats.")
        case .savedMessages: L("Messages ready to go with the photos, their blanks filled in.")
        case .bookkeeping: L("Receipts handed on for the books, and the monthly PDF.")
        case .shopHeader: L("Your shop’s name and logo above the covered screenshot.")
        case .folderCover: L("Covered copies of what lands in a folder, saved in another.")
        case .markup: L("Arrows, boxes, highlights, numbered steps and words on a photo.")
        case .guides: L("Guides recorded from your clicks, sent as a PDF or a picture.")
        case .backgrounds: L("A photo set on a colour, with room, rounded corners and a shadow.")
        case .shareLinks: L("A link to a covered photo, a recording or a PDF, for seven days.")
        case .studio: L("Recordings that zoom in on clicks and typing, with marks drawn over them.")
        case .aiApps: L("Claude on your Mac asks Snapfly for what hangs on the line, covered.")
        }
    }
}

/// The Pro features as the screen lists them: three groups, each feature once.
enum ProCatalog {
    enum Group: CaseIterable {
        case orders, pictures, sharing

        var title: String {
            switch self {
            case .orders: L("Orders and Receipts")
            case .pictures: L("Pictures and Videos")
            case .sharing: L("Sharing and Routines")
            }
        }

        var features: [Plan.ProFeature] {
            switch self {
            case .orders: [.orderBinder, .orderCard, .sendLog, .savedMessages, .bookkeeping, .shopHeader]
            case .pictures: [.markup, .backgrounds, .studio, .guides]
            case .sharing: [.shareLinks, .coveringProfiles, .folderCover, .aiApps]
            }
        }
    }

    /// Every feature once, in the order the screen lists them.
    static var all: [Plan.ProFeature] { Group.allCases.flatMap(\.features) }
}

// MARK: The ways to pay

/// One way to pay for Pro, as the App Store offers it, in the store's own
/// currency and words.
struct ProOffer: Identifiable, Equatable {
    enum Period: Equatable {
        case week, month, year
        /// Any other length, in the App Store's words ("3 months").
        case other(String)
    }

    /// The product's identifier in App Store Connect.
    let id: String
    let period: Period
    let price: Decimal
    /// The price as the App Store writes it, in the store's currency.
    let displayPrice: String
    /// What a year comes to each month, in the store's currency; only for a year.
    var perMonth: String? = nil
    /// How long the free trial lasts, in the App Store's words, when this
    /// Apple account may still have one.
    var trial: String? = nil
}

/// The subscriptions in App Store Connect: one group, Snapfly Pro, that opens
/// Pro on the Mac and the iPhone alike.
enum ProProducts {
    static let yearly = "de.ghazarian.Snapfly.pro.yearly"
    static let monthly = "de.ghazarian.Snapfly.pro.monthly"
    static let ids = [yearly, monthly]
}

/// The words around a price, so that both apps say the same.
enum ProOffers {
    /// The year first, then the month, the week and any other.
    static func sorted(_ offers: [ProOffer]) -> [ProOffer] {
        offers.sorted { rank($0.period) < rank($1.period) }
    }

    private static func rank(_ period: ProOffer.Period) -> Int {
        switch period {
        case .year: 0
        case .month: 1
        case .week: 2
        case .other: 3
        }
    }

    /// The offer chosen at first: the year, when there is one.
    static func preferred(in offers: [ProOffer]) -> ProOffer? {
        sorted(offers).first
    }

    /// How much less a year costs than twelve months, in whole percent,
    /// rounded down; nil without both, or under 5%.
    static func savings(in offers: [ProOffer]) -> Int? {
        guard let year = offers.first(where: { $0.period == .year }),
              let month = offers.first(where: { $0.period == .month }), month.price > 0 else { return nil }
        let twelve = month.price * 12
        guard year.price < twelve else { return nil }
        var share = (twelve - year.price) / twelve * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &share, 0, .down)
        let percent = NSDecimalNumber(decimal: whole).intValue
        return percent >= 5 ? percent : nil
    }

    /// The plan's name on its tile.
    static func name(of period: ProOffer.Period) -> String {
        switch period {
        case .year: L("Yearly")
        case .month: L("Monthly")
        case .week: L("Weekly")
        case .other(let words): words
        }
    }

    /// The words under a tile's price: "a year".
    static func unit(of period: ProOffer.Period) -> String {
        switch period {
        case .year: L("a year")
        case .month: L("a month")
        case .week: L("a week")
        case .other(let words): String(format: L("every %@"), words)
        }
    }

    /// What is billed, in one phrase: "€39.99 a year".
    static func billing(_ offer: ProOffer) -> String {
        switch offer.period {
        case .year: String(format: L("%@ a year"), offer.displayPrice)
        case .month: String(format: L("%@ a month"), offer.displayPrice)
        case .week: String(format: L("%@ a week"), offer.displayPrice)
        case .other(let words): String(format: L("%1$@ every %2$@"), offer.displayPrice, words)
        }
    }

    /// A year by the month, under its price: "€3.33 a month".
    static func perMonthLine(_ offer: ProOffer) -> String? {
        offer.perMonth.map { String(format: L("%@ a month"), $0) }
    }

    /// How much a year saves: "Saves 16%".
    static func savingsLine(_ percent: Int) -> String {
        String(format: L("Saves %d%%"), percent)
    }

    /// The free trial on a tile: "1 week free".
    static func trialLine(_ offer: ProOffer) -> String? {
        offer.trial.map { String(format: L("%@ free"), $0) }
    }

    /// What happens once Subscribe is pressed, said before it.
    static func renewal(_ offer: ProOffer) -> String {
        if let trial = offer.trial {
            return String(format: L("Free for %1$@, then %2$@, renewing until you cancel."), trial, billing(offer))
        }
        return String(format: L("Renews at %@ until you cancel."), billing(offer))
    }

    /// How to stop it, said beside every price.
    static var cancelling: String {
        L("Cancel any time in your Apple account, at least 24 hours before it renews.")
    }

    /// Who sells it, said at the foot of the screen.
    static var seller: String {
        L("Snapfly Pro is sold by Apple. Paying, renewing, cancelling and withdrawing all go through your Apple account.")
    }
}

// MARK: What the screen shows

/// Pro as the App Store last told it on this device.
struct ProSubscription: Equatable {
    let productID: String
    /// The transaction that opened it, for Apple's withdrawal and refund.
    let transactionID: UInt64
    /// When the period paid for ends.
    let ends: Date?
    /// Whether it renews then; nil when the App Store did not say.
    let renews: Bool?

    /// The line under "You have Snapfly Pro".
    var line: String? {
        guard let ends else { return nil }
        let day = ends.formatted(date: .long, time: .omitted)
        switch renews {
        case true?: return String(format: L("Renews on %@."), day)
        case false?: return String(format: L("Ends on %@."), day)
        case nil: return String(format: L("Paid until %@."), day)
        }
    }
}

/// What the Pro screen shows, from what the App Store and Plan say.
enum ProPhase: String, Equatable, CaseIterable {
    /// Asking the App Store for the prices.
    case loading
    /// The prices are there, ready to subscribe.
    case offers
    /// The App Store gave no prices: offline, or nothing set up yet.
    case unavailable
    /// The App Store's own sheet is open.
    case buying
    /// Waiting for someone in the family to approve it (Ask to Buy).
    case pending
    /// Just subscribed, on this screen.
    case welcome
    /// Pro is on.
    case subscribed
    /// Snapfly was used here before Pro began, so everything stays open.
    case keeps
    /// This copy cannot subscribe: the Mac's edition from the website.
    case elsewhere

    static func of(canBuy: Bool, keeps: Bool, subscribed: Bool, justBought: Bool, pending: Bool,
                   buying: Bool, loading: Bool, hasOffers: Bool) -> ProPhase {
        if subscribed { return justBought ? .welcome : .subscribed }
        if keeps { return .keeps }
        if !canBuy { return .elsewhere }
        if pending { return .pending }
        if buying { return .buying }
        if hasOffers { return .offers }
        return loading ? .loading : .unavailable
    }

    /// Whether Subscribe can be pressed.
    var canSubscribe: Bool { self == .offers }

    /// Whether the prices are part of the screen.
    var showsOffers: Bool { [.loading, .offers, .unavailable, .buying, .pending].contains(self) }
}

// MARK: Links

/// Where the Pro screen's links lead: the terms on Snapfly's website, in the
/// language Snapfly shows, and Apple's own pages for the contract.
enum ProLinks {
    static let site = "https://mgrd281.github.io/Screenshots/"

    /// The website's folder for a language: German and Arabic have their own.
    static func folder(for language: String) -> String {
        let code = String(language.prefix(2))
        return ["de", "ar"].contains(code) ? code + "/" : ""
    }

    /// The language Snapfly shows.
    static var language: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    static func page(_ name: String, language: String = ProLinks.language) -> URL {
        URL(string: site + folder(for: language) + name + ".html")!
    }

    /// The terms of use (AGB).
    static func terms(language: String = ProLinks.language) -> URL { page("terms", language: language) }

    /// The privacy policy.
    static func privacy(language: String = ProLinks.language) -> URL { page("privacy", language: language) }

    /// How to withdraw from Pro and cancel it.
    static func withdrawal(language: String = ProLinks.language) -> URL { page("withdrawal", language: language) }

    /// Apple's own withdrawal: the purchase history, then Withdraw Transaction.
    static let appleWithdrawal = URL(string: "https://reportaproblem.apple.com/")!

    /// Apple's own subscriptions page, where Pro is cancelled.
    static let appleSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

// MARK: How often

/// When a locked feature may open the whole Pro screen: the first time on a
/// day. Later that day a note says so instead, so Pro never nags.
enum ProNudge {
    static let key = "proScreenDay"

    static func opensScreen(lastShown: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastShown else { return true }
        return !calendar.isDate(lastShown, inSameDayAs: now)
    }

    /// Asks, and notes the day when the answer is yes.
    static func takeScreen(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        let last = defaults.object(forKey: key) as? Date
        guard opensScreen(lastShown: last, now: now) else { return false }
        defaults.set(now, forKey: key)
        return true
    }

    /// The note, and the chip on the Pro screen: "Studio is part of Snapfly Pro."
    static func note(for feature: Plan.ProFeature) -> String {
        String(format: L("%@ is part of Snapfly Pro."), feature.title)
    }
}

// MARK: Samples

/// The Pro screen at launch with made-up prices, for the captures CI takes:
/// `-SnapflyPro <phase>`, `-SnapflyProFeature <feature>` and
/// `-SnapflyReduceMotion`. Only in debug builds; nothing is bought or kept.
enum ProSample {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static let phase: ProPhase? = value(after: "-SnapflyPro").flatMap(ProPhase.init(rawValue:))
    static let feature: Plan.ProFeature? = value(after: "-SnapflyProFeature").flatMap(Plan.ProFeature.init(rawValue:))
    static let still = arguments.contains("-SnapflyReduceMotion")
    /// `-SnapflyProScroll features` or `footer`: where the iPhone's screen starts.
    static let scroll: String? = value(after: "-SnapflyProScroll")
    static var requested: Bool { phase != nil }

    /// A year with a week's trial and a month, in euros. Made up for the
    /// captures: the real prices come from App Store Connect.
    static var offers: [ProOffer] {
        let year = Decimal(string: "39.99")!, month = Decimal(string: "3.99")!
        let euros = Decimal.FormatStyle.Currency(code: "EUR")
        let week = DateComponentsFormatter()
        week.unitsStyle = .full
        week.allowedUnits = [.weekOfMonth]
        return [
            ProOffer(id: ProProducts.yearly, period: .year, price: year, displayPrice: year.formatted(euros),
                     perMonth: (year / 12).formatted(euros),
                     trial: week.string(from: DateComponents(weekOfMonth: 1))),
            ProOffer(id: ProProducts.monthly, period: .month, price: month, displayPrice: month.formatted(euros)),
        ]
    }

    static var subscription: ProSubscription {
        ProSubscription(productID: ProProducts.yearly, transactionID: 1,
                        ends: Date().addingTimeInterval(300 * 86_400), renews: true)
    }
    #else
    static let phase: ProPhase? = nil
    static let feature: Plan.ProFeature? = nil
    static let still = false
    static let scroll: String? = nil
    static var requested: Bool { false }
    static var offers: [ProOffer] { [] }
    static var subscription: ProSubscription {
        ProSubscription(productID: ProProducts.yearly, transactionID: 0, ends: nil, renews: nil)
    }
    #endif
}
