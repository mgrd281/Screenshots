import SwiftUI

/// What More and its pages show and change: the kinds chosen, the cover
/// look and the two switches beside it, Apple Intelligence, and what Always
/// Hide holds. Each is read and kept through the setting it always was
/// (`Choice.details`, `CoverStyle.current`, `Finder`, `OwnRules`), under the
/// same key, so nothing kept before changes. For screenshots made in CI and
/// the UI tests, a made-up set held in memory alone (`MoreSample`), never
/// kept.
@MainActor
final class MoreStore: ObservableObject {
    @Published private(set) var chosen: Set<PrivateDetail>
    @Published private(set) var look: CoverStyle
    @Published private(set) var keepsLastDigits: Bool
    @Published private(set) var strongest: Bool
    @Published private(set) var usesIntelligence: Bool
    @Published private(set) var own: OwnSummary
    let intelligenceAvailable: Bool
    /// A sample's: changed in memory, never written anywhere.
    private let inMemory: Bool

    init() {
        #if DEBUG
        if MoreSample.requested {
            chosen = MoreSample.chosen
            look = MoreSample.look
            keepsLastDigits = MoreSample.keepsLastDigits
            strongest = MoreSample.strongest
            usesIntelligence = true
            own = OwnSummary(MoreSample.own)
            intelligenceAvailable = Finder.intelligenceAvailable
            inMemory = true
            return
        }
        #endif
        chosen = Choice.details
        look = CoverStyle.current
        keepsLastDigits = Finder.keepsLastDigits
        strongest = Finder.strongest
        usesIntelligence = Finder.usesIntelligence
        own = OwnSummary(OwnRules.all)
        intelligenceAvailable = Finder.intelligenceAvailable
        inMemory = false
    }

    var summary: CoverSummary { CoverSummary(chosen) }

    /// Apple Intelligence reads along: turned on, where this iPhone has it.
    var intelligenceOn: Bool { usesIntelligence && intelligenceAvailable }

    func choose(_ kinds: Set<PrivateDetail>) {
        chosen = kinds
        if !inMemory { Choice.details = kinds }
    }

    func setLook(_ style: CoverStyle) {
        look = style
        if !inMemory { CoverStyle.current = style }
    }

    func setKeepsLastDigits(_ on: Bool) {
        keepsLastDigits = on
        if !inMemory { Finder.keepsLastDigits = on }
    }

    func setStrongest(_ on: Bool) {
        strongest = on
        if !inMemory { Finder.strongest = on }
    }

    func setUsesIntelligence(_ on: Bool) {
        usesIntelligence = on
        if !inMemory { Finder.usesIntelligence = on }
    }

    /// Read again as More shows, after Always Hide or another page may have
    /// changed what it holds.
    func reload() {
        guard !inMemory else { return }
        chosen = Choice.details
        own = OwnSummary(OwnRules.all)
    }

    /// How long covering took lately, each measure's middle and its slowest
    /// but a few (P50, P95), in milliseconds; nil until a few were covered.
    func timing(_ measure: Timing.Measure) -> (middle: Int, slow: Int)? {
        let times: [Int]
        #if DEBUG
        times = MoreSample.requested ? MoreSample.times(measure) : Timing.recent(measure)
        #else
        times = Timing.recent(measure)
        #endif
        guard let middle = Timing.percentile(times, 0.5), let slow = Timing.percentile(times, 0.95) else { return nil }
        return (middle, slow)
    }

    /// How long the last screenshot took, in milliseconds, once one was covered.
    var lastTime: Int? {
        #if DEBUG
        if MoreSample.requested { return MoreSample.last }
        #endif
        return Timing.last?.milliseconds
    }
}

/// The pages More opens.
enum MorePage: Hashable {
    case covered, alwaysHide, style, detection, assistant, apps, backTap, macAndCloud, preparing
}

/// A page and what opened it: a tile it grows out of, from iOS 18 on, or
/// nothing, for the system's push.
struct MoreRoute: Hashable {
    let page: MorePage
    var source: String?
}

/// For screenshots made in CI and the UI tests: More on made-up choices,
/// held in memory alone, as `-SnapflyMore <state>` asks, maybe on one of its
/// pages; `-SnapflyMoreLook <look>` chooses the cover look,
/// `-SnapflyMoreEnd` opens a page at its end, and `-SnapflyReduceMotion`
/// plays it as Reduce Motion would. Nothing of it is in a release build.
enum MoreSample {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// What was asked for: root, off, all, own, covered, people, style,
    /// strong, digits, detection or mac.
    static let state = value(after: "-SnapflyMore")

    static var requested: Bool { state != nil }

    static let reduceMotion = arguments.contains("-SnapflyReduceMotion")

    /// Where a page opens: at its end with `-SnapflyMoreEnd`, so a frame
    /// shows what is under the fold.
    static var endAnchor: UnitPoint? { arguments.contains("-SnapflyMoreEnd") ? .bottom : nil }

    static var look: CoverStyle { value(after: "-SnapflyMoreLook").flatMap(CoverStyle.init(rawValue:)) ?? .ink }

    static var chosen: Set<PrivateDetail> {
        switch state ?? "" {
        case "off": []
        case "all": Set(PrivateDetail.allCases)
        case "own": PrivateDetail.recommended.subtracting([.otherPeople, .codes]).union([.amounts])
        default: PrivateDetail.recommended
        }
    }

    static var keepsLastDigits: Bool { state == "strong" || state == "digits" }
    static var strongest: Bool { state == "strong" }

    /// The page the sample opens, if any.
    static var page: MorePage? {
        switch state ?? "" {
        case "covered", "people": .covered
        case "style", "strong", "digits": .style
        case "detection": .detection
        case "mac": .macAndCloud
        default: nil
        }
    }

    /// The group What Is Covered shows alone, if any.
    static var group: CoverGroup? { state == "people" ? .people : nil }

    /// Always Hide's made-up name, card and rules.
    static var own: [OwnRule] { [AlwaysHideSample.name, AlwaysHideSample.card] + AlwaysHideSample.rules }

    /// Made-up times, in milliseconds.
    static func times(_ measure: Timing.Measure) -> [Int] {
        switch measure {
        case .shown: [380, 410, 395, 450, 420, 610, 400, 430, 390, 520]
        case .ready: [1050, 1180, 990, 1320, 1240, 1710, 1100, 1150, 1080, 1400]
        }
    }

    static let last = 1120
    #else
    static let requested = false
    static let reduceMotion = false
    static let endAnchor: UnitPoint? = nil
    #endif
}

/// Whether More moves: never with Reduce Motion, as the system has it or a
/// sample asks.
extension EnvironmentValues {
    var moreStill: Bool { accessibilityReduceMotion || MoreSample.reduceMotion }
}
