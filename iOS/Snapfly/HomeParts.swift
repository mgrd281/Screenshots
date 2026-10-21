import Photos
import SwiftUI
import UIKit

/// The iPhone's own colours: one protecting green, a soft green behind the
/// picture of stacked photos, and the accent (the asset catalogue's
/// AccentColor) for links and tools.
enum SnapflyTokens {
    /// The protect button's green, the same in light and dark: white on it 4.5:1.
    static let protect = Color(red: 7 / 255, green: 135 / 255, blue: 92 / 255)
    /// The same green, pressed.
    static let protectPressed = Color(red: 5 / 255, green: 107 / 255, blue: 73 / 255)
    /// The badge's lighter top.
    static let protectLight = Color(red: 18 / 255, green: 165 / 255, blue: 114 / 255)
    /// The green as a glyph or words on glass or the page: the protect
    /// green, lighter at night so it reads on dark.
    static let protectTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18 / 255, green: 165 / 255, blue: 114 / 255, alpha: 1)
            : UIColor(red: 7 / 255, green: 135 / 255, blue: 92 / 255, alpha: 1)
    })
    /// Under the picture in Protect Picture: a bright, near-white ground, so
    /// the page stands on it; black at night.
    static let editorGround = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor(red: 248 / 255, green: 249 / 255, blue: 250 / 255, alpha: 1)
    })
    /// The soft green round the stacked photos; a deep green at night.
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 16 / 255, green: 42 / 255, blue: 32 / 255, alpha: 1)
            : UIColor(red: 234 / 255, green: 247 / 255, blue: 240 / 255, alpha: 1)
    })
    /// Cards and the paper of the photos.
    static let card = Color(.secondarySystemGroupedBackground)
    /// The cover ink, as a covered copy shows it: the editor's, and the first
    /// launch's sample screenshot's.
    static let ink = Color(white: 0.12)
    /// A ballpoint's blue, for the signature and the stamp on the first
    /// run's doctor's letter; it is printed on white in light and dark alike.
    static let penInk = Color(red: 43 / 255, green: 69 / 255, blue: 160 / 255)

    // MARK: More and Always Hide

    /// The ground of More, its pages, Always Hide and its sheets: a cool
    /// light grey; near black at night.
    static let hideGround = color(0xF2F3F5, dark: 0x0B0D10)
    /// Their rows and cards.
    static let hideCard = color(0xFFFFFF, dark: 0x17191D)
    /// The lines between their rows, inset to the words.
    static let hideSeparator = color(0xECEEF1, dark: 0x262A30)
    /// Their words: 18:1 on their cards; at night 17:1.
    static let hideText = color(0x111318, dark: 0xF3F4F6)
    /// Their quieter words: 5.8:1 on their cards and 5.2:1 on their ground;
    /// at night 7.3:1 and 8.4:1.
    static let hideSecondary = color(0x5F6670, dark: 0xA0A7B0)
    /// Their green, as words and edges: 5.4:1 on their cards; at night the
    /// light green, 9.7:1.
    static let hideAccent = color(0x077A56, dark: 0x5BD6A6)
    /// The mint behind every symbol's tile, the chips and what keeps the
    /// details private; the green words on it 4.7:1, at night 7:1.
    static let hideAccentSoft = color(0xE7F4EE, dark: 0x11392C)
    /// Its main button, the same green in light and dark: white on it 5.4:1.
    static let hideButton = Color(red: 7 / 255, green: 122 / 255, blue: 86 / 255)
    /// The main button while it waits: a grey with dark grey words, 6.5:1;
    /// at night 6.8:1. Never pale words on a pale green.
    static let hideButtonOff = color(0xE4E6EA, dark: 0x2C3036)
    static let hideButtonOffText = color(0x4A5059, dark: 0xB4BBC4)
    /// The fields in a sheet, grey on the sheet's white, and the lines
    /// between them.
    static let hideField = color(0xF2F3F5, dark: 0x2A2E34)
    static let hideFieldLine = color(0xE1E4E8, dark: 0x3A3F46)
    /// What is wrong with what was typed, in words: 4.6:1 on its ground; at
    /// night 9.7:1.
    static let hideWarning = color(0xB35200, dark: 0xFFA54D)
    /// The rows' and sections' corners, the small cards' and fields', and
    /// the sheets'.
    static let hideRowRadius: CGFloat = 22
    static let hideCardRadius: CGFloat = 18
    static let hideSheetRadius: CGFloat = 32
    /// A row of a detail or a rule, at the body's text size.
    static let hideRowHeight: CGFloat = 64
    /// The smallest a finger's target is.
    static let touch: CGFloat = 44

    /// A symbol on its mint tile: the one accent, 4.4:1 (3:1 is what a
    /// symbol needs); at night the light green, 7:1.
    static let moreGlyph = color(0x0B7F58, dark: 0x5BD6A6)
    /// More's hero card: a deep green, white words on it 12:1; at night a
    /// little deeper, inside an edge of a lighter green.
    static let moreHero = color(0x0E3B2E, dark: 0x0F3A2D)
    static let moreHeroEdge = color(0x0E3B2E, dark: 0x1D5644)
    /// The hero with nothing covered: a neutral dark grey, day and night.
    static let moreHeroOff = Color(red: 42 / 255, green: 46 / 255, blue: 52 / 255)
    /// A kind turned on: solid green with white words, 5:1; at night the
    /// light green with near-black words, 10:1.
    static let morePillOn = color(0x0B7F58, dark: 0x5BD6A6)
    static let morePillOnText = color(0xFFFFFF, dark: 0x0B0D10)
    /// A kind turned off: the card, inside a grey edge.
    static let morePillEdge = color(0xD5D9DF, dark: 0x343941)
    /// The preset control's track, and the thumb raised on it for the
    /// preset chosen: white by day, a lighter grey at night.
    static let moreTrack = color(0xE4E6EA, dark: 0x1E2126)
    static let moreThumb = color(0xFFFFFF, dark: 0x3A3F47)
    /// The quiet tiles of More's Features: grey, the symbol dark grey, 7:1.
    static let moreNeutralTile = color(0xEEF0F2, dark: 0x262A30)
    static let moreNeutralGlyph = color(0x4A5059, dark: 0xB4BBC4)
    /// A document drawn small, as a cover look shows on it: white paper in
    /// light and dark alike, its words near black and grey, its lines grey.
    static let morePaper = Color.white
    static let morePaperText = Color(red: 17 / 255, green: 19 / 255, blue: 24 / 255)
    static let morePaperLabel = Color(red: 95 / 255, green: 102 / 255, blue: 112 / 255)
    static let morePaperLine = Color(red: 214 / 255, green: 218 / 255, blue: 224 / 255)
    /// More's corners: the hero's, and the buttons'. Tiles and cards take
    /// `hideRowRadius`, pills are capsules.
    static let moreHeroRadius: CGFloat = 28
    static let moreButtonRadius: CGFloat = 18

    /// A colour as its hex, and another at night.
    private static func color(_ hex: UInt32, dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let day = ui(hex), night = ui(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? night : day })
    }
}

// MARK: The picture of stacked photos

/// Snapfly's picture on the home screen: three photos stacked, a document
/// with a line covered, a chat with a name covered and a landscape in
/// front, with the green photo badge over the front one's lower edge. Drawn
/// with shapes, so it fits light and dark and shows no one's details. It
/// settles in once a launch, and not at all with Reduce Motion.
struct PhotoHero: View {
    /// From 0 to 1: 1 the full picture, smaller for whoever has screenshots.
    var scale: CGFloat = 1
    @State private var settled = PhotoHero.played
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Played already this launch: coming back shows it at rest.
    private static var played = false

    private let size = CGSize(width: 320, height: 250)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(SnapflyTokens.surface)
                .frame(width: 300, height: 190)
                .blur(radius: 18)
            DocumentCard()
                .modifier(Settle(settled: settled, angle: -11, offset: CGSize(width: -80, height: 14), delay: 0.05,
                                 still: reduceMotion))
            ChatCard()
                .modifier(Settle(settled: settled, angle: 10, offset: CGSize(width: 80, height: 10), delay: 0.1,
                                 still: reduceMotion))
            LandscapeCard()
                .modifier(Settle(settled: settled, angle: 0, offset: CGSize(width: 0, height: -10), delay: 0,
                                 still: reduceMotion))
            PhotoBadge()
                .offset(y: 78)
                .scaleEffect(settled ? 1 : 0.6)
                .opacity(settled ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(0.25), value: settled)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .accessibilityHidden(true)
        .onAppear {
            Self.played = true
            settled = true
        }
    }

    /// A card coming in from the middle, turning to its place.
    private struct Settle: ViewModifier {
        let settled: Bool
        let angle: Double
        let offset: CGSize
        let delay: Double
        let still: Bool

        func body(content: Content) -> some View {
            content
                .rotationEffect(.degrees(settled ? angle : 0))
                .offset(settled ? offset : CGSize(width: offset.width * 0.3, height: 24))
                .opacity(settled ? 1 : 0)
                .animation(still ? nil : .spring(response: 0.6, dampingFraction: 0.82).delay(delay), value: settled)
        }
    }
}

/// A card of the stack: paper with a hairline edge and a soft shadow.
private struct StackCard<Content: View>: View {
    var width: CGFloat = 124
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(width: width, height: width * 4 / 3, alignment: .topLeading)
            .background(SnapflyTokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// Lines of a page, one of them covered.
private struct DocumentCard: View {
    var body: some View {
        StackCard {
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(Color.primary.opacity(0.22)).frame(width: 46, height: 6)
                Spacer().frame(height: 4)
                ForEach([0.9, 0.62, 0.8, 0.7, 0.86, 0.5], id: \.self) { share in
                    Capsule()
                        .fill(share == 0.62 ? Color.primary.opacity(0.85) : Color.primary.opacity(0.1))
                        .frame(width: 100 * share, height: 6)
                }
            }
        }
    }
}

/// A chat, a name in it covered.
private struct ChatCard: View {
    var body: some View {
        StackCard {
            VStack(alignment: .leading, spacing: 8) {
                bubble(70, mine: false, covered: false)
                bubble(56, mine: true, covered: false)
                bubble(82, mine: false, covered: true)
                bubble(48, mine: true, covered: false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func bubble(_ width: CGFloat, mine: Bool, covered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(mine ? SnapflyTokens.protect.opacity(0.22) : Color.primary.opacity(0.08))
            .frame(width: width, height: 20)
            .overlay(alignment: .leading) {
                if covered {
                    Capsule().fill(Color.primary.opacity(0.85)).frame(width: width * 0.55, height: 6).padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// A landscape, as a photo print in front.
private struct LandscapeCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let night = scheme == .dark
        ZStack(alignment: .bottom) {
            LinearGradient(colors: night ? [Color(red: 0.11, green: 0.23, blue: 0.32), Color(red: 0.06, green: 0.12, blue: 0.17)]
                           : [Color(red: 0.73, green: 0.88, blue: 0.96), Color(red: 0.95, green: 0.98, blue: 0.99)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color(red: 1, green: 0.84, blue: 0.42).opacity(night ? 0.75 : 1))
                .frame(width: 26, height: 26)
                .offset(x: 34, y: -112)
            Mountain(peak: 0.35, height: 0.62)
                .fill(Color(red: 0.5, green: 0.72, blue: 0.64).opacity(night ? 0.7 : 1))
            Mountain(peak: 0.7, height: 0.5)
                .fill(Color(red: 0.18, green: 0.56, blue: 0.42).opacity(night ? 0.85 : 1))
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.67, blue: 0.78), Color(red: 0.2, green: 0.5, blue: 0.64)],
                                     startPoint: .top, endPoint: .bottom).opacity(night ? 0.7 : 1))
                .frame(height: 34)
        }
        .frame(width: 136, height: 182)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(5)
        .background(SnapflyTokens.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }
}

/// A mountain from the bottom edge, its peak at a share of the width.
private struct Mountain: Shape {
    let peak: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - rect.width * 0.2, y: rect.maxY - 30))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * peak, y: rect.maxY - rect.height * height))
        path.addLine(to: CGPoint(x: rect.maxX + rect.width * 0.2, y: rect.maxY - 30))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The green photo badge, ringed in the background's colour.
private struct PhotoBadge: View {
    var body: some View {
        Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(LinearGradient(colors: [SnapflyTokens.protectLight, SnapflyTokens.protectPressed],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 4).padding(-4))
            .shadow(color: SnapflyTokens.protect.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: The protect button

/// The one green action: a compact pill, white words, pressed a shade
/// darker and a little smaller; 44 pt tall at least.
struct ProtectButtonStyle: ButtonStyle {
    /// Smaller, beside the small picture once there are screenshots.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .body.weight(.medium))
            .dynamicTypeSize(compact ? ...DynamicTypeSize.xLarge : ...DynamicTypeSize.accessibility5)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 8 : 11)
            .frame(minHeight: compact ? 36 : 44)
            .background(configuration.isPressed ? SnapflyTokens.protectPressed : SnapflyTokens.protect, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: Screenshots

/// What a screenshot's menu does, without opening it.
enum QuickCover {
    case copy, share, save
}

/// Where the Protected tab's screenshots go when they are taken off: off
/// its list alone, staying in Photos, or out of Photos, as iOS asks first.
enum Removing {
    case fromList, fromPhotos
}

/// One screenshot as a card: its top, at 3 by 4, or square where cards sit
/// four to a row, when it was taken, and a green shield once it was
/// protected here lately.
struct ScreenshotCard: View {
    let asset: PHAsset
    var protected = false
    var showsDate = true
    var square = false
    @State private var image: UIImage?

    init(asset: PHAsset, protected: Bool = false, showsDate: Bool = true, square: Bool = false) {
        self.asset = asset
        self.protected = protected
        self.showsDate = showsDate
        self.square = square
        // Made lately, as when choosing starts or the grid changes: at once.
        _image = State(initialValue: Library.keptThumbnail(of: asset, width: Self.width))
    }

    /// The width the small pictures are made at, the same for every card.
    private static let width: CGFloat = 360

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(square ? 1 : 3 / 4, contentMode: .fit)
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsDate, let date = asset.creationDate {
                    // Small, as the card is, and whole: the time alone today, else the
                    // day alone; it grows no larger than at the default text size.
                    Text(Self.short(date))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, square ? 5 : 7)
                        .padding(.vertical, square ? 2 : 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(square ? 4 : 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if protected {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(SnapflyTokens.protect, in: Circle())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: square ? 12 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: square ? 12 : 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .task(id: asset.localIdentifier) { image = await Library.thumbnail(of: asset, width: Self.width) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    private var label: String {
        var parts = [L("Cover Private Details")]
        if let date = asset.creationDate { parts.append(Self.taken.string(from: date)) }
        if protected { parts.append(L("Protected")) }
        return parts.joined(separator: ", ")
    }

    /// "20:03" today, "19.10." before, "19.10.25" in an earlier year, as the
    /// language writes them.
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time.string(from: date) }
        return calendar.isDate(date, equalTo: .now, toGranularity: .year)
            ? day.string(from: date) : dayAndYear.string(from: date)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMM")
        return formatter
    }()

    private static let dayAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMyy")
        return formatter
    }()

    /// "Today, 20:03", as the language says it, for VoiceOver.
    private static let taken: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// A screenshot opened from a card, and where the card is, so it grows out
/// of the card it was tapped on.
struct ShotLink: Hashable {
    enum Place: Hashable {
        case home, recent, all
    }

    let id: String
    let place: Place

    var source: ProtectSession.Source { .asset(id) }
}

extension View {
    /// A card a screenshot grows out of as it opens, from iOS 18 on.
    @ViewBuilder func zoomSource(_ link: ShotLink, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: link, in: namespace)
        } else {
            self
        }
    }

    /// The screenshot opened, grown out of its card, from iOS 18 on; with
    /// Reduce Motion, iOS fades it in instead.
    @ViewBuilder func zoomed(from link: ShotLink, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: link, in: namespace))
        } else {
            self
        }
    }
}

/// Screenshots in a grid of square cards, three to a row, or four pinched
/// closer, as in Photos (`GridZoom`): a tap opens one to protect, growing
/// out of its card; holding it covers it and copies, shares or saves it.
/// While several are being chosen (`GridSelection`), a tap turns a card on
/// or off, and from iOS 18 on a finger drawn sideways across the cards
/// takes in a run of them.
struct ScreenshotGrid: View {
    let shots: [PHAsset]
    let protected: Set<String>
    let place: ShotLink.Place
    let zoom: Namespace.ID
    let quick: @MainActor (PHAsset, QuickCover) -> Void
    /// What is chosen while several are being chosen; nil otherwise.
    var selection: Binding<GridSelection?> = .constant(nil)
    /// Whether a finger is being drawn across, so the page holds still.
    var sweeping: Binding<Bool> = .constant(false)
    /// Takes cards off, from their menu: on the Protected tab alone.
    var remove: (@MainActor ([PHAsset], Removing) -> Void)?
    /// The cards have risen into place, once, the first time there are any.
    @State private var risen = false
    /// The grid's width, to find the card under a finger.
    @State private var width: CGFloat = 0
    /// How many to a row, the same in every grid.
    @AppStorage(GridZoom.key) private var columns = GridZoom.standard
    /// How large the grid shows while it is pinched, back to its size on a
    /// spring once the fingers let go, or the pinch is called off.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.42, dampingFraction: 0.86)))
    private var pinch: CGFloat = 1
    /// Around which point, where the fingers came down.
    @State private var anchor = UnitPoint.center
    /// Each change of the grid, for its haptic.
    @State private var changes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off while the chosen ones are being covered.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: GridZoom.clamped(columns)),
                  spacing: 8) {
            ForEach(Array(shots.enumerated()), id: \.element.localIdentifier) { index, asset in
                card(asset)
                    .opacity(risen ? 1 : 0)
                    .offset(y: risen || reduceMotion ? 0 : 8)
                    .animation(rise(index), value: risen)
                    // A card taken off shrinks away as the others close up; one put back grows in.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .modifier(SweepToChoose(active: selection.wrappedValue != nil && isEnabled, began: beginSweep, changed: sweep,
                                ended: endSweep))
        .sensoryFeedback(.selection, trigger: selection.wrappedValue?.count)
        .scaleEffect(pinch, anchor: anchor)
        .simultaneousGesture(magnify)
        .sensoryFeedback(.selection, trigger: changes)
        .onAppear { if !shots.isEmpty { risen = true } }
        .onChange(of: shots.isEmpty) { if !shots.isEmpty { risen = true } }
        // A finger can't be drawn across what is gone: the page never stays held.
        .onChange(of: selection.wrappedValue == nil) { _, none in if none { endSweep() } }
        .onDisappear { endSweep() }
    }

    /// Two fingers pinch the grid: it follows them, up to the size of the
    /// next grid's cards, and once let go past a little way, the cards settle
    /// into the next grid on a spring (`zoom.grid`); else they settle back.
    /// With Reduce Motion the grid doesn't follow, and changes at once.
    private var magnify: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .updating($pinch) { value, pinch, _ in
                guard !reduceMotion else { return }
                pinch = GridZoom.scale(pinch: value.magnification, columns: columns)
            }
            .onChanged { value in
                if anchor != value.startAnchor { anchor = value.startAnchor }
            }
            .onEnded { value in
                let next = GridZoom.after(pinch: value.magnification, from: columns)
                guard next != GridZoom.clamped(columns) else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    columns = next
                }
                changes += 1
            }
    }

    /// A card: a way into Protect Picture, or, while several are being
    /// chosen, a card to turn on or off.
    @ViewBuilder private func card(_ asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        if let chosen = selection.wrappedValue {
            Button {
                selection.wrappedValue?.toggle(id)
            } label: {
                ScreenshotCard(asset: asset, protected: protected.contains(id), square: true)
                    .modifier(ChosenMark(chosen: chosen.contains(id)))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen.contains(id) ? .isSelected : [])
        } else {
            let link = ShotLink(id: id, place: place)
            NavigationLink(value: link) {
                ScreenshotCard(asset: asset, protected: protected.contains(id), square: true)
                    .zoomSource(link, in: zoom)
            }
            .buttonStyle(.plain)
            .contextMenu { menu(asset) }
            .phoneGuideTarget(.firstShot, on: id == shots.first?.localIdentifier)
        }
    }

    // MARK: A finger drawn across

    private func beginSweep(at point: CGPoint) {
        guard let index = card(at: point) else { return }
        sweeping.wrappedValue = true
        selection.wrappedValue?.begin(at: index, in: shots.map(\.localIdentifier))
    }

    private func sweep(to point: CGPoint) {
        guard let index = card(at: point) else { return }
        selection.wrappedValue?.move(to: index, in: shots.map(\.localIdentifier))
    }

    private func endSweep() {
        if selection.wrappedValue?.isSweeping == true { selection.wrappedValue?.end() }
        if sweeping.wrappedValue { sweeping.wrappedValue = false }
    }

    private func card(at point: CGPoint) -> Int? {
        GridSelection.index(atX: point.x, y: point.y, width: width, columns: GridZoom.clamped(columns),
                            spacing: 8, count: shots.count)
    }

    /// The cards rise in reading order, a beat apart (`stagger.grid`), the
    /// first row and a half; with Reduce Motion they only fade in.
    private func rise(_ index: Int) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15)
            : .spring(response: 0.42, dampingFraction: 0.82).delay(Double(min(index, 11)) * 0.035)
    }

    @ViewBuilder private func menu(_ asset: PHAsset) -> some View {
        Button { quick(asset, .copy) } label: { Label(L("Cover and Copy"), systemImage: "doc.on.doc") }
        Button { quick(asset, .share) } label: { Label(L("Cover and Share"), systemImage: "square.and.arrow.up") }
        Button { quick(asset, .save) } label: { Label(L("Cover and Save"), systemImage: "square.and.arrow.down") }
        if let remove {
            Section {
                Button { remove([asset], .fromList) } label: {
                    Label(L("Remove from Protected"), systemImage: "minus.circle")
                }
                Button(role: .destructive) { remove([asset], .fromPhotos) } label: {
                    Label(L("Delete from Photos"), systemImage: "trash")
                }
            }
        }
    }
}

/// Every screenshot, behind See All: searched by the words they say, as
/// read ahead of time on this iPhone, shown by what they hold or whether
/// they were protected, newest or oldest first.
struct AllScreenshotsView: View {
    let shots: [PHAsset]
    let protected: Set<String>
    let zoom: Namespace.ID
    let quick: @MainActor (PHAsset, QuickCover) -> Void
    @State private var query = LibraryQuery()
    @AppStorage(GridZoom.key) private var columns = GridZoom.standard
    /// The screenshots chosen, while several are being chosen.
    @State private var selection: GridSelection?
    @State private var sweeping = false
    @ObservedObject private var batch = BatchCover.shared
    /// What each screenshot read ahead of time says and holds, in memory
    /// only while this shows.
    @State private var read: [String: (text: String, kinds: [String])] = [:]
    @State private var loaded = false

    var body: some View {
        let shown = matching
        ScrollView {
            if shown.isEmpty, query.narrows {
                ContentUnavailableView.search(text: query.search)
                    .padding(.top, 40)
            } else {
                ScreenshotGrid(shots: shown, protected: protected, place: .all, zoom: zoom, quick: quick,
                               selection: $selection, sweeping: $sweeping)
                    .padding(16)
                    .disabled(batch.running)
            }
            if loaded, read.isEmpty, !query.words.isEmpty {
                Label(L("Words are found in screenshots read ahead of time. Turn on Faster picture processing in Settings."),
                      systemImage: "text.magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .scrollDisabled(sweeping)
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L("Search words in screenshots"))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selection != nil)
        .toolbar {
            if selection != nil {
                ToolbarItem(placement: .topBarLeading) { allOrNone(shown.map(\.localIdentifier)) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Cancel")) {
                        withAnimation(.snappy) { selection = nil }
                    }
                    .fontWeight(.semibold)
                    .disabled(batch.running)
                }
            }
            if selection == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Select")) {
                        withAnimation(.snappy) { selection = GridSelection() }
                    }
                    .disabled(shown.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { options }
            }
        }
        // While choosing, the tab bar steps aside for the choice's own bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection {
                SelectionBar(count: selection.count, save: { coverChosen(.photos) }, share: { coverChosen(.share) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(selection == nil ? .automatic : .hidden, for: .tabBar)
        .animation(.snappy, value: selection == nil)
        .quickNotes()
        .task { await load() }
    }

    /// Select All, or Deselect All once all those shown are.
    private func allOrNone(_ ids: [String]) -> some View {
        let all = selection.map { chosen in ids.allSatisfy(chosen.contains) } ?? false
        return Button(all ? L("Deselect All") : L("Select All")) {
            selection?.toggleAll(ids)
        }
        .disabled(batch.running || ids.isEmpty)
    }

    /// How many are chosen, while choosing.
    private var title: String {
        guard let selection else { return L("Screenshots") }
        return selection.isEmpty ? L("Select screenshots") : String(format: L("%d Selected"), selection.count)
    }

    /// The screenshots chosen, covered as Settings says, one after another:
    /// those shown in their order, then any a search has hidden since, as
    /// the count says; those that could not be stay chosen.
    private func coverChosen(_ way: BatchCover.Way) {
        guard let chosen = selection?.chosen, !chosen.isEmpty else { return }
        let shown = matching.filter { chosen.contains($0.localIdentifier) }
        let first = Set(shown.map(\.localIdentifier))
        let assets = shown + shots.filter { chosen.contains($0.localIdentifier) && !first.contains($0.localIdentifier) }
        Task {
            let failed = await batch.run(assets, way: way)
            withAnimation(.snappy) {
                if failed.isEmpty { selection = nil } else { selection?.keep(failed) }
            }
        }
    }

    /// What shows, and in which order.
    private var options: some View {
        Menu {
            Picker(L("Show"), selection: $query.filter) {
                Text(L("All Screenshots")).tag(LibraryQuery.Filter.all)
                Text(L("With Private Details")).tag(LibraryQuery.Filter.privateDetails)
                Text(L("Protected")).tag(LibraryQuery.Filter.protected)
                Text(L("Not protected")).tag(LibraryQuery.Filter.unprotected)
            }
            Picker(L("Sort"), selection: $query.order) {
                Text(L("Newest First")).tag(LibraryQuery.Order.newest)
                Text(L("Oldest First")).tag(LibraryQuery.Order.oldest)
            }
            // As a pinch does, for whoever doesn't pinch.
            Picker(L("Per Row"), selection: Binding(get: { GridZoom.clamped(columns) },
                                                    set: { new in withAnimation(.snappy) { columns = new } })) {
                ForEach(Array(GridZoom.range), id: \.self) { count in
                    Text(String(format: L("%d per Row"), count)).tag(count)
                }
            }
        } label: {
            Image(systemName: query.filter == .all ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(L("Filter"))
    }

    private var matching: [PHAsset] {
        let byID = Dictionary(shots.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let items = shots.map { asset in
            LibraryQuery.Item(id: asset.localIdentifier, created: asset.creationDate,
                              text: read[asset.localIdentifier]?.text, kinds: read[asset.localIdentifier]?.kinds ?? [],
                              protected: protected.contains(asset.localIdentifier))
        }
        return query.apply(items).compactMap { byID[$0.id] }
    }

    /// The words and kinds of the screenshots read ahead of time.
    private func load() async {
        var found: [String: (text: String, kinds: [String])] = [:]
        for asset in shots {
            guard let photo = await IndexStore.shared.photo(asset.localIdentifier) else { continue }
            found[asset.localIdentifier] = (photo.lines.map(\.text).joined(separator: " "), photo.kinds)
        }
        read = found
        loaded = true
    }
}
