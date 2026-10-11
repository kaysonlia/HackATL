import SoundSightCore
import UserNotifications

/// The single notification for moderate and urgent sounds (urgency spec §6). Every request uses the same identifier, so a new
/// alert replaces the delivered one instead of stacking. Rate-limited by `NotificationPolicy`.
@MainActor
final class UrgentNotifier {
    private let center = UNUserNotificationCenter.current()
    private var policy = NotificationPolicy()

    /// Prompts the first time; afterwards returns the current setting.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Clears rate limits; call when listening restarts (the capture timeline restarts at 0).
    func reset() { policy = NotificationPolicy() }

    /// Posts for the most urgent event the policy lets through, if any. `events` is sorted by score.
    func consider(_ events: [EventDisplay], forward: Double, now: Double, isForeground: Bool) {
        for e in events where e.band != .low {
            guard policy.shouldNotify(group: e.group, score: e.score, now: now, isForeground: isForeground, hits: e.hits) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(e.group): \(e.directionPhrase(forward: forward))"
            content.body = e.levelText.map { "\($0) away" } ?? "\(e.band.label) sound nearby"
            content.sound = .default
            content.interruptionLevel = .active
            center.add(UNNotificationRequest(identifier: NotificationPolicy.identifier, content: content, trigger: nil),
                       withCompletionHandler: nil)
            return
        }
    }

    /// Removes the delivered notification, e.g. when listening stops.
    func clear() {
        center.removeDeliveredNotifications(withIdentifiers: [NotificationPolicy.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [NotificationPolicy.identifier])
    }
}
