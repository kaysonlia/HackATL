import Testing
@testable import EchoCore

struct IntensityAnalyzerTests {
    let analyzer = try! IntensityAnalyzer()

    @Test func binRangeAt48k() {
        #expect(analyzer.binRange(sampleRate: 48_000) == 5...170)
        #expect(analyzer.binRange(sampleRate: 44_100) == 5...185)
        #expect(analyzer.binRange(sampleRate: 16_000) == 13...512)
    }

    @Test func planeWavePointsAtSourceAndIsNotDiffuse() {
        var rng = SeededRNG(seed: 1)
        for bearing in stride(from: 0.0, to: 360, by: 40) {
            let r = analyzer.analyze(FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: bearing))
            #expect(abs(Circular.difference(Circular.bearing(r.summedRaw), bearing)) < 1)
            #expect(r.diffuseness < 0.05)
            #expect(!r.bins.isEmpty)
        }
    }

    @Test func silenceProducesNoBins() {
        let r = analyzer.analyze(FOASynth.silence)
        #expect(r.bins.isEmpty)
        #expect(r.diffuseness == 1)
        #expect(r.totalEnergy == 0)
    }

    @Test func diffuseFieldIsDiffuse() {
        var rng = SeededRNG(seed: 2)
        let r = analyzer.analyze(FOASynth.diffuseNoise(totalAmplitude: 0.1, rng: &rng))
        #expect(r.diffuseness > 0.6)
    }

    @Test func shortWindowYieldsNoFrames() {
        let r = analyzer.analyze(FOASynth.planeWave([Float](repeating: 0.1, count: 512), bearing: 0))
        #expect(r.bins.isEmpty)
        #expect(r.diffuseness == 1)
    }
}
