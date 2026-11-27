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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    var body: some View {
        let outline = ResolvedContinuousCorner(radius: NotchCorners.contentRadius)
        let isDark = colorScheme == .dark
        let relief = isPressed ? 0.32 : 1.0
        let rimStrength = isPressed ? 0.5 : 1.0
        let bottom = isDark ? 0.17 : 0.88
        let top = bottom + (isDark ? 0.07 : 0.075) * relief
        let shadow = (isDark ? 0.40 : 0.11) * relief

        outline.fill(LinearGradient(colors: [Color(white: top), Color(white: bottom)],
                                    startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(shadow), radius: isPressed ? 0.6 : 1.45,
                    y: isPressed ? 0.35 : (isDark ? 1.65 : 1))
            .overlay {
                outline.stroke(LinearGradient(colors: [
                    .white.opacity((isDark ? 0.29 : 0.78) * rimStrength),
                    .clear,
                    .black.opacity((isDark ? 0.46 : 0.12) * rimStrength)
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1.25)
                .clipShape(outline)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isPressed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                .shadow(color: .black.opacity(isDark ? 0.40 : 0.25), radius: 5.2, x: 0.8, y: 4)
                .shadow(color: .black.opacity(isDark ? 0.46 : 0.27), radius: 1.45, x: 0.3, y: 1.6)
                .overlay {
                    // A thin rim catches the light above and shades the lower edge.
                    outline.stroke(LinearGradient(stops: [
                        .init(color: .white.opacity(isDark ? 0.58 : 0.49), location: 0),
                        .init(color: .white.opacity(0.14), location: 0.43),
                        .init(color: .clear, location: 0.58),
                        .init(color: .black.opacity(0.62), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
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
