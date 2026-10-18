import Foundation

/// What Snapfly will one day keep for Pro, a subscription. Nothing is held
/// back yet: until `proStarts` is set, every feature is open to everyone, and
/// whoever used Snapfly before that day keeps every feature for good.
/// Covering private details, of every kind, is never Pro.
enum Plan {
    /// The features that will need Pro, each free until Pro begins.
    enum ProFeature: String, CaseIterable {
        /// Screenshots kept together by order number, for as long as chosen.
        case orderBinder
        /// What was sent, when and into which chat, to look up or export.
        case sendLog
        /// The details of an order read off a screenshot, ready to copy.
        case orderCard
        /// How much to cover, chosen for each chat or person sent to; to
        /// begin with, everything in AI chats.
        case coveringProfiles
        /// Messages kept ready to go with the photos, their blanks filled in.
        case savedMessages
        /// Receipts handed on for the books: a named covered copy and a line
        /// for a table, and the monthly pack.
        case bookkeeping
        /// The covered screenshot under a band with the shop's name and logo.
        case shopHeader
        /// Covered copies of what lands in a folder, saved in another.
        case folderCover
        /// Arrows, boxes, highlights, numbered steps, words and a crop drawn
        /// on a photo, on what leaves the line, and Crop on its own.
        case markup
    }

    /// The day Pro begins. Until it is set, nothing is held back.
    static let proStarts: Date? = nil

    /// Whether a Pro feature is open here: always before Pro begins, then to
    /// whoever used Snapfly before that day, and with Pro.
    static func allows(_ feature: ProFeature, now: Date = Date(), proStarts: Date? = Plan.proStarts,
                       firstLaunch: Date? = Plan.firstLaunch, subscribed: Bool = false) -> Bool {
        guard let proStarts, now >= proStarts else { return true }
        if subscribed { return true }
        if let firstLaunch, firstLaunch < proStarts { return true }
        return false
    }

    // MARK: First launch

    static let firstLaunchKey = "firstLaunch"

    /// When Snapfly first opened on this Mac or iPhone, from the first launch
    /// of a version that notes it.
    static var firstLaunch: Date? {
        UserDefaults.standard.object(forKey: firstLaunchKey) as? Date
    }

    /// Notes the first launch, once, and keeps that date from then on.
    @discardableResult
    static func recordFirstLaunch(in defaults: UserDefaults = .standard, now: Date = Date()) -> Date {
        if let date = defaults.object(forKey: firstLaunchKey) as? Date { return date }
        defaults.set(now, forKey: firstLaunchKey)
        return now
    }
}
