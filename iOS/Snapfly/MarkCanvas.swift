import SwiftUI
import UIKit

/// The picture being protected, to zoom with two fingers, with its places
/// marked. A tap turns the place under the finger on or off; while adding,
/// a drag with one finger covers a part by hand, and two fingers move the
/// picture. Places are from 0 to 1 from the bottom left, as Vision measures.
struct MarkCanvas: UIViewRepresentable {
    let image: UIImage
    let marks: [ProtectionPlan.Mark]
    /// Whether the picture is the covered copy itself, so a covered place
    /// needs no ink of its own on it.
    let isCopy: Bool
    let adding: Bool
    let onTap: (CGPoint) -> Void
    let onDraw: (CGRect) -> Void

    func makeUIView(context: Context) -> CanvasView {
        CanvasView()
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.onTap = onTap
        view.onDraw = onDraw
        view.show(image, marks: marks, isCopy: isCopy, adding: adding)
    }
}

final class CanvasView: UIScrollView, UIScrollViewDelegate {
    var onTap: ((CGPoint) -> Void)?
    var onDraw: ((CGRect) -> Void)?
    private let content = UIView()
    private let picture = UIImageView()
    private let overlay = MarksView()
    private var imageSize = CGSize.zero
    /// The size the picture was last fitted to, so it is fitted again only
    /// when the room changes.
    private var fitted = CGSize.zero
    private var start: CGPoint?

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        addSubview(content)
        content.addSubview(picture)
        content.addSubview(overlay)
        picture.contentMode = .scaleToFill
        picture.layer.cornerRadius = 12
        picture.layer.cornerCurve = .continuous
        picture.clipsToBounds = true
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.contentMode = .redraw
        content.addGestureRecognizer(tap)
        drag.maximumNumberOfTouches = 1
        drag.isEnabled = false
        content.addGestureRecognizer(drag)
        isAccessibilityElement = true
        accessibilityLabel = L("Covered screenshot")
        accessibilityHint = L("Details lists every place, to cover or uncover each one.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ image: UIImage, marks: [ProtectionPlan.Mark], isCopy: Bool, adding: Bool) {
        if picture.image !== image {
            picture.image = image
            if image.size != imageSize {
                imageSize = image.size
                fitted = .zero
                setNeedsLayout()
            }
        }
        overlay.marks = marks
        overlay.isCopy = isCopy
        overlay.setNeedsDisplay()
        drag.isEnabled = adding
        // While adding, one finger draws and two move the picture.
        panGestureRecognizer.minimumNumberOfTouches = adding ? 2 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != fitted {
            fitted = bounds.size
            zoomScale = 1
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            content.bounds = CGRect(origin: .zero, size: size)
            picture.frame = content.bounds
            overlay.frame = content.bounds
            contentSize = size
        }
        center()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
    }

    /// The picture in the middle while it is smaller than the room.
    private func center() {
        content.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                                 y: max(contentSize.height, bounds.height) / 2)
    }

    /// A point on the picture, from 0 to 1 from the bottom left.
    private func normalized(_ point: CGPoint) -> CGPoint {
        let size = content.bounds.size
        return CGPoint(x: point.x / max(size.width, 1), y: 1 - point.y / max(size.height, 1))
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onTap?(normalized(gesture.location(in: content)))
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: content)
        switch gesture.state {
        case .began:
            start = point
        case .changed:
            guard let start else { return }
            overlay.drawing = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                     width: abs(point.x - start.x), height: abs(point.y - start.y))
            overlay.setNeedsDisplay()
        case .ended:
            if let drawing = overlay.drawing {
                let size = content.bounds.size
                onDraw?(CGRect(x: drawing.minX / size.width, y: 1 - drawing.maxY / size.height,
                               width: drawing.width / size.width, height: drawing.height / size.height))
            }
            fallthrough
        default:
            start = nil
            overlay.drawing = nil
            overlay.setNeedsDisplay()
        }
    }
}

/// The marks over the picture: ink over a covered place until the copy is
/// made, a dashed outline in the accent round a place to check, a dashed
/// grey one round a place left uncovered, and the part being drawn.
private final class MarksView: UIView {
    var marks: [ProtectionPlan.Mark] = []
    var isCopy = false
    var drawing: CGRect?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let size = bounds.size
        for mark in marks {
            let place = CGRect(x: mark.rect.minX * size.width, y: (1 - mark.rect.maxY) * size.height,
                               width: mark.rect.width * size.width, height: mark.rect.height * size.height)
            let radius = min(place.height / 4, place.width / 2, 8)
            let path = UIBezierPath(roundedRect: place, cornerRadius: radius)
            if mark.covered {
                if !isCopy {
                    // The cover ink, as the copy will show it.
                    UIColor(white: 0.12, alpha: 1).setFill()
                    path.fill()
                }
                if mark.check { outline(path, color: tintColor, in: context) }
            } else {
                outline(path, color: mark.origin == .possible && mark.check ? tintColor : .secondaryLabel, in: context)
            }
        }
        if let drawing {
            outline(UIBezierPath(roundedRect: drawing, cornerRadius: 4), color: tintColor, in: context)
        }
    }

    private func outline(_ path: UIBezierPath, color: UIColor, in context: CGContext) {
        context.saveGState()
        color.setStroke()
        path.lineWidth = 2
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
        context.restoreGState()
    }
}
