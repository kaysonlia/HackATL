/// When to post a notification for a moderate or urgent sound (urgency spec §6). Every notification
/// reuses one identifier, so a new one replaces the last instead of stacking. An urgent sound isn't
/// held back by the global gap after a moderate notification.
public struct NotificationPolicy: Sendable {
    public static let identifier = "soundsight.urgent"

    public var minGap = 10.0
    public var groupCooldown = 30.0
    public var scoreRise = 0.15
    /// Detections an event needs before it may notify; filters one-window false alarms.
    public var minHits = 2
    private var lastAny: Double?
    private var lastWasUrgent = false
    private var lastByGroup: [String: (time: Double, score: Double)] = [:]

    public init() {}

    /// True if a notification should be posted now; records it when so.
    public mutating func shouldNotify(group: String, score: Double, now: Double, isForeground: Bool, hits: Int) -> Bool {
        // The capture clock restarted (route or sample-rate change): forget the old timeline.
        if let lastAny, now < lastAny {
            self.lastAny = nil
            lastByGroup = [:]
        }
        guard !isForeground, score >= UrgencyScore.moderateThreshold, hits >= minHits else { return false }
        let urgent = score >= UrgencyScore.urgentThreshold
        if let lastAny, now - lastAny < minGap, !(urgent && !lastWasUrgent) { return false }
        if let last = lastByGroup[group], now - last.time < groupCooldown, score < last.score + scoreRise { return false }
        lastAny = now
        lastWasUrgent = urgent
        lastByGroup[group] = (now, score)
        return true
    }
}
