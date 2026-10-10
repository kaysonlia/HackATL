import Accelerate
import simd

public struct IntensityConfig: Sendable {
    public var fftSize = 1024
    public var hopSize = 512
    public var minHz = 200.0
    public var maxHz = 8000.0
    /// Bins at or below this percentile of the window's bin energies are dropped.
    public var noiseFloorPercentile = 0.2
    /// Bins at or below this absolute energy are always dropped (digital silence).
    public var absoluteEnergyFloor: Float = 1e-9

    public init() {}
}

/// Active intensity of one STFT bin, in raw FOA axes: (Re(W*X), Re(W*Y), Re(W*Z)).
public struct BinIntensity: Sendable {
    public var raw: SIMD3<Float>
    public var energy: Float
}

public struct IntensityResult: Sendable {
    /// Bins that passed the band and noise-floor filters.
    public var bins: [BinIntensity]
    /// 1 − |Σ I| / Σ E over kept bins: 0 for a single plane wave, → 1 for a diffuse field.
    public var diffuseness: Float
    /// Σ I over kept bins (raw FOA axes). Its direction is the energy-weighted arrival direction.
    public var summedRaw: SIMD3<Float>
    public var totalEnergy: Float
}

/// Turns an FOA window into per-bin active-intensity vectors.
public final class IntensityAnalyzer {
    public let config: IntensityConfig
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]

    public init(config: IntensityConfig = .init()) throws {
        self.config = config
        dft = try vDSP.DiscreteFourierTransform(
            count: config.fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: config.fftSize, isHalfWindow: false)
    }

    /// Inclusive FFT bin range kept for a sample rate.
    public func binRange(sampleRate: Double) -> ClosedRange<Int> {
        let n = Double(config.fftSize)
        let lo = max(1, Int((config.minHz * n / sampleRate).rounded(.up)))
        let hi = min(config.fftSize / 2, Int((config.maxHz * n / sampleRate).rounded(.down)))
        return lo...max(lo, hi)
    }

    public func analyze(_ win: FOAWindow) -> IntensityResult {
        let n = config.fftSize
        let range = binRange(sampleRate: win.sampleRate)
        let zeros = [Float](repeating: 0, count: n)
        var all: [BinIntensity] = []
        var start = 0
        while start + n <= win.w.count {
            let spectra = [win.w, win.x, win.y, win.z].map { ch -> (re: [Float], im: [Float]) in
                let frame = vDSP.multiply(ch[start..<(start + n)], window)
                let out = dft.transform(real: frame, imaginary: zeros)
                return (out.real, out.imaginary)
            }
            let (wr, wi) = spectra[0]
            for k in range {
                let i = SIMD3<Float>(
                    wr[k] * spectra[1].re[k] + wi[k] * spectra[1].im[k],
                    wr[k] * spectra[2].re[k] + wi[k] * spectra[2].im[k],
                    wr[k] * spectra[3].re[k] + wi[k] * spectra[3].im[k])
                var e = wr[k] * wr[k] + wi[k] * wi[k]
                for c in 1...3 { e += spectra[c].re[k] * spectra[c].re[k] + spectra[c].im[k] * spectra[c].im[k] }
                all.append(BinIntensity(raw: i, energy: 0.5 * e))
            }
            start += config.hopSize
        }
        guard !all.isEmpty else { return IntensityResult(bins: [], diffuseness: 1, summedRaw: .zero, totalEnergy: 0) }
        let sorted = all.map(\.energy).sorted()
        let pIndex = min(sorted.count - 1, Int(Double(sorted.count) * config.noiseFloorPercentile))
        let floor = max(sorted[pIndex], config.absoluteEnergyFloor)
        let kept = all.filter { $0.energy > floor }
        let sum = kept.reduce(SIMD3<Float>.zero) { $0 + $1.raw }
        let energy = kept.reduce(Float(0)) { $0 + $1.energy }
        let diffuseness = energy > 0 ? max(0, min(1, 1 - simd_length(sum) / energy)) : 1
        return IntensityResult(bins: kept, diffuseness: diffuseness, summedRaw: sum, totalEnergy: energy)
    }
}
