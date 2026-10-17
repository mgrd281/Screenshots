import AppKit
import SwiftUI

/// Whether this Mac draws Liquid Glass, the material of macOS 26.
var hasLiquidGlass: Bool {
    if #available(macOS 26, *) { return true }
    return false
}

/// The dark badge on a photo: a lock, the PDF capsule, the size while an area
/// is chosen. Its white text or glyph sits on translucent black, the one
/// see-through surface of our own with text on it, so it turns solid when
/// Reduce Transparency is on. Materials and Liquid Glass turn opaque by
/// themselves.
enum PhotoBadge {
    /// The fill for SwiftUI, from the environment's Reduce Transparency.
    static func fill(reduced: Bool) -> Color {
        reduced ? Color(white: 0.12) : Color.black.opacity(0.55)
    }

    /// Whether the system asks for less transparency, for what AppKit draws.
    @MainActor static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

/// How things move, and how they keep still when Reduce Motion is on in
/// System Settings › Accessibility › Display: slides, swings and flights
/// give way to short fades.
enum Motion {
    /// For AppKit code, which has no SwiftUI environment to read it from.
    @MainActor static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A spring, or a short fade when motion is reduced.
    static func spring(response: Double, damping: Double, reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.15) : .spring(response: response, dampingFraction: damping)
    }
}

extension View {
    /// Glass around a photo. A photo is content, so this is always the
    /// system's frosted material with a thin edge lit from above. No
    /// refraction: the screenshot stays sharp inside it.
    func glassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        modifier(GlassFrame(shape: glassShape(cornerRadius, circle, capsule), floats: false))
    }

    /// Glass under a control that floats over the photos or over other
    /// apps, like the tag or a corner button: Liquid Glass on macOS 26, the
    /// same frosted glass as the photos before it.
    func controlGlass(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        modifier(GlassFrame(shape: glassShape(cornerRadius, circle, capsule), floats: true))
    }

    private func glassShape(_ cornerRadius: CGFloat, _ circle: Bool, _ capsule: Bool) -> AnyShape {
        if circle { return AnyShape(Circle()) }
        if capsule { return AnyShape(Capsule()) }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Frosted glass, with a firmer edge when Increase Contrast is on.
private struct GlassFrame: ViewModifier {
    let shape: AnyShape
    /// A control over content, which takes Liquid Glass where there is one.
    let floats: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if floats {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                frosted(content)
            }
        } else {
            frosted(content)
        }
    }

    private func frosted(_ content: Content) -> some View {
        let firm = contrast == .increased
        let light = LinearGradient(colors: [Color.white.opacity(firm ? 0.8 : 0.55), Color.white.opacity(firm ? 0.3 : 0.12)],
                                   startPoint: .top, endPoint: .bottom)
        return content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(light, lineWidth: 0.75))
            .overlay(shape.stroke(Color.black.opacity(firm ? 0.45 : 0.10), lineWidth: firm ? 1 : 0.5).padding(-0.5))
    }
}

/// The brand's colours, amber to coral to violet, as the app icon has them.
/// They belong to the icon and the About pane only, never to a control.
enum Brand {
    static let amber = Color(red: 1.0, green: 0.769, blue: 0.361)
    static let coral = Color(red: 1.0, green: 0.369, blue: 0.384)
    static let violet = Color(red: 0.698, green: 0.204, blue: 0.839)

    static let gradient = LinearGradient(colors: [amber, coral, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}
