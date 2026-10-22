import SwiftUI
import UIKit

/// A page's corners set by hand, when Vision was not sure where it is in a
/// photo, or to cut a page again: the picture whole on black, its four
/// corners as round handles, the page's edges in white and the rest dimmed.
/// While a corner is dragged, a loupe in the top corner away from the
/// finger shows the picture under it two and a half times larger, with a
/// cross where the corner is. Done cuts the page there; Cancel leaves it as
/// it was; Whole Picture takes all of it. VoiceOver moves each corner a
/// little at a time.
struct ScanCornerEditor: View {
    let picture: UIImage
    let done: (ScanQuad?) -> Void
    @State private var quad: ScanQuad
    @State private var dragging: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(image: CGImage, quad: ScanQuad, done: @escaping (ScanQuad?) -> Void) {
        picture = UIImage(cgImage: image)
        self.done = done
        _quad = State(initialValue: quad.clamped)
    }

    private static let loupe: CGFloat = 120
    private static let zoom: CGFloat = 2.5

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let frame = fitted(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: picture)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityHidden(true)
                    edges(in: frame, size: geometry.size)
                    ForEach(0..<4, id: \.self) { corner in
                        handle(corner, in: frame)
                    }
                    if let dragging {
                        loupe(for: dragging, in: frame, size: geometry.size)
                            .transition(.opacity)
                    }
                }
                .coordinateSpace(.named("corners"))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: dragging)
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text(L("Drag the corners onto the page's corners."))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Button(L("Whole Picture")) { quad = .whole }
                        .accessibilityIdentifier("scan-corners-whole")
                        .font(.subheadline.weight(.medium))
                        .tint(.white)
                        .frame(minHeight: SnapflyTokens.touch)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle(L("Crop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { done(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { done(quad) }
                        .fontWeight(.semibold)
                        .disabled(!quad.isUsable)
                        .accessibilityIdentifier("scan-corners-done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The picture as large as fits, in the middle.
    private func fitted(in size: CGSize) -> CGRect {
        let scale = min(size.width / max(picture.size.width, 1), size.height / max(picture.size.height, 1))
        let width = picture.size.width * scale, height = picture.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// A corner where it shows, from the picture's 0 to 1 from the bottom left.
    private func shown(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + (1 - point.y) * frame.height)
    }

    /// Where a finger is, on the picture, from 0 to 1 from the bottom left.
    private func onPicture(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - frame.minX) / frame.width, 0), 1),
                y: min(max(1 - (point.y - frame.minY) / frame.height, 0), 1))
    }

    /// The page's edges in white, everything outside them dimmed.
    private func edges(in frame: CGRect, size: CGSize) -> some View {
        let points = quad.corners.map { shown($0, in: frame) }
        return ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addLines(points)
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Path { path in
                path.addLines(points)
                path.closeSubpath()
            }
            .stroke(Color.white, lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handle(_ corner: Int, in frame: CGRect) -> some View {
        // In two parts, so the compiler checks each in good time.
        let dot = Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(SnapflyTokens.protect, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            .frame(width: SnapflyTokens.touch, height: SnapflyTokens.touch)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("corners"))
                .onChanged { drag in
                    if dragging != corner {
                        dragging = corner
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    var corners = quad.corners
                    corners[corner] = onPicture(drag.location, in: frame)
                    quad.corners = corners
                }
                .onEnded { _ in dragging = nil })
        // Placed last, so the corner is one element where it shows, not all of the picture.
        return dot
            .accessibilityElement()
            .accessibilityLabel(Self.name(of: corner))
            .accessibilityIdentifier("scan-corner-\(corner)")
            .accessibilityAction(named: L("Move Up")) { nudge(corner, x: 0, y: 0.01) }
            .accessibilityAction(named: L("Move Down")) { nudge(corner, x: 0, y: -0.01) }
            .accessibilityAction(named: L("Move Left")) { nudge(corner, x: -0.01, y: 0) }
            .accessibilityAction(named: L("Move Right")) { nudge(corner, x: 0.01, y: 0) }
            .position(shown(quad.corners[corner], in: frame))
    }

    private func nudge(_ corner: Int, x: CGFloat, y: CGFloat) {
        var corners = quad.corners
        corners[corner] = CGPoint(x: min(max(corners[corner].x + x, 0), 1), y: min(max(corners[corner].y + y, 0), 1))
        quad.corners = corners
    }

    private static func name(of corner: Int) -> String {
        switch corner {
        case 0: L("Top left corner")
        case 1: L("Top right corner")
        case 2: L("Bottom right corner")
        default: L("Bottom left corner")
        }
    }

    /// The picture under the corner being dragged, larger, in a round loupe
    /// in the top corner away from it, with a cross where the corner is.
    private func loupe(for corner: Int, in frame: CGRect, size: CGSize) -> some View {
        let point = shown(quad.corners[corner], in: frame)
        let diameter = Self.loupe, zoom = Self.zoom
        let x = point.x < size.width / 2 ? size.width - diameter / 2 - 4 : diameter / 2 + 4
        return ZStack(alignment: .topLeading) {
            Color.black
            Image(uiImage: picture)
                .resizable()
                .frame(width: frame.width * zoom, height: frame.height * zoom)
                .offset(x: diameter / 2 - (point.x - frame.minX) * zoom, y: diameter / 2 - (point.y - frame.minY) * zoom)
        }
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .clipShape(Circle())
        .overlay {
            ZStack {
                Rectangle().fill(SnapflyTokens.protect).frame(width: 1.5, height: 22)
                Rectangle().fill(SnapflyTokens.protect).frame(width: 22, height: 1.5)
            }
        }
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .position(x: x, y: diameter / 2 + 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
