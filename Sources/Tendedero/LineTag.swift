import AppKit
import SwiftUI

/// A small tag clipped on near the right end of the line. Its grip moves the
/// whole line up or down the screen, with photos picked it can join them
/// into one image, its send button pastes the photos into the app in front,
/// like a chat, and its trash takes everything down at once, each photo the
/// way of its own corner cross.
struct LineTag: View {
    @ObservedObject var line: Line

    static let width: CGFloat = 26
    /// Room for the clip and the four tools. The tag hangs from the top.
    static let maxHeight: CGFloat = 128

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            VStack(spacing: 0) {
                tool("arrow.up.and.down")
                    // Under the clip is grip too.
                    .padding(.top, 12)
                    .overlay(TagArea(label: L("Move the line"), movesLine: true))
                if line.pickedIDs.count > 1 {
                    tool("rectangle.split.1x2")
                        .overlay(TagArea(label: L("Combine into one image")) { line.combine() })
                        .transition(.opacity)
                }
                if line.liveCount > 0 {
                    // The photos picked with ⌘-click, or all of them.
                    tool("paperplane")
                        .overlay(TagArea(label: L("Paste into the app in front")) { line.paste() })
                        .transition(.opacity)
                    // Like the corner cross: a trash only when something goes
                    // to the Trash, rather than only off the line.
                    tool(line.items.contains { !$0.falling && line.isInInbox($0.id) } ? "trash" : "eye.slash")
                        .overlay(TagArea(label: L("Take everything down")) { line.clear() })
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 2)
            .glassFrame(capsule: true)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: TagRectKey.self, value: g.frame(in: .global))
                }
            )
        }
        .animation(.easeOut(duration: 0.2), value: line.liveCount > 0)
        .animation(.easeOut(duration: 0.2), value: line.pickedIDs.count > 1)
    }

    private func tool(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: Self.width, height: 24)
    }
}

/// Clicks and drags on the tag, through AppKit like GrabArea: the panel
/// never becomes key, so only a view of its own takes the first click.
struct TagArea: NSViewRepresentable {
    let label: String
    var movesLine = false
    var onClick: () -> Void = {}

    func makeNSView(context: Context) -> TagView {
        let view = TagView()
        view.setAccessibilityElement(true)
        configure(view)
        return view
    }

    func updateNSView(_ view: TagView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TagView) {
        view.movesLine = movesLine
        view.onClick = onClick
        view.setAccessibilityRole(movesLine ? NSAccessibility.Role.handle : .button)
        view.setAccessibilityLabel(label)
    }
}

final class TagView: NSView {
    /// The line is being moved with the grip. Meanwhile it stays down and
    /// keeps the mouse, wherever the pointer goes.
    static var isMovingLine = false

    var movesLine = false
    var onClick: () -> Void = {}

    /// Where the pointer and the line were when the grip was pressed.
    private var start: (pointer: CGFloat, drop: CGFloat)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard movesLine, let panel = window as? LinePanel else { return }
        start = (NSEvent.mouseLocation.y, panel.drop)
        TagView.isMovingLine = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, let panel = window as? LinePanel else { return }
        // In screen coordinates: the strip changes size under the pointer as
        // the line moves, so its own coordinates would drift.
        panel.moveLine(to: start.drop + start.pointer - NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        if !movesLine, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
        start = nil
        TagView.isMovingLine = false
    }
}
