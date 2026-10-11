import Testing
@testable import EchoCore

struct AmbientTests {
    @Test func ambientIgnoresShortSpikes() {
        var a = AmbientTracker()
        for i in 0..<80 { a.add(level: i % 16 == 0 ? 80 : 50) }
        #expect(a.level == 50)
    }

    @Test func ambientFollowsSustainedNoise() {
        var a = AmbientTracker()
        for _ in 0..<80 { a.add(level: 50) }
        for _ in 0..<80 { a.add(level: 70) }
        #expect(a.level == 70)
    }

    @Test func spikeRuleRidesOnAmbient() {
        #expect(AmbientTracker.isSpike(level: 58, ambient: 50))
        #expect(!AmbientTracker.isSpike(level: 57.9, ambient: 50))
        #expect(!AmbientTracker.isSpike(level: 44, ambient: 30))  // below the 45 dB floor
        #expect(AmbientTracker.isSpike(level: 46, ambient: 30))
        #expect(AmbientTracker.isSpike(level: 92, ambient: 80))
    }

    @Test func wordsAndRingStrength() {
        #expect(AmbientTracker.word(for: 40) == "Quiet")
        #expect(AmbientTracker.word(for: 50) == "Moderate")
        #expect(AmbientTracker.word(for: 70) == "Loud")
        #expect(AmbientTracker.word(for: 80) == "Very loud")
        #expect(AmbientTracker.ringStrength(for: 30) == 0)
        #expect(AmbientTracker.ringStrength(for: 100) == 1)
        #expect(abs(AmbientTracker.ringStrength(for: 62.5) - 0.5) < 1e-12)
    }

    @Test func directionProfilePointsAtTheBackground() {
        var d = AmbientDirection()
        var h = [Double](repeating: 0, count: 72)
        h[36] = 1; h[35] = 0.5; h[37] = 0.5  // background around 180°
        for _ in 0..<50 { d.add(histogram: h) }
        #expect(d.profile.count == 72)
        #expect(d.profile[36] == 1)
        #expect(d.profile[0] < 0.2)
    }
}

struct MarkerTests {
    @Test func spikesCreateAndMergeMarkers() {
        var m = MarkerTracker()
        m.spike(bearing: 90, level: 70, now: 0)
        m.spike(bearing: 110, level: 72, now: 0.3)  // within 30°: same marker
        m.spike(bearing: 250, level: 65, now: 0.4)  // elsewhere: new marker
        #expect(m.markers.count == 2)
        let first = m.markers.first { abs(Circular.difference($0.bearing, 100)) < 15 }
        #expect(first?.lastSpike == 0.3)
        #expect(first?.claimedBy == nil)
    }

    @Test func unclaimedMarkerClassifiesForFiveSecondsThenStaysUnclassified() {
        var m = MarkerTracker()
        m.spike(bearing: 0, level: 70, now: 0)
        let marker = m.markers[0]
        #expect(m.state(of: marker, now: 4.9) == .classifying)
        #expect(m.state(of: marker, now: 5.1) == .unclassified)
        #expect(m.opacity(of: marker, now: 6) == 1)
        #expect(abs(m.opacity(of: marker, now: 7.5) - 0.5) < 1e-9)  // fades over the last second
        m.expire(now: 7.9)
        #expect(m.markers.count == 1)
        m.expire(now: 8.1)  // shown as Unclassified for 3 s after the 5 s of classifying
        #expect(m.markers.isEmpty)
    }

    @Test func ongoingSpikesKeepMarkerAlive() {
        var m = MarkerTracker()
        m.spike(bearing: 0, level: 70, now: 0)
        m.spike(bearing: 5, level: 70, now: 6)
        m.expire(now: 8.5)
        #expect(m.markers.count == 1)
        #expect(m.state(of: m.markers[0], now: 8.5) == .unclassified)
    }

    @Test func claimedMarkerFadesSoonAfterLastSpike() {
        var m = MarkerTracker()
        m.spike(bearing: 0, level: 70, now: 0)
        m.claim(group: "Dog", bearing: nil, windowStart: 0)
        #expect(m.state(of: m.markers[0], now: 1) == .claimed("Dog"))
        m.expire(now: 2.4)
        #expect(m.markers.count == 1)
        m.expire(now: 2.6)
        #expect(m.markers.isEmpty)
    }

    @Test func classificationClaimsMatchingMarker() {
        var m = MarkerTracker()
        m.spike(bearing: 90, level: 70, now: 10.2)
        m.spike(bearing: 270, level: 70, now: 10.3)
        m.claim(group: "Dog", bearing: 95, windowStart: 10)  // window 10–11 s, from the right
        #expect(m.markers.first { $0.bearing < 180 }?.claimedBy == "Dog")
        #expect(m.markers.first { $0.bearing > 180 }?.claimedBy == nil)
    }

    @Test func claimNeedsTimeAndDirectionMatch() {
        var m = MarkerTracker()
        m.spike(bearing: 90, level: 70, now: 5)
        m.claim(group: "Siren", bearing: 200, windowStart: 5)  // wrong direction
        m.claim(group: "Dog", bearing: 90, windowStart: 9)  // spike long before this window
        #expect(m.markers[0].claimedBy == nil)
    }

    @Test func claimWithoutDirectionTakesMostRecentMarker() {
        var m = MarkerTracker()
        m.spike(bearing: 30, level: 70, now: 1.0)
        m.spike(bearing: 200, level: 70, now: 1.4)
        m.claim(group: "Knock", bearing: nil, windowStart: 1)
        #expect(m.markers.first { $0.bearing > 180 }?.claimedBy == "Knock")
        #expect(m.markers.first { $0.bearing < 180 }?.claimedBy == nil)
    }
}
