import SwiftUI

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

    func path(in rect: CGRect) -> Path {
        let w = max(0, rect.width), h = max(0, rect.height)
        let expansion = min(1, max(0, (h - compactHeight) / 100))
        let scale = max(0, compactHeight) / 32
        let tension = min(1, max(0, compactTension))
        let shoulder = min(h / 3, w / 4,
                           6 * scale + (16 - 6 * scale) * expansion - 1.5 * scale * tension)
        // A straight side must remain between the upper and lower curves, even mid-morph.
        let bottom = min(max(0, h - shoulder - 1), max(0, w / 2 - shoulder),
                         8 * scale + (46 - 8 * scale) * expansion + scale * tension)
        let circle: CGFloat = 0.5522847498
        let topControlX = shoulder * (circle + (1 - circle) * expansion)
        let topControlY = shoulder * (1 - circle) * (1 - expansion) + 6 * expansion
        // At full expansion the cubic is exactly the previous quadratic glass corner.
        let bottomControl = bottom * (circle + (2 / 3 - circle) * expansion)
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
        if drawsTopEdge { p.closeSubpath() }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
