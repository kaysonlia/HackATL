import Testing
import simd
@testable import SoundSightCore

/// Per-frequency-band intensity sums, for the direction test recording.
struct BandSumTests {
    let analyzer = try! IntensityAnalyzer()

    @Test func binsKnowTheirFrequency() {
        var rng = SeededRNG(seed: 50)
        let r = analyzer.analyze(FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 0))
        #expect(r.bins.allSatisfy { $0.frequency >= 200 && $0.frequency <= 8000 })
    }

    @Test func bandsSplitEnergyByFrequency() {
        var rng = SeededRNG(seed: 51)
        let low = FOASynth.planeWave(FOASynth.tones(band: 300...450, rng: &rng), bearing: 90)
        let high = FOASynth.planeWave(FOASynth.tones(band: 2500...3500, rng: &rng), bearing: 270)
        let bands = analyzer.analyze(FOASynth.mix(low, high)).bandSums(edges: IntensityResult.directionTestBands)
        #expect(bands.count == IntensityResult.directionTestBands.count - 1)
        // 200–500 Hz holds the low source (pointing right), 2–4 kHz the high one (pointing left).
        #expect(abs(Circular.difference(Circular.bearing(bands[0].raw), 90)) < 5)
        #expect(abs(Circular.difference(Circular.bearing(bands[3].raw), 270)) < 5)
        #expect(bands[1].energy < 0.05 * bands[0].energy)
    }
}
