import SwiftUI

@main struct Check {
    static func sample(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.forEach { element in
            switch element {
            case let .move(to):
                current = to; points.append(to)
            case let .line(to):
                current = to; points.append(to)
            case let .curve(to, c1, c2):
                let start = current
                for step in 1...24 {
                    let t = CGFloat(step) / 24, u = 1 - t
                    points.append(CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*to.x,
                                          y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*to.y))
                }
                current = to
            default: break
            }
        }
        return points
    }

    static func main() {
        var curves: [(CGPoint, CGPoint, CGPoint, CGPoint)] = []
        var current = CGPoint.zero
        NotchOutline().path(in: CGRect(x: 0, y: 0, width: 360, height: 132)).forEach { element in
            switch element {
            case let .move(to), let .line(to): current = to
            case let .curve(to, c1, c2): curves.append((current, c1, c2, to)); current = to
            default: break
            }
        }
        func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x-b.x, y: a.y-b.y) }
        func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x*b.y-a.y*b.x }
        // SwiftUI Path may quantize control points to float precision.
        func close(_ a: CGPoint, _ b: CGPoint) { precondition(hypot(a.x-b.x,a.y-b.y)<0.0001) }
        for i in [0, curves.count - 2] {
            let (s,a,b,m) = curves[i], (n,c,d,e) = curves[i+1]
            precondition(abs(cross(subtract(a,s),subtract(b,a)))<0.00001, "Entry curvature must be zero")
            precondition(abs(cross(subtract(e,d),subtract(d,c)))<0.00001, "Exit curvature must be zero")
            close(m,n)
            close(subtract(m,b),subtract(c,n))
            close(subtract(subtract(m,b),subtract(b,a)),subtract(subtract(d,c),subtract(c,n)))
        }
        let layout = NotchLayout(reservedTop: 32, menuBarInset: 33, notchGap: 185)
        let width = layout.compactSize(hovering: false).width
        precondition(width == 273)
        precondition((width - 185) / 2 - NotchLayout.compactOuterInset - layout.compactArtworkSize >= 8)
        precondition(layout.compactSize(hovering: true) == CGSize(width: 285, height: 32))
        precondition(layout.expandedSize == CGSize(width: 420, height: 208))
        let panel = NotchLayout.panelFrame(on: CGRect(x: 0, y: 0, width: 1512, height: 982))
        precondition(panel == CGRect(x: 426, y: 662, width: 660, height: 320))
        precondition(layout.interactionRect(in: panel, expanded: false, hovering: true)
                     == CGRect(x: 619.5, y: 950, width: 273, height: 32))
        precondition(layout.interactionRect(in: panel, expanded: true, hovering: true)
                     == CGRect(x: 560, y: 774, width: 392, height: 208))
        let shorterMenu = NotchLayout(reservedTop: 32, menuBarInset: 24)
        precondition(shorterMenu.compactSize(hovering: false) == CGSize(width: 252, height: 24))
        precondition(shorterMenu.compactArtworkSize == 16)
        for top: CGFloat in [32, 44] {
            for step in 0...100 {
                let progress = CGFloat(step) / 100
                let size = GlassMotion.size(progress: progress,
                                            closed: CGSize(width: width, height: top),
                                            open: CGSize(width: 360, height: top + 100))
                for tension: CGFloat in [0, 0.5, 1] {
                    let path = NotchOutline(compactHeight: top, compactTension: tension * (1 - progress))
                        .path(in: CGRect(origin: .zero, size: size))
                    let points = sample(path)
                    for (a, b) in zip(points, points.dropFirst()) {
                        // The old 32 pt outline reversed direction where its two corner curves met.
                        if a.x > size.width / 2 && b.x > size.width / 2 {
                            precondition(b.y >= a.y - 0.0001, "Right edge folds back")
                        }
                        if a.x < size.width / 2 && b.x < size.width / 2 {
                            precondition(b.y <= a.y + 0.0001, "Left edge folds back")
                        }
                        precondition(b.x >= -0.0001 && b.x <= size.width + 0.0001)
                        precondition(b.y >= -0.0001 && b.y <= size.height + 0.0001)
                    }
                }
            }
            let compact = NotchOutline(compactHeight: top)
                .path(in: CGRect(x: 0, y: 0, width: width, height: top))
            for x in [NotchLayout.compactOuterInset, NotchLayout.compactOuterInset + 22] {
                for y in [(top - 22) / 2, (top + 22) / 2] {
                    precondition(compact.contains(CGPoint(x: x, y: y)))
                    precondition(compact.contains(CGPoint(x: width - x, y: y)))
                }
            }
            let expanded = sample(NotchOutline(compactHeight: top)
                .path(in: CGRect(x: 0, y: 0, width: 360, height: top + 100)))
            var opticalOutline = NotchOutline(compactHeight: top)
            opticalOutline.opticalTopExtension = 32
            let optical = sample(opticalOutline.path(in: CGRect(x: 0, y: 0, width: 360, height: top + 100)))
            // Only the closing edge moves offscreen; every visible corner and side stays identical.
            precondition(Array(optical.prefix(expanded.count)) == expanded)
            precondition(optical.dropFirst(expanded.count).map(\.y) == [-32, -32, 0])
            precondition(NotchCorners.bottomRadius(height: top + NotchLayout.expandedContentHeight, compactHeight: top) == NotchCorners.expandedRadius)

        }
        print("Settled layout and hit regions, hardware clearance, unclipped wings, monotone morph edges, and native continuous bottom corners and smooth concave shoulders passed")
    }
}
