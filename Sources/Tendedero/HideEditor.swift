import AppKit
import SwiftUI

/// Hide Part: the screenshot large, to drag a box over anything that should
/// not leave the line, like a name the reading missed. What Hide private
/// details covers shows too, so what you see is what goes. The boxes are
/// kept with the photo, and the file itself is never changed.
@MainActor
final class HideEditor: NSObject, NSWindowDelegate {
    static let shared = HideEditor()

    private var window: NSWindow?

    /// Calls back once new boxes are saved; not when cancelled.
    func edit(_ url: URL, saved: @escaping () -> Void) {
        window?.close()
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            NSSound.beep()
            return
        }
        let model = HideModel(image: image, hand: PrivateDetails.hand(url))
        readCovered(url, into: model)

        // As large as fits, never larger than the screenshot itself.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let room = CGSize(width: screen.width * 0.8, height: screen.height * 0.8 - 60)
        let scale = min(1, room.width / image.size.width, room.height / image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        let view = HideEditorView(model: model, size: size) { [weak self] save in
            if save {
                PrivateDetails.setHand(model.hand, for: url)
                saved()
            }
            self?.window?.close()
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = url.deletingPathExtension().lastPathComponent
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.isReleasedWhenClosed = false
        // Over the line, which floats.
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
    }

    /// What Hide private details covers, read in the background.
    private func readCovered(_ url: URL, into model: HideModel) {
        let chosen = PrivateDetails.details
        guard !chosen.isEmpty, isImage(url) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak model] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            let areas = Cover.areas(in: image, chosen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let model { model.found = areas }
                }
            }
        }
    }
}

@MainActor
final class HideModel: ObservableObject {
    let image: NSImage
    /// Hidden by hand, from 0 to 1 from the bottom left.
    @Published var hand: [CGRect]
    /// Covered by Hide private details, the same way.
    @Published var found: [CGRect] = []

    init(image: NSImage, hand: [CGRect]) {
        self.image = image
        self.hand = hand
    }
}

private struct HideEditorView: View {
    @ObservedObject var model: HideModel
    let size: CGSize
    let finish: (Bool) -> Void

    /// The box being drawn, in the view.
    @State private var drawing: CGRect?
    @State private var hovered: Int?
    @State private var crosshair = false

    private static let cover = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: model.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                ForEach(Array(model.found.enumerated()), id: \.offset) { _, box in
                    place(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.cover), box)
                        .allowsHitTesting(false)
                }
                ForEach(Array(model.hand.enumerated()), id: \.offset) { i, box in
                    place(handBox(hovering: hovered == i), box)
                        .onHover { inside in
                            if inside { hovered = i } else if hovered == i { hovered = nil }
                        }
                        .onTapGesture {
                            hovered = nil
                            model.hand.remove(at: i)
                        }
                }
                if let drawing {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                        .frame(width: drawing.width, height: drawing.height)
                        .offset(x: drawing.minX, y: drawing.minY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            // Alongside the boxes' clicks, so a drag can start on one too.
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drawing = rect(from: $0.startLocation, to: $0.location) }
                    .onEnded { value in
                        let rect = rect(from: value.startLocation, to: value.location)
                        drawing = nil
                        guard rect.width >= 4, rect.height >= 4 else { return }
                        model.hand.append(normalized(rect))
                    }
            )
            .onHover { inside in
                guard inside != crosshair else { return }
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                crosshair = inside
            }
            .onDisappear {
                if crosshair { NSCursor.pop() }
            }

            HStack(spacing: 10) {
                Text(L("Drag over anything to hide it. Click a box to show it again."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(L("Remove All")) { model.hand = [] }
                    .disabled(model.hand.isEmpty)
                Button(L("Cancel")) { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button(L("Done")) { finish(true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .frame(width: max(size.width, 520))
        }
    }

    private func handBox(hovering: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Self.cover)
            .overlay {
                if hovering {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: hovering ? 2 : 0))
            .contentShape(Rectangle())
    }

    /// A box from 0 to 1 from the bottom left, placed over the image.
    private func place(_ view: some View, _ box: CGRect) -> some View {
        let rect = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        return view
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Between two points of a drag, kept on the image.
    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        let minX = max(0, min(a.x, b.x)), maxX = min(size.width, max(a.x, b.x))
        let minY = max(0, min(a.y, b.y)), maxY = min(size.height, max(a.y, b.y))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func normalized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / size.width, y: 1 - rect.maxY / size.height,
               width: rect.width / size.width, height: rect.height / size.height)
    }
}
