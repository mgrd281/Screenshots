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
            // Picked with ⌘-click, to copy along with others: a ring and a
            // check in the corner opposite the cross.
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .opacity(picked ? 1 : 0)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor, in: Circle())
                    .padding(3)
                    .opacity(picked ? 1 : 0)
                    .scaleEffect(picked ? 1 : 0.6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
            .overlay(alignment: .bottomTrailing) {
                // Sends this photo into the app in front, like a chat. Drawn
                // here and clicked through GrabView, like the cross.
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(4)
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
