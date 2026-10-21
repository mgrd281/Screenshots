import SwiftUI

/// The owner's own name, first under People in Settings, beside the
/// switches for whose names are covered: saved, with "always covered" and
/// a shield, as it is whichever names are chosen; else a row to add it. A
/// tap opens its sheet (`DetailSheet`), as in Always Hide.
struct OwnNameRow: View {
    let name: OwnRule?

    var body: some View {
        HStack(spacing: 12) {
            OwnDetailTile(kind: .name)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Your Name"))
                    .foregroundStyle(.primary)
                Text(name.map { String(format: L("%@ · always covered"), OwnDetails.masked($0)) }
                     ?? L("Add it, and it is covered however it is written"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: name == nil ? "plus.circle.fill" : "checkmark.shield.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(SnapflyTokens.protect)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A detail's symbol, white on its kind's colour in a rounded square (the
/// name green, an address blue, a card orange, an account purple), as
/// Settings and Always Hide show their rows. It grows with the text.
struct OwnDetailTile: View {
    let kind: OwnRule.Kind
    /// Its side at the body's text size.
    static let base: CGFloat = 36
    /// Its side at the largest text sizes, so the words keep their room.
    static let largest: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var size = OwnDetailTile.base

    var body: some View {
        let side = min(size, OwnDetailTile.largest)
        Image(systemName: kind.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(SnapflyTokens.detail(kind), in: RoundedRectangle(cornerRadius: side / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}
