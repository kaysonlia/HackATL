/// Haptic pattern for an urgency score (urgency spec §3): ≥ 0.75 triple, ≥ 0.5 double, ≥ 0.3 single.
public enum HapticPattern: Int, Sendable, Equatable {
    case single = 1, double, triple

    public init?(score: Double) {
        if score >= UrgencyScore.urgentThreshold {
            self = .triple
        } else if score >= 0.5 {
            self = .double
        } else if score >= 0.3 {
            self = .single
        } else {
            return nil
        }
    }
}

/// Decides when an event may buzz: only scores with a pattern, at most once per group per cooldown.
public struct HapticGate: Sendable {
    public let cooldown: Double
    private var lastFired: [String: Double] = [:]

    public init(cooldown: Double = 5) { self.cooldown = cooldown }

    public mutating func shouldFire(group: String, score: Double, now: Double) -> HapticPattern? {
        guard let pattern = HapticPattern(score: score) else { return nil }
        if let last = lastFired[group], now - last < cooldown { return nil }
        lastFired[group] = now
        return pattern
    }
}
