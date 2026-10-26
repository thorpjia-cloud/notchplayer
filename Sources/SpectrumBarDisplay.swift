import SwiftUI

// Separate rendering from audio capture so the actual small-size glass can be checked with fixed levels.
struct SpectrumBarDisplay: View {
    let levels: [CGFloat]
    let upper: Color
    let lower: Color

    private var gradient: LinearGradient {
        // Short bars need color at both ends, with a compact transition that does not wash them together.
        LinearGradient(stops: [
            .init(color: upper, location: 0),
            .init(color: upper, location: 0.30),
            .init(color: lower, location: 0.70),
            .init(color: lower, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var coloredBars: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4) { i in
                Capsule().fill(gradient).opacity(0.94)
                    .overlay {
                        // Keep the reflection subpixel-thin; a wide white rim erases a 3.5 pt bar's hue.
                        Capsule().strokeBorder(
                            LinearGradient(stops: [
                                .init(color: .white.opacity(0.38), location: 0),
                                .init(color: .clear, location: 0.30),
                                .init(color: .clear, location: 0.72),
                                .init(color: .white.opacity(0.16), location: 1)
                            ], startPoint: .leading, endPoint: .trailing), lineWidth: 0.3
                        )
                    }
                    .frame(width: 3.5, height: 3 + 13 * levels[i])
            }
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<4) { i in
                            Capsule().fill(.clear)
                                .frame(width: 3.5, height: 3 + 13 * levels[i])
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
