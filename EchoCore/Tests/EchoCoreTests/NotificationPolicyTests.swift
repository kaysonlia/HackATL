import Testing
@testable import EchoCore

struct NotificationPolicyTests {
    @Test func notificationsNeverInForegroundOrBelowUrgent() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: true),
            p.shouldNotify(group: "Siren", score: 0.74, now: 0, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.75, now: 0, isForeground: false),
        ]
        #expect(sent == [false, false, true])
        #expect(NotificationPolicy.identifier == "echo.urgent")
    }

    @Test func notificationGlobalGap() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: false),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 9.9, isForeground: false),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 10, isForeground: false),
        ]
        #expect(sent == [true, false, true])
    }

    @Test func notificationGroupCooldownAndRise() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.8, now: 0, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.85, now: 15, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.96, now: 15, isForeground: false),  // rose by ≥ 0.15
            p.shouldNotify(group: "Siren", score: 0.95, now: 44, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.8, now: 45, isForeground: false),   // 30 s after the last
        ]
        #expect(sent == [true, false, true, false, true])
    }
}
