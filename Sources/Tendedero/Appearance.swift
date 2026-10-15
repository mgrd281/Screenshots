import AppKit
import SwiftUI

/// Whether this Mac draws Liquid Glass, the material of macOS 26.
var hasLiquidGlass: Bool {
    if #available(macOS 26, *) { return true }
    return false
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
