/// Decides when an event may buzz: MEDIUM and above only, at most once per group per cooldown.
public struct HapticGate: Sendable {
    public let cooldown: Double
    private var lastFired: [String: Double] = [:]

    public init(cooldown: Double = 5) { self.cooldown = cooldown }

    public mutating func shouldFire(group: String, urgency: Urgency, now: Double) -> Bool {
        guard urgency >= .medium else { return false }
        if let last = lastFired[group], now - last < cooldown { return false }
        lastFired[group] = now
        return true
    }
}
