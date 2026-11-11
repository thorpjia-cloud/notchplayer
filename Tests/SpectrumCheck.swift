import Foundation

@main enum SpectrumCheck {
    static func main() {
        let rate = 48000.0
        for (expected, frequency) in [100.0, 250, 630, 1600, 4000, 10000].enumerated() {
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
        let analyzer = SpectrumAnalyzer(sampleRate: rate)
        var index = 0
        func tone(_ amplitude: Double, frames: Int) -> CGFloat {
            for _ in 0..<frames {
                let sample = Float(amplitude * sin(2 * Double.pi * 250 * Double(index) / rate))
                analyzer.push(left: sample, right: sample)
                index += 1
            }
            return CGFloat(analyzer.snapshot()[1])
        }
        let quiet = tone(0.006, frames: 4096)
        let steady = tone(0.10, frames: 4096)
        let beat = tone(0.60, frames: 2048)
        let silence = tone(0, frames: 4096)
        precondition(quiet < 0.05 && steady > 0.4 && beat > steady + 0.25 && beat < 0.99 && silence == 0,
                     "Expected a low floor, visible steady signal and unclipped transient: \([quiet, steady, beat, silence])")

        let rise = AudioSpectrum.smoothedLevel(steady, toward: beat, over: 1.0 / 60)
        precondition(rise - steady > (beat - steady) * 0.5 && rise < beat)
        let fall = AudioSpectrum.smoothedLevel(beat, toward: silence, over: 0.09)
        precondition(fall > beat * 0.3 && fall < beat * 0.4)
        precondition(AudioSpectrum.smoothedLevel(beat, toward: beat, over: 1.0 / 60) == beat)
        print("PASS quiet signal, transient headroom and smoothing: \([quiet, steady, beat, silence])")
    }
}
