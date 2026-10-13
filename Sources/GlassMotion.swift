import Foundation
import simd

enum GlassMotion {
    static func size(progress: CGFloat, closed: CGSize, open: CGSize) -> CGSize {
        let p = min(1, max(0, progress))
        // Lateral release precedes depth; reversing the same path gathers the lower lip first.
        let width = 1 - pow(1 - p, 3)
        let height = p * p * (3 - 2 * p)
        return CGSize(width: closed.width + (open.width - closed.width) * width,
                      height: closed.height + (open.height - closed.height) * height)
    }

    struct RimSample {
        var point: CGPoint
        var strength: Double
    }

    static func reflections(size: CGSize, topHeight: CGFloat, pointer: CGPoint) -> [RimSample] {
        let w = Double(size.width), h = Double(size.height), r = min(46, h * 0.55)
        guard w > 32 + 2 * r, h > Double(topHeight) + 2 else { return [] }
        let px = Double(min(1, max(-1, pointer.x))), py = Double(min(1, max(-1, pointer.y)))
        let shift = SIMD3<Double>(px * 38, py * 18, 0)
        let lights = [SIMD3<Double>(-240, Double(topHeight) + 34, 25) + shift,
                      SIMD3<Double>(220, Double(topHeight) + 228, 35) + shift * 0.65,
                      SIMD3<Double>(-45, Double(topHeight) + 173, 20) + shift * 0.8]
        let powers = [1.0, 0.54, 0.28]
        let sharpness = [180.0, 220.0, 260.0]
        var samples: [RimSample] = []
        func append(_ x: Double, _ y: Double, _ nx: Double, _ ny: Double) {
            let normal = SIMD3<Double>(nx * 0.65, ny * 0.65, sqrt(1 - 0.65 * 0.65))
            var strength = 0.0
            for index in 0..<lights.count {
                let light = simd_normalize(lights[index] - SIMD3<Double>(x - w / 2, y, 0))
                let halfVector = simd_normalize(light + SIMD3<Double>(0, 0, 1))
                let lobe = pow(max(0, simd_dot(normal, halfVector)), sharpness[index])
                // Zero the optical tail so weak reflections never form an unbroken border.
                let t = min(1, max(0, (lobe - 0.035) / 0.12))
                strength += powers[index] * lobe * t * t * (3 - 2 * t)
            }
            let capFade = min(1, max(0, (y - Double(topHeight) - 2) / 10))
            samples.append(RimSample(point: CGPoint(x: x, y: y), strength: min(1, strength) * capFade))
        }
        // Sample the actual side walls and quadratic corners, never the top edge.
        let sideStart = min(h - r, Double(topHeight) + 2)
        for i in 0...40 {
            let y = sideStart + (h - r - sideStart) * Double(i) / 40
            append(16, y, -1, 0)
        }
        for i in 1...64 {
            let t = Double(i) / 64, n = simd_normalize(SIMD2<Double>(-(1 - t), t))
            append(16 + r * t * t, h - r * (1 - t) * (1 - t), n.x, n.y)
        }
        for i in 1...160 { append(16 + r + (w - 32 - 2 * r) * Double(i) / 160, h, 0, 1) }
        for i in 1...64 {
            let t = 1 - Double(i) / 64, n = simd_normalize(SIMD2<Double>(1 - t, t))
            append(w - 16 - r * t * t, h - r * (1 - t) * (1 - t), n.x, n.y)
        }
        for i in 1...40 { append(w - 16, h - r - (h - r - sideStart) * Double(i) / 40, 1, 0) }
        return samples
    }
}
