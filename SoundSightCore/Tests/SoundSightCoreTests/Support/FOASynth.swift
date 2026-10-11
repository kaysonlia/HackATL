import Foundation
@testable import SoundSightCore

/// Deterministic SplitMix64 generator so synthetic tests are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds synthetic SN3D first-order ambisonic signals. With `.identity` calibration the
/// raw FOA axes equal the device axes, so `bearing`/`elevation` are device-frame angles.
enum FOASynth {
    static let sampleRate = 48_000.0
    static let windowLength = 48_000

    static func whiteNoise(count: Int = windowLength, amplitude: Float = 0.1, rng: inout SeededRNG) -> [Float] {
        (0..<count).map { _ in Float.random(in: -amplitude...amplitude, using: &rng) }
    }

    /// Sum of `toneCount` random-phase sinusoids with frequencies drawn from `band` (Hz).
    static func tones(count: Int = windowLength, band: ClosedRange<Double>, toneCount: Int = 40,
                      amplitude: Float = 0.02, rng: inout SeededRNG) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for _ in 0..<toneCount {
            let f = Double.random(in: band, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            for n in 0..<count { out[n] += amplitude * Float(sin(2 * .pi * f * Double(n) / sampleRate + phase)) }
        }
        return out
    }

    static func planeWave(_ s: [Float], bearing: Double, elevation: Double = 0, startSample: Int64 = 0) -> FOAWindow {
        let u = Circular.unitVector(bearing: bearing, elevation: elevation)
        return FOAWindow(w: s, x: s.map { $0 * u.x }, y: s.map { $0 * u.y }, z: s.map { $0 * u.z },
                         sampleRate: sampleRate, startSample: startSample)
    }

    static func mix(_ a: FOAWindow, _ b: FOAWindow) -> FOAWindow {
        func add(_ p: [Float], _ q: [Float]) -> [Float] { zip(p, q).map { $0 + $1 } }
        return FOAWindow(w: add(a.w, b.w), x: add(a.x, b.x), y: add(a.y, b.y), z: add(a.z, b.z),
                         sampleRate: a.sampleRate, startSample: a.startSample)
    }

    /// Approximates a diffuse field: many uncorrelated noise plane waves from random directions.
    static func diffuseNoise(sources: Int = 48, totalAmplitude: Float, rng: inout SeededRNG) -> FOAWindow {
        let per = totalAmplitude / Float(Double(sources).squareRoot())
        var acc = planeWave([Float](repeating: 0, count: windowLength), bearing: 0)
        for _ in 0..<sources {
            let s = whiteNoise(amplitude: per, rng: &rng)
            acc = mix(acc, planeWave(s, bearing: Double.random(in: 0..<360, using: &rng),
                                     elevation: Double.random(in: -60...60, using: &rng)))
        }
        return acc
    }

    static let silence = planeWave([Float](repeating: 0, count: windowLength), bearing: 0)
}
