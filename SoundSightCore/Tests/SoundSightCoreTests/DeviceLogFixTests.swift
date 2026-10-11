import Foundation
import Testing
@testable import SoundSightCore

/// Regressions found in the 2026-10-10 device session logs (intermittent dog barks).
struct DeviceLogFixTests {
    let urgency = UrgencyMap(tiers: ["Dog": .medium])
    func doa(_ bearing: Double) -> DOAFrame {
        DOAFrame(windowStart: 0, peaks: [DOAPeak(bearing: bearing, weight: 1)], diffuseness: 0.5, histogram: [])
    }

    @Test func directionSurvivesGapsBetweenBarks() {
        // Barks were classified in only ~1 of 3 windows; the direction must not fade between them.
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: doa(90), now: 0)
        t.ingest(active: ["Dog": 0.9], doa: doa(90), now: 0.5)
        for i in 2..<7 { t.ingest(active: [:], doa: doa(200), now: Double(i) * 0.5) }  // 2.5 s without a bark
        #expect(t.events[0].belief.concentration >= 0.5)
        #expect(t.events[0].showsDirection)
    }

    @Test func directionLatchHasHysteresis() {
        var latch = DirectionLatch()
        let shown = [0.45, 0.55, 0.4, 0.31, 0.29, 0.45, 0.5].map { latch.update(concentration: $0) }
        #expect(shown == [false, true, true, true, false, false, true])
    }

    @Test func importantGroupsNeedAtMost085() throws {
        // Barks scored 0.86-0.93 on device but Dog needed 0.938; MEDIUM+ groups are capped at 0.85.
        let r = try ClassificationResources.bundled()
        let important = r.urgency.groups.filter { r.urgency.urgency(for: $0) >= .medium }
        #expect(important.allSatisfy { r.thresholds.threshold(for: $0) <= 0.85 })
        #expect(r.thresholds.threshold(for: "Dog") == 0.85)
        #expect(r.thresholds.threshold(for: "Traffic Warning") == 0.85)
    }
}
