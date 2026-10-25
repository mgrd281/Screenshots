import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The parts of the Scan tab's start (`ScanTab`): one job, a scan started
/// in one tap. The emerald card that is the scan button, three quick
/// actions, the three documents edited last as their covered first pages,
/// or "Noch nichts gescannt." while there are none yet, and "So
/// funktioniert's" behind the "?". They come in once per launch, one after
/// another; nothing on them moves after that.
enum ScanStart {
    /// They came in once since Snapfly started: they do not again on every visit.
    @MainActor static var entered = false
    /// The newest document the row showed, so a new one is told as it arrives.
    @MainActor static var newest: UUID?
    /// How many recent documents show, side by side.
    static let shown = 3
    /// Whether the documents' small pictures are shown or veiled
    /// (`ScanVeil`), kept on this iPhone; veiled until the owner shows them.
    static let previewKey = "snapfly.scan.showsPreviews"
}

extension ScanVeil {
    /// A small picture veiled, as a picture again; nil where it cannot be read.
    static func image(_ picture: CGImage) -> CGImage? {
        ScanCleaner.bitmap(picture).flatMap { ScanCleaner.image(veiled($0), gray: false) }
    }
}

/// The round glass eye over the documents: shows their small pictures, or
/// veils them again, with a light tap.
struct PreviewToggle: View {
    @AppStorage(ScanStart.previewKey) private var shows = false
    @ScanCalm private var calm

    var body: some View {
        Button {
            withAnimation(SnapflyMotion.toggle(calm)) { shows.toggle() }
        } label: {
            Image(systemName: shows ? "eye" : "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .editorGlass(in: Circle())
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: shows)
        .accessibilityLabel(shows ? L("Hide Preview") : L("Show Preview"))
        .accessibilityIdentifier("scan-preview-toggle")
    }
}

/// Where the Scan tab goes besides a page: Alle anzeigen.
enum ScanRoute: Hashable {
    case allDocuments
}

/// Whether the screen keeps still: Reduce Motion, Low Power Mode, or the
/// made-up scans played as Reduce Motion would.
@propertyWrapper
struct ScanCalm: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var wrappedValue: Bool { reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || ScanDemo.still }
}

extension View {
    /// Content under the tab bar's glass reads as a soft blur, never as
    /// sharp words; before iOS 26 the bar is solid already.
    @ViewBuilder func softBottomEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }

    /// Rises into place as the start comes in: faded, 16 pt lower and a
    /// little smaller, then in place `step` × 50 ms after the first; with
    /// Reduce Motion or Low Power Mode, a short fade.
    func scanEntrance(_ shown: Bool, step: Int, calm: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || calm ? 0 : 16)
            .scaleEffect(shown || calm ? 1 : 0.98)
            .animation(calm ? SnapflyMotion.calm : .spring(response: 0.5, dampingFraction: 0.86).delay(Double(step) * 0.05),
                       value: shown)
    }
}

// MARK: The card

/// The emerald card: "Nur auf diesem iPhone", "Dokument scannen", one line
/// of what it does in white, the white Open Camera pill, and a page in a
/// viewfinder with a mint line across it. The whole card is the button.
struct ScanHero: View {
    let supported: Bool
    let scan: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .subheadline) private var lineSize: CGFloat = 14

    var body: some View {
        Button(action: scan) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    chip
                    Spacer(minLength: 14)
                    Text(L("Scan a document"))
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Straight, bright and private details already covered."))
                        .font(.system(size: lineSize))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    pill
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    ScanHeroPage()
                        .frame(width: 112, height: 150)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
            .background(
                LinearGradient(colors: [SnapflyTokens.scanHeroTop, SnapflyTokens.scanHeroBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: SnapflyTokens.scanHeroRadius, style: .continuous))
            .shadow(color: scheme == .dark ? .clear : .black.opacity(0.12), radius: 14, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.scanHeroRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!supported)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Scan a document"))
        .accessibilityHint(L("Opens the camera"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("scan-camera")
    }

    /// "Nur auf diesem iPhone" on a dark glass, so its small words keep 4.5:1 on the green.
    private var chip: some View {
        Label(L("Only on this iPhone"), systemImage: "shield")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }

    private var pill: some View {
        // One line, a little smaller where the screen is narrow; two at the accessibility sizes.
        Label(L("Open Camera"), systemImage: "dot.viewfinder")
            .font(.body.weight(.semibold))
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(SnapflyTokens.scanHeroInk)
            .padding(.horizontal, 18)
            .frame(minHeight: SnapflyTokens.scanPillHeight)
            .background(.white, in: Capsule())
    }
}

/// A page tilted a little inside four white corners, its lines drawn with
/// shapes, and a mint line across its middle, still.
private struct ScanHeroPage: View {
    var body: some View {
        ZStack {
            page
                .rotationEffect(.degrees(-5))
            Corners()
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            Capsule()
                .fill(SnapflyTokens.scanSweep)
                .frame(width: 104, height: 3)
        }
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white)
            .frame(width: 78, height: 104)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.black.opacity(0.85)).frame(width: 30, height: 4)
                    ForEach([CGFloat(50), 44], id: \.self) { width in
                        Capsule().fill(Color.black.opacity(0.14)).frame(width: width, height: 3)
                    }
                    Capsule().fill(Color.black.opacity(0.85)).frame(width: 40, height: 4)
                    ForEach([CGFloat(52), 38, 46], id: \.self) { width in
                        Capsule().fill(Color.black.opacity(0.14)).frame(width: width, height: 3)
                    }
                    Capsule().fill(Color.black.opacity(0.85)).frame(width: 34, height: 4)
                }
                .padding(11)
            }
    }

    /// The four corners of a viewfinder.
    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let arm = rect.width * 0.2, inset: CGFloat = 2
            let r = rect.insetBy(dx: inset, dy: inset)
            var path = Path()
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1),
            ]
            for (corner, dx, dy) in corners {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }
            return path
        }
    }
}

// MARK: Quick actions

/// Aus Fotos, Verbinden and PDF öffnen side by side, equally tall; one
/// under another at the accessibility text sizes.
struct ScanQuickActions: View {
    @Binding var picked: [PhotosPickerItem]
    @State private var choosingPDF = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: SnapflyTokens.scanItemGap) { actions }
            } else {
                HStack(spacing: SnapflyTokens.scanItemGap) { actions }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            ProjectStore.shared.start(.files([url]))
        }
    }

    @ViewBuilder private var actions: some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
            tile(L("From Photos"), symbol: "photo.on.rectangle")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Choose from Photos"))
        .accessibilityIdentifier("scan-photos")
        Button { ProjectStore.shared.start() } label: {
            tile(L("Combine"), symbol: "plus.square.on.square")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Combine PDFs and photos"))
        .accessibilityIdentifier("project-merge")
        Button { choosingPDF = true } label: {
            tile(L("Open PDF"), symbol: "doc.text")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Open a PDF, put its pages in order and cover them"))
        .accessibilityIdentifier("project-open-pdf")
    }

    /// The glyph top leading, the title bottom leading: on one line, a
    /// little smaller where the tile is narrow; at the accessibility sizes,
    /// beside the glyph, wrapped between words and never cut.
    private func tile(_ title: String, symbol: String) -> some View {
        let large = typeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        return layout {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SnapflyTokens.scanQuickGlyph)
                .frame(width: 24, height: 24)
                .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                .background(SnapflyTokens.projectTile, in: Circle())
                .accessibilityHidden(true)
            if !large { Spacer(minLength: 10) }
            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(large ? nil : 1)
                .minimumScaleFactor(large ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: large)
            if large { Spacer(minLength: 0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: SnapflyTokens.scanQuickHeight, maxHeight: .infinity, alignment: .leading)
        .background(SnapflyTokens.scanQuick, in: RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.05)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
    }
}

// MARK: Recent documents

/// "Zuletzt", the eye and Alle anzeigen over the three documents edited
/// last, newest first, side by side and each whole, as their covered first
/// pages. A new one takes the first place with a light tap; with Reduce
/// Motion it only fades in. Without documents, "Noch nichts gescannt."
struct RecentDocuments: View {
    let projects: [PDFProject]
    let showAll: () -> Void
    @ScanCalm private var calm
    @State private var landings = 0

    var body: some View {
        VStack(alignment: .leading, spacing: SnapflyTokens.scanHeaderGap) {
            HStack(alignment: .center) {
                Text(L("Recent"))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !projects.isEmpty {
                    PreviewToggle()
                    Button(L("Show All"), action: showAll)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SnapflyTokens.protectTint)
                        .frame(minHeight: SnapflyTokens.touch)
                        .accessibilityIdentifier("scan-show-all")
                }
            }
            if projects.isEmpty {
                empty
            } else {
                HStack(alignment: .top, spacing: SnapflyTokens.scanItemGap) {
                    ForEach(projects) { project in
                        RecentDocumentCard(project: project)
                            .frame(maxWidth: .infinity)
                            .transition(calm ? .opacity : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                    }
                    // Fewer than three keep the width of three.
                    ForEach(min(projects.count, ScanStart.shown)..<ScanStart.shown, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("Recent"))
            }
        }
        .animation(calm ? SnapflyMotion.calm : SnapflyMotion.document(false), value: projects.map(\.id))
        .sensoryFeedback(.impact(weight: .light), trigger: landings)
        .onAppear { notice(projects.first?.id) }
        .onChange(of: projects.first?.id) { _, first in notice(first) }
    }

    /// No document yet: one calm line and where they will be.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Nothing scanned yet."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(L("Scan a document and it waits here, covered."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnapflyTokens.scanQuick, in: RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan-recent-empty")
    }

    /// A document new in the first place since the row last showed is told once, with a light tap.
    private func notice(_ first: UUID?) {
        defer { ScanStart.newest = first }
        guard let first, let before = ScanStart.newest, before != first,
              !projects.dropFirst().contains(where: { $0.id == first }) else { return }
        landings += 1
    }
}

/// A recent document: its first page whole in an 18 pt frame 156 high, a
/// chip with how its places stand, then its name and how many pages it
/// has and when it was changed, one line each. A tap opens it; held,
/// Share, Rename and Delete.
struct RecentDocumentCard: View {
    let project: PDFProject
    @ObservedObject private var store = ProjectStore.shared
    @AppStorage(ScanStart.previewKey) private var showsPreview = false
    @Environment(\.scenePhase) private var phase
    /// The first page covered, and the same veiled.
    @State private var picture: UIImage?
    @State private var veiled: UIImage?
    /// How the first page's places stood when it was covered.
    @State private var counts: ProjectStore.FirstCounts?
    @State private var unreadable = false
    @State private var renaming = false
    @State private var name = ""
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var aboutSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var chipSize: CGFloat = 11
    @ScanCalm private var calm

    var body: some View {
        Button { store.open(project.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(RecentDocumentCard.about(project))
                        .font(.system(size: aboutSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            Button { store.share(project.id) } label: { Label(L("Share"), systemImage: "square.and.arrow.up") }
            Button {
                name = project.name
                renaming = true
            } label: { Label(L("Rename"), systemImage: "pencil") }
            Button(role: .destructive) {
                withAnimation(SnapflyMotion.document(calm)) { store.delete(project.id) }
            } label: { Label(L("Delete"), systemImage: "trash") }
        }
        .alert(L("Rename"), isPresented: $renaming) {
            TextField(L("Name"), text: $name)
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Done")) { store.rename(project.id, to: name) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("Share")) { store.share(project.id) }
        .accessibilityAction(named: L("Delete")) { store.delete(project.id) }
        .accessibilityIdentifier("scan-recent")
        .task(id: project.pages.first.map { "\($0.id)-\($0.turns)" }) {
            picture = await store.coveredFirstPage(project)
            veiled = await store.veiledFirstPage(project)
            counts = store.firstCounts(project)
            unreadable = picture == nil
        }
    }

    /// Veiled unless the owner shows the pictures, and always while Snapfly
    /// is away (the app switcher's snapshot) or something on the page is
    /// still to check.
    private var hidden: Bool {
        guard showsPreview, phase == .active else { return true }
        return state.toCheck > 0
    }

    /// How the first page's places stand: as it was left once opened, else
    /// as it was covered for the picture.
    private var state: (covered: Int, toCheck: Int) {
        if let first = project.pages.first, let tally = store.opened(first.id)?.plan.tally {
            return (tally.covered, tally.toCheck)
        }
        return (counts?.covered ?? 0, counts?.toCheck ?? 0)
    }

    /// "2 zu prüfen" while any place is still to check, else "3 verdeckt";
    /// nothing where nothing was covered, never "Nichts Privates".
    private var chip: (text: String, toCheck: Bool)? {
        let state = state
        if state.toCheck > 0 { return (String(format: L("%d to check"), state.toCheck), true) }
        if state.covered > 0 { return (String(format: L("%d covered"), state.covered), false) }
        return nil
    }

    /// Its name, its pages, the day and its chip; never what is on the page.
    private var spoken: String {
        var parts = [project.name.isEmpty ? L("Document") : project.name,
                     String(format: L("Pages: %d"), project.pages.count), Self.day(project.modified, spoken: true)]
        if let chip { parts.append(chip.text) }
        if hidden { parts.append(L("Preview hidden")) }
        return parts.joined(separator: ", ")
    }

    /// The first page covered and whole on the grey, the chip under it; a
    /// lock where it cannot be shown covered.
    private var preview: some View {
        let frame = RoundedRectangle(cornerRadius: SnapflyTokens.scanRecentRadius, style: .continuous)
        let page = RoundedRectangle(cornerRadius: SnapflyTokens.scanRecentPageRadius, style: .continuous)
        return SnapflyTokens.scanRecentGround
            .frame(height: SnapflyTokens.scanRecentHeight)
            .overlay {
                Group {
                    if let shown = hidden ? veiled : picture {
                        Image(uiImage: shown)
                            .resizable()
                            .scaledToFit()
                            .clipShape(page)
                            .overlay(page.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                            .id(hidden)
                            .transition(.opacity)
                    } else if unreadable {
                        Image(systemName: "lock.doc")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, chip == nil ? 12 : 32)
            }
            .overlay(alignment: .bottomLeading) {
                if let chip {
                    Text(chip.text)
                        .font(.system(size: chipSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(chip.toCheck ? SnapflyTokens.scanChipCheckInk : SnapflyTokens.scanChipCoveredInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(chip.toCheck ? SnapflyTokens.scanChipCheck : SnapflyTokens.projectTile, in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(frame)
            .animation(.easeOut(duration: calm ? 0.15 : 0.2), value: picture != nil)
            .animation(SnapflyMotion.toggle(calm), value: hidden)
    }

    /// "5 Seiten · Gestern"; spoken, "5 Seiten, gestern".
    static func about(_ project: PDFProject, spoken: Bool = false) -> String {
        ProjectNaming.pages(project.pages.count) + (spoken ? ", " : " · ") + day(project.modified, spoken: spoken)
    }

    /// Today, yesterday, the day before, a weekday this week, else the date.
    static func day(_ date: Date, spoken: Bool = false) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        guard days >= 0, days < 7 else { return date.formatted(.dateTime.day().month(.abbreviated)) }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let said = formatter.localizedString(from: DateComponents(day: -days))
        guard !spoken, let first = said.first else { return said }
        return first.uppercased() + said.dropFirst()
    }
}

/// Every document, newest first, as Alle anzeigen opens them.
struct AllDocumentsView: View {
    @ObservedObject private var store = ProjectStore.shared

    var body: some View {
        let documents = store.projects.filter { !$0.pages.isEmpty }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: SnapflyTokens.scanItemGap,
                                             alignment: .top)],
                      spacing: 20) {
                ForEach(documents) { project in
                    RecentDocumentCard(project: project)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L("All Documents"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("scan-all-documents")
    }
}

// MARK: How it works

/// A step's number in a mint circle.
struct ScanStepNumber: View {
    let number: Int

    var body: some View {
        Text(number, format: .number)
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(SnapflyTokens.protectTint)
            .frame(width: 26, height: 26)
            .background(SnapflyTokens.projectTile, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "So funktioniert's", from the "?": the four steps, each with its title,
/// as tall as it needs.
struct ScanHowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("How It Works"))
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(L("Everything happens on this iPhone."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
            }
            VStack(spacing: 10) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        ScanStepNumber(number: index + 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.headline)
                            Text(row.line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .measuredHeight($height)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("scan-how-sheet")
    }

    static var rows: [(title: String, line: String)] {
        [(L("Hold"), L("Hold your iPhone over the page. It is found and taken by itself.")),
         (L("Prepare"), L("The page is straightened and brightened. No text is changed.")),
         (L("Cover"), L("Names, numbers and other private details are covered, as your settings say.")),
         (L("Share"), L("Check the places, then copy, share or save the page as a PDF or a picture."))]
    }
}
