/// The room's background level (noise floor): the 20th percentile of the last 8 s of 0.1 s block levels.
/// Short spikes don't move it; sustained noise (a crowded room) raises it within a few seconds.
public struct AmbientTracker: Sendable {
    public static let blocksKept = 80
    public static let percentile = 0.2
    /// A block is a spike when it is this many dB above ambient…
    public static let spikeMargin = 8.0
    /// …and at least this loud (approximate dB SPL).
    public static let spikeFloor = 50.0

    private var recent: [Double] = []
    public private(set) var level: Double = 0

    public init() {}

    public mutating func add(level blockLevel: Double) {
        recent.append(blockLevel)
        if recent.count > Self.blocksKept { recent.removeFirst(recent.count - Self.blocksKept) }
        let sorted = recent.sorted()
        level = sorted[Int(Double(sorted.count - 1) * Self.percentile)]
    }

    public static func isSpike(level: Double, ambient: Double) -> Bool {
        level >= max(ambient + spikeMargin, spikeFloor)
    }

    public static func word(for dB: Double) -> String {
        switch dB {
        case ..<45: "Quiet"
        case ..<60: "Moderate"
        case ..<75: "Loud"
        default: "Very loud"
        }
    }

    /// 0 at ≤ 40 dB, 1 at ≥ 85 dB: thickness and strength of the ambient ring.
    public static func ringStrength(for dB: Double) -> Double {
        min(1, max(0, (dB - 40) / 45))
    }
}

/// Where the background noise comes from: a slow average of world-frame direction histograms of
/// non-spike blocks (e.g. "the crowd is behind you").
public struct AmbientDirection: Sendable {
    public var rate = 0.05
    private var accumulated = [Double](repeating: 0, count: AzimuthBelief.binCount)

    public init() {}

    public mutating func add(histogram: [Double]) {
        guard histogram.count == accumulated.count, let top = histogram.max(), top > 0 else { return }
        for i in accumulated.indices {
            accumulated[i] = (1 - rate) * accumulated[i] + rate * histogram[i] / top
        }
    }

    /// Background weight per 5° bin, scaled so the strongest is 1 (all zero before any data).
    public var profile: [Double] {
        guard let top = accumulated.max(), top > 0 else { return accumulated }
        return accumulated.map { $0 / top }
    }
}
