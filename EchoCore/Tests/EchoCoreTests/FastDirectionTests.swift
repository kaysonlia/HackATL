import Testing
@testable import EchoCore

/// 0.1 s blocks nudge the direction of named sounds between classifier windows (10 updates/s).
struct FastDirectionTests {
    let urgency = UrgencyMap(tiers: ["Dog": .medium])

    func trackerWithDog(at bearing: Double) -> EventTracker {
        let t = EventTracker(urgencyMap: urgency)
        let doa = DOAFrame(windowStart: 0, peaks: [DOAPeak(bearing: bearing, weight: 1)], diffuseness: 0.3, histogram: [])
        for i in 0..<4 { t.ingest(active: ["Dog": 0.9], doa: doa, now: Double(i) * 0.5) }
        return t
    }

    @Test func nudgesMoveANamedSoundTowardNearbyBlocks() {
        let t = trackerWithDog(at: 90)
        #expect(t.events[0].showsDirection)
        for i in 0..<8 { t.nudge(peaks: [DOAPeak(bearing: 115, weight: 1)], now: 1.6 + Double(i) * 0.1) }
        #expect(t.events[0].belief.peakBearing > 100)
    }

    @Test func farBlocksDontMoveIt() {
        let t = trackerWithDog(at: 90)
        for i in 0..<8 { t.nudge(peaks: [DOAPeak(bearing: 220, weight: 1)], now: 1.6 + Double(i) * 0.1) }
        #expect(abs(Circular.difference(t.events[0].belief.peakBearing, 90)) < 5)
    }

    @Test func staleOrDirectionlessSoundsArentNudged() {
        let t = trackerWithDog(at: 90)
        let before = t.events[0].belief.probabilities
        t.nudge(peaks: [DOAPeak(bearing: 110, weight: 1)], now: 3.0)  // last detected at 1.5 s: stale
        #expect(t.events[0].belief.probabilities == before)
        let fresh = EventTracker(urgencyMap: urgency)
        fresh.ingest(active: ["Dog": 0.9], doa: nil, now: 0)  // no direction yet
        let flat = fresh.events[0].belief.probabilities
        fresh.nudge(peaks: [DOAPeak(bearing: 110, weight: 1)], now: 0.1)
        #expect(fresh.events[0].belief.probabilities == flat)
    }

    @Test func demoModeLowersTypicalLevels() {
        let base = SourceLevels(levels: ["Siren": 120, "Dog": 90], defaultLevel: 70)
        let demo = base.adjusted(by: -45)
        #expect(demo.level(for: "Siren") == 75)
        #expect(demo.level(for: "Dog") == 45)
        #expect(demo.level(for: "Unknown") == 25)
    }
}
