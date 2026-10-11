import Testing
@testable import SoundSightCore

struct AlertTests {
    @Test func everyDetectedSoundBuzzes() {
        #expect(HapticPattern(score: 0.75) == .triple)
        #expect(HapticPattern(score: 0.4) == .double)
        #expect(HapticPattern(score: 0.39) == .single)
        #expect(HapticPattern(score: 0.01) == .single)
        #expect(HapticPattern(score: 0) == nil)
    }

    @Test func burstsAreLongAndStrongerWithUrgency() {
        #expect(HapticPattern.single.duration == 0.6)
        #expect(HapticPattern.double.duration == 1.2)
        #expect(HapticPattern.triple.duration == 2.0)
        let taps = HapticPattern.triple.tapTimes
        #expect(taps.first == 0)
        #expect(taps.count == 20)
        #expect(taps.allSatisfy { $0 < HapticPattern.triple.duration })
    }

    @Test func defaultCooldownIsThreeSeconds() {
        var g = HapticGate()
        let fired = [
            g.shouldFire(group: "Siren", score: 0.9, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 2.9),
            g.shouldFire(group: "Siren", score: 0.9, now: 3),
        ]
        #expect(fired == [.triple, nil, .triple])
    }

    @Test func hapticGateCooldown() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Speech", score: 0.1, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 4.9),
            g.shouldFire(group: "Dog", score: 0.35, now: 4.9),
            g.shouldFire(group: "Siren", score: 0.6, now: 5),
        ]
        #expect(fired == [.single, .triple, nil, .single, .double])
    }

    /// Final review #2: a diluted first window (single tap) must not block the urgent triple for 5 s.
    @Test func strongerPatternBreaksTheCooldown() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Siren", score: 0.35, now: 0),
            g.shouldFire(group: "Siren", score: 0.85, now: 0.25),
            g.shouldFire(group: "Siren", score: 0.9, now: 0.5),
        ]
        #expect(fired == [.single, .triple, nil])
    }

    /// Final review #5: the capture clock restarting (route or sample-rate change) must not mute the gate.
    @Test func hapticGateSurvivesClockRestart() {
        var g = HapticGate(cooldown: 5)
        let fired = [g.shouldFire(group: "Siren", score: 0.9, now: 600), g.shouldFire(group: "Siren", score: 0.9, now: 1)]
        #expect(fired == [.triple, .triple])
    }

    @Test func directionPhrases() {
        #expect(DirectionPhrase.describe(radarAngle: 0) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 120) == "behind you to the right (4 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 270) == "to your left (9 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 350) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.clockHour(radarAngle: 184) == 6)
    }
}
