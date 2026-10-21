import SwiftUI

/// A detail's symbol in the one accent, green on a mint rounded square, as
/// Always Hide shows its rows, the same tile as every symbol under More. It
/// grows with the text.
struct OwnDetailTile: View {
    let kind: OwnRule.Kind
    /// Its side at the body's text size.
    static let base: CGFloat = 36
    /// Its side at the largest text sizes, so the words keep their room.
    static let largest: CGFloat = 52

    var body: some View {
        SymbolTile(symbol: kind.symbol)
    }
}

/// A symbol on a rounded square: in the one accent on mint, as every tile
/// under More has it (`moreGlyph` on `hideAccentSoft`), or grey on grey in
/// More's Features. It grows with the text, up to `OwnDetailTile.largest`.
struct SymbolTile: View {
    let symbol: String
    var base = OwnDetailTile.base
    var ground = SnapflyTokens.hideAccentSoft
    var glyph = SnapflyTokens.moreGlyph
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = min(base * scale, OwnDetailTile.largest)
        Image(systemName: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(glyph)
            .frame(width: side, height: side)
            .background(ground, in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
