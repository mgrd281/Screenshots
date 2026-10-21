import SwiftUI

/// Detection (Erkennung), from More: Apple Intelligence reading along on this
/// iPhone, a switch; the check before sharing, always on, not a switch;
/// Faster picture processing, opening its page; and how long covering took
/// on this iPhone lately, two tiles with the middle time large and the
/// slowest but a few small. Kept where they always were (`Finder`,
/// `IndexSettings`, `Timing`).
struct DetectionView: View {
    @ObservedObject var store: MoreStore
    let openPreparing: () -> Void
    @ObservedObject private var indexer = PhotoIndexer.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                reading
                performance
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .defaultScrollAnchor(MoreSample.endAnchor)
        .background(SnapflyTokens.hideGround.ignoresSafeArea())
        .morePage(L("Detection"))
    }

    private var reading: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(get: { store.intelligenceOn }, set: { store.setUsesIntelligence($0) })) {
                row(L("Find more with Apple Intelligence"), symbol: "wand.and.sparkles",
                    detail: store.intelligenceAvailable ? L("Runs only on this iPhone")
                        : L("Needs Apple Intelligence on this device."))
            }
            .tint(SnapflyTokens.hideAccent)
            .disabled(!store.intelligenceAvailable)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("more-intelligence")
            MoreDivider()
            HStack(spacing: 12) {
                row(L("Check before sharing"), symbol: "checkmark.shield",
                    detail: L("Every copy is read again before it leaves, and whatever private still shows is covered too."))
                Spacer(minLength: 8)
                MoreBadge(title: L("Always On"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("more-check")
            MoreDivider()
            Button(action: openPreparing) {
                HStack(spacing: 12) {
                    row(L("Faster picture processing"), symbol: "bolt.badge.clock", detail: nil)
                    Spacer(minLength: 8)
                    Text(indexer.settings.isOn ? L("On") : L("Off"))
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("more-preparing")
        }
        .background(SnapflyTokens.hideCard,
                    in: RoundedRectangle(cornerRadius: SnapflyTokens.hideRowRadius, style: .continuous))
    }

    private func row(_ title: String, symbol: String, detail: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SymbolTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(SnapflyTokens.hideText)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SnapflyTokens.hideSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var performance: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: L("Performance on This iPhone"))
            let shown = store.timing(.shown)
            let ready = store.timing(.ready)
            if shown == nil && ready == nil {
                Text(L("Shows once a few screenshots are protected."))
                    .font(.subheadline)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .moreCard()
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { stats(shown: shown, ready: ready) }
                    VStack(spacing: 12) { stats(shown: shown, ready: ready) }
                }
            }
            if let last = store.lastTime {
                Text(L("Last screenshot") + ": " + Self.duration(last))
                    .font(.footnote)
                    .foregroundStyle(SnapflyTokens.hideSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func stats(shown: (middle: Int, slow: Int)?, ready: (middle: Int, slow: Int)?) -> some View {
        if let shown { stat(L("Picture shown"), shown) }
        if let ready { stat(L("Ready to share"), ready) }
    }

    private func stat(_ title: String, _ times: (middle: Int, slow: Int)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SnapflyTokens.hideText)
            Text(Self.duration(times.middle))
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SnapflyTokens.hideText)
                .accessibilityLabel(String(format: L("Median %@"), Self.duration(times.middle)))
            Text(String(format: L("95%% under %@"), Self.duration(times.slow)))
                .font(.footnote)
                .foregroundStyle(SnapflyTokens.hideSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .moreCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("more-stat")
    }

    /// Milliseconds as the language says a duration, like "0.8 s".
    static func duration(_ milliseconds: Int) -> String {
        Measurement(value: Double(milliseconds) / 1000, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
