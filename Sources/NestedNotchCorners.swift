import SwiftUI

private struct ResolvedContinuousCorner: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        // Rebuild primitive elements: returning the original Path preserves its rounded-rect
        // storage, which the active container can reinterpret during clipping.
        let source = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        var resolved = Path()
        source.forEach { element in
            switch element {
            case let .move(to): resolved.move(to: to)
            case let .line(to): resolved.addLine(to: to)
            case let .quadCurve(to, control): resolved.addQuadCurve(to: to, control: control)
            case let .curve(to, c1, c2): resolved.addCurve(to: to, control1: c1, control2: c2)
            case .closeSubpath: resolved.closeSubpath()
            }
        }
        return resolved
    }
}

// The body container follows the visible side walls, excluding the notch's concave top shoulders.
struct NotchCornerContainer: ViewModifier {
    var topHeight: CGFloat
    var height: CGFloat
    func body(content: Content) -> some View {
        let shoulder = NotchCorners.topRadius * topHeight / 32
        let radius = NotchCorners.bottomRadius(height: height, compactHeight: topHeight)
        content.padding(.horizontal, -shoulder)
            .containerShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                                   bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous))
            .padding(.horizontal, shoulder)
    }
}

struct DeviceCornerBackground: View {
    let fill: Color

    var body: some View {
        // Use the inset radius on all four corners without resolving against the container again.
        ResolvedContinuousCorner(radius: NotchCorners.contentRadius).fill(fill)
    }
}
struct ArtworkSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var expanded: Bool
    var size: CGFloat
    var topHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if expanded {
            let outline = ResolvedContinuousCorner(radius: NotchCorners.contentRadius)
            let isDark = colorScheme == .dark
            content.clipShape(outline)
                .shadow(color: .black.opacity(isDark ? 0.30 : 0.20), radius: 5, y: 3)
                .shadow(color: .black.opacity(isDark ? 0.23 : 0.16), radius: 1.25, y: 1)
                .overlay {
                    // Keep the thin reflection inside the existing artwork clip.
                    outline.stroke(
                        LinearGradient(colors: [.white.opacity(isDark ? 0.35 : 0.22), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .clipShape(outline)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        } else {
            // The detached compact thumbnail is an independent control, not a copy of the concave notch.
            content.clipShape(RoundedRectangle(cornerRadius: NotchCorners.radius * min(1, size / 48) * topHeight / 32, style: .continuous))
        }
    }
}
