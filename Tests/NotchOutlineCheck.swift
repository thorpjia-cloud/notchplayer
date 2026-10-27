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
        let width = CompactNotchLayout.width(notchWidth: 185)
        precondition(width == 273)
        precondition((width - 185) / 2 - CompactNotchLayout.outerInset
                     - CompactNotchLayout.artworkSize >= 8)
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
            for x in [CompactNotchLayout.outerInset, CompactNotchLayout.outerInset + 22] {
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
            let compactPoints = sample(compact)
            // Expanding may move the corners, but must not change either corner's curvature.
            for i in 0..<50 {
                let expected = CGPoint(x: compactPoints[i].x + 360 - width,
                                       y: compactPoints[i].y + (i >= 25 ? 100 : 0))
                precondition(hypot(expanded[i].x - expected.x, expanded[i].y - expected.y) < 0.0001)
            }
        }
        print("Compact width, hardware clearance, unclipped wings, monotone morph edges, and consistent compact/expanded corners passed")
    }
}
