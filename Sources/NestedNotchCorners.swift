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
        if #available(macOS 26.0, *) { ConcentricRectangle().fill(.white.opacity(0.07)) }
        else { UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                      bottomTrailingRadius: max(0, NotchCorners.expandedRadius - NotchCorners.contentInset), topTrailingRadius: 0,
                                      style: .continuous).fill(.white.opacity(0.07)) }
    }
}
struct ArtworkCornerClip: ViewModifier {
    var expanded: Bool
    var size: CGFloat
    var topHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if expanded {
            if #available(macOS 26.0, *) { content.clipShape(ConcentricRectangle()) }
            else {
                content.clipShape(UnevenRoundedRectangle(topLeadingRadius: 0,
                    bottomLeadingRadius: max(0, NotchCorners.expandedRadius - NotchCorners.contentInset),
                    bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
            }
        } else {
            // The detached compact thumbnail is an independent control, not a copy of the concave notch.
            content.clipShape(RoundedRectangle(cornerRadius: NotchCorners.radius * min(1, size / 48) * topHeight / 32, style: .continuous))
        }
    }
}
