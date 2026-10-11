/// Haptic burst for an urgency score: every detected sound buzzes hard. Urgent (≥ 0.75) triple,
/// moderate (≥ 0.4) double, anything else single; the burst gets longer with urgency.
public enum HapticPattern: Int, Sendable, Equatable {
    case single = 1, double, triple

    public init?(score: Double) {
        if score >= UrgencyScore.urgentThreshold {
            self = .triple
        } else if score >= UrgencyScore.moderateThreshold {
            self = .double
        } else if score > 0 {
            self = .single
        } else {
            return nil
        }
    }

    /// Seconds of continuous full-strength rumble.
    public var duration: Double {
        switch self {
        case .single: 0.6
        case .double: 1.2
        case .triple: 2.0
        }
    }

    public static let tapInterval = 0.1

    /// Sharp taps layered over the rumble, every `tapInterval` from 0 until the burst ends.
    public var tapTimes: [Double] {
        (0..<Int((duration / Self.tapInterval).rounded())).map { Double($0) * Self.tapInterval }
    }
}

/// Decides when an event may buzz: only scores with a pattern, at most once per group per cooldown,
/// except that a stronger pattern (a sound turning urgent) buzzes at once. A clock that jumps backwards
/// (capture restarted) counts as a fresh start.
public struct HapticGate: Sendable {
    public let cooldown: Double
    private var lastFired: [String: (time: Double, pattern: HapticPattern)] = [:]

    public init(cooldown: Double = 3) { self.cooldown = cooldown }

    public mutating func shouldFire(group: String, score: Double, now: Double) -> HapticPattern? {
        guard let pattern = HapticPattern(score: score) else { return nil }
        if let last = lastFired[group], now >= last.time, now - last.time < cooldown,
           pattern.rawValue <= last.pattern.rawValue { return nil }
        lastFired[group] = (now, pattern)
        return pattern
    }
}
