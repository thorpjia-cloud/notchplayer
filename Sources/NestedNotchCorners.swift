import SwiftUI

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
        if #available(macOS 26.0, *) { ConcentricRectangle(topLeadingCorner: .fixed(8), topTrailingCorner: .fixed(8), bottomLeadingCorner: .fixed(8), bottomTrailingCorner: .concentric).fill(.white.opacity(0.07)) }
        else { UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                      bottomTrailingRadius: max(0, NotchCorners.expandedRadius - NotchCorners.contentInset), topTrailingRadius: 8,
                                      style: .continuous).fill(.white.opacity(0.07)) }
    }
}
struct ArtworkCornerClip: ViewModifier {
    var expanded: Bool
    var size: CGFloat
    var topHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if expanded {
            if #available(macOS 26.0, *) { content.clipShape(ConcentricRectangle(topLeadingCorner: .fixed(12), topTrailingCorner: .fixed(12), bottomLeadingCorner: .concentric, bottomTrailingCorner: .fixed(12))) }
            else {
                content.clipShape(UnevenRoundedRectangle(topLeadingRadius: 12,
                    bottomLeadingRadius: max(0, NotchCorners.expandedRadius - NotchCorners.contentInset),
                    bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous))
            }
        } else {
            // The detached compact thumbnail is an independent control, not a copy of the concave notch.
            content.clipShape(RoundedRectangle(cornerRadius: NotchCorners.radius * min(1, size / 48) * topHeight / 32, style: .continuous))
        }
    }
}
