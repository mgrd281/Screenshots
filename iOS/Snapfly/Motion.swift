import SwiftUI

/// Snapfly's named motion on the iPhone (`MOTION_SYSTEM.md`): each token a
/// SwiftUI animation, and its calm answer for Reduce Motion and Low Power
/// Mode, a short fade where things would move.
enum SnapflyMotion {
    /// The calm answer: 0.15 s on an ease-out.
    static let calm = Animation.easeOut(duration: 0.15)

    /// A touch answered (`motion.feedback`): 0.12 s.
    static let feedback = Animation.easeOut(duration: 0.12)

    /// A switch or a chip turned (`motion.toggle`).
    static func toggle(_ calm: Bool) -> Animation {
        calm ? Self.calm : .spring(response: 0.25, dampingFraction: 0.85)
    }

    /// A detail found: its marks snap in (`motion.find`).
    static func find(_ calm: Bool) -> Animation {
        calm ? Self.calm : .spring(response: 0.3, dampingFraction: 0.7)
    }

    /// A cover laid or taken away, from the reading side (`motion.redact`).
    static func redact(_ calm: Bool) -> Animation {
        calm ? Self.calm : .timingCurve(0.16, 1, 0.3, 1, duration: 0.34)
    }

    /// A page moving from one place to the next (`motion.document`).
    static func document(_ calm: Bool) -> Animation {
        calm ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86)
    }

    /// Protected: the shield landing (`motion.success`).
    static func success(_ calm: Bool) -> Animation {
        calm ? Self.calm : .spring(response: 0.42, dampingFraction: 0.7)
    }

    /// The scanner finding a page's edges and locking on (`motion.lock`).
    static func lock(_ calm: Bool) -> Animation {
        calm ? Self.calm : .spring(response: 0.45, dampingFraction: 0.8)
    }
}

/// A button that gives a little under the finger (`scale.press`), at once
/// with Reduce Motion.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(SnapflyMotion.feedback, value: configuration.isPressed)
    }
}
