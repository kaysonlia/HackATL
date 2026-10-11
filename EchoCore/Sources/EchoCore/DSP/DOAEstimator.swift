import simd

public struct DOAConfig: Sendable {
    public var binCount = 72  // 5° bins
    public var smoothingKappa = 8.0
    public var maxPeaks = 3
    public var minPeakFraction = 0.25
    public var minPeakSeparation = 30.0
    /// Drop the device z component (through the phone's thickness) before rotating to the world frame.
    /// On iPhone 16 Pro Max that FOA axis leans strongly toward the camera for every source (device log
    /// 2026-10-11), so only the screen plane carries usable direction.
    public var ignoreThicknessAxis = true

    public init() {}

    public var binWidth: Double { 360 / Double(binCount) }
}

/// A direction-of-arrival peak in the world frame.
public struct DOAPeak: Sendable, Equatable {
    public var bearing: Double
    /// Share of the frame's total peak height, in (0, 1]; the weights of one frame sum to 1.
    public var weight: Double

    public init(bearing: Double, weight: Double) {
        self.bearing = bearing
        self.weight = weight
    }
}

public struct DOAFrame: Sendable {
    public var windowStart: Int64
    public var peaks: [DOAPeak]
    public var diffuseness: Double
    /// Smoothed world-frame histogram (`binCount` bins), for debugging and the probe.
    public var histogram: [Double]

    public init(windowStart: Int64, peaks: [DOAPeak], diffuseness: Double, histogram: [Double]) {
        self.windowStart = windowStart
        self.peaks = peaks
        self.diffuseness = diffuseness
        self.histogram = histogram
    }
}

/// FOA window → world-frame direction peaks (spec §3.3).
public final class DOAEstimator {
    public let config: DOAConfig
    public let intensity: IntensityAnalyzer
    private let kernel: [Double]

    public init(intensity: IntensityConfig = .init(), config: DOAConfig = .init()) throws {
        self.config = config
        self.intensity = try IntensityAnalyzer(config: intensity)
        kernel = (0..<config.binCount).map { Circular.vonMises(Double($0) * config.binWidth, kappa: config.smoothingKappa) }
    }

    public func estimate(_ window: FOAWindow, calibration: FOAAxisCalibration, deviceToWorld: simd_float3x3) -> DOAFrame {
        estimate(intensity.analyze(window), windowStart: window.startSample, calibration: calibration, deviceToWorld: deviceToWorld)
    }

    public func estimate(_ result: IntensityResult, windowStart: Int64, calibration: FOAAxisCalibration,
                         deviceToWorld: simd_float3x3) -> DOAFrame {
        let n = config.binCount
        var raw = [Double](repeating: 0, count: n)
        for bin in result.bins {
            var device = calibration.matrix * bin.raw
            if config.ignoreThicknessAxis { device.z = 0 }
            let v = deviceToWorld * device
            let h = Double(simd_length(SIMD2(v.x, v.y)))
            guard h > 0 else { continue }
            raw[Int(Circular.bearing(v) / config.binWidth) % n] += h
        }
        var smooth = [Double](repeating: 0, count: n)
        for i in 0..<n where raw[i] > 0 {
            for j in 0..<n { smooth[j] += raw[i] * kernel[(j - i + n) % n] }
        }
        return DOAFrame(windowStart: windowStart, peaks: peaks(in: smooth), diffuseness: Double(result.diffuseness), histogram: smooth)
    }

    private func peaks(in s: [Double]) -> [DOAPeak] {
        let n = s.count
        guard let top = s.max(), top > 0 else { return [] }
        let candidates = (0..<n)
            .filter { s[$0] >= s[($0 - 1 + n) % n] && s[$0] > s[($0 + 1) % n] && s[$0] >= config.minPeakFraction * top }
            .sorted { s[$0] > s[$1] }
        var chosen: [(bearing: Double, height: Double)] = []
        for i in candidates where chosen.count < config.maxPeaks {
            let neighborhood = (-2...2).map { (i + $0 + n) % n }
            let bearing = Circular.mean(neighborhood.map { (Double($0) + 0.5) * config.binWidth },
                                        weights: neighborhood.map { s[$0] }) ?? (Double(i) + 0.5) * config.binWidth
            if chosen.allSatisfy({ abs(Circular.difference($0.bearing, bearing)) >= config.minPeakSeparation }) {
                chosen.append((bearing, s[i]))
            }
        }
        let total = chosen.reduce(0) { $0 + $1.height }
        return chosen.map { DOAPeak(bearing: $0.bearing, weight: $0.height / total) }
    }
}
