import Foundation

/// Per-label world-frame direction belief over 72 × 5° bins (spec §3.4).
public struct AzimuthBelief: Sendable {
    public static let binCount = 72
    public static let binWidth = 360.0 / Double(binCount)

    public private(set) var probabilities: [Double]
    public var decay = 0.15
    public var epsilon = 0.05
    public var kappa = 6.0

    public init() {
        probabilities = Array(repeating: 1 / Double(Self.binCount), count: Self.binCount)
    }

    public static func binCenter(_ i: Int) -> Double { (Double(i) + 0.5) * binWidth }

    /// Blends toward uniform: p ← (1 − λ)·p + λ·uniform.
    public mutating func decayTowardUniform() {
        let u = 1 / Double(Self.binCount)
        probabilities = probabilities.map { (1 - decay) * $0 + decay * u }
    }

    /// Decays, then multiplies by ε + confidence·Σ wₖ·vonMises(θ − peakₖ, κ) and renormalizes.
    public mutating func update(peaks: [DOAPeak], confidence: Double) {
        decayTowardUniform()
        guard !peaks.isEmpty else { return }
        let c = min(1, max(0, confidence))
        for i in 0..<Self.binCount {
            let theta = Self.binCenter(i)
            let like = peaks.reduce(epsilon) { $0 + c * $1.weight * Circular.vonMises(theta - $1.bearing, kappa: kappa) }
            probabilities[i] *= like
        }
        let sum = probabilities.reduce(0, +)
        probabilities = probabilities.map { $0 / sum }
    }

    /// Mean resultant length R ∈ [0, 1]: 0 = no idea, 1 = certain.
    public var concentration: Double {
        var s = 0.0, c = 0.0
        for (i, p) in probabilities.enumerated() {
            s += p * sin(Self.binCenter(i) * .pi / 180)
            c += p * cos(Self.binCenter(i) * .pi / 180)
        }
        return (s * s + c * c).squareRoot()
    }

    /// Most likely bearing: the argmax bin refined by a circular mean over ±3 bins.
    public var peakBearing: Double {
        let n = Self.binCount
        let i = probabilities.indices.max { probabilities[$0] < probabilities[$1] }!
        let near = (-3...3).map { (i + $0 + n) % n }
        return Circular.mean(near.map(Self.binCenter), weights: near.map { probabilities[$0] }) ?? Self.binCenter(i)
    }
}
