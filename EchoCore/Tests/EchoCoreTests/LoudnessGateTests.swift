import Testing
@testable import EchoCore

/// Only sounds that stand out from the room get named: the window's loudest 0.1 s block must be
/// 6 dB over the ambient level (and at least 45 dB). Sounds already being tracked carry on.
struct LoudnessGateTests {
    let urgency = UrgencyMap(tiers: ["Siren": .critical, "Dog": .medium])

    /// Ten 0.1 s blocks from `start`, all at `level` except `peak` (if given) at block 5.
    func gate(start: Double = 0, level: Double, ambient: Double, peak: Double? = nil) -> LoudnessGate {
        var g = LoudnessGate()
        for i in 0..<10 {
            g.addBlock(level: i == 5 ? (peak ?? level) : level, ambient: ambient, time: start + Double(i) * 0.1)
        }
        return g
    }

    @Test func quietSoundsAreNotNamed() {
        let g = gate(level: 44, ambient: 40)
        #expect(!g.passes(windowStart: 0))
        #expect(g.filter(["Dog": 0.9], windowStart: 0, tracked: [], evictAfter: 2).isEmpty)
    }

    @Test func soundsWellAboveTheRoomAreNamed() {
        let g = gate(level: 52, ambient: 40)
        #expect(g.passes(windowStart: 0))
        #expect(g.filter(["Dog": 0.9], windowStart: 0, tracked: [], evictAfter: 2) == ["Dog": 0.9])
    }

    @Test func oneLoudBlockIsEnough() {
        // A short bang: the 1 s average barely moves, the loudest 0.1 s does.
        #expect(gate(level: 41, ambient: 40, peak: 60).passes(windowStart: 0))
    }

    @Test func aQuietRoomStillNeedsTheFloor() {
        #expect(!gate(level: 40, ambient: 25).passes(windowStart: 0))
    }

    @Test func blocksOutsideTheWindowDontCount() {
        let g = gate(start: 5, level: 60, ambient: 40)
        #expect(!g.passes(windowStart: 0))
        #expect(g.passes(windowStart: 4.5))
    }

    @Test func trackedSoundsCarryOnOnceTheRoomCatchesUp() {
        // A long siren: the ambient level has risen to meet it, but it was named and is still going.
        let t = EventTracker(urgencyMap: urgency, evictAfter: 2)
        t.ingest(active: ["Siren": 0.9], doa: nil, now: 4)
        let g = gate(start: 5, level: 62, ambient: 60)
        let kept = g.filter(["Siren": 0.9, "Dog": 0.8], windowStart: 5, tracked: t.events, evictAfter: 2)
        #expect(kept == ["Siren": 0.9])
    }

    @Test func aSoundGoneQuietMustPassAgain() {
        let t = EventTracker(urgencyMap: urgency, evictAfter: 2)
        t.ingest(active: ["Siren": 0.9], doa: nil, now: 1)
        let g = gate(start: 5, level: 62, ambient: 60)
        #expect(g.filter(["Siren": 0.9], windowStart: 5, tracked: t.events, evictAfter: 2).isEmpty)
    }

    @Test func oldBlocksArePruned() {
        var g = gate(level: 60, ambient: 40)
        g.addBlock(level: 40, ambient: 40, time: 20)
        #expect(!g.passes(windowStart: 0))
    }
}

extension LoudnessGateTests {
    @Test func theMarginIsAdjustable() {
        var strict = LoudnessGate()
        strict.margin = 12
        strict.addBlock(level: 50, ambient: 40, time: 0)
        #expect(!strict.passes(windowStart: 0))
        var loose = LoudnessGate()
        loose.margin = 0
        loose.addBlock(level: 46, ambient: 45.5, time: 0)
        #expect(loose.passes(windowStart: 0))
        #expect(LoudnessGate.marginRange == 0...20)
    }
}
