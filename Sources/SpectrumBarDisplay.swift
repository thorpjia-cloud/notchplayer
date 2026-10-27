import SwiftUI

// Separate rendering from audio capture so the actual small-size glass can be checked with fixed levels.
struct SpectrumBarDisplay: View {
    let levels: [CGFloat]
    let upper: Color
    let lower: Color

    private var gradient: LinearGradient {
        // Readable endpoints keep the smooth vertical transition visible on short bars.
        LinearGradient(stops: [
            .init(color: upper, location: 0),
            .init(color: upper, location: 0.12),
            .init(color: lower, location: 0.88),
            .init(color: lower, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var coloredBars: some View {
        HStack(alignment: .center, spacing: 1.25) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule().fill(gradient).opacity(0.98)
                    .overlay {
                        // Keep the reflection subpixel-thin; a wide white rim erases a narrow bar's hue.
                        Capsule().strokeBorder(
                            LinearGradient(stops: [
                                .init(color: .white.opacity(0.16), location: 0),
                                .init(color: .clear, location: 0.12),
                                .init(color: .clear, location: 0.72),
                                .init(color: .white.opacity(0.06), location: 1)
                            ], startPoint: .leading, endPoint: .trailing), lineWidth: 0.2
                        )
                    }
                    .colorMultiply(Color(white: 1 - 0.32 * Double(i) / Double(max(1, levels.count - 1))))
                    .frame(width: 2.25, height: 2.25 + 13.75 * levels[i])
            }
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    HStack(alignment: .center, spacing: 1.25) {
                        ForEach(levels.indices, id: \.self) { i in
                            Capsule().fill(.clear)
                                .frame(width: 2.25, height: 2.25 + 13.75 * levels[i])
                                .glassEffect(.clear, in: Capsule())
                        }
                    }
                }
                .environment(\.appearsActive, true)
                .materialActiveAppearance(.active)
                // Native glass composites beneath the colored core, preserving both album colors.
                .overlay { coloredBars }
            } else {
                coloredBars
            }
        }
        .animation(.easeInOut(duration: 0.35), value: upper)
        .animation(.easeInOut(duration: 0.35), value: lower)
    }
}
