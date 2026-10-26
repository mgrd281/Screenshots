import AppKit
import SwiftUI

// MARK: - What the introduction is made of

/// What a step of the introduction points at, on the screen as it is now.
enum GuideTarget: Equatable {
    case none
    /// Snapfly's icon in the menu bar.
    case menuBarIcon
    /// The newest photo on the line.
    case newestPhoto
    /// The lock on the newest photo.
    case lock
    /// The newest photo with the row of icons under it.
    case icons
    /// The pick circle on the newest photo.
    case pickCircle
    /// The tag at the end of the line.
    case tag

    /// On the line, which then stays down while it is pointed at.
    var onLine: Bool { self != .none && self != .menuBarIcon }

    /// The corners of what it points at, which the hole round it follows.
    var corner: CGFloat {
        switch self {
        case .none: 0
        case .menuBarIcon: 6
        case .newestPhoto, .icons: Frame.radius
        case .lock, .pickCircle: 14
        case .tag: Layout.tagWidth / 2
        }
    }
}

/// Something done on the real thing, which can see a step through.
enum GuideEvent: Hashable {
    /// The menu bar icon's menu opened and closed again.
    case menuBarMenu
    /// A photo came onto the line.
    case photoHung
    /// A photo was copied, picked or sent.
    case photoUsed
    /// A photo's menu opened and closed again.
    case photoMenu
}

/// One step: what it points at, what it says, and what sees it through.
struct GuideStep: Identifiable, Equatable {
    /// What must be there for a step to make sense. Without it, the step
    /// is skipped.
    enum Need: Equatable {
        case photo
        case coveredPhoto
        case iconsUnderPhotos
        case twoPhotos
    }

    /// A button that does what the step asks, like taking the screenshot.
    struct Action: Equatable {
        enum Kind: Equatable { case takeScreenshot }
        let title: String
        let symbol: String
        let kind: Kind
    }

    let id: String
    let target: GuideTarget
    let symbol: String
    let title: String
    let text: String
    /// Done on the real thing, the step moves on by itself.
    var completes: Set<GuideEvent> = []
    /// Resting the pointer on what it points at moves on too.
    var rests = false
    var needs: Need?
    /// The screen dims round what it points at; not while a screenshot is
    /// taken, so the picture stays as it is.
    var dims = true
    var action: Action?

    /// It waits for something done on the real thing, rather than for Next.
    var waits: Bool { !completes.isEmpty || rests }

    /// The introduction, in order: where Snapfly lives, the first screenshot,
    /// and what to do with it on the line.
    /// - Parameters:
    ///   - capture: Snapfly's own screenshot shortcut, as macOS writes it.
    ///   - appStore: the App Store edition, which sees only its own
    ///     screenshots, not those of ⇧⌘4.
    static func introduction(capture: String?, appStore: Bool) -> [GuideStep] {
        let screenshot: String
        switch (appStore, capture) {
        case (false, let shortcut?):
            screenshot = String(format: L("Press ⇧⌘4 and drag over an area, or use Snapfly's own shortcut, %@. It hangs on the line at once."), shortcut)
        case (false, nil):
            screenshot = L("Press ⇧⌘4 and drag over an area. It hangs on the line at once.")
        case (true, let shortcut?):
            screenshot = String(format: L("Press %@ and drag over an area. It hangs on the line at once."), shortcut)
        case (true, nil):
            screenshot = L("Click Take Screenshot and drag over an area. It hangs on the line at once.")
        }
        return [
            GuideStep(id: "menuBar", target: .menuBarIcon, symbol: "menubar.rectangle",
                      title: L("Snapfly lives in the menu bar"),
                      text: L("Click its icon: screenshots, the line, Settings and this introduction are all there."),
                      completes: [.menuBarMenu]),
            GuideStep(id: "screenshot", target: .none, symbol: "camera.viewfinder",
                      title: L("Take a screenshot"), text: screenshot,
                      completes: [.photoHung], dims: false,
                      action: Action(title: L("Take Screenshot"), symbol: "camera.viewfinder", kind: .takeScreenshot)),
            GuideStep(id: "photo", target: .newestPhoto, symbol: "cursorarrow.click",
                      title: L("It hangs on the line"),
                      text: L("Click it and it is copied, ready to paste into any chat. Or drag it straight into one."),
                      completes: [.photoUsed], needs: .photo),
            GuideStep(id: "covered", target: .lock, symbol: "lock.fill",
                      title: L("Private details are covered"),
                      text: L("Names, addresses, bank details and more go out covered. Rest the pointer on the lock to see where."),
                      rests: true, needs: .coveredPhoto),
            GuideStep(id: "chats", target: .icons, symbol: "paperplane",
                      title: L("Into a chat in one click"),
                      text: L("Rest the pointer on the photo: the icons under it send it to ChatGPT, Claude, WhatsApp or your mail."),
                      rests: true, needs: .iconsUnderPhotos),
            GuideStep(id: "menu", target: .newestPhoto, symbol: "contextualmenu.and.cursorarrow",
                      title: L("More in its menu"),
                      text: L("Right-click the photo to crop it, hide a part, draw on it, translate its words and more."),
                      completes: [.photoMenu], needs: .photo),
            GuideStep(id: "tag", target: .tag, symbol: "tag",
                      title: L("Everything at once"),
                      text: L("At the end of the line: search your screenshots, paste or download them all, or take them all down."),
                      needs: .photo),
        ]
    }
}

/// One thing at a time, from Help & Introduction: a step or two of the
/// introduction, on the line as it is.
enum GuideLesson: String, CaseIterable, Identifiable {
    case screenshot, covered, chats, menu, tag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshot: L("Taking a Screenshot")
        case .covered: L("What Gets Covered")
        case .chats: L("Sending into a Chat")
        case .menu: L("A Photo's Menu")
        case .tag: L("The Tag at the End of the Line")
        }
    }

    /// The introduction's steps it shows.
    var steps: [String] {
        switch self {
        case .screenshot: ["screenshot", "photo"]
        case .covered: ["covered"]
        case .chats: ["chats"]
        case .menu: ["menu"]
        case .tag: ["tag"]
        }
    }
}

/// A hint the first time something is in reach, pointing at it. Each shows
/// once, and not at all once the introduction has shown it.
enum GuideTip: String, CaseIterable {
    case lock, pick

    var target: GuideTarget {
        switch self {
        case .lock: .lock
        case .pick: .pickCircle
        }
    }

    var needs: GuideStep.Need {
        switch self {
        case .lock: .coveredPhoto
        case .pick: .twoPhotos
        }
    }

    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .pick: "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .lock: L("Covered before it leaves")
        case .pick: L("Several at once")
        }
    }

    var text: String {
        switch self {
        case .lock: L("Rest the pointer on the lock to see what was covered, and where.")
        case .pick: L("Click the circle on each photo, or ⌘-click, to send or copy just those together.")
        }
    }

    /// The introduction's step that already teaches it.
    var taughtBy: String? {
        switch self {
        case .lock: "covered"
        case .pick: nil
        }
    }
}

// MARK: - Running it

/// The introduction: it points at the real thing on the screen, the menu
/// bar icon, a photo on the line, its lock, its icons and the tag, with
/// the screen dimmed round it and a card beside it saying what it is and
/// what to try. Doing it moves on by itself; Next, Back and the cross are
/// always there, and nothing on the screen is held back meanwhile. It is
/// offered once at launch, goes on from where it was ended, and shows one
/// thing at a time from Help & Introduction. Tips point at something the
/// first time it is in reach.
@MainActor
final class Guide {
    static let shared = Guide()

    /// The introduction's version. A newer one is offered once more at
    /// launch, also to whoever saw an older one.
    static let version = 1

    // MARK: What the app delegate tells it

    /// Where something is on the screen right now, in the screen's
    /// coordinates; nil while it is not showing.
    var frame: (GuideTarget) -> CGRect? = { _ in nil }
    /// Whether what a step needs is there, like a photo with something covered.
    var has: (GuideStep.Need) -> Bool = { _ in false }
    /// Why what a step needs is not there, in a note's words, like the
    /// newest photo having nothing covered; nil when it cannot be told.
    var lacks: (GuideStep.Need) -> String? = { _ in nil }
    /// Keeps the line down while a step points at it, and lets it go after.
    var holdLine: (Bool) -> Void = { _ in }
    /// The screen the line hangs on.
    var screen: () -> NSScreen? = { NSScreen.main }

    // MARK: Settings

    private static let tipsOffKey = "guideTipsOff"
    private static let tipsShownKey = "guideTipsShown"

    /// Tips while you work, from Settings › Support. On unless turned off.
    static var tipsOn: Bool {
        get { !UserDefaults.standard.bool(forKey: tipsOffKey) }
        set { UserDefaults.standard.set(!newValue, forKey: tipsOffKey) }
    }

    private static var tipsShown: [String] {
        get { UserDefaults.standard.stringArray(forKey: tipsShownKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: tipsShownKey) }
    }

    /// Changes when the introduction starts, moves on or ends, for
    /// Settings to say where it stands.
    static let changed = Notification.Name("guideChanged")

    /// Where it stands, as kept.
    static var progress: GuideProgress { GuideProgress.load() }

    // MARK: State

    private enum Stage: Equatable {
        case welcome
        case step(String)
        case done
        case tip(GuideTip)
    }

    private var stage: Stage?
    private var steps: [GuideStep] = []
    private var lesson: GuideLesson?
    private var then: (() -> Void)?

    private let shade = GuideShadeModel()
    private let card = GuideCardModel()
    private var shadePanel: GuidePanel?
    private var cardPanel: GuidePanel?
    private var cardHost: NSHostingController<GuideCardView>?
    private var timer: Timer?
    private var restingSince: Date?
    private var missingSince: Date?
    /// The check shows on a step seen through, before the next.
    private var seeingThrough = false
    /// Hidden while something else of Snapfly's takes the screen, like
    /// Crop, or during a call.
    private var paused = false
    /// The card glides to a new place; until then it is not moved again.
    private var glidingUntil = Date.distantPast
    private var cardHeight: CGFloat = 0
    private var shownOn: NSScreen?

    /// A step, a card or a tip shows, so the line and tips know.
    var isRunning: Bool { stage != nil }

    private init() {
        card.start = { [weak self] in self?.begin() }
        card.skip = { [weak self] in self?.skip() }
        card.next = { [weak self] in self?.next() }
        card.back = { [weak self] in self?.back() }
        card.end = { [weak self] in self?.end() }
        card.act = { [weak self] kind in self?.act(kind) }
        card.stopTips = { [weak self] in
            Guide.tipsOn = false
            self?.close()
        }
    }

    // MARK: Starting

    /// Not yet offered on this Mac, or a newer introduction is.
    var offersAtLaunch: Bool { GuideProgress.load().offers(version: Self.version) }

    /// At launch: the welcome card, with Start Introduction and Skip for
    /// Now. What comes after, like the question about screenshots, waits
    /// until it is gone.
    func offer(then: (() -> Void)? = nil) {
        var progress = GuideProgress.load()
        progress.version = Self.version
        progress.save()
        steps = Self.introductionSteps
        lesson = nil
        self.then = then
        show(.welcome, focus: true)
    }

    /// From the menu bar or Settings: on from where it was ended, or from
    /// the beginning.
    func startIntroduction() {
        var progress = GuideProgress.load()
        let from = progress.canContinue ? progress.stoppedAt : nil
        progress.version = max(progress.version, Self.version)
        progress.restart()
        progress.save()
        steps = Self.introductionSteps
        lesson = nil
        then = nil
        // Without a photo to go on with, it goes on at the screenshot.
        let first = GuideFlow.resume(from: from, in: ids, shows: shows) ?? "screenshot"
        show(.step(first), focus: true)
    }

    /// One thing, from Help & Introduction. It needs a photo on the line,
    /// unless it starts with the screenshot; without what it shows, a note
    /// says why.
    func show(_ lesson: GuideLesson) {
        if let missing = missing(for: lesson) {
            Notice.show(missing)
            return
        }
        steps = Self.introductionSteps.filter { lesson.steps.contains($0.id) }
        self.lesson = lesson
        then = nil
        guard let first = GuideFlow.step(after: nil, in: ids, shows: shows) else { return }
        show(.step(first), focus: true)
    }

    /// Why a lesson has nothing to show on the line as it is, in a note's
    /// words: no photo yet, or none with what it points at, like the lock.
    /// Nil when one of its steps can show.
    func missing(for lesson: GuideLesson) -> String? {
        let needs = Self.introductionSteps.filter { lesson.steps.contains($0.id) }.map(\.needs)
        guard !needs.contains(where: { $0.map(has) ?? true }) else { return nil }
        // Only a missing photo is for taking a screenshot.
        guard has(.photo) else { return L("Take a screenshot first: this shows on a photo on the line.") }
        return needs.compactMap { $0.flatMap(lacks) }.first
    }

    private static var introductionSteps: [GuideStep] {
        GuideStep.introduction(capture: Shortcut.current(.capture)?.display, appStore: Edition.appStore)
    }

    // MARK: What happens on the real thing

    /// Something done on the line or in the menu bar, which may see the
    /// step showing through.
    func happened(_ event: GuideEvent) {
        // Even while it steps aside: the screenshot hangs as Crop fades.
        guard case .step(let id) = stage, !seeingThrough,
              let step = steps.first(where: { $0.id == id }), step.completes.contains(event) else { return }
        seeThrough(step)
    }

    /// The line came down on purpose: a tip, if one is due and in reach.
    func lineCameDown() {
        guard stage == nil, Self.tipsOn, !offersAtLaunch, !Calls.shared.keepingAway else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.offerTip()
        }
    }

    private func offerTip() {
        guard stage == nil, Self.tipsOn else { return }
        let shown = Self.tipsShown
        let seen = GuideProgress.load().seen
        guard let tip = GuideTip.allCases.first(where: { tip in
            !shown.contains(tip.rawValue) && !(tip.taughtBy.map(seen.contains) ?? false)
                && has(tip.needs) && frame(tip.target) != nil
        }) else { return }
        // Once, even if it is gone before it is read.
        Self.tipsShown = shown + [tip.rawValue]
        steps = []
        lesson = nil
        then = nil
        show(.tip(tip), focus: false)
    }

    // MARK: Moving through it

    private var ids: [String] { steps.map(\.id) }

    private func shows(_ id: String) -> Bool {
        guard let step = steps.first(where: { $0.id == id }) else { return false }
        return step.needs.map(has) ?? true
    }

    private func begin() {
        guard let first = GuideFlow.step(after: nil, in: ids, shows: shows) else { return close() }
        go(to: first)
    }

    private func next() {
        guard case .step(let id) = stage else { return }
        note(seen: id)
        if let following = GuideFlow.step(after: id, in: ids, shows: shows) {
            go(to: following)
        } else {
            finish()
        }
    }

    private func back() {
        guard case .step(let id) = stage, let before = GuideFlow.step(before: id, in: ids, shows: shows) else { return }
        go(to: before)
    }

    /// Done on the real thing: a check for a moment, then the next step.
    private func seeThrough(_ step: GuideStep) {
        seeingThrough = true
        card.passed = true
        note(seen: step.id)
        announce(L("Done."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, case .step(let id) = self.stage, id == step.id else { return }
            self.next()
        }
    }

    private func go(to id: String) {
        guard let step = steps.first(where: { $0.id == id }) else { return }
        stage = .step(id)
        seeingThrough = false
        restingSince = nil
        missingSince = nil
        card.passed = false
        holdLine(step.target.onLine)
        if lesson == nil {
            var progress = GuideProgress.load()
            progress.stoppedAt = id
            progress.save()
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
        render()
    }

    /// The last card of the introduction, at the menu bar icon: where to
    /// find it all again.
    private func finish() {
        guard lesson == nil else { return close() }
        var progress = GuideProgress.load()
        progress.finished = true
        progress.stoppedAt = nil
        progress.save()
        NotificationCenter.default.post(name: Self.changed, object: nil)
        holdLine(false)
        stage = .done
        render()
    }

    /// The cross or Escape: ended where it is, to go on from there later.
    private func end() {
        let early: Bool
        if case .step = stage, lesson == nil { early = true } else { early = false }
        close()
        if early {
            Notice.show(L("Continue any time from Snapfly's menu, under Continue Introduction."), lasting: 6)
        }
    }

    /// Skip for Now, on the welcome card.
    private func skip() {
        close()
        Notice.show(L("The introduction waits in Snapfly's menu, whenever you want it."), lasting: 6)
    }

    private func act(_ kind: GuideStep.Action.Kind) {
        switch kind {
        case .takeScreenshot:
            // Snapfly's own screenshot leaves its windows out of the picture.
            Capture.shared.start(after: 0.2)
        }
    }

    private func note(seen id: String) {
        var progress = GuideProgress.load()
        progress.see(id)
        progress.save()
    }

    // MARK: Showing and hiding

    private func show(_ stage: Stage, focus: Bool) {
        let first = self.stage == nil
        self.stage = stage
        seeingThrough = false
        restingSince = nil
        missingSince = nil
        paused = false
        if case .step(let id) = stage, let step = steps.first(where: { $0.id == id }) {
            holdLine(step.target.onLine)
            if lesson == nil {
                var progress = GuideProgress.load()
                progress.stoppedAt = id
                progress.save()
            }
        }
        makePanels()
        render()
        if first, let shadePanel, let cardPanel {
            shadePanel.alphaValue = 1
            cardPanel.alphaValue = 0
            shadePanel.orderFrontRegardless()
            cardPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                cardPanel.animator().alphaValue = 1
            }
            // Return, Escape and the arrows work at once; a tip leaves the
            // keyboard where it is.
            if focus { cardPanel.makeKey() }
            startTicking()
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// Everything away: the shade, the card and the line held down.
    func close() {
        guard stage != nil else { return }
        stage = nil
        lesson = nil
        timer?.invalidate()
        timer = nil
        paused = false
        cardPanel?.ignoresMouseEvents = false
        holdLine(false)
        shade.shown = false
        let panels = [shadePanel, cardPanel].compactMap { $0 }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            for panel in panels { panel.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                // Unless it was shown again meanwhile.
                guard Guide.shared.stage == nil else { return }
                for panel in panels { panel.orderOut(nil) }
            }
        })
        NotificationCenter.default.post(name: Self.changed, object: nil)
        let then = self.then
        self.then = nil
        if let then {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { then() }
        }
    }

    private func makePanels() {
        if shadePanel == nil {
            let panel = GuidePanel(interactive: false)
            let host = NSHostingView(rootView: GuideShadeView(model: shade))
            host.sizingOptions = []
            panel.contentView = host
            shadePanel = panel
        }
        if cardPanel == nil {
            let host = NSHostingController(rootView: GuideCardView(model: card))
            host.sizingOptions = []
            let panel = GuidePanel(interactive: true)
            panel.contentViewController = host
            panel.setContentSize(NSSize(width: GuideCard.windowWidth, height: 200))
            // Invisible until it has its place and fades in.
            panel.alphaValue = 0
            cardHost = host
            cardPanel = panel
        }
    }

    /// The card says what the stage is about; the shade and the card go
    /// where it points.
    private func render() {
        guard let stage else { return }
        switch stage {
        case .welcome:
            card.content = .welcome
        case .step(let id):
            guard let step = steps.first(where: { $0.id == id }) else { return }
            // Before the first screenshot hangs, the steps that need a photo
            // are still to come, so they count.
            let comingSoon = !has(.photo) && ids.contains("screenshot")
            let place = GuideFlow.place(of: id, in: ids) { other in
                self.shows(other) || (comingSoon && self.steps.first(where: { $0.id == other })?.needs == .photo)
            }
            let canGoBack = GuideFlow.step(before: id, in: ids, shows: shows) != nil
            card.content = .step(step, number: place?.number ?? 1, count: place?.count ?? 1,
                                 canGoBack: canGoBack, lesson: lesson != nil)
            announce([String(format: L("Step %1$d of %2$d"), place?.number ?? 1, place?.count ?? 1),
                      step.title, step.text].joined(separator: ". "))
        case .done:
            card.content = .done
            announce(L("You're all set") + ". " + doneText)
        case .tip(let tip):
            card.content = .tip(tip)
            announce(tip.title + ". " + tip.text)
        }
        card.doneText = doneText
        card.revision += 1
        measure()
        // The new words lay out first, then the card moves to its place.
        DispatchQueue.main.async { [weak self] in
            self?.measure()
            self?.place(gliding: true)
        }
        place(gliding: true)
    }

    private var doneText: String {
        String(format: L("Find it again any time in Snapfly's menu, and one thing at a time in %@."),
               [L("Settings"), L("Support")].joined(separator: " › "))
    }

    private func measure() {
        guard let cardHost else { return }
        let size = cardHost.sizeThatFits(in: CGSize(width: GuideCard.windowWidth, height: 2000))
        cardHeight = ceil(size.height)
    }

    // MARK: Following what it points at

    private func startTicking() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Menus run their own loop: the timer goes on while one is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var target: GuideTarget {
        switch stage {
        case .step(let id): steps.first(where: { $0.id == id })?.target ?? .none
        case .done: .menuBarIcon
        case .tip(let tip): tip.target
        case .welcome, nil: .none
        }
    }

    private func tick() {
        guard let stage else { return }
        let now = Date()
        let busy = somethingElseTakesTheScreen() || Calls.shared.keepingAway
        if busy != paused {
            paused = busy
            for panel in [shadePanel, cardPanel] {
                panel?.animator().alphaValue = busy ? 0 : 1
            }
        }
        // Only the card itself takes clicks: its clear margin, round the
        // arrow and the shadow, lets them through to what it points at.
        if let cardPanel {
            let body = cardPanel.frame.insetBy(dx: GuideCard.margin - GuideCardShape.arrowLength,
                                               dy: GuideCard.margin - GuideCardShape.arrowLength)
            let ignore = paused || !body.contains(NSEvent.mouseLocation)
            if cardPanel.ignoresMouseEvents != ignore { cardPanel.ignoresMouseEvents = ignore }
        }
        guard !paused else { return }

        let rect = target == .none ? nil : frame(target)
        if target != .none && rect == nil {
            let since = missingSince ?? now
            missingSince = since
            // Only what is on the line can go: the photo taken down, or the
            // line kept up by a full screen app.
            if target.onLine && now.timeIntervalSince(since) > 1.5 { lost() }
        } else {
            missingSince = nil
        }
        place(gliding: false)

        guard case .step(let id) = stage, !seeingThrough,
              let step = steps.first(where: { $0.id == id }), step.rests, let rect else {
            restingSince = nil
            return
        }
        if rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
            let since = restingSince ?? now
            restingSince = since
            if now.timeIntervalSince(since) >= 0.8 { seeThrough(step) }
        } else {
            restingSince = nil
        }
    }

    /// What a step pointed at is gone. Without a photo on the line, back
    /// to taking one; with one, on to the next step. A tip just goes.
    private func lost() {
        missingSince = nil
        switch stage {
        case .tip:
            close()
        case .step(let id):
            if !has(.photo) {
                if lesson == nil, steps.contains(where: { $0.id == "screenshot" }) {
                    go(to: "screenshot")
                } else {
                    close()
                    Notice.show(L("Take a screenshot first: this shows on a photo on the line."))
                }
            } else if let following = GuideFlow.step(after: id, in: ids, shows: shows) {
                go(to: following)
            } else {
                finish()
            }
        default:
            break
        }
    }

    /// Crop, a screenshot being taken, a dialog or a window of Snapfly's in
    /// front: the introduction steps aside until it is gone.
    private func somethingElseTakesTheScreen() -> Bool {
        NSApp.windows.contains { window in
            // A flight over the screen lets every click through: not a window.
            guard window.isVisible, !(window is GuidePanel), window.alphaValue > 0.01,
                  !window.ignoresMouseEvents else { return false }
            if window.styleMask.contains(.titled) { return window.isKeyWindow }
            guard let screen = window.screen else { return false }
            return window.frame.width >= screen.frame.width - 1 && window.frame.height >= screen.frame.height - 1
        }
    }

    /// The shade's hole round what is pointed at, and the card beside it,
    /// on the screen it is on.
    private func place(gliding: Bool) {
        guard let stage, let shadePanel, let cardPanel else { return }
        let rect = target == .none ? nil : frame(target)
        let screen = rect.flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        } ?? self.screen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let full = screen.frame
        if shownOn != screen || shadePanel.frame != full {
            shownOn = screen
            shadePanel.setFrame(full, display: true)
        }
        // From the screen's top left, as the views draw.
        func down(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - full.minX, y: full.maxY - r.maxY, width: r.width, height: r.height)
        }

        let dims: Bool
        switch stage {
        case .welcome: dims = true
        case .step(let id): dims = (steps.first(where: { $0.id == id })?.dims ?? true) && rect != nil
        case .done: dims = rect != nil
        case .tip: dims = false
        }
        if let rect {
            let hole = GuidePlacement.hole(around: down(rect), corner: target.corner)
            if shade.hole.map({ !Self.near($0, hole.rect) }) ?? true || shade.corner != hole.corner {
                shade.hole = hole.rect
                shade.corner = hole.corner
            }
        } else if shade.hole != nil {
            shade.hole = nil
        }
        if shade.shown != dims { shade.shown = dims }

        guard gliding || Date() >= glidingUntil else { return }
        let size = CGSize(width: GuideCard.width, height: max(40, cardHeight - GuideCard.margin * 2))
        // Pointing at nothing, it sits under where the line hangs.
        let top = Layout.panelHeight + Layout.drop + 4
        let placed = GuidePlacement.place(size, at: rect.map(down), in: down(screen.visibleFrame), gap: 14,
                                          margin: 12, top: top)
        if card.side != placed.side { card.side = placed.side }
        if abs(card.arrow - placed.arrow) > 0.5 { card.arrow = placed.arrow }
        let frame = CGRect(x: full.minX + placed.frame.minX - GuideCard.margin,
                           y: full.maxY - placed.frame.maxY - GuideCard.margin,
                           width: GuideCard.windowWidth, height: size.height + GuideCard.margin * 2)
        guard !Self.near(frame, cardPanel.frame) else { return }
        if gliding && cardPanel.alphaValue > 0 && !Motion.reduced {
            glidingUntil = Date().addingTimeInterval(0.32)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                cardPanel.animator().setFrame(frame, display: true)
            }
        } else {
            cardPanel.setFrame(frame, display: true)
        }
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

// MARK: - The windows

/// The introduction's two windows, over the line and the menu bar and under
/// menus: the shade over the screen, which every click goes through, and
/// the card, which takes its own clicks and, once clicked or opened on
/// purpose, the keyboard, without bringing Snapfly to the front.
final class GuidePanel: NSPanel {
    private let interactive: Bool

    init(interactive: Bool) {
        self.interactive = interactive
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (interactive ? 2 : 1))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = !interactive
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        // Out of what a call shares, like the rest of Snapfly's windows.
        Calls.shared.keepOffSharedScreens(self)
    }

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }
}

// MARK: - The shade

@MainActor
final class GuideShadeModel: ObservableObject {
    /// The hole round what is pointed at, from the screen's top left.
    @Published var hole: CGRect?
    @Published var corner: CGFloat = 12
    @Published var shown = false
}

/// The screen dimmed round what is pointed at, which shows through a hole
/// with an accent edge. The hole glides from one thing to the next.
struct GuideShadeView: View {
    @ObservedObject var model: GuideShadeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Where the hole last was, so a new one glides from there.
    @State private var last = CGRect.zero

    var body: some View {
        let hole = model.hole ?? last
        ZStack(alignment: .topLeading) {
            GuideShade(hole: hole, corner: model.corner, open: model.hole != nil)
                .fill(Color.black.opacity(contrast == .increased ? 0.5 : 0.38), style: FillStyle(eoFill: true))
            if model.hole != nil {
                RoundedRectangle(cornerRadius: model.corner, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.shown ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: model.shown)
        .animation(Motion.spring(response: 0.45, damping: 0.86, reduced: reduceMotion), value: model.hole)
        .onChange(of: model.hole) { _, now in if let now { last = now } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The card

enum GuideCard {
    static let width: CGFloat = 340
    /// Clear room round the card for its shadow and its arrow.
    static let margin: CGFloat = 28
    static var windowWidth: CGFloat { width + margin * 2 }
}

@MainActor
final class GuideCardModel: ObservableObject {
    enum Content: Equatable {
        case welcome
        case step(GuideStep, number: Int, count: Int, canGoBack: Bool, lesson: Bool)
        case done
        case tip(GuideTip)
    }

    @Published var content = Content.welcome
    /// The step was seen through: a check for a moment.
    @Published var passed = false
    @Published var side = GuidePlacement.Side.none
    @Published var arrow: CGFloat = 0
    /// Each new card, so the view lays out its words again.
    @Published var revision = 0
    var doneText = ""

    var start: () -> Void = {}
    var skip: () -> Void = {}
    var next: () -> Void = {}
    var back: () -> Void = {}
    var end: () -> Void = {}
    var act: (GuideStep.Action.Kind) -> Void = { _ in }
    var stopTips: () -> Void = {}
}

/// A floating card in the system's material, its arrow on the edge facing
/// what it points at: a symbol and a title, a line or two, how far along
/// it is, and Back and Next.
struct GuideCardView: View {
    @ObservedObject var model: GuideCardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        content
            .padding(16)
            .frame(width: GuideCard.width, alignment: .leading)
            .background(GuideCardBackground(side: model.side, arrow: model.arrow))
            .padding(GuideCard.margin)
            .animation(Motion.spring(response: 0.3, damping: 0.7, reduced: reduceMotion), value: model.passed)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .welcome:
            welcome
        case let .step(step, number, count, canGoBack, lesson):
            stepCard(step, number: number, count: count, canGoBack: canGoBack, lesson: lesson)
        case .done:
            done
        case .tip(let tip):
            tipCard(tip)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Welcome! Discover Snapfly."))
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("About a minute"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Text(L("We'll show you the most important features, right in the app and step by step."))
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Side by side where they fit; long words put them one over the other.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    skipButton
                    startButton
                }
                VStack(alignment: .trailing, spacing: 8) {
                    startButton
                    skipButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var skipButton: some View {
        Button(L("Skip for Now"), action: model.skip)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
    }

    private var startButton: some View {
        Button(action: model.start) {
            Label(L("Start Introduction"), systemImage: "arrow.forward")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private func stepCard(_ step: GuideStep, number: Int, count: Int, canGoBack: Bool, lesson: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                symbol(model.passed ? "checkmark" : step.symbol)
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                endButton(lesson: lesson)
            }
            Text(step.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Snapfly's own screenshot, a click away, over the footer.
            if let action = step.action {
                Button {
                    model.act(action.kind)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            ViewThatFits(in: .horizontal) {
                footer(step, number: number, count: count, canGoBack: canGoBack, dots: true)
                footer(step, number: number, count: count, canGoBack: canGoBack, dots: false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// How far along, Back, and Next, which is the main act unless the step
    /// waits for the real thing or has its own button.
    private func footer(_ step: GuideStep, number: Int, count: Int, canGoBack: Bool, dots: Bool) -> some View {
        HStack(spacing: 8) {
            if dots && count > 1 {
                GuideDots(number: number, count: count)
            }
            Spacer(minLength: 8)
            if canGoBack {
                Button(L("Back"), action: model.back)
                    .controlSize(.large)
                    .keyboardShortcut(layoutDirection == .rightToLeft ? .rightArrow : .leftArrow, modifiers: [])
            }
            nextButton(prominent: !step.waits && step.action == nil)
        }
    }

    @ViewBuilder
    private func nextButton(prominent: Bool) -> some View {
        let arrowKey: KeyEquivalent = layoutDirection == .rightToLeft ? .leftArrow : .rightArrow
        if prominent {
            Button(action: model.next) {
                Label(L("Next"), systemImage: "arrow.forward")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else {
            Button(L("Next"), action: model.next)
                .controlSize(.large)
                .keyboardShortcut(arrowKey, modifiers: [])
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                symbol("checkmark")
                Text(L("You're all set"))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            Text(model.doneText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(action: model.end) {
                    Label(L("Done"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tipCard(_ tip: GuideTip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                symbol(tip.symbol)
                Text(tip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            Text(tip.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("No More Tips"), action: model.stopTips)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                Button(L("OK"), action: model.end)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The step's symbol in the accent on a circle of the accent at 12%,
    /// as a floating card's header draws it.
    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.12), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    /// The cross: ends the introduction, to go on later.
    private func endButton(lesson: Bool) -> some View {
        Button(action: model.end) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help(lesson ? L("Close") : L("End Introduction"))
        .accessibilityLabel(lesson ? L("Close") : L("End Introduction"))
        .keyboardShortcut(.cancelAction)
    }
}

/// How far along: a dot a step, the one showing drawn long in the accent.
private struct GuideDots: View {
    let number: Int
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, count), id: \.self) { i in
                Capsule()
                    .fill(i == number ? Color.accentColor : Color.primary.opacity(i < number ? 0.35 : 0.15))
                    .frame(width: i == number ? 14 : 6, height: 6)
            }
        }
        .animation(Motion.spring(response: 0.35, damping: 0.85, reduced: reduceMotion), value: number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("Step %1$d of %2$d"), number, count))
    }
}

/// The card's material and edge, as a floating card has them, with its
/// arrow drawn into the same outline.
private struct GuideCardBackground: View {
    let side: GuidePlacement.Side
    let arrow: CGFloat

    var body: some View {
        let shape = GuideCardShape(side: side, arrow: arrow)
        shape
            .fill(.regularMaterial)
            .overlay(
                shape.stroke(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                            startPoint: .top, endPoint: .bottom),
                             lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// A rounded card with a small arrow on one edge, as one outline. The
/// arrow is placed on the screen, so it is not mirrored right to left.
struct GuideCardShape: Shape {
    var side: GuidePlacement.Side
    var arrow: CGFloat

    static let corner: CGFloat = 20
    static let arrowWidth: CGFloat = 18
    static let arrowLength: CGFloat = 8

    var animatableData: CGFloat {
        get { arrow }
        set { arrow = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = RoundedRectangle(cornerRadius: Self.corner, style: .continuous).path(in: rect)
        let half = Self.arrowWidth / 2
        let length = Self.arrowLength
        // From the base on the edge out to a softly rounded tip.
        var tip = Path()
        switch side {
        case .none:
            return body
        case .below:
            let x = rect.minX + arrow
            tip.move(to: CGPoint(x: x - half, y: rect.minY + 1))
            tip.addLine(to: CGPoint(x: x - 1.6, y: rect.minY - length + 1.2))
            tip.addQuadCurve(to: CGPoint(x: x + 1.6, y: rect.minY - length + 1.2), control: CGPoint(x: x, y: rect.minY - length))
            tip.addLine(to: CGPoint(x: x + half, y: rect.minY + 1))
        case .above:
            let x = rect.minX + arrow
            tip.move(to: CGPoint(x: x - half, y: rect.maxY - 1))
            tip.addLine(to: CGPoint(x: x - 1.6, y: rect.maxY + length - 1.2))
            tip.addQuadCurve(to: CGPoint(x: x + 1.6, y: rect.maxY + length - 1.2), control: CGPoint(x: x, y: rect.maxY + length))
            tip.addLine(to: CGPoint(x: x + half, y: rect.maxY - 1))
        case .right:
            let y = rect.minY + arrow
            tip.move(to: CGPoint(x: rect.minX + 1, y: y - half))
            tip.addLine(to: CGPoint(x: rect.minX - length + 1.2, y: y - 1.6))
            tip.addQuadCurve(to: CGPoint(x: rect.minX - length + 1.2, y: y + 1.6), control: CGPoint(x: rect.minX - length, y: y))
            tip.addLine(to: CGPoint(x: rect.minX + 1, y: y + half))
        case .left:
            let y = rect.minY + arrow
            tip.move(to: CGPoint(x: rect.maxX - 1, y: y - half))
            tip.addLine(to: CGPoint(x: rect.maxX + length - 1.2, y: y - 1.6))
            tip.addQuadCurve(to: CGPoint(x: rect.maxX + length - 1.2, y: y + 1.6), control: CGPoint(x: rect.maxX + length, y: y))
            tip.addLine(to: CGPoint(x: rect.maxX - 1, y: y + half))
        }
        tip.closeSubpath()
        return body.union(tip)
    }
}
