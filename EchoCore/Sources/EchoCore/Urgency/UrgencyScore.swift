import Foundation

/// Continuous urgency in [0, 1] from class tier, loudness and approximate distance (urgency spec §2).
public enum UrgencyScore {
    /// Added to dBFS to approximate dB SPL. Apple's FOA stream is strongly gained: on device a silent room
    /// reads about −45 dBFS on the omni channel and typing nearby −40 to −30, so +80 maps them to ~35 and
    /// 40–50 dB SPL. (The first guess, +120, made a silent room read 77 dB.) Uncalibrated; tune on device.
    public static let dbOffset = 80.0
    /// Scores at or above this are "Urgent": VoiceOver announcement, triple haptic.
    public static let urgentThreshold = 0.75
    /// Scores at or above this are "Moderate" or higher, and post a notification in the background.
    public static let moderateThreshold = 0.4

    public static func classWeight(_ urgency: Urgency) -> Double {
        switch urgency {
        case .critical: 1.0
        case .high: 0.75
        case .medium: 0.5
        case .low: 0.15
        }
    }

    /// Omni-channel RMS → approximate dB SPL, floored at 0 (silence).
    public static func level(rms: Double) -> Double {
        rms > 0 ? max(0, 20 * log10(rms) + dbOffset) : 0
    }

    /// Metres at which a source with typical 1 m level `sourceLevel` is heard at `level`, clamped to [0.5, 100].
    public static func distance(level: Double, sourceLevel: Double) -> Double {
        min(100, max(0.5, pow(10, (sourceLevel - level) / 20)))
    }

    /// 1 at ≤ 2 m, 0 at ≥ 50 m, log-linear between.
    public static func closeness(distance: Double) -> Double {
        clamp(1 - log10(distance / 2) / log10(25))
    }

    /// 0 at ≤ 40 dB, 1 at ≥ 90 dB.
    public static func loudness(level: Double) -> Double {
        clamp((level - 40) / 50)
    }

    /// u = c · (0.35 + 0.65 · (0.6·closeness + 0.4·loudness)).
    public static func score(urgency: Urgency, level: Double, sourceLevel: Double) -> Double {
        let p = closeness(distance: distance(level: level, sourceLevel: sourceLevel))
        return classWeight(urgency) * (0.35 + 0.65 * (0.6 * p + 0.4 * loudness(level: level)))
    }

    /// Gradient hue in degrees: 120 (green) at 0, 60 (yellow) at 0.5, 0 (red) at 1.
    public static func hueDegrees(_ score: Double) -> Double {
        120 * (1 - clamp(score))
    }

    /// "< 1 m", "~3 m", "~20 m", "~100 m": one significant figure.
    public static func formatDistance(_ meters: Double) -> String {
        guard meters >= 1 else { return "< 1 m" }
        let magnitude = pow(10, floor(log10(meters)))
        return "~\(Int((meters / magnitude).rounded() * magnitude)) m"
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// Words for score ranges, so meaning never depends on color alone.
public enum UrgencyBand: Sendable, Equatable {
    case low, moderate, urgent

    public init(score: Double) {
        self = score >= UrgencyScore.urgentThreshold ? .urgent : score >= UrgencyScore.moderateThreshold ? .moderate : .low
    }

    public var label: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .urgent: "Urgent"
        }
    }
}
