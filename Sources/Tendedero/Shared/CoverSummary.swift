import Foundation

/// The kinds chosen, as the iPhone's More tab tells them: how many of the
/// twenty-two, the preset they make if any, and how many in each of the
/// five groups the page shows. The choice itself stays where it always was
/// (`hiddenDetails`); this only reads one and works out the next.
struct CoverSummary: Equatable {
    let chosen: Set<PrivateDetail>

    init(_ chosen: Set<PrivateDetail>) {
        self.chosen = chosen
    }

    /// Every kind there is.
    static let total = PrivateDetail.allCases.count

    var count: Int { chosen.count }

    /// Nothing is covered: More says the protection is off.
    var isOff: Bool { chosen.isEmpty }

    /// The preset the choice is, or nil when it is the owner's own.
    var preset: CoverPreset? { CoverPreset.matching(chosen) }

    /// The preset's name, or that the choice is the owner's own.
    var presetTitle: String { preset?.title ?? L("Your Choice") }

    /// How much of the whole is chosen, from 0 to 1, for a meter.
    var share: Double { Double(count) / Double(Self.total) }

    func count(in group: CoverGroup) -> Int {
        group.kinds.filter(chosen.contains).count
    }

    /// Every kind of the group is on.
    func isWhole(_ group: CoverGroup) -> Bool {
        group.kinds.allSatisfy(chosen.contains)
    }

    /// The choice with every kind of a group on, or every one off; the
    /// other groups as they were.
    func setting(_ group: CoverGroup, on: Bool) -> Set<PrivateDetail> {
        on ? chosen.union(group.kinds) : chosen.subtracting(group.kinds)
    }

    /// The choice with one kind turned the other way, as its switch was.
    func toggling(_ kind: PrivateDetail) -> Set<PrivateDetail> {
        chosen.contains(kind) ? chosen.subtracting([kind]) : chosen.union([kind])
    }

    /// The kinds one choice and another differ in, in the order the page
    /// shows them, so a change can run down them one after another.
    static func changed(from old: Set<PrivateDetail>, to new: Set<PrivateDetail>) -> [PrivateDetail] {
        CoverGroup.allCases.flatMap(\.kinds).filter { old.contains($0) != new.contains($0) }
    }
}

/// The three choices of before, Check All, Recommended and Uncheck All, as
/// one control: they write exactly what those buttons wrote.
enum CoverPreset: String, CaseIterable, Identifiable {
    case recommended, all, none

    var id: String { rawValue }

    var kinds: Set<PrivateDetail> {
        switch self {
        case .recommended: PrivateDetail.recommended
        case .all: Set(PrivateDetail.allCases)
        case .none: []
        }
    }

    var title: String {
        switch self {
        case .recommended: L("Recommended")
        case .all: L("All")
        case .none: L("None")
        }
    }

    /// The preset a choice is exactly; nil for any other.
    static func matching(_ chosen: Set<PrivateDetail>) -> CoverPreset? {
        allCases.first { $0.kinds == chosen }
    }
}

/// The kinds in five groups, as the iPhone's What Is Covered page shows
/// them: People and Companies, Money, Health, Documents and Access. The Mac
/// keeps its six (`PrivateDetail.Group`); these are the same, with the
/// companies beside the people.
enum CoverGroup: CaseIterable, Identifiable {
    case people, money, health, documents, access

    var id: Self { self }

    /// The group's card.
    var title: String {
        switch self {
        case .people: L("People and Companies")
        case .money: L("Money")
        case .health: L("Health")
        case .documents: L("Documents")
        case .access: L("Access")
        }
    }

    /// The group's tab, short.
    var shortTitle: String {
        switch self {
        case .people: L("People")
        case .money: L("Money")
        case .health: L("Health")
        case .documents: L("Documents")
        case .access: L("Access")
        }
    }

    /// Its kinds, in the order the Mac lists them.
    var kinds: [PrivateDetail] {
        switch self {
        case .people: PrivateDetail.Group.people.kinds + PrivateDetail.Group.organizations.kinds
        case .money: PrivateDetail.Group.money.kinds
        case .health: PrivateDetail.Group.health.kinds
        case .documents: PrivateDetail.Group.documents.kinds
        case .access: PrivateDetail.Group.access.kinds
        }
    }

    static func of(_ kind: PrivateDetail) -> CoverGroup {
        switch kind.group {
        case .people, .organizations: .people
        case .money: .money
        case .health: .health
        case .documents: .documents
        case .access: .access
        }
    }
}

/// What Always Hide holds, as More counts it: the owner's details, their
/// rules and how many of those are on, and the initials of their name.
struct OwnSummary: Equatable {
    let details: Int
    let rules: Int
    let activeRules: Int
    /// Up to two letters, like "MM"; nil without a name.
    let initials: String?

    init(_ all: [OwnRule]) {
        let kept = all.filter { !$0.isBlank }
        details = kept.filter(\.kind.isDetail).count
        rules = kept.filter { !$0.kind.isDetail }.count
        activeRules = OwnRules.activeCount(kept)
        initials = kept.first { $0.kind == .name }.flatMap { Self.initials(of: $0.text) }
    }

    /// The first letter of the first given name and of the surname's last
    /// word: "Mustermann, Max" is "MM", "Max van Berg" "MB".
    static func initials(of name: String) -> String? {
        let (given, surname) = OwnDetails.nameParts(name)
        let letters = [given.first, surname.last].compactMap { $0?.first(where: \.isLetter) }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    /// "1 detail · 2 rules", as the Always Hide tile says it.
    var line: String {
        let details = details == 1 ? L("1 detail") : String(format: L("%d details"), details)
        let rules = activeRules == 1 ? L("1 rule") : String(format: L("%d rules"), activeRules)
        return details + " · " + rules
    }
}
