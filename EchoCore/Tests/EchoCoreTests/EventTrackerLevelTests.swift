import Testing
@testable import EchoCore

struct EventTrackerLevelTests {
    let urgency = UrgencyMap(tiers: ["Dog": .medium])

    @Test func levelIsSmoothedWhileActive() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0, levelDB: 80)
        #expect(t.events[0].levelDB == 80)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0.5, levelDB: 60)
        #expect(t.events[0].levelDB == 70)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 1, levelDB: nil)
        #expect(t.events[0].levelDB == 70)
        t.ingest(active: [:], doa: nil, now: 1.5, levelDB: 20)  // not active: level unchanged
        #expect(t.events[0].levelDB == 70)
    }

    @Test func levelStartsNilWhenUnknown() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0)
        #expect(t.events[0].levelDB == nil)
    }

    @Test func silenceNeverBecomesAnEvent() {
        let t = EventTracker(urgencyMap: urgency)
        let created = t.ingest(active: ["Silence": 0.99, "Dog": 0.9], doa: nil, now: 0)
        #expect(created.map(\.group) == ["Dog"])
        #expect(t.events.map(\.group) == ["Dog"])
    }

    @Test func countsDetectionsPerEvent() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0)
        t.ingest(active: [:], doa: nil, now: 0.5)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 1)
        #expect(t.events[0].hits == 2)
    }
}
