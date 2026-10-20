import CoreGraphics
import Foundation

/// The iPhone's first run: a made-up invoice whose private details are found
/// and covered in front of the owner, then theirs to change, then scanned
/// and made ready to share, as one story of under fifteen seconds. Pure, so
/// the story is checked without a screen: the script says what happens
/// when, the state says what each moment shows, and the categories chosen
/// are the one source of truth for what is covered.
enum FirstRun {
    // MARK: The sample

    /// The categories the first run offers, each a kind of Settings.
    enum Category: String, CaseIterable, Hashable, Sendable {
        case names, emails, bank

        var detail: PrivateDetail {
            switch self {
            case .names: .names
            case .emails: .emails
            case .bank: .bank
            }
        }

        var title: String {
            switch self {
            case .names: L("Names")
            case .emails: L("Emails")
            case .bank: L("Bank details")
            }
        }
    }

    /// A line of the sample invoice: its value, made up, and the category
    /// Snapfly covers it as; none where nothing is private, like the amount.
    struct Field: Identifiable, Equatable, Sendable {
        enum ID: String, CaseIterable, Sendable {
            case name, email, iban, amount
        }

        let id: ID
        let value: String
        let category: Category?
        /// How far down the page it is, from 0 at the top to 1 at the
        /// bottom, so the reading line finds it as it passes.
        let depth: Double

        /// Its label as the invoice prints it.
        var label: String {
            switch id {
            case .name: L("Name")
            case .email: L("Email")
            case .iban: "IBAN"
            case .amount: L("Amount")
            }
        }
    }

    /// The sample's details: a placeholder name, an address at example.com,
    /// the standard example IBAN and an amount. They belong to no one. Which
    /// category covers each is what the engine finds on the invoice
    /// (`FirstRunTests`), so the first run shows nothing it would not do.
    static let fields: [Field] = [
        Field(id: .name, value: "Erika Mustermann", category: .names, depth: 0.35),
        Field(id: .email, value: "erika@example.com", category: .emails, depth: 0.43),
        Field(id: .iban, value: "DE89 3704 0044 0532 0130 00", category: .bank, depth: 0.51),
        Field(id: .amount, value: "149,90 €", category: nil, depth: 0.81),
    ]

    /// The sample page's height for its width: a sheet of A4, standing, as
    /// a printed invoice is.
    static let pageRatio = 297.0 / 210.0

    static func field(_ id: Field.ID) -> Field {
        fields.first { $0.id == id }!
    }

    /// The fields a category covers, in reading order.
    static var privateFields: [Field] { fields.filter { $0.category != nil } }

    // MARK: The story

    /// Where the story is: the reveal, the owner's control, the scanner,
    /// sharing, and the end, where it waits for the owner.
    enum Scene: Int, Comparable, CaseIterable, Sendable {
        case reveal, control, scan, share, complete

        static func < (a: Scene, b: Scene) -> Bool { a.rawValue < b.rawValue }
    }

    /// What is happening to the sample's details.
    enum Phase: String, Sendable {
        /// Readable, before anything is found.
        case initial
        /// Read: the line passes, or the camera looks for the page.
        case detecting
        /// Found, and marked, not yet covered.
        case highlighted
        /// Covers going on.
        case redacting
        /// Everything chosen covered.
        case protected
        /// A cover coming off, as its category was turned off.
        case revealing
        /// The story waits: the owner is trying the categories, or the app
        /// is away.
        case paused
        /// The end, waiting for the owner.
        case complete
    }

    /// The scanner's steps, in the scan scene.
    enum ScanStep: Int, Comparable, Sendable {
        /// Not scanning.
        case none
        /// The page lies before the camera, tipped away.
        case placed
        /// Its edges found.
        case edges
        /// Straightened, as the scanner corrects its perspective.
        case straight
        /// Its words read.
        case reading
        /// Covered.
        case done

        static func < (a: ScanStep, b: ScanStep) -> Bool { a.rawValue < b.rawValue }
    }

    /// Everything a moment of the story shows.
    struct State: Equatable, Sendable {
        var scene = Scene.reveal
        var phase = Phase.initial
        /// The categories chosen: what is covered, once covers are laid.
        var chosen = Set(Category.allCases)
        /// The details found so far.
        var found: Set<Field.ID> = []
        /// The details whose cover has been laid; each shows while its
        /// category is chosen.
        var laid: Set<Field.ID> = []
        var scan = ScanStep.none
        /// The protected shield, once the covers are on.
        var shield = false
        /// Each pass of the reading line, so it sweeps again.
        var sweeps = 0
        /// The owner changed a category: the story changes none for them.
        var tookOver = false

        func isCovered(_ field: Field) -> Bool {
            guard let category = field.category else { return false }
            return laid.contains(field.id) && chosen.contains(category)
        }

        /// Found and marked, while not covered yet.
        func isFound(_ field: Field) -> Bool {
            guard let category = field.category else { return false }
            return found.contains(field.id) && chosen.contains(category) && !laid.contains(field.id)
        }

        /// The shield shows only while something is chosen to cover.
        var showsShield: Bool { shield && !chosen.isEmpty }

        /// The phase to report: the story's own, or paused while it waits.
        func reported(held: Bool) -> Phase {
            held && phase != .complete ? .paused : phase
        }
    }

    /// One thing that happens in the story.
    enum Event: Equatable, Sendable {
        case scene(Scene)
        case phase(Phase)
        case sweep
        case find(Field.ID)
        case lay(Field.ID)
        case shield(Bool)
        case scan(ScanStep)
        /// The story turning a category off or on, while the owner has not.
        case auto(Category, Bool)
        /// A cover has finished moving.
        case settle
    }

    /// An event and when it happens, in seconds from the start.
    struct Beat: Equatable, Sendable {
        let at: Double
        let event: Event

        init(_ at: Double, _ event: Event) {
            self.at = at
            self.event = event
        }
    }

    /// When each scene starts, in seconds.
    static let controlStart = 2.2
    static let scanStart = 6.2
    static let shareStart = 10.4
    static let completeStart = 13.6
    /// How long the reading line takes over the page (`sweep.scan`).
    static let sweep = 0.9
    /// One cover after another (`stagger.demo`).
    static let stagger = 0.17
    /// How long a cover takes to come or go.
    static let settle = 0.35
    /// How long the story waits after the owner's last change.
    static let hold = 2.5

    /// The story, in order. The reveal is over within two seconds; the
    /// owner can change the categories from the control scene on.
    static let script: [Beat] = {
        var beats = [Beat(0.25, .phase(.detecting)), Beat(0.25, .sweep)]
        beats += privateFields.map { Beat(0.25 + sweep * $0.depth, .find($0.id)) }
        beats.append(Beat(1.15, .phase(.highlighted)))
        beats.append(Beat(1.3, .phase(.redacting)))
        beats += privateFields.enumerated().map { Beat(1.3 + stagger * Double($0.offset), .lay($0.element.id)) }
        beats += [Beat(1.85, .shield(true)), Beat(1.85, .phase(.protected))]
        // The owner's control: the names come off and go on again, shown
        // as a tap would do it, unless the owner tries it first.
        beats.append(Beat(controlStart, .scene(.control)))
        beats += [Beat(3.4, .auto(.names, false)), Beat(3.4 + settle, .settle),
                  Beat(4.8, .auto(.names, true)), Beat(4.8 + settle, .settle)]
        // The scanner: the page placed, its edges found, straightened, read
        // and covered as chosen.
        beats.append(Beat(scanStart, .scene(.scan)))
        beats += [Beat(6.8, .scan(.edges)), Beat(7.6, .scan(.straight)), Beat(8.2, .scan(.reading)), Beat(8.2, .sweep)]
        beats += privateFields.map { Beat(8.2 + sweep * $0.depth, .find($0.id)) }
        beats.append(Beat(9.2, .phase(.highlighted)))
        beats.append(Beat(9.35, .phase(.redacting)))
        beats += privateFields.enumerated().map { Beat(9.35 + stagger * Double($0.offset), .lay($0.element.id)) }
        beats += [Beat(9.9, .scan(.done)), Beat(9.9, .shield(true)), Beat(9.9, .phase(.protected))]
        beats.append(Beat(shareStart, .scene(.share)))
        beats.append(Beat(completeStart, .scene(.complete)))
        return beats
    }()

    /// What an event does to the state.
    static func apply(_ event: Event, to state: inout State) {
        switch event {
        case .scene(let scene):
            state.scene = scene
            switch scene {
            case .scan:
                // The page as the camera sees it: printed, nothing found yet.
                state.found = []
                state.laid = []
                state.shield = false
                state.scan = .placed
                state.phase = .initial
            case .complete:
                state.phase = .complete
            case .reveal, .control, .share:
                break
            }
        case .phase(let phase):
            guard state.phase != .complete else { return }
            state.phase = phase
        case .sweep:
            state.sweeps += 1
        case .find(let id):
            state.found.insert(id)
        case .lay(let id):
            state.laid.insert(id)
        case .shield(let on):
            state.shield = on
        case .scan(let step):
            state.scan = step
            if step == .edges { state.phase = .detecting }
        case .auto(let category, let on):
            guard !state.tookOver else { return }
            set(category, on, in: &state)
        case .settle:
            if state.phase == .revealing || state.phase == .redacting { state.phase = .protected }
        }
    }

    /// The owner turns a category on or off; from then on the story leaves
    /// the categories to them.
    static func toggle(_ category: Category, in state: inout State) {
        state.tookOver = true
        set(category, !state.chosen.contains(category), in: &state)
    }

    private static func set(_ category: Category, _ on: Bool, in state: inout State) {
        if on { state.chosen.insert(category) } else { state.chosen.remove(category) }
        // A cover moves only where one is laid.
        guard state.phase != .complete,
              fields.contains(where: { $0.category == category && state.laid.contains($0.id) }) else { return }
        state.phase = on ? .redacting : .revealing
    }

    /// The story at a moment, as if left alone.
    static func state(at time: Double) -> State {
        var state = State()
        for beat in script where beat.at <= time {
            apply(beat.event, to: &state)
        }
        return state
    }

    // MARK: The scanner's perspective

    /// The page as the camera first sees it, lying tipped away: its corners
    /// as parts of its width and height, from the top left, clockwise.
    static let tipped = [CGPoint(x: 0.12, y: 0.07), CGPoint(x: 0.9, y: 0.02),
                         CGPoint(x: 1, y: 0.97), CGPoint(x: 0, y: 1)]
    /// The page straightened.
    static let flat = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

    /// The corners on the way from tipped to straight, `progress` from 0 to 1.
    static func corners(straightened progress: Double) -> [CGPoint] {
        let t = CGFloat(min(max(progress, 0), 1))
        return zip(tipped, flat).map { from, to in
            CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    /// The projective transform taking a rectangle of `size`, from its top
    /// left, to the four `corners` (top left, top right, bottom right,
    /// bottom left), as a 3 by 3 matrix row by row, for points as columns.
    static func homography(_ size: CGSize, to corners: [CGPoint]) -> [Double] {
        guard corners.count == 4, size.width > 0, size.height > 0 else { return [1, 0, 0, 0, 1, 0, 0, 0, 1] }
        let x = corners.map { Double($0.x) }, y = corners.map { Double($0.y) }
        let dx1 = x[1] - x[2], dx2 = x[3] - x[2], dx3 = x[0] - x[1] + x[2] - x[3]
        let dy1 = y[1] - y[2], dy2 = y[3] - y[2], dy3 = y[0] - y[1] + y[2] - y[3]
        let det = dx1 * dy2 - dx2 * dy1
        let g = det == 0 ? 0 : (dx3 * dy2 - dx2 * dy3) / det
        let h = det == 0 ? 0 : (dx1 * dy3 - dx3 * dy1) / det
        let a = x[1] - x[0] + g * x[1], b = x[3] - x[0] + h * x[3], c = x[0]
        let d = y[1] - y[0] + g * y[1], e = y[3] - y[0] + h * y[3], f = y[0]
        // From the unit square to the corners, after the rectangle is made one.
        let w = Double(size.width), v = Double(size.height)
        return [a / w, b / v, c, d / w, e / v, f, g / w, h / v, 1]
    }

    /// Where a point goes under a homography.
    static func project(_ point: CGPoint, by matrix: [Double]) -> CGPoint {
        let px = Double(point.x), py = Double(point.y)
        let w = matrix[6] * px + matrix[7] * py + matrix[8]
        return CGPoint(x: (matrix[0] * px + matrix[1] * py + matrix[2]) / w,
                       y: (matrix[3] * px + matrix[4] * py + matrix[5]) / w)
    }

    /// The invoice as text, label and value, the way the engine reads a
    /// page: for the tests that hold the sample to what the engine finds.
    static func lines(title: String = "Rechnung", labels: [Field.ID: String] = [
        .name: "Name:", .email: "E-Mail:", .iban: "IBAN:", .amount: "Betrag:",
    ]) -> [String] {
        [title] + fields.map { "\(labels[$0.id] ?? "") \($0.value)" }
    }
}
