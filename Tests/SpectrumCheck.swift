import Foundation

@main enum SpectrumCheck {
    static func main() {
        let rate = 48000.0
        for (expected, frequency) in [120.0, 500, 2000, 8000].enumerated() {
            let analyzer = SpectrumAnalyzer(sampleRate: rate)
            // Synthetic tones verify frequency routing, including opposite-phase stereo.
            for i in 0..<4096 {
                let sample = Float(0.2 * sin(2 * Double.pi * frequency * Double(i) / rate))
                analyzer.push(left: sample, right: -sample)
            }
            let bands = analyzer.snapshot()
            let strongest = bands.indices.max(by: { bands[$0] < bands[$1] })!
            precondition(strongest == expected && bands[expected] > 0.5, "Incorrect band for \(frequency) Hz: \(bands)")
            for i in bands.indices where i != expected {
                precondition(bands[expected] - bands[i] > 0.3, "Excessive band leakage: \(bands)")
            }
            for _ in 0..<4096 { analyzer.push(left: 0, right: 0) }
            precondition(analyzer.snapshot().allSatisfy { $0 == 0 }, "Silence must not animate")
            print("PASS \(Int(frequency)) Hz -> band \(expected + 1), stereo phase, silence")
        }
    }
}
