import Testing
@testable import SoundSightCore

struct AzimuthBeliefTests {
    @Test func startsUniform() {
        let b = AzimuthBelief()
        #expect(b.concentration < 1e-9)
        #expect(abs(b.probabilities.reduce(0, +) - 1) < 1e-9)
    }

    @Test func convergesOnConsistentEvidence() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 93, weight: 1)], confidence: 1) }
        #expect(abs(Circular.difference(b.peakBearing, 93)) < 5)
        #expect(b.concentration >= 0.5)
    }

    @Test func convergesAcrossZero() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 358, weight: 1)], confidence: 0.8) }
        #expect(abs(Circular.difference(b.peakBearing, 358)) < 5)
    }

    @Test func decaysWithoutEvidence() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 200, weight: 1)], confidence: 1) }
        for _ in 0..<30 { b.decayTowardUniform() }
        #expect(b.concentration < 0.05)
    }

    @Test func emptyPeaksOnlyDecay() {
        var a = AzimuthBelief(), b = AzimuthBelief()
        a.update(peaks: [DOAPeak(bearing: 10, weight: 1)], confidence: 1)
        b.update(peaks: [DOAPeak(bearing: 10, weight: 1)], confidence: 1)
        a.update(peaks: [], confidence: 1)
        b.decayTowardUniform()
        #expect(a.probabilities == b.probabilities)
    }

    @Test func zeroConfidenceDoesNotMoveBelief() {
        var b = AzimuthBelief()
        b.update(peaks: [DOAPeak(bearing: 45, weight: 1)], confidence: 0)
        #expect(b.concentration < 1e-9)
    }
}

struct EventTrackerTests {
    let urgency = UrgencyMap(tiers: ["Siren": .critical, "Dog": .medium, "Speech": .low])
    func doa(_ bearing: Double, diffuseness: Double = 0.1) -> DOAFrame {
        DOAFrame(windowStart: 0, peaks: [DOAPeak(bearing: bearing, weight: 1)], diffuseness: diffuseness, histogram: [])
    }

    @Test func createsRefreshesAndEvicts() {
        let t = EventTracker(urgencyMap: urgency)
        #expect(t.ingest(active: ["Dog": 0.9], doa: nil, now: 0).map(\.group) == ["Dog"])
        #expect(t.ingest(active: ["Dog": 0.5], doa: nil, now: 0.5).isEmpty)
        #expect(abs(t.events[0].confidence - 0.7) < 1e-12)
        #expect(t.events[0].firstSeen == 0 && t.events[0].lastSeen == 0.5)
        t.ingest(active: [:], doa: nil, now: 3.5)
        #expect(t.events.count == 1)  // exactly 3 s since lastSeen: kept
        t.ingest(active: [:], doa: nil, now: 3.6)
        #expect(t.events.isEmpty)
    }

    @Test func sortsByUrgencyThenConfidence() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Speech": 0.99, "Dog": 0.6, "Siren": 0.5], doa: nil, now: 0)
        #expect(t.events.map(\.group) == ["Siren", "Dog", "Speech"])
        #expect(t.events[0].urgency == .critical)
    }

    @Test func activeLabelsLearnDirectionIndependently() {
        let t = EventTracker(urgencyMap: urgency)
        for i in 0..<6 { t.ingest(active: ["Siren": 1], doa: doa(270), now: Double(i) * 0.5) }
        for i in 6..<12 { t.ingest(active: ["Siren": 1, "Dog": 1], doa: nil, now: Double(i) * 0.5) }
        for i in 12..<18 { t.ingest(active: ["Dog": 1], doa: doa(45), now: Double(i) * 0.5) }
        let dog = t.events.first { $0.group == "Dog" }!
        #expect(abs(Circular.difference(dog.belief.peakBearing, 45)) < 5)
        #expect(dog.belief.concentration >= 0.5)
    }

    @Test func diffuseFramesDoNotUpdateBelief() {
        let t = EventTracker(urgencyMap: urgency)
        for i in 0..<6 { t.ingest(active: ["Dog": 1], doa: doa(90, diffuseness: 0.95), now: Double(i)) }
        #expect(t.events[0].belief.concentration < 1e-9)
    }

    @Test func unknownGroupDefaultsToLow() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Mystery": 0.9], doa: nil, now: 0)
        #expect(t.events[0].urgency == .low)
    }
}
