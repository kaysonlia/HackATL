import Testing
@testable import EchoCore

/// Fewer false arrows: handling noise is ignored, quick quiet sounds need two blocks, loud impulses pass,
/// and Low/Medium named sounds need two detections.
struct HandlingTests {
    @Test func tapsAndBumpsCountAsHandling() {
        var d = HandlingDetector()
        let flags = [
            d.update(userAcceleration: SIMD3(0, 0, 0.005)),   // phone at rest
            d.update(userAcceleration: SIMD3(0.01, 0, 0.01)),  // slow, smooth turn
            d.update(userAcceleration: SIMD3(0, 0, 0.09)),     // sharp tap: sudden jerk
            d.update(userAcceleration: SIMD3(0.2, 0, 0.1)),    // bump
        ]
        #expect(flags == [false, false, true, true])
    }

    @Test func timelineFlagsOverlappingWindows() {
        var t = HandlingTimeline()
        t.mark(from: 10.0, to: 10.35)
        #expect(t.overlaps(9.5, 10.5))
        #expect(t.overlaps(10.3, 11.3))
        #expect(!t.overlaps(10.4, 11.4))
        #expect(!t.overlaps(8.0, 9.0))
        t.prune(before: 20)
        #expect(!t.overlaps(9.5, 10.5))
    }
}

struct SpikeGateTests {
    @Test func singleQuietClickIsIgnored() {
        var g = SpikeGate()
        let a = g.feed(level: 52, ambient: 40, bearing: 90, now: 0)
        let b = g.feed(level: 41, ambient: 40, bearing: nil, now: 0.1)
        #expect(a == nil && b == nil)
    }

    @Test func sustainedSoundShowsFromItsFirstBlock() {
        var g = SpikeGate()
        let first = g.feed(level: 55, ambient: 40, bearing: 90, now: 0)
        let shown = g.feed(level: 56, ambient: 40, bearing: 100, now: 0.1)
        let more = g.feed(level: 56, ambient: 40, bearing: 95, now: 0.2)  // continues
        #expect(first == nil)
        #expect(shown?.bearing == 100)
        #expect(more != nil)
    }

    @Test func loudImpulsePassesAtOnce() {
        var g = SpikeGate()
        let shot = g.feed(level: 65, ambient: 40, bearing: 200, now: 0)  // 25 dB over the room
        #expect(shot?.bearing == 200)
    }

    @Test func twoBlocksFromDifferentDirectionsDontCount() {
        var g = SpikeGate()
        let a = g.feed(level: 55, ambient: 40, bearing: 90, now: 0)
        let b = g.feed(level: 55, ambient: 40, bearing: 250, now: 0.1)
        #expect(a == nil && b == nil)
    }

    @Test func barRaisedToTenDecibels() {
        #expect(!AmbientTracker.isSpike(level: 59.9, ambient: 50))
        #expect(AmbientTracker.isSpike(level: 60, ambient: 50))
    }
}

struct ConfirmationTests {
    func event(_ u: Urgency, hits: Int) -> SoundEvent {
        var e = SoundEvent(group: "X", urgency: u, confidence: 0.9, belief: AzimuthBelief(), firstSeen: 0, lastSeen: 0)
        e.hits = hits
        return e
    }

    @Test func lowAndMediumNeedTwoDetections() {
        #expect(!event(.low, hits: 1).isConfirmed)
        #expect(!event(.medium, hits: 1).isConfirmed)
        #expect(event(.medium, hits: 2).isConfirmed)
        #expect(event(.high, hits: 1).isConfirmed)
        #expect(event(.critical, hits: 1).isConfirmed)
    }
}
