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
    @State private var cardHover = false
    /// The pointer is over the photo or the row of icons under it, which
    /// GrabView sees, as that row lies outside the card.
    @State private var overStrip = false
    /// The pointer rests on the lock: where it is covered lights up.
    @State private var overLock = false
    private var hovering: Bool { cardHover || overStrip }
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
    /// The chats whose icons stand under this photo, the rest behind a ⋯.
    private var chats: ChatTarget.Row { ChatTarget.row(ChatTarget.takes(item) ? ChatTarget.onPhotosNow : []) }
    /// The room under the card that the row of icons takes, which the photo's
    /// view reaches into; none without icons.
    private var stripHeight: CGFloat { chats.count == 0 ? 0 : PhotoButtons.stripHeight }
    /// One like it was sent lately, and Settings marks it.
    private var sentBefore: Bool { Line.marksSentBefore && line.sentBefore[item.id] != nil }
    /// Where the photo, as it shows, is covered.
    private var coveredPlaces: [CGRect] { PrivateDetails.report(for: item.url)?.places ?? [] }

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
        // A line tucked away under the pointer never sees it leave.
        .onChange(of: line.revealed) { _, _ in
            overStrip = false
            overLock = false
        }
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
            .overlay {
                // Search: each place the words are, marked like a highlighter,
                // laid out from the left as the picture is, in every language.
                ZStack(alignment: .topLeading) {
                    ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                        Highlight(place: place, photo: photoSize)
                    }
                }
                .frame(width: photoSize.width, height: photoSize.height, alignment: .topLeading)
                .environment(\.layoutDirection, .leftToRight)
            }
            .overlay {
                // On the lock: the rest of the photo steps back, and what is
                // covered is outlined, to see at a glance whether it is all.
                if overLock, item.covered, !coveredPlaces.isEmpty {
                    CoveredPlaces(places: coveredPlaces)
                        .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: overLock)
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
                // a chat. Drawn here and clicked through GrabView, like the cross.
                sendButtons
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // ChatGPT, Claude, WhatsApp and Gmail under the card.
            .overlay(alignment: .bottom) { chatStrip }
            .overlay(GrabArea(item: item, line: line, overStrip: $overStrip, overLock: $overLock)
                .padding(.bottom, -stripHeight))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .controlGlass(capsule: true)
                        // Below the row of icons, when there is one.
                        .offset(y: 16 + stripHeight)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { cardHover = $0 }
            .background(
                GeometryReader { g in
                    // Under the card too while its icons show, so a click on one
                    // does not go through to the app behind.
                    let frame = g.frame(in: .global)
                    let reach = hovering ? stripHeight : 0
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: CGRect(x: frame.minX, y: frame.minY,
                                                                                         width: frame.width, height: frame.height + reach)])
                }
            )
    }

    /// The paper plane, in the bottom trailing corner of the card.
    private var sendButtons: some View {
        Image(systemName: "paperplane.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: PhotoButtons.size, height: PhotoButtons.size)
            .background(Color.accentColor, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .padding(PhotoButtons.inset)
    }

    /// The chats' icons in a row under the card, so the card itself keeps
    /// only its own buttons. Drawn here and clicked through GrabView, which
    /// reaches below the card as far as they do.
    private var chatStrip: some View {
        HStack(spacing: PhotoButtons.chatGap) {
            ForEach(chats.shown) { chat in
                ChatIcon(chat: chat, size: PhotoButtons.chatSize)
            }
            if !chats.more.isEmpty {
                MoreChatsIcon(size: PhotoButtons.chatSize)
            }
        }
        .offset(y: PhotoButtons.stripGap + PhotoButtons.chatSize)
        .opacity(hovering && !dragging ? 1 : 0)
        .offset(y: hovering ? 0 : -6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// A chat's logo, or the app's own icon wherever it is on this Mac, under a
/// photo and in Settings. An app icon keeps a margin round its shape, so it
/// is drawn a little larger to look as large as a logo. Without either, a
/// glass circle with the chat's short mark in plain letters.
struct ChatIcon: View {
    let chat: ChatTarget
    var size: CGFloat

    var body: some View {
        ZStack {
            if let icon = chat.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * chat.iconScale, height: size * chat.iconScale)
            } else {
                Text(chat.mark)
                    .font(.system(size: size * 0.375, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .controlGlass(circle: true)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// The ⋯ in the last place of a photo's row when more chats are on than it
/// holds; a click lists the rest. A glass circle, as a chat without a logo
/// shows.
struct MoreChatsIcon: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .controlGlass(circle: true)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
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

/// Where a photo is covered, shown while the pointer rests on its lock: the
/// rest steps back under black at 40%, and each covered place keeps its
/// look, outlined in the accent.
private struct CoveredPlaces: View {
    /// From 0 to 1 from the bottom left.
    let places: [CGRect]

    var body: some View {
        Canvas { context, size in
            // Joined first, so places that overlap open one clear hole.
            var outlines = Path()
            for place in places {
                let rect = CGRect(x: place.minX * size.width, y: (1 - place.maxY) * size.height,
                                  width: place.width * size.width, height: place.height * size.height)
                outlines = outlines.union(Path(roundedRect: rect.insetBy(dx: -1, dy: -1),
                                               cornerSize: CGSize(width: 2, height: 2)))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)).subtracting(outlines),
                         with: .color(.black.opacity(0.4)))
            context.stroke(outlines, with: .color(.accentColor), lineWidth: 1.5)
        }
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
    /// A send button across, and the room round it.
    static let size: CGFloat = 22
    static let inset: CGFloat = 4
    /// The pick circle, drawn as the corner cross is.
    static let pickSize: CGFloat = 20
    static let pickInset: CGFloat = 3
    /// The chats' icons, in a row under the card: each, the room between
    /// them, the room between the card and the row, and the room the row
    /// takes below the card, which GrabView and the hit rect reach into.
    static let chatSize: CGFloat = 20
    static let chatGap: CGFloat = 4
    /// As many as a card's row holds, at the size photos hang in at first;
    /// with more on, the last place is a ⋯ that holds the rest.
    static let maxChats = 6
    static let stripGap: CGFloat = 6
    static var stripHeight: CGFloat { stripGap + chatSize + 4 }

    /// The paper plane, in the bottom trailing corner.
    static func plane(card: CGSize) -> CGRect {
        CGRect(x: card.width - inset - size, y: card.height - inset - size, width: size, height: size)
    }

    /// Each chat's icon, side by side in the middle under the card, which
    /// is counted from its top left; the first at the leading end.
    static func chats(card: CGSize, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let row = CGFloat(count) * chatSize + CGFloat(count - 1) * chatGap
        let start = (card.width - row) / 2
        return (0..<count).map { i in
            CGRect(x: start + CGFloat(i) * (chatSize + chatGap), y: card.height + stripGap, width: chatSize, height: chatSize)
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
