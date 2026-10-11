/// Four urgency tiers, ordered from least to most urgent.
public enum Urgency: Int, Comparable, Sendable, CaseIterable {
    case low, medium, high, critical

    public init?(tier: String) {
        switch tier.uppercased() {
        case "LOW": self = .low
        case "MEDIUM": self = .medium
        case "HIGH": self = .high
        case "CRITICAL": self = .critical
        default: return nil
        }
    }

    public static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }
}
