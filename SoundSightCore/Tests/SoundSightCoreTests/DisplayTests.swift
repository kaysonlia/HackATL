import Testing
@testable import SoundSightCore

struct DisplayTests {
    @Test func sweepFadesOutAfterThreeSeconds() {
        #expect(RadarSweep.opacity(elapsed: 0) == 1)
        #expect(RadarSweep.opacity(elapsed: 1.99) == 1)
        #expect(abs(RadarSweep.opacity(elapsed: 2.5) - 0.5) < 1e-12)
        #expect(RadarSweep.opacity(elapsed: 3) == 0)
        #expect(RadarSweep.opacity(elapsed: 60) == 0)
        #expect(RadarSweep.opacity(elapsed: -1) == 0)
    }

    @Test func haloStaysWithinFifteenDegreesOfPeak() {
        var b = AzimuthBelief()
        b.update(peaks: [DOAPeak(bearing: 93, weight: 1)], confidence: 0.3)  // broad belief
        let bins = Halo.bins(b.probabilities, around: b.peakBearing)
        #expect(!bins.isEmpty)
        #expect(bins.allSatisfy { abs(Circular.difference(AzimuthBelief.binCenter($0.index), b.peakBearing)) <= 15 })
        #expect(bins.contains { $0.strength == 1 })
        #expect(bins.allSatisfy { $0.strength >= 0.5 })
    }

    @Test func haloDropsWeakBinsAndEmptyBelief() {
        var p = [Double](repeating: 0.001, count: 72)
        p[18] = 1; p[19] = 0.6; p[17] = 0.4
        #expect(Halo.bins(p, around: 92.5).map(\.index) == [18, 19])
        #expect(Halo.bins([Double](repeating: 0, count: 72), around: 0).isEmpty)
        // Uniform belief: exactly the 7 bins whose centers lie within ±15° of the peak.
        #expect(Halo.bins([Double](repeating: 1.0 / 72, count: 72), around: 2.5).count == 7)
    }

    @Test func throttleSendsFirstThenRateLimits() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: "Siren", score: 0.9, levelDB: 80, radarAngle: 10)
        var b = a; b.group = "Dog"
        let sent = [t.shouldSend(a, now: 0), t.shouldSend(b, now: 0.5), t.shouldSend(b, now: 1)]
        #expect(sent == [true, false, true])
    }

    @Test func throttleIgnoresSmallChanges() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: "Siren", score: 0.9, levelDB: 80, radarAngle: 355)
        var small = a; small.score = 0.94; small.levelDB = 82; small.radarAngle = 5
        var angle = a; angle.radarAngle = 20
        var dB = a; dB.levelDB = 83
        var paused = a; paused.paused = true
        var lost = a; lost.radarAngle = nil
        let sent = [
            t.shouldSend(a, now: 0), t.shouldSend(small, now: 2), t.shouldSend(angle, now: 3),
            t.shouldSend(dB, now: 4), t.shouldSend(paused, now: 5), t.shouldSend(lost, now: 6),
        ]
        #expect(sent == [true, false, true, true, true, true])
    }

    /// Final review #3: an interruption must reach the lock screen even within 1 s of the last update.
    @Test func pausedChangesBypassTheRateLimit() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: "Siren", score: 0.9, levelDB: 80, radarAngle: 10)
        var paused = a; paused.paused = true
        let sent = [t.shouldSend(a, now: 0), t.shouldSend(paused, now: 0.3), t.shouldSend(a, now: 0.5)]
        #expect(sent == [true, true, true])
    }

    @Test func throttleKeepAlive() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: nil, score: 0, levelDB: 0, radarAngle: nil)
        let sent = [t.shouldSend(a, now: 0), t.shouldSend(a, now: 7.9), t.shouldSend(a, now: 8)]
        #expect(sent == [true, false, true])
    }

    @Test func shortDirections() {
        #expect(DirectionPhrase.short(radarAngle: 0) == "front")
        #expect(DirectionPhrase.short(radarAngle: 350) == "front")
        #expect(DirectionPhrase.short(radarAngle: 45) == "front-right")
        #expect(DirectionPhrase.short(radarAngle: 100) == "right")
        #expect(DirectionPhrase.short(radarAngle: 200) == "back")
        #expect(DirectionPhrase.short(radarAngle: 280) == "left")
        #expect(DirectionPhrase.short(radarAngle: 330) == "front-left")
    }
}
