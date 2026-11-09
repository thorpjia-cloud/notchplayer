import Foundation

/// The settled panel geometry shared by SwiftUI drawing and AppKit hit testing.
struct NotchLayout: Equatable {
    static let expandedContentHeight: CGFloat = 176
    static let expandedArtworkSize: CGFloat = 156
    static let compactOuterInset: CGFloat = 14
    private static let compactArtworkMaximum: CGFloat = 22
    private static let hardwareClearance: CGFloat = 8

    let topHeight: CGFloat
    let hardwareWidth: CGFloat

    init(reservedTop: CGFloat = 32, menuBarInset: CGFloat = 0, notchGap: CGFloat? = nil) {
        topHeight = menuBarInset > 0 ? min(reservedTop, menuBarInset) : reservedTop
        hardwareWidth = notchGap.map { max(130, $0) } ?? 164
    }

    var compactArtworkSize: CGFloat { min(Self.compactArtworkMaximum, topHeight - 8) }

    func compactSize(hovering: Bool) -> CGSize {
        // Reserve space for the full-size artwork even on a shorter menu bar.
        let wing = Self.compactOuterInset + Self.compactArtworkMaximum + Self.hardwareClearance
        return CGSize(width: hardwareWidth + 2 * wing + (hovering ? 12 : 0), height: topHeight)
    }

    var expandedSize: CGSize {
        CGSize(width: 420, height: topHeight + Self.expandedContentHeight)
    }

    static func panelFrame(on screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - 330, y: screen.maxY - 320, width: 660, height: 320)
    }

    func interactionRect(in panel: CGRect, expanded: Bool, hovering: Bool) -> CGRect {
        // Hit testing follows the settled state, independent of in-flight drawing animations.
        let size = expanded ? expandedSize : compactSize(hovering: hovering)
        let inset: CGFloat = expanded ? 14 : 6 * topHeight / 32
        return CGRect(x: panel.midX - size.width / 2 + inset,
                      y: panel.maxY - size.height,
                      width: size.width - 2 * inset, height: size.height)
    }
}
