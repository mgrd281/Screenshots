import SwiftUI

/// The introduction's shade on the Mac and the iPhone: the whole view less a
/// hole round what is pointed at, filled even-odd. The hole glides from one
/// thing to the next.
struct GuideShade: Shape {
    var hole: CGRect
    var corner: CGFloat
    /// Without a hole, the shade is whole.
    var open: Bool

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, corner) }
        set {
            hole.animatableData = newValue.first
            corner = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if open, hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        }
        return path
    }
}
