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
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) { ConcentricRectangle(corners: .concentric, isUniform: true).fill(.white.opacity(0.07))
            .clipShape(ResolvedContinuousCorner(radius: max(0, NotchCorners.expandedRadius - 2 * NotchCorners.contentInset))) }
        else { RoundedRectangle(cornerRadius: max(0, NotchCorners.expandedRadius - 2 * NotchCorners.contentInset),
                                style: .continuous).fill(.white.opacity(0.07)) }
    }
}
struct ArtworkCornerClip: ViewModifier {
    var expanded: Bool
    var size: CGFloat
    var topHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if expanded {
            // The single visible mask uses the actual outer radius minus the cover inset.
            content.clipShape(ResolvedContinuousCorner(radius: max(0, NotchCorners.expandedRadius - NotchCorners.contentInset)))
        } else {
            // The detached compact thumbnail is an independent control, not a copy of the concave notch.
            content.clipShape(RoundedRectangle(cornerRadius: NotchCorners.radius * min(1, size / 48) * topHeight / 32, style: .continuous))
        }
    }
}
