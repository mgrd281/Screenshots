import AppKit

extension Backdrop {
    /// The photo on its colour, with its room, corners and shadow, and
    /// where it sits, for the places covered in it.
    static func render(_ image: CGImage, _ backdrop: Backdrop) -> (image: CGImage, layout: Layout)? {
        let layout = backdrop.layout(width: image.width, height: image.height)
        let width = Int(layout.canvas.width), height = Int(layout.canvas.height)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high

        paint(backdrop.fill, in: context, size: layout.canvas)
        let shape = CGPath(roundedRect: layout.picture, cornerWidth: layout.radius, cornerHeight: layout.radius, transform: nil)
        castShadow(of: shape, blur: layout.blur, drop: layout.drop, in: context)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.draw(image, in: layout.picture)
        context.restoreGState()
        guard let made = context.makeImage() else { return nil }
        return (made, layout)
    }

    /// The colour over the whole context, from the top left to the bottom
    /// right, as a photo's and a video's background have it.
    static func paint(_ fill: Fill, in context: CGContext, size: CGSize) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let stops = fill.stops
        let colors = stops.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } as CFArray
        let locations = stops.indices.map { CGFloat($0) / CGFloat(max(1, stops.count - 1)) }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// The soft shadow under a photo or a video, from a shape of its own size
    /// under it; nothing without a blur.
    static func castShadow(of shape: CGPath, blur: CGFloat, drop: CGFloat, in context: CGContext) {
        guard blur > 0 else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -drop), blur: blur, color: CGColor(gray: 0, alpha: 0.32))
        context.addPath(shape)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }
}
