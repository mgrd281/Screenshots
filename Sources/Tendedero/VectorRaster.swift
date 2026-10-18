import CoreGraphics
import ImageIO

/// A picture to and from the tracer's own pixels.
enum VectorRaster {
    /// Pictures with more pixels than this are made smaller before they are traced.
    static let maximumPixels = 12_000_000

    /// The picture in a file as the tracer reads it: upright, and kept to
    /// `limit` pixels, shrunk if it has more. nil when the file is no picture.
    static func pixels(of url: URL, limit: Int = maximumPixels) -> VectorPixels? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let image: CGImage?
        if width * height > limit {
            let scale = (Double(limit) / Double(width * height)).squareRoot()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int((Double(max(width, height)) * scale).rounded(.down)),
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = Cover.upright(source)
        }
        return image.flatMap(pixels(of:))
    }

    /// The picture's colours as straight (not premultiplied) red, green, blue
    /// and alpha, for each pixel from the top left.
    static func pixels(of image: CGImage) -> VectorPixels? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let count = width * height * 4
        let bytes = data.bindMemory(to: UInt8.self, capacity: count)
        var rgba = [UInt8](repeating: 0, count: count)
        for i in stride(from: 0, to: count, by: 4) {
            let alpha = Int(bytes[i + 3])
            rgba[i + 3] = UInt8(alpha)
            if alpha == 255 {
                rgba[i] = bytes[i]
                rgba[i + 1] = bytes[i + 1]
                rgba[i + 2] = bytes[i + 2]
            } else if alpha > 0 {
                // Colours come out of the context already multiplied by the alpha.
                for c in 0..<3 { rgba[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + alpha / 2) / alpha)) }
            }
        }
        return VectorPixels(width: width, height: height, rgba: rgba)
    }

    /// The shapes drawn `width` pixels across, on nothing, as they would
    /// look in an SVG viewer.
    static func render(_ image: VectorImage, width: Int) -> CGImage? {
        guard image.width > 0, image.height > 0, width > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let height = max(1, Int((Double(width) * Double(image.height) / Double(image.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        // The picture counts from its top left, a context from its bottom left.
        let scale = Double(width) / Double(image.width)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        for layer in image.layers {
            context.setFillColor(CGColor(srgbRed: CGFloat(layer.color.red) / 255, green: CGFloat(layer.color.green) / 255,
                                         blue: CGFloat(layer.color.blue) / 255, alpha: 1))
            if layer.fillsPicture {
                context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            } else {
                context.addPath(path(of: layer))
                context.fillPath(using: .evenOdd)
            }
        }
        return context.makeImage()
    }

    /// The outlines of one colour as a path.
    static func path(of layer: VectorLayer) -> CGPath {
        let path = CGMutablePath()
        for contour in layer.contours {
            path.move(to: CGPoint(x: contour.start.x, y: contour.start.y))
            for segment in contour.segments {
                switch segment {
                case .line(let end):
                    path.addLine(to: CGPoint(x: end.x, y: end.y))
                case .curve(let c1, let c2, let end):
                    path.addCurve(to: CGPoint(x: end.x, y: end.y), control1: CGPoint(x: c1.x, y: c1.y),
                                  control2: CGPoint(x: c2.x, y: c2.y))
                }
            }
            path.closeSubpath()
        }
        return path
    }
}
