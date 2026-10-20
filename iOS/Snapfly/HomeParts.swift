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

/// One screenshot as a card: its top, at 3 by 4, or square where cards sit
/// four to a row, when it was taken, and a green shield once it was
/// protected here lately.
struct ScreenshotCard: View {
    let asset: PHAsset
    var protected = false
    var showsDate = true
    var square = false
    @State private var image: UIImage? = nil

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
            .task(id: asset.localIdentifier) { image = await Library.thumbnail(of: asset, width: 360) }
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

/// Screenshots in a grid of small square cards, four to a row on most
/// iPhones: a tap opens one to protect, growing out of its card; holding
/// it covers it and copies, shares or saves it.
struct ScreenshotGrid: View {
    let shots: [PHAsset]
    let protected: Set<String>
    let place: ShotLink.Place
    let zoom: Namespace.ID
    let quick: @MainActor (PHAsset, QuickCover) -> Void
    /// The cards have risen into place, once, the first time there are any.
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 160), spacing: 8)], spacing: 8) {
            ForEach(Array(shots.enumerated()), id: \.element.localIdentifier) { index, asset in
                let link = ShotLink(id: asset.localIdentifier, place: place)
                NavigationLink(value: link) {
                    ScreenshotCard(asset: asset, protected: protected.contains(asset.localIdentifier), square: true)
                        .zoomSource(link, in: zoom)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(asset) }
                .phoneGuideTarget(.firstShot, on: asset.localIdentifier == shots.first?.localIdentifier)
                .opacity(risen ? 1 : 0)
                .offset(y: risen || reduceMotion ? 0 : 8)
                .animation(rise(index), value: risen)
            }
        }
        .onAppear { if !shots.isEmpty { risen = true } }
        .onChange(of: shots.isEmpty) { if !shots.isEmpty { risen = true } }
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
                ScreenshotGrid(shots: shown, protected: protected, place: .all, zoom: zoom, quick: quick)
                    .padding(16)
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
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L("Search words in screenshots"))
        .navigationTitle(L("Screenshots"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { options }
        }
        .task { await load() }
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
