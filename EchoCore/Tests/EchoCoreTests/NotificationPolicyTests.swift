import Testing
@testable import EchoCore

struct NotificationPolicyTests {
    @Test func notificationsNeverInForegroundOrBelowUrgent() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: true, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.74, now: 0, isForeground: false, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.75, now: 0, isForeground: false, hits: 2),
        ]
        #expect(sent == [false, false, true])
        #expect(NotificationPolicy.identifier == "echo.urgent")
    }

    @Test func notificationGlobalGap() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: false, hits: 2),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 9.9, isForeground: false, hits: 2),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 10, isForeground: false, hits: 2),
        ]
        #expect(sent == [true, false, true])
    }

    @Test func notificationGroupCooldownAndRise() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.8, now: 0, isForeground: false, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.85, now: 15, isForeground: false, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.96, now: 15, isForeground: false, hits: 2),  // rose by ≥ 0.15
            p.shouldNotify(group: "Siren", score: 0.95, now: 44, isForeground: false, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.8, now: 45, isForeground: false, hits: 2),   // 30 s after the last
        ]
        #expect(sent == [true, false, true, false, true])
    }

    @Test func needsTwoDetectionsBeforeNotifying() {
        // YAMNet (background) produced one-window false alarms like Glass Shatter; require confirmation.
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Glass Shatter", score: 0.9, now: 0, isForeground: false, hits: 1),
            p.shouldNotify(group: "Glass Shatter", score: 0.9, now: 0.5, isForeground: false, hits: 2),
        ]
        #expect(sent == [false, true])
    }

    /// Final review #5: a capture-clock restart must not suppress notifications for the old elapsed time.
    @Test func policySurvivesClockRestart() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 600, isForeground: false, hits: 2),
            p.shouldNotify(group: "Siren", score: 0.9, now: 1, isForeground: false, hits: 2),
        ]
        #expect(sent == [true, true])
    }
}
