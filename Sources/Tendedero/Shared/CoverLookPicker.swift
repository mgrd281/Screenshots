import SwiftUI

/// The cover looks three to a row, each a little chat covered by the same
/// code as a copy, to pick one by looking: in Settings on the Mac. The
/// iPhone's Cover Style page draws its own (`CoverStylePage`).
struct CoverLookPicker: View {
    @Binding var selection: CoverStyle
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                  spacing: 14) {
            ForEach(CoverStyle.allCases) { style in
                tile(style)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ style: CoverStyle) -> some View {
        let chosen = style == selection
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selection = style
        } label: {
            VStack(spacing: 7) {
                sample(style)
                    .aspectRatio(CoverStyle.sampleSize.width / CoverStyle.sampleSize.height, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.12),
                                                lineWidth: chosen ? 2.5 : 1))
                    .shadow(color: .black.opacity(chosen ? 0.18 : 0.06), radius: chosen ? 6 : 2, y: 2)
                Text(style.title)
                    .font(Self.titleFont(chosen: chosen))
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    @ViewBuilder
    private func sample(_ style: CoverStyle) -> some View {
        let scale = max(1, displayScale)
        if let image = picture(style, dark: scheme == .dark, scale: scale) {
            Image(decorative: image, scale: scale)
                .resizable()
                .interpolation(.high)
        } else {
            Color.secondary.opacity(0.15)
        }
    }

    /// Drawn once for each look, appearance and screen.
    private func picture(_ style: CoverStyle, dark: Bool, scale: CGFloat) -> CGImage? {
        let key = "\(style.rawValue)-\(dark)-\(scale)"
        if let drawn = Self.samples[key] { return drawn }
        let drawn = style.sample(dark: dark, scale: scale)
        Self.samples[key] = drawn
        return drawn
    }

    @MainActor private static var samples: [String: CGImage] = [:]

    private static func titleFont(chosen: Bool) -> Font {
        #if os(macOS)
        return .system(size: 11, weight: chosen ? .semibold : .regular)
        #else
        return .caption.weight(chosen ? .semibold : .regular)
        #endif
    }
}
