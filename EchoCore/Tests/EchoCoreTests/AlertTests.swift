import Testing
@testable import EchoCore

struct AlertTests {
    @Test func hapticGateCooldownAndTiers() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Speech", urgency: .low, now: 0),
            g.shouldFire(group: "Siren", urgency: .critical, now: 0),
            g.shouldFire(group: "Siren", urgency: .critical, now: 4.9),
            g.shouldFire(group: "Dog", urgency: .medium, now: 4.9),
            g.shouldFire(group: "Siren", urgency: .critical, now: 5),
        ]
        #expect(fired == [false, true, false, true, true])
    }

    @Test func directionPhrases() {
        #expect(DirectionPhrase.describe(radarAngle: 0) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 120) == "behind you to the right (4 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 270) == "to your left (9 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 350) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.clockHour(radarAngle: 184) == 6)
    }
}
