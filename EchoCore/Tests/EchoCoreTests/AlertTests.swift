import Testing
@testable import EchoCore

struct AlertTests {
    @Test func hapticPatternsFollowScore() {
        #expect(HapticPattern(score: 0.75) == .triple)
        #expect(HapticPattern(score: 0.6) == .double)
        #expect(HapticPattern(score: 0.3) == .single)
        #expect(HapticPattern(score: 0.29) == nil)
    }

    @Test func hapticGateCooldown() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Speech", score: 0.1, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 4.9),
            g.shouldFire(group: "Dog", score: 0.45, now: 4.9),
            g.shouldFire(group: "Siren", score: 0.6, now: 5),
        ]
        #expect(fired == [nil, .triple, nil, .single, .double])
    }

    @Test func directionPhrases() {
        #expect(DirectionPhrase.describe(radarAngle: 0) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 120) == "behind you to the right (4 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 270) == "to your left (9 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 350) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.clockHour(radarAngle: 184) == 6)
    }
}
