import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The parts of the Scan tab's start (`ScanTab`): one job, a scan started
/// in one tap. The emerald card that is the scan button, three quick
/// actions, the documents edited last as their covered first pages, or how
/// a scan goes while there are none yet, and "So funktioniert's" behind
/// the "?". They come in once per launch, one after another.
enum ScanStart {
    /// They came in once since Snapfly started: they do not again on every visit.
    @MainActor static var entered = false
    /// The newest document the row showed, so a new one is told as it arrives.
    @MainActor static var newest: UUID?
    /// How many recent documents show.
    static let shown = 10
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
/// of what it does, the white Open Camera pill, and a page in a viewfinder
/// a mint line reads. The whole card is the button.
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
                        .foregroundStyle(.white.opacity(0.9))
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
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
            .background(
                LinearGradient(colors: [SnapflyTokens.scanHeroTop, SnapflyTokens.scanHeroBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: SnapflyTokens.scanHeroRadius, style: .continuous))
            .shadow(color: scheme == .dark ? .clear : SnapflyTokens.protect.opacity(0.28), radius: 18, y: 10)
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
            .frame(minHeight: 50)
            .background(.white, in: Capsule())
    }
}

/// A page tilted a little inside four white corners, its lines drawn with
/// shapes, and a mint line reading it top to bottom every 2.6 s while the
/// screen shows; still in the middle with Reduce Motion, in Low Power Mode
/// and while Snapfly is away.
private struct ScanHeroPage: View {
    @ScanCalm private var calm
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            page
                .rotationEffect(.degrees(-5))
            Corners()
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            TimelineView(.animation(paused: calm || phase != .active)) { time in
                line(at: calm || phase != .active ? 0.5 : Self.progress(time.date))
            }
        }
    }

    /// How far the line is through its 2.6 s, from 0 to 1.
    private static func progress(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
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

    /// The mint line at `progress` of its way down, fading in and out at its ends.
    private func line(at progress: Double) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [SnapflyTokens.scanSweep.opacity(0), SnapflyTokens.scanSweep,
                                          SnapflyTokens.scanSweep.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 104, height: 3)
            .shadow(color: SnapflyTokens.scanSweep.opacity(0.8), radius: 6)
            .offset(y: CGFloat(progress - 0.5) * 120)
            .opacity(calm ? 0.9 : sin(progress * .pi))
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

/// Aus Fotos, Zusammenfügen and PDF öffnen side by side; one under another
/// at the accessibility text sizes.
struct ScanQuickActions: View {
    @Binding var picked: [PhotosPickerItem]
    @State private var choosingPDF = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { actions }
            } else {
                HStack(spacing: 10) { actions }
            }
        }
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            ProjectStore.shared.start(.files([url]))
        }
    }

    @ViewBuilder private var actions: some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
            tile(L("From Photos"), symbol: "photo")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Choose from Photos"))
        .accessibilityIdentifier("scan-photos")
        Button { ProjectStore.shared.start() } label: {
            tile(L("Merge"), symbol: "plus.square.on.square")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Merge photos, scans and PDFs"))
        .accessibilityIdentifier("project-merge")
        Button { choosingPDF = true } label: {
            tile(L("Open PDF"), symbol: "doc.text")
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("Open a PDF, put its pages in order and cover them"))
        .accessibilityIdentifier("project-open-pdf")
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: labelSize, weight: .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
    }

    private func tile(_ title: String, symbol: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        return layout {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SnapflyTokens.protectTint)
                .frame(width: 34, height: 34)
                .background(SnapflyTokens.projectTile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 10) }
            // On one line where it fits; else broken where its words allow
            // ("Zusammen-fügen"), not wherever the line runs out.
            ViewThatFits(in: .horizontal) {
                label(title).lineLimit(1)
                label(title.replacingOccurrences(of: "\u{AD}", with: "-\n"))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(SnapflyTokens.scanQuick, in: RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.05)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
    }
}

// MARK: Recent documents

/// "Zuletzt" and Alle anzeigen over the documents edited last, newest
/// first, as their covered first pages in a row that scrolls sideways. A
/// new one drops into the first place with a light tap, the others making
/// room, and a soft green ring pulses twice round it.
struct RecentDocuments: View {
    let projects: [PDFProject]
    let showAll: () -> Void
    @ScanCalm private var calm
    /// The document that just arrived, while it is told.
    @State private var arrived: UUID?
    @State private var landings = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Recent"))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                PreviewToggle()
                Button(L("Show All"), action: showAll)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .frame(minHeight: SnapflyTokens.touch)
                    .accessibilityIdentifier("scan-show-all")
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(projects) { project in
                        RecentDocumentCard(project: project, arrived: arrived == project.id)
                            .transition(calm ? .opacity : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Recent"))
        }
        .animation(calm ? SnapflyMotion.calm : SnapflyMotion.document(false), value: projects.map(\.id))
        .sensoryFeedback(.impact(weight: .light), trigger: landings)
        .onAppear { notice(projects.first?.id) }
        .onChange(of: projects.first?.id) { _, first in notice(first) }
    }

    /// A document new in the first place since the row last showed is told once.
    private func notice(_ first: UUID?) {
        defer { ScanStart.newest = first }
        guard let first, let before = ScanStart.newest, before != first,
              !projects.dropFirst().contains(where: { $0.id == first }) else { return }
        withAnimation(calm ? SnapflyMotion.calm : .spring(response: 0.6, dampingFraction: 0.62)) { arrived = first }
        landings += 1
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            arrived = nil
        }
    }
}

/// A recent document: its first page covered, 128 pt wide and 150 high on
/// the grey, its name and how many pages it has and when it was changed;
/// nothing drawn on the page. A tap opens it; held, Share, Rename and Delete.
struct RecentDocumentCard: View {
    let project: PDFProject
    var arrived = false
    var width: CGFloat = 128
    @ObservedObject private var store = ProjectStore.shared
    @AppStorage(ScanStart.previewKey) private var showsPreview = false
    @Environment(\.scenePhase) private var phase
    /// The first page covered, and the same veiled.
    @State private var picture: UIImage?
    @State private var veiled: UIImage?
    @State private var unreadable = false
    @State private var renaming = false
    @State private var name = ""
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var aboutSize: CGFloat = 13
    @ScanCalm private var calm

    var body: some View {
        Button { store.open(project.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(scaled > 1.3 ? 2 : 1)
                    Text(RecentDocumentCard.about(project))
                        .font(.system(size: aboutSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(scaled > 1.3 ? 2 : 1)
                }
            }
            .frame(width: width * min(scaled, 1.8), alignment: .leading)
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
            unreadable = picture == nil
        }
    }

    /// Veiled unless the owner shows the pictures, and always while Snapfly
    /// is away (the app switcher's snapshot) or something on the page is
    /// still to check.
    private var hidden: Bool {
        guard showsPreview, phase == .active else { return true }
        guard let first = project.pages.first else { return true }
        return (store.opened(first.id)?.plan.tally.toCheck ?? 0) > 0
    }

    /// Its name, its pages and the day; never what is on the page.
    private var spoken: String {
        var parts = [project.name.isEmpty ? L("Document") : project.name,
                     String(format: L("Pages: %d"), project.pages.count), Self.day(project.modified, spoken: true)]
        if hidden { parts.append(L("Preview hidden")) }
        return parts.joined(separator: ", ")
    }

    /// The first page covered, on the grey; a lock where it cannot be shown covered.
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: SnapflyTokens.scanRecentRadius, style: .continuous)
        return SnapflyTokens.scanRecentGround
            .frame(height: 150 * min(scaled, 1.8))
            .overlay(alignment: .top) {
                if let shown = hidden ? veiled : picture {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .frame(width: (width - 28) * min(scaled, 1.8))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                        .padding(.top, 14)
                        .id(hidden)
                        .transition(.opacity)
                } else if unreadable {
                    Image(systemName: "lock.doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                }
            }
            .clipShape(shape)
            .overlay {
                if arrived && !calm { ArrivalRing(shape: shape) }
            }
            .animation(.easeOut(duration: calm ? 0.15 : 0.2), value: picture != nil)
            .animation(.easeOut(duration: calm ? 0.15 : 0.2), value: hidden)
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

/// A soft green ring round a document that just arrived, pulsing twice.
private struct ArrivalRing: View {
    let shape: RoundedRectangle

    var body: some View {
        shape
            .strokeBorder(SnapflyTokens.protectLight, lineWidth: 3)
            .shadow(color: SnapflyTokens.protectLight.opacity(0.6), radius: 8)
            .keyframeAnimator(initialValue: 0.0, repeating: false) { ring, glow in
                ring.opacity(glow)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1, duration: 0.3)
                    LinearKeyframe(0.2, duration: 0.35)
                    LinearKeyframe(1, duration: 0.3)
                    LinearKeyframe(0, duration: 0.45)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Every document, newest first, as Alle anzeigen opens them.
struct AllDocumentsView: View {
    @ObservedObject private var store = ProjectStore.shared

    var body: some View {
        let documents = store.projects.filter { !$0.pages.isEmpty }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 180), spacing: 12, alignment: .top)],
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

// MARK: How a scan goes

/// The four steps, short, under "So geht's", while there are no documents yet.
struct ScanSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("How It Goes"))
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Divider().padding(.leading, 56) }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        ScanStepNumber(number: index + 1)
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(SnapflyTokens.scanQuick, in: RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SnapflyTokens.scanQuickRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05)))
        }
        .accessibilityIdentifier("scan-steps")
    }

    static var steps: [String] {
        [L("Hold it over the page; it is taken by itself."),
         L("Straightened and brightened, without changing the text."),
         L("Private details are covered."),
         L("Check, then share or save as a PDF.")]
    }
}

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
