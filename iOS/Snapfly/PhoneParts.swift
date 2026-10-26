import SwiftUI

extension View {
    /// A capsule of glass floating over the picture, as the iPhone's
    /// floating controls are.
    func floatingPill() -> some View {
        font(.footnote)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .padding(.horizontal, 16)
    }

    /// A small control's target for a finger: at least 44 pt across and
    /// down, centred on it, without moving it or changing how it looks.
    /// Where two such controls sit closer than that, the later one takes
    /// the room between them.
    func touchTarget() -> some View {
        contentShape(.interaction, TouchArea())
    }
}

/// A view's own frame, grown evenly on each side to at least a finger's
/// 44 pt across and down.
private struct TouchArea: Shape {
    func path(in rect: CGRect) -> Path {
        let side = SnapflyTokens.touch
        return Path(rect.insetBy(dx: min(0, (rect.width - side) / 2), dy: min(0, (rect.height - side) / 2)))
    }
}

/// A round floating tool over the picture, 44 pt to touch: glass, or the
/// green with a white glyph while it is on.
struct ToolButton: View {
    let symbol: String
    var active = false

    var body: some View {
        let glyph = Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
        Group {
            if active {
                glyph.background(SnapflyTokens.protect, in: Circle())
            } else {
                glyph.editorGlass(in: Circle())
            }
        }
        .contentShape(Circle())
    }
}
