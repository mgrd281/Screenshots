import SwiftUI

/// One photo with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line
    /// How it leans where it hangs, from Layout.tilt.
    var tilt: Double = 0
    /// On a rope: it hangs from a clip, arrives with a swing and sways.
    var swings = true
    /// On a rope or a wire: it hangs from a clip.
    var clipped = true

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false
    /// Reduce Motion: no drop, swing or sway; photos fade in where they hang.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var copied: Bool { line.copiedIDs.contains(item.id) }
    private var picked: Bool { line.pickedIDs.contains(item.id) }
    private var dragging: Bool { line.draggingID == item.id }
    private var pressed: Bool { line.pressedID == item.id }
    /// Something is typed in Search and this photo does not say it.
    private var dimmed: Bool { line.found.map { $0[item.id] == nil } ?? false }
    /// Where this photo says what is typed in Search.
    private var places: [CGRect] { line.found?[item.id] ?? [] }
    /// One like it was sent lately, and Settings marks it.
    private var sentBefore: Bool { Line.marksSentBefore && line.sentBefore[item.id] != nil }
    /// The badges in the bottom leading corner, which the send buttons keep clear of.
    private var badges: Int { item.isDocument ? 0 : (item.covered ? 1 : 0) + (sentBefore ? 1 : 0) }

    var body: some View {
        VStack(spacing: -12) {
            // Without a rope or a wire there is nothing to clip on to; the
            // clip keeps its room so the card sits where Layout says.
            Clothespin()
                .opacity(clipped ? 1 : 0)
                .zIndex(1)
            card
        }
        .rotationEffect(.degrees(swing + tilt), anchor: .top)
        .offset(y: arrived || reduceMotion ? 0 : -46)
        // The fall itself is drawn over the whole screen by CaptureFlight, so
        // the card here just steps aside at once.
        .opacity(item.falling || item.flying ? 0 : (arrived ? 1 : 0))
        .transaction { t in if item.falling { t.animation = nil } }
        .animation(.easeOut(duration: 0.16), value: item.flying)
        .onAppear(perform: arrive)
        .onChange(of: item.flying) { was, now in if was && !now { land() } }
        .onChange(of: line.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, isCopied in if isCopied { nudge(3) } }
        .onChange(of: item.pinned) { _, _ in nudge(3) }
        // Search: what does not say it steps back.
        .opacity(dimmed ? 0.25 : 1)
        .saturation(dimmed ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: dimmed)
    }

    /// The photo fits inside the card area keeping its proportions, so the
    /// white border hugs it whether the screenshot is wide or tall.
    static func photoSize(for size: CGSize) -> CGSize {
        let maxW = Layout.cardWidth - 14, maxH = Layout.photoMaxHeight
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / size.width, maxH / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The card around the photo: the photo plus the glass inset.
    static func cardSize(for size: CGSize) -> CGSize {
        let p = photoSize(for: size)
        return CGSize(width: p.width + Frame.inset * 2, height: p.height + Frame.inset * 2)
    }

    /// Distance from the top of the hanging view (the clip) to the card.
    static let cardOffsetBelowTop: CGFloat = Layout.cardBelowTop

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }

    private var card: some View {
        Image(nsImage: item.thumb)
            .resizable()
            .interpolation(.high)
            .accessibilityHidden(true)
            .frame(width: photoSize.width, height: photoSize.height)
            // Concentric corners: the photo's radius is the frame's minus the
            // inset, the way macOS rounds nested shapes.
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                // Search: each place the words are, marked like a highlighter.
                ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                    Highlight(place: place, photo: photoSize)
                }
            }
            .overlay {
                // A recording says so with a play button over its first frame.
                if item.isRecording {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .controlGlass(circle: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(Frame.inset)
            .glassFrame(cornerRadius: Frame.radius)
            // Picked, to go along with others: a ring, and the check in the
            // pick circle, in the corner opposite the cross.
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .opacity(picked ? 1 : 0)
            )
            .animation(.easeOut(duration: 0.18), value: picked)
            .overlay(alignment: .bottomLeading) {
                // Private details are covered in what leaves the line, and a
                // paper plane after the lock says one like it went lately. A
                // PDF says so in its own capsule.
                if !item.isDocument && (item.covered || sentBefore) {
                    HStack(spacing: 4) {
                        if item.covered { badge("lock.fill") }
                        if sentBefore { badge("paperplane.fill") }
                    }
                    .padding(5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: item.covered)
            .animation(.easeOut(duration: 0.2), value: sentBefore)
            .overlay(alignment: .bottomLeading) {
                // A PDF says so, and how many pages it has when there are
                // several, where a photo shows its lock.
                if item.isDocument {
                    HStack(spacing: 4) {
                        // While its pages are being covered, a spinner; once
                        // they are, the lock, as on a photo.
                        if item.preparing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                                .scaleEffect(0.7)
                                .frame(width: 10, height: 10)
                        } else if item.covered {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text(verbatim: item.pages > 1 ? "PDF · \(item.pages)" : "PDF")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(PhotoBadge.fill(reduced: reduceTransparency), in: Capsule())
                    .padding(5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(.easeOut(duration: 0.2), value: item.preparing)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            // Holding presses the photo in slowly, so a long press feels like
            // it is building up to something.
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
            .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .opacity(dragging ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                Corner(pinned: item.pinned, trashes: line.isInInbox(item.id), hovering: hovering, dragging: dragging)
            }
            .overlay(alignment: .topTrailing) {
                PickCircle(picked: picked, hovering: hovering && !dragging)
            }
            .overlay(alignment: .bottomTrailing) {
                // The paper plane sends this photo into the app in front, like
                // a chat; ChatGPT and Claude beside it, into a chat of theirs.
                // Drawn here and clicked through GrabView, like the cross.
                sendButtons
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(GrabArea(item: item, line: line))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .controlGlass(capsule: true)
                        .offset(y: 16)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: g.frame(in: .global)])
                }
            )
    }

    /// The paper plane, with the chats' icons beside it where the photo has
    /// room for them, as `PhotoButtons` places them.
    private var sendButtons: some View {
        let chats = ChatTarget.takes(item) ? ChatTarget.onPhotosNow : []
        let fit = PhotoButtons.layout(card: Self.cardSize(for: item.thumb.size), chats: chats.count,
                                      leadingRoom: PhotoButtons.leadingRoom(badges: badges, document: item.isDocument))
        let stack = fit.arrangement == .column ? AnyLayout(VStackLayout(spacing: PhotoButtons.gap))
                                               : AnyLayout(HStackLayout(spacing: PhotoButtons.gap))
        return stack {
            // As many as the card holds, the first ones.
            ForEach(Array(chats.prefix(fit.count))) { chat in
                chatIcon(chat)
            }
            Image(systemName: "paperplane.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: PhotoButtons.size, height: PhotoButtons.size)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .padding(PhotoButtons.inset)
    }

    /// The app's own icon, wherever it is on this Mac. An app icon keeps a
    /// margin round its shape, so it is drawn a little larger to look as
    /// large as the paper plane. Without the app, a glass circle with the
    /// chat's short mark in plain letters.
    private func chatIcon(_ chat: ChatTarget) -> some View {
        ZStack {
            if let icon = chat.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: PhotoButtons.size * 1.22, height: PhotoButtons.size * 1.22)
            } else {
                Text(chat.mark)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(width: PhotoButtons.size, height: PhotoButtons.size)
                    .controlGlass(circle: true)
            }
        }
        .frame(width: PhotoButtons.size, height: PhotoButtons.size)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    /// A white glyph on the photo badge, as the lock is drawn.
    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(PhotoBadge.fill(reduced: reduceTransparency), in: Circle())
    }

    private func arrive() {
        // A capture that flew in is already in place; the flight did the arriving.
        if item.flying {
            arrived = true
            return
        }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { arrived = true }
            return
        }
        swing = swings ? 16 : 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: 46, damping: 2.6)) { swing = 0 }
    }

    /// Landing after the flight: no jump, just a small sway from rest.
    private func land() {
        nudge(2.2)
    }

    private func breeze() {
        guard swings, !reduceMotion else { return }
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    private func nudge(_ degrees: Double) {
        guard swings, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.3)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
        }
    }
}

/// The corner button. Drawn here, clicked through GrabView, which sits on
/// top. A cross sends a file in Tendedero's folder to the Trash; for a file
/// anywhere else it only hides it from the line. A pinned photo has a pin
/// there instead, always showing, which unpins.
private struct Corner: View {
    let pinned: Bool
    let trashes: Bool
    let hovering: Bool
    let dragging: Bool

    var body: some View {
        ZStack {
            if pinned {
                Image(systemName: hovering ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.orange, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Image(systemName: trashes ? "xmark" : "eye.slash")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .controlGlass(circle: true)
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
            }
        }
        .padding(3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pinned)
    }
}

/// The circle in the top trailing corner. On a photo under the pointer a
/// click picks it, to go with others; picked, it holds the accent check,
/// always showing, and a click puts it back. Drawn here, clicked through
/// GrabView, which sits on top.
private struct PickCircle: View {
    let picked: Bool
    let hovering: Bool

    var body: some View {
        ZStack {
            if picked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: PhotoButtons.pickSize, height: PhotoButtons.pickSize)
                    .background(Color.accentColor, in: Circle())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: PhotoButtons.pickSize, height: PhotoButtons.pickSize)
                    .controlGlass(circle: true)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
            }
        }
        .padding(PhotoButtons.pickInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.18), value: picked)
    }
}

/// A word found by Search, marked on the photo like a highlighter.
private struct Highlight: View {
    /// From 0 to 1 from the bottom left.
    let place: CGRect
    let photo: CGSize

    var body: some View {
        let width: CGFloat = max(place.width * photo.width + 4, 6)
        let height: CGFloat = max(place.height * photo.height + 2, 5)
        let x: CGFloat = place.minX * photo.width - 2
        let y: CGFloat = (1 - place.maxY) * photo.height - 1
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return shape
            .fill(Color.yellow.opacity(0.45))
            .overlay(shape.strokeBorder(Color.yellow, lineWidth: 1))
            .frame(width: width, height: height)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}

enum Frame {
    static let radius: CGFloat = 16
    static let inset: CGFloat = 4
}

/// Where the buttons on a photo under the pointer sit, for drawing them and
/// for clicking them through GrabView. The pick circle takes the top
/// trailing corner, as the cross takes the top leading one. The paper plane
/// takes the bottom trailing corner, with the AI chats' icons beside it in a
/// row, or above it on a narrow photo, or left out on one too small for
/// either: the photo's menu has them all the same. Counted from the card's
/// top left, left to right; GrabView mirrors them for right to left.
enum PhotoButtons {
    /// A send button across, and the room between them and round them.
    static let size: CGFloat = 22
    static let gap: CGFloat = 4
    static let inset: CGFloat = 4
    /// The pick circle, drawn as the corner cross is.
    static let pickSize: CGFloat = 20
    static let pickInset: CGFloat = 3

    enum Arrangement: Equatable {
        case row, column, none
    }

    /// The room the bottom leading corner takes, which a row keeps clear
    /// of: the lock and the paper plane of a photo sent before, each 18 pt
    /// and 4 apart, or a PDF's capsule.
    static func leadingRoom(badges: Int, document: Bool) -> CGFloat {
        if document { return 72 }
        guard badges > 0 else { return 0 }
        return 5 + CGFloat(badges) * 18 + CGFloat(badges - 1) * 4 + gap
    }

    /// How a card of this size holds the paper plane and that many chats:
    /// all of them in a row, when the card is wide enough beside its lock
    /// badges or PDF capsule; else all in a column above the plane, clear of
    /// the pick circle; else as many as the roomier of the two holds, the
    /// first ones, and none when neither holds one.
    static func layout(card: CGSize, chats: Int, leadingRoom: CGFloat) -> (arrangement: Arrangement, count: Int) {
        guard chats > 0 else { return (.none, 0) }
        let step = size + gap
        let row = max(0, Int(((card.width - leadingRoom - inset - size) / step).rounded(.down)))
        let column = max(0, Int(((card.height - pickInset - pickSize - gap - inset - size) / step).rounded(.down)))
        if row >= chats { return (.row, chats) }
        if column >= chats { return (.column, chats) }
        if row == 0 && column == 0 { return (.none, 0) }
        return row >= column ? (.row, row) : (.column, column)
    }

    /// The paper plane, in the bottom trailing corner.
    static func plane(card: CGSize) -> CGRect {
        CGRect(x: card.width - inset - size, y: card.height - inset - size, width: size, height: size)
    }

    /// Each chat's icon, the first the farthest from the paper plane.
    static func chats(card: CGSize, count: Int, arrangement: Arrangement) -> [CGRect] {
        guard arrangement != .none, count > 0 else { return [] }
        let corner = Self.plane(card: card)
        return (0..<count).map { i in
            let step = CGFloat(count - i) * (size + gap)
            return arrangement == .row ? corner.offsetBy(dx: -step, dy: 0) : corner.offsetBy(dx: 0, dy: -step)
        }
    }

    /// The pick circle, in the top trailing corner.
    static func pick(card: CGSize) -> CGRect {
        CGRect(x: card.width - pickInset - pickSize, y: pickInset, width: pickSize, height: pickSize)
    }
}

/// A minimal aluminium clip: a brushed metal pill with a slot where it
/// grips the line, and a soft shadow so it reads on any background.
struct Clothespin: View {
    private let metal = LinearGradient(
        stops: [
            .init(color: Color(white: 0.70), location: 0),
            .init(color: Color(white: 0.93), location: 0.35),
            .init(color: Color(white: 0.82), location: 0.65),
            .init(color: Color(white: 0.62), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(metal)
            .frame(width: 9, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.black.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.6)
            )
            .overlay(alignment: .top) {
                // The slot the line passes through.
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 5, height: 1.4)
                    .padding(.top, 8.5)
            }
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}
