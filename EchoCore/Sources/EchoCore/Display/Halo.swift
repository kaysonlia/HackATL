/// One belief bin to draw in the radar halo.
public struct HaloBin: Sendable, Equatable {
    public var index: Int
    /// Probability relative to the strongest bin, in (0, 1].
    public var strength: Double

    public init(index: Int, strength: Double) {
        self.index = index
        self.strength = strength
    }
}

/// Keeps the colored halo tight (urgency spec §3): only bins within `halfWidth` degrees of the
/// belief peak whose probability is at least `minFraction` of the strongest bin.
public enum Halo {
    public static func bins(_ probabilities: [Double], around peak: Double,
                            halfWidth: Double = 15, minFraction: Double = 0.5) -> [HaloBin] {
        guard let top = probabilities.max(), top > 0 else { return [] }
        let width = 360 / Double(probabilities.count)
        return probabilities.indices.compactMap { i in
            let center = (Double(i) + 0.5) * width
            let p = probabilities[i]
            guard abs(Circular.difference(center, peak)) <= halfWidth, p >= minFraction * top else { return nil }
            return HaloBin(index: i, strength: p / top)
        }
    }
}
