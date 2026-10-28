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
        // A longer easing span preserves the old diagonal cut while softening entry into the corner.
        let bottom = min(max(0, h - shoulder - 1), max(0, w / 2 - shoulder),
                         (NotchCorners.radius * scale + scale * tension) * 1.5)
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        smoothCorner(&p, from: CGPoint(x: w, y: 0),
                     through: CGPoint(x: w - shoulder, y: 0),
                     to: CGPoint(x: w - shoulder, y: shoulder))
        p.addLine(to: CGPoint(x: w - shoulder, y: h - bottom))
        smoothCorner(&p, from: CGPoint(x: w - shoulder, y: h - bottom),
                     through: CGPoint(x: w - shoulder, y: h),
                     to: CGPoint(x: w - shoulder - bottom, y: h))
        p.addLine(to: CGPoint(x: shoulder + bottom, y: h))
        smoothCorner(&p, from: CGPoint(x: shoulder + bottom, y: h),
                     through: CGPoint(x: shoulder, y: h),
                     to: CGPoint(x: shoulder, y: h - bottom))
        p.addLine(to: CGPoint(x: shoulder, y: shoulder))
        smoothCorner(&p, from: CGPoint(x: shoulder, y: shoulder),
                     through: CGPoint(x: shoulder, y: 0), to: .zero)
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

    private func smoothCorner(_ path: inout Path, from start: CGPoint, through corner: CGPoint, to end: CGPoint) {
        let a = CGSize(width: corner.x - start.x, height: corner.y - start.y)
        let b = CGSize(width: end.x - corner.x, height: end.y - corner.y)
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: start.x + a.width * u + b.width * v,
                    y: start.y + a.height * u + b.height * v)
        }
        // Collinear endpoint controls bring curvature to zero at each straight edge.
        // The two cubics also share first and second derivatives at their midpoint.
        path.addCurve(to: point(0.8, 0.2), control1: point(0.2, 0), control2: point(0.6, 0))
        path.addCurve(to: end, control1: point(1, 0.4), control2: point(1, 0.8))
    }

}
