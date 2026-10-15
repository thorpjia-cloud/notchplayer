import Foundation

@main struct Check {
    static func main() {
        precondition(GlassMotion.presenceWidth(progress: 0, notchWidth: 172, visibleWidth: 292) == 172)
        precondition(GlassMotion.presenceWidth(progress: 1, notchWidth: 172, visibleWidth: 292) == 292)
        precondition(GlassMotion.presenceTension(progress: 0) == 0)
        precondition(GlassMotion.presenceTension(progress: 1) == 0)
        for step in 0...100 {
            let p = CGFloat(step) / 100
            let width = GlassMotion.presenceWidth(progress: p, notchWidth: 172, visibleWidth: 292)
            precondition((172...292).contains(width))
            precondition((0...1).contains(GlassMotion.presenceTension(progress: p)))
        }
        for top: CGFloat in [32, 44] {
            let closed = CGSize(width: 292, height: top), open = CGSize(width: 360, height: top + 100)
            let start = GlassMotion.size(progress: 0, closed: closed, open: open)
            let end = GlassMotion.size(progress: 1, closed: closed, open: open)
            precondition(start.width == closed.width && start.height == closed.height)
            precondition(end.width == open.width && end.height == open.height)
            for step in 0...100 {
                let size = GlassMotion.size(progress: CGFloat(step) / 100, closed: closed, open: open)
                let samples = GlassMotion.reflections(size: size, topHeight: top, pointer: CGPoint(x: 0, y: 0))
                for sample in samples {
                    precondition(sample.point.x.isFinite && sample.point.y.isFinite && sample.strength.isFinite)
                    precondition((0...1).contains(sample.strength))
                    precondition(sample.point.x >= 0 && sample.point.x <= size.width)
                    precondition(sample.point.y >= 0 && sample.point.y <= size.height)
                    if sample.point.y <= top + 2 { precondition(sample.strength == 0) }
                }
            }
            var previous: [GlassMotion.RimSample]?
            var first: [GlassMotion.RimSample] = []
            var last: [GlassMotion.RimSample] = []
            for step in 0...100 {
                let p = CGFloat(step) / 50 - 1
                let samples = GlassMotion.reflections(size: open, topHeight: top, pointer: CGPoint(x: p, y: p))
                // Reflections must leave real gaps, including while the pointer crosses the panel.
                precondition(samples.filter { $0.strength == 0 }.count > samples.count / 2)
                if let previous {
                    precondition(zip(previous, samples).allSatisfy { abs($0.strength - $1.strength) < 0.08 })
                }
                if step == 0 { first = samples }
                last = samples
                previous = samples
            }
            precondition(zip(first, last).contains { abs($0.strength - $1.strength) > 0.3 })
        }
        print("Motion endpoints, rim gaps, cap exclusion, and continuous pointer response passed")
    }
}
