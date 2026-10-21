import Foundation

/// What Is Covered as a live preview, on the iPhone: three made-up documents
/// in which every kind chosen is covered as it happens, and the groups the
/// switches sit in. Every one of the twenty-two kinds is in at least one
/// document. All of it is fixed and fake; nothing here reads or writes the
/// choice, which stays where it always was (`hiddenDetails`).
enum CoverStudioSample: Int, CaseIterable, Identifiable {
    /// A doctor's bill, with most of the kinds a letter carries.
    case bill
    /// A chat, with a face, a name and what people send.
    case chat
    /// A note of numbers and codes.
    case note

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .bill: L("Doctor’s Bill")
        case .chat: L("Chat")
        case .note: L("Note")
        }
    }

    /// Its fields in reading order, each a value of one kind; the words
    /// around them stay shown.
    var fields: [CoverStudioField] {
        switch self {
        case .bill:
            [.init("bill.doctor", .otherPeople), .init("bill.email", .emails), .init("bill.phone", .phones),
             .init("bill.patient", .patientNames), .init("bill.birth", .birthDates),
             .init("bill.address", .addresses), .init("bill.number", .orders), .init("bill.date", .dates),
             .init("bill.diagnosis", .health), .init("bill.amount", .amounts), .init("bill.iban", .bank),
             .init("bill.link", .links), .init("bill.qr", .barcodes)]
        case .chat:
            [.init("chat.face", .faces), .init("chat.name", .names), .init("chat.phone", .phones),
             .init("chat.parcel", .tracking), .init("chat.user", .usernames), .init("chat.company", .organizations)]
        case .note:
            [.init("note.tax", .ids), .init("note.wifi", .codes), .init("note.key", .keys),
             .init("note.ip", .ipAddresses), .init("note.login", .emails)]
        }
    }

    /// The kinds it shows, in reading order, each once.
    var kinds: [PrivateDetail] {
        var seen = Set<PrivateDetail>()
        return fields.map(\.kind).filter { seen.insert($0).inserted }
    }

    func shows(_ kind: PrivateDetail) -> Bool {
        fields.contains { $0.kind == kind }
    }

    /// How many of its fields a choice covers.
    func covered(by chosen: Set<PrivateDetail>) -> Int {
        fields.filter { chosen.contains($0.kind) }.count
    }

    /// The document a group opens on: the one with most of its fields,
    /// the first of them where two have as many.
    static func showing(_ group: CoverGroup) -> CoverStudioSample {
        let kinds = Set(group.kinds)
        let counts = allCases.map { sample in (sample, sample.fields.filter { kinds.contains($0.kind) }.count) }
        return counts.reduce(counts[0]) { $1.1 > $0.1 ? $1 : $0 }.0
    }

    /// Where a kind turned shows: the document shown, when it has it, else
    /// the first that does.
    static func showing(_ kind: PrivateDetail, from current: CoverStudioSample) -> CoverStudioSample {
        current.shows(kind) ? current : allCases.first { $0.shows(kind) } ?? current
    }
}

/// A value on a sample document, and the kind that covers it.
struct CoverStudioField: Identifiable, Equatable {
    let id: String
    let kind: PrivateDetail

    init(_ id: String, _ kind: PrivateDetail) {
        self.id = id
        self.kind = kind
    }
}

/// A part of a group's sheet: its kinds, under a heading where the group has
/// more than one part, with a note under it where one is needed.
struct CoverGroupSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let kinds: [PrivateDetail]
    var footer: String?
}

extension CoverGroup {
    /// People and Companies in three parts, names, contact and the rest;
    /// the other groups in one.
    var sections: [CoverGroupSection] {
        switch self {
        case .people:
            [CoverGroupSection(id: "names", title: L("Names"), kinds: [.names, .patientNames, .otherPeople],
                               footer: L("Names without a clear role, as in chats. All three together cover everyone’s names.")),
             CoverGroupSection(id: "contact", title: L("Contact"), kinds: [.addresses, .emails, .phones, .usernames]),
             CoverGroupSection(id: "more", title: L("More"), kinds: [.birthDates, .faces, .organizations])]
        default:
            [CoverGroupSection(id: "all", title: nil, kinds: kinds)]
        }
    }

    /// The group's symbol on its tile.
    var symbol: String {
        switch self {
        case .people: "person.2"
        case .money: "creditcard"
        case .health: "heart"
        case .documents: "doc.text"
        case .access: "key"
        }
    }
}

extension PrivateDetail {
    /// The kind's symbol on its row in a group's sheet.
    var symbol: String {
        switch self {
        case .names: "person"
        case .patientNames: "cross.case"
        case .otherPeople: "person.2"
        case .addresses: "house"
        case .emails: "envelope"
        case .phones: "phone"
        case .usernames: "at"
        case .birthDates: "calendar"
        case .faces: "face.smiling"
        case .organizations: "building.2"
        case .bank: "creditcard"
        case .amounts: "eurosign"
        case .health: "heart.text.square"
        case .ids: "person.text.rectangle"
        case .barcodes: "qrcode"
        case .orders: "bag"
        case .tracking: "shippingbox"
        case .dates: "calendar.badge.clock"
        case .links: "link"
        case .codes: "key"
        case .keys: "chevron.left.forwardslash.chevron.right"
        case .ipAddresses: "network"
        }
    }
}

extension CoverSummary {
    /// How a group stands, as its tile says it: all of it, none, or how many.
    enum GroupState: Equatable {
        case all, none
        case some(Int, of: Int)
    }

    func state(of group: CoverGroup) -> GroupState {
        let on = count(in: group)
        if on == 0 { return .none }
        if on == group.kinds.count { return .all }
        return .some(on, of: group.kinds.count)
    }

    /// How much of a group is on, from 0 to 1, for its ring.
    func share(of group: CoverGroup) -> Double {
        Double(count(in: group)) / Double(max(1, group.kinds.count))
    }

    /// "7 von 10", "Alle aktiv" or "Aus", as the tile says it.
    func status(of group: CoverGroup) -> String {
        switch state(of: group) {
        case .all: L("All active")
        case .none: L("Off")
        case let .some(on, total): String(format: L("%d of %d"), on, total)
        }
    }

    /// When each changed kind's cover starts as a preset or a group's
    /// button runs down a document: in its reading order, 25 ms apart, all
    /// of them started within 0.4 s. Kinds the document doesn't show start
    /// at once.
    static func sweep(_ changed: [PrivateDetail], on sample: CoverStudioSample) -> [PrivateDetail: Double] {
        let order = sample.kinds.filter(changed.contains)
        let step = order.count > 1 ? min(0.025, 0.4 / Double(order.count - 1)) : 0
        var delays: [PrivateDetail: Double] = [:]
        for kind in changed { delays[kind] = 0 }
        for (place, kind) in order.enumerated() { delays[kind] = Double(place) * step }
        return delays
    }
}

extension CoverPreset {
    /// Its line in the page's menu.
    var menuTitle: String {
        switch self {
        case .recommended: L("Recommended Selection")
        case .all: L("Turn All On")
        case .none: L("Turn All Off")
        }
    }
}
