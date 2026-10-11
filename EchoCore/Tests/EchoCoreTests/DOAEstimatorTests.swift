import Testing
import simd
@testable import EchoCore

/// deviceToWorld for a phone lying flat, turned clockwise (seen from above) by `degrees`.
func yawRotation(clockwise degrees: Double) -> simd_float3x3 {
    let r = Float(degrees * .pi / 180)
    return simd_float3x3(columns: (SIMD3(cos(r), -sin(r), 0), SIMD3(sin(r), cos(r), 0), SIMD3(0, 0, 1)))
}

struct DOAEstimatorTests {
    let estimator = try! DOAEstimator()
    let flat = matrix_identity_float3x3

    @Test func singleSourceEveryDirection() {
        var rng = SeededRNG(seed: 10)
        for bearing in stride(from: 0.0, to: 360, by: 5) {
            let w = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: bearing)
            let f = estimator.estimate(w, calibration: .identity, deviceToWorld: flat)
            #expect(f.peaks.count == 1)
            #expect(abs(Circular.difference(f.peaks[0].bearing, bearing)) < 5)
            #expect(f.diffuseness < 0.05)
        }
    }

    @Test func elevatedSourceKeepsAzimuth() {
        var rng = SeededRNG(seed: 11)
        let f = estimator.estimate(FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 200, elevation: 60),
                                   calibration: .identity, deviceToWorld: flat)
        #expect(abs(Circular.difference(f.peaks[0].bearing, 200)) < 5)
    }

    @Test func twoSourcesWithDifferentSpectra() {
        var rng = SeededRNG(seed: 12)
        let low = FOASynth.planeWave(FOASynth.tones(band: 300...1500, rng: &rng), bearing: 0)
        let high = FOASynth.planeWave(FOASynth.tones(band: 3000...7000, rng: &rng), bearing: 120)
        let f = estimator.estimate(FOASynth.mix(low, high), calibration: .identity, deviceToWorld: flat)
        #expect(f.peaks.count == 2)
        #expect(f.peaks.contains { abs(Circular.difference($0.bearing, 0)) < 10 })
        #expect(f.peaks.contains { abs(Circular.difference($0.bearing, 120)) < 10 })
        #expect(abs(f.peaks.map(\.weight).reduce(0, +) - 1) < 1e-9)
    }

    @Test func diffuseNoiseAt6dBSNR() {
        var rng = SeededRNG(seed: 13)
        let source = FOASynth.planeWave(FOASynth.whiteNoise(amplitude: 0.1, rng: &rng), bearing: 60)
        let clean = estimator.estimate(source, calibration: .identity, deviceToWorld: flat)
        // 6 dB SNR: diffuse field amplitude is half the source amplitude.
        let noisy = estimator.estimate(FOASynth.mix(source, FOASynth.diffuseNoise(totalAmplitude: 0.05, rng: &rng)),
                                       calibration: .identity, deviceToWorld: flat)
        #expect(abs(Circular.difference(noisy.peaks[0].bearing, 60)) < 15)
        #expect(noisy.diffuseness > clean.diffuseness)
    }

    @Test func silenceHasNoPeaks() {
        let f = estimator.estimate(FOASynth.silence, calibration: .identity, deviceToWorld: flat)
        #expect(f.peaks.isEmpty)
        #expect(f.diffuseness == 1)
    }

    @Test func rotatesIntoWorldFrame() {
        var rng = SeededRNG(seed: 14)
        // Source 30° right of the phone's top; phone turned 90° clockwise → world bearing 120°.
        let w = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 30)
        let f = estimator.estimate(w, calibration: .identity, deviceToWorld: yawRotation(clockwise: 90))
        #expect(abs(Circular.difference(f.peaks[0].bearing, 120)) < 5)
    }

    @Test func appliesAxisCalibration() {
        var rng = SeededRNG(seed: 15)
        let cal = FOAAxisCalibration.initialGuess
        // Encode in device frame, then express in raw FOA axes: raw = Cᵀ · device.
        let dev = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 250)
        let m = cal.matrix.transpose
        func raw(_ i: Int, _ n: Int) -> Float {
            let v = m * SIMD3(dev.x[n], dev.y[n], dev.z[n])
            return v[i]
        }
        let count = dev.w.count
        let foa = FOAWindow(w: dev.w, x: (0..<count).map { raw(0, $0) }, y: (0..<count).map { raw(1, $0) },
                            z: (0..<count).map { raw(2, $0) }, sampleRate: dev.sampleRate, startSample: 0)
        let f = estimator.estimate(foa, calibration: cal, deviceToWorld: flat)
        #expect(abs(Circular.difference(f.peaks[0].bearing, 250)) < 5)
    }

    @Test func passesWindowStartThrough() {
        let f = estimator.estimate(FOASynth.planeWave([Float](repeating: 0, count: 48_000), bearing: 0, startSample: 24_000),
                                   calibration: .identity, deviceToWorld: flat)
        #expect(f.windowStart == 24_000)
    }
}

/// Device log 2026-10-11: the FOA axis through the phone's thickness (screen ↔ camera) carries a strong
/// constant lean toward the camera (elevation −50…−85° for every source). Tilting the phone must not let
/// it leak into the horizontal bearing.
struct ThicknessAxisTests {
    @Test func thicknessBiasDoesNotShiftBearingOnATiltedPhone() throws {
        var rng = SeededRNG(seed: 21)
        let estimator = try DOAEstimator()
        let source = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 90)  // to the phone's right
        // Constant lean along device z, correlated with W (as measured on device).
        let biased = FOAWindow(w: source.w, x: source.x, y: source.y,
                               z: zip(source.z, source.w).map { $0 + 0.8 * $1 },
                               sampleRate: source.sampleRate, startSample: 0)
        let f = estimator.estimate(biased, calibration: .identity, deviceToWorld: tilt(40))
        #expect(abs(Circular.difference(f.peaks[0].bearing, 90)) < 5)
    }
}
