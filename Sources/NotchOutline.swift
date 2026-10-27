import SwiftUI

enum NotchCorners {
    // A developer-reported approximation, not an Apple hardware specification. NSScreen exposes
    // the cutout bounds, not its curve; scale one profile instead of inventing model overrides.
    // https://notchbay.com/blog/macbook-notch-size/
    static let topRadius: CGFloat = 4
    static let radius: CGFloat = 8
}

enum CompactNotchLayout {
    static let outerInset: CGFloat = 14
    static let artworkSize: CGFloat = 22
    static let hardwareClearance: CGFloat = 8

    static func width(notchWidth: CGFloat) -> CGFloat {
        notchWidth + 2 * (outerInset + artworkSize + hardwareClearance)
    }
}

struct NotchOutline: Shape {
    var drawsTopEdge = true
    var compactHeight: CGFloat = 32
    var compactTension: CGFloat = 0
    var opticalTopExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = max(0, rect.width), h = max(0, rect.height)
        let scale = max(0, compactHeight) / 32
        let tension = min(1, max(0, compactTension))
        let shoulder = min(h / 3, w / 4,
                           NotchCorners.topRadius * scale - 1.5 * scale * tension)
        // A straight side must remain between the upper and lower curves, even mid-morph.
        let bottom = min(max(0, h - shoulder - 1), max(0, w / 2 - shoulder),
                         NotchCorners.radius * scale + scale * tension)
        let circle: CGFloat = 0.5522847498
        let topControlX = shoulder * circle
        let topControlY = shoulder * (1 - circle)
        // Keep the same circular corners as the compact notch while the side walls lengthen.
        let bottomControl = bottom * circle
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        p.addCurve(to: CGPoint(x: w - shoulder, y: shoulder),
                   control1: CGPoint(x: w - topControlX, y: 0),
                   control2: CGPoint(x: w - shoulder, y: topControlY))
        p.addLine(to: CGPoint(x: w - shoulder, y: h - bottom))
        p.addCurve(to: CGPoint(x: w - shoulder - bottom, y: h),
                   control1: CGPoint(x: w - shoulder, y: h - bottom + bottomControl),
                   control2: CGPoint(x: w - shoulder - bottom + bottomControl, y: h))
        p.addLine(to: CGPoint(x: shoulder + bottom, y: h))
        p.addCurve(to: CGPoint(x: shoulder, y: h - bottom),
                   control1: CGPoint(x: shoulder + bottom - bottomControl, y: h),
                   control2: CGPoint(x: shoulder, y: h - bottom + bottomControl))
        p.addLine(to: CGPoint(x: shoulder, y: shoulder))
        p.addCurve(to: .zero,
                   control1: CGPoint(x: shoulder, y: topControlY),
                   control2: CGPoint(x: topControlX, y: 0))
        if drawsTopEdge {
            // The native lens closes above the screen so its top specular edge stays offscreen.
            if opticalTopExtension > 0 {
                p.addLine(to: CGPoint(x: 0, y: -opticalTopExtension))
                p.addLine(to: CGPoint(x: w, y: -opticalTopExtension))
                p.addLine(to: CGPoint(x: w, y: 0))
            }
            p.closeSubpath()
        }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
