/// When to post the urgent notification (urgency spec §6). Every notification reuses one
/// identifier, so a new one replaces the last instead of stacking.
public struct NotificationPolicy: Sendable {
    public static let identifier = "echo.urgent"

    public var minGap = 10.0
    public var groupCooldown = 30.0
    public var scoreRise = 0.15
    private var lastAny: Double?
    private var lastByGroup: [String: (time: Double, score: Double)] = [:]

    public init() {}

    /// True if a notification should be posted now; records it when so.
    public mutating func shouldNotify(group: String, score: Double, now: Double, isForeground: Bool) -> Bool {
        guard !isForeground, score >= UrgencyScore.urgentThreshold else { return false }
        if let lastAny, now - lastAny < minGap { return false }
        if let last = lastByGroup[group], now - last.time < groupCooldown, score < last.score + scoreRise { return false }
        lastAny = now
        lastByGroup[group] = (now, score)
        return true
    }
}
