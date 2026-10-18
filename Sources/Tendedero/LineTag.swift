import AppKit
import SwiftUI

/// A small tag clipped on near the right end of the line. Its grip moves the
/// whole line up or down the screen, with photos picked it can join them
/// into one image, its magnifying glass searches the words in them, its
/// send button pastes the photos into the app in front,
/// like a chat, its arrow saves them into Downloads as they leave the line,
/// and its trash takes everything down at once, each photo the way of its
/// own corner cross.
struct LineTag: View {
    @ObservedObject var line: Line
    /// On a rope or a wire it is clipped on; in a holder, beside a stack,
    /// with floating photos or at the end of a fan its tools sit a little
    /// closer together.
    var style: Layout.Style = .clothesline

    static let width: CGFloat = Layout.tagWidth
    /// Room for the clip and the tools. The tag hangs from the top.
    static let maxHeight: CGFloat = 152

    /// How tall each tool stands: with a clip 24, without 22, and 20 when
    /// six tools share the tag, so it keeps its height.
    static func rowHeight(tools: Int, clipped: Bool) -> CGFloat {
        tools > 5 ? 20 : (clipped ? 24 : 22)
    }

    private var compact: Bool { !style.clipped }

    /// Combine, with two photos picked or more, is the sixth tool.
    private var rowHeight: CGFloat {
        let tools = line.liveCount > 0 && line.pickedIDs.count > 1 ? 6 : 5
        return Self.rowHeight(tools: tools, clipped: style.clipped)
    }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .opacity(compact ? 0 : 1)
                .zIndex(1)
            VStack(spacing: 0) {
                // Under the clip is grip too.
                TagTool(symbol: "arrow.up.and.down", label: L("Move the line"), style: style, height: rowHeight,
                     topPadding: compact ? 0 : 12, movesLine: true)
                if line.pickedIDs.count > 1 {
                    TagTool(symbol: "rectangle.split.1x2", label: L("Combine into one image"), style: style,
                            height: rowHeight) {
                        line.combine()
                    }
                    .transition(.opacity)
                }
                // With photos picked, PDF takes search's place, so the tag
                // never holds more than six tools.
                if !line.pickedIDs.isEmpty {
                    TagTool(symbol: "doc.richtext", label: L("Make PDF"), style: style, height: rowHeight) {
                        line.makePDF()
                    }
                    .transition(.opacity)
                }
                if line.liveCount > 0 {
                    if line.pickedIDs.isEmpty {
                        TagTool(symbol: "magnifyingglass", label: L("Search screenshots"), style: style,
                                height: rowHeight) {
                            line.onSearch?()
                        }
                        .transition(.opacity)
                    }
                    // The photos picked with ⌘-click, or all of them.
                    TagTool(symbol: "paperplane", label: L("Paste into the app in front"), style: style,
                            height: rowHeight) {
                        _ = line.paste()
                    }
                    .transition(.opacity)
                    // The same photos, saved as they leave the line, above
                    // the trash.
                    TagTool(symbol: "arrow.down.to.line", label: L("Download"), style: style, height: rowHeight) {
                        line.download()
                    }
                    .transition(.opacity)
                    // Like the corner cross: a trash only when something goes
                    // to the Trash, rather than only off the line.
                    TagTool(symbol: trashes ? "trash" : "eye.slash", label: L("Take everything down"), style: style,
                            height: rowHeight) {
                        line.clear()
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 2)
            .background(backing)
            // Liquid Glass carries its own depth; frosted glass needs a shadow
            // to lift it off the desktop.
            .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 6, y: 3)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: TagRectKey.self, value: g.frame(in: .global))
                }
            )
        }
        .animation(.easeOut(duration: 0.2), value: line.liveCount > 0)
        .animation(.easeOut(duration: 0.2), value: line.pickedIDs.count > 1)
        .animation(.easeOut(duration: 0.2), value: line.pickedIDs.isEmpty)
    }

    /// Whether anything on the line goes to the Trash when taken down.
    private var trashes: Bool {
        line.items.contains { !$0.falling && line.isInInbox($0.id) }
    }

    /// Without a holder the tag floats on its own.
    private var lifted: Bool {
        !style.held && !hasLiquidGlass
    }

    /// Glass of its own without a holder; on a shelf, an island or a
    /// filmstrip it shares the holder's, with only a faint capsule to group
    /// the tools.
    @ViewBuilder
    private var backing: some View {
        if !style.held {
            Capsule().fill(.clear).controlGlass(capsule: true)
        } else if style.dark {
            Capsule().fill(Color.white.opacity(0.1))
        } else {
            Capsule().fill(Color.primary.opacity(0.06))
        }
    }
}

/// One of the tag's tools: an SF Symbol that lights up under the pointer,
/// clicked through TagArea.
private struct TagTool: View {
    let symbol: String
    let label: String
    let style: Layout.Style
    var height: CGFloat = 24
    var topPadding: CGFloat = 0
    var movesLine = false
    var action: () -> Void = {}

    @State private var hovering = false

    private var onDark: Bool { style.dark }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(onDark ? Color.white.opacity(0.9) : Color.primary)
            .frame(width: LineTag.width, height: height)
            .background(
                Circle()
                    .fill(onDark ? Color.white.opacity(0.18) : Color.primary.opacity(0.1))
                    .frame(width: min(22, height), height: min(22, height))
                    .opacity(hovering ? 1 : 0)
            )
            .padding(.top, topPadding)
            .overlay(TagArea(label: label, movesLine: movesLine, onClick: action))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
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
