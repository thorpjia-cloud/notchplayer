import SwiftUI

enum NotchCorners {
    // A developer-reported approximation, not an Apple hardware specification. NSScreen exposes
    // the cutout bounds, not its curve; scale one profile instead of inventing model overrides.
    // https://notchbay.com/blog/macbook-notch-size/
    static let topRadius: CGFloat = 4
    static let radius: CGFloat = 8
    static let expandedRadius: CGFloat = 28
    static let contentInset: CGFloat = 10
    static let expandedContentHeight: CGFloat = 176
    static func bottomRadius(height: CGFloat, compactHeight: CGFloat) -> CGFloat {
        let p = min(1, max(0, (height - compactHeight) / expandedContentHeight))
        return radius * compactHeight / 32 + (expandedRadius - radius * compactHeight / 32) * p
    }
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
        let radius = NotchCorners.bottomRadius(height: h, compactHeight: compactHeight)
        let lower = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous)
            .path(in: CGRect(x: shoulder, y: 0, width: max(0, w - 2 * shoulder), height: h))
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        smoothCorner(&p, from: CGPoint(x: w, y: 0),
                     through: CGPoint(x: w - shoulder, y: 0),
                     to: CGPoint(x: w - shoulder, y: shoulder))
        // Reuse SwiftUI's actual continuous bottom corners, matching the rounded container semantics.
        var finishedLower = false
        lower.forEach { element in
            guard !finishedLower else { return }
            switch element {
            case let .move(to): p.addLine(to: to)
            case let .line(to):
                if to.y <= 0 { finishedLower = true } else { p.addLine(to: to) }
            case let .curve(to, c1, c2): p.addCurve(to: to, control1: c1, control2: c2)
            default: break
            }
        }
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
