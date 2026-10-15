import AppKit
import SwiftUI

/// A small tag clipped on near the right end of the line. Its grip moves the
/// whole line up or down the screen, with photos picked it can join them
/// into one image, its magnifying glass searches the words in them, its
/// send button pastes the photos into the app in front,
/// like a chat, and its trash takes everything down at once, each photo the
/// way of its own corner cross.
struct LineTag: View {
    @ObservedObject var line: Line
    /// On a rope it is clipped on; on a shelf, an island or beside a stack
    /// its tools sit in the holder, a little closer together.
    var style: Layout.Style = .clothesline

    static let width: CGFloat = Layout.tagWidth
    /// Room for the clip and the five tools. The tag hangs from the top.
    static let maxHeight: CGFloat = 152

    private var compact: Bool { style != .clothesline }
    private var toolHeight: CGFloat { compact ? 22 : 24 }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .opacity(compact ? 0 : 1)
                .zIndex(1)
            VStack(spacing: 0) {
                tool("arrow.up.and.down")
                    // Under the clip is grip too.
                    .padding(.top, compact ? 0 : 12)
                    .overlay(TagArea(label: L("Move the line"), movesLine: true))
                if line.pickedIDs.count > 1 {
                    tool("rectangle.split.1x2")
                        .overlay(TagArea(label: L("Combine into one image")) { line.combine() })
                        .transition(.opacity)
                }
                if line.liveCount > 0 {
                    tool("magnifyingglass")
                        .overlay(TagArea(label: L("Search screenshots")) { line.onSearch?() })
                        .transition(.opacity)
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
            .background(backing)
            .shadow(color: .black.opacity(style == .clothesline || style == .stack ? 0.18 : 0), radius: 6, y: 3)
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
            .foregroundStyle(style == .island ? Color.white.opacity(0.9) : Color.primary)
            .frame(width: Self.width, height: toolHeight)
    }

    /// Glass of its own on a rope or beside a stack; on a shelf or an island
    /// it shares the holder's, with only a faint capsule to group the tools.
    @ViewBuilder
    private var backing: some View {
        switch style {
        case .clothesline, .stack:
            Capsule().fill(.clear).glassFrame(capsule: true)
        case .shelf:
            Capsule().fill(Color.primary.opacity(0.06))
        case .island:
            Capsule().fill(Color.white.opacity(0.1))
        }
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
