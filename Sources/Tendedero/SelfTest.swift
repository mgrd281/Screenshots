import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Test on a Sample, in Settings › Privacy: a made-up order confirmation
/// with one of nearly every kind of detail, covered as Settings says, to
/// show what each kind hides. It speaks only for this sample; a real
/// screenshot reads differently.
enum SelfTest {
    /// The sample's lines, the same in every language, so what it holds is
    /// known: it is a picture of a document, not words of Snapfly's.
    static let lines = [
        "Order #1024",
        "Shop: Muster Versand GmbH",
        "Date: 17.10.2026",
        "Customer: Lena Hoffmann",
        "lena.hoffmann@example.com",
        "+49 151 23456789",
        "IBAN: DE89 3704 0044 0532 0130 00",
        "Tax ID: DE123456789",
        "Tracking: 1Z999AA10123456784",
        "PIN: 4821",
        "API key: sk-proj-4fGh7Kp2Qx9Lm3Vb8Nc1Zr6Td",
        "IP: 203.0.113.42",
        "@lena_h",
        "Total: 74,00 €",
        "https://shop.example.com/orders/1024",
        "Medication: Ibuprofen 400 mg",
        "Ship to",
        "Lena Hoffmann",
        "Musterstraße 12",
        "10115 Berlin",
    ]

    /// What the sample's QR code says.
    static let code = "https://shop.example.com/orders/1024"

    /// The sample: black text on white, with the QR code beside it.
    static func sample() -> CGImage? {
        let lineHeight = 72, width = 1500
        let height = lineHeight * lines.count + 120
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = NSFont.systemFont(ofSize: 44)
        for (i, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 70, y: CGFloat(height - 110 - lineHeight * i))
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        if let qr = qrCode(side: 300) {
            context.interpolationQuality = .none
            context.draw(qr, in: CGRect(x: width - 70 - 300, y: height - 70 - 300, width: 300, height: 300))
        }
        return context.makeImage()
    }

    private static func qrCode(side: CGFloat) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(code.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let small = filter.outputImage else { return nil }
        let scale = side / small.extent.width
        let large = small.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(large, from: large.extent)
    }

    /// The sample covered with the given kinds, as a PNG, and what was
    /// covered in it. Off the main thread: it reads the sample as any
    /// screenshot is read.
    static func run(_ chosen: Set<PrivateDetail>) -> (png: Data, report: CoverReport)? {
        guard let sample = sample() else { return nil }
        // The same each time: Apple Intelligence does not read along here.
        guard let made = Finder.covered(sample, chosen, intelligence: false) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, made.image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, CoverReport(made.areas))
    }

    /// The kinds checked that nothing on the sample was covered as, in
    /// Settings' order.
    static func missing(_ chosen: Set<PrivateDetail>, in report: CoverReport) -> [PrivateDetail] {
        PrivateDetail.allCases.filter { chosen.contains($0) && report.kinds[$0, default: 0] == 0 }
    }

    /// What the test says under the sample: what was covered on it, then
    /// what was checked and not found there.
    static func sentences(_ chosen: Set<PrivateDetail>, _ report: CoverReport) -> (covered: String, missing: String?) {
        let covered = report.isEmpty ? L("Nothing checked was found on this sample.")
            : String(format: L("Covered on this sample: %@"), report.summary)
        let absent = missing(chosen, in: report)
        let missing = absent.isEmpty ? nil
            : String(format: L("Checked, but not on this sample: %@"), absent.map(\.title).joined(separator: " · "))
        return (covered, missing)
    }
}
