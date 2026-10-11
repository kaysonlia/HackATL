import Foundation
import Testing
@testable import SoundSightCore

struct ClassificationTests {
    @Test func urgencyOrderingAndParsing() {
        #expect(Urgency.low < .medium && Urgency.medium < .high && Urgency.high < .critical)
        #expect(Urgency(tier: "critical") == .critical)
        #expect(Urgency(tier: "nope") == nil)
    }

    @Test func noisyOrMatchesWorkedExample() {
        let m = LabelMapper(labelToGroup: ["music": "Music", "classical": "Music", "guitar": "Music", "drum": "Music", "dog_bark": "Dog"])
        // Music=0.5, Classical=0.7 → 1 − 0.5·0.3 = 0.85 (worked example).
        #expect(abs(m.groupScores(["music": 0.5, "classical": 0.7])["Music"]! - 0.85) < 1e-12)
        // Only the top 3 members count: 0.1 is ignored.
        let top3 = m.groupScores(["music": 0.5, "classical": 0.5, "guitar": 0.5, "drum": 0.1])["Music"]!
        #expect(abs(top3 - (1 - 0.125)) < 1e-12)
        // Single member passes through; unknown labels ignored; values clamped.
        #expect(m.groupScores(["dog_bark": 1.4, "unknown": 0.9]) == ["Dog": 1])
        #expect(m.groupScores([:]).isEmpty)
    }

    @Test func thresholdsFilterAndDefault() {
        let t = GroupThresholds(thresholds: ["Siren": 0.5], defaultThreshold: 0.9)
        #expect(t.active(["Siren": 0.5, "Dog": 0.89, "Speech": 0.95]) == ["Siren": 0.5, "Speech": 0.95])
        #expect(t.threshold(for: "Anything") == 0.9)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try GroupThresholds(json: Data("{\"x\":1}".utf8)) }
        #expect(throws: (any Error).self) { try LabelMapper(json: Data("[1,2]".utf8)) }
        #expect(throws: (any Error).self) { try UrgencyMap(json: Data("{\"URGENT\": [\"Siren\"]}".utf8)) }
    }

    @Test func bundledResourcesAreConsistent() throws {
        let r = try ClassificationResources.bundled()
        #expect(r.mapper.labelToGroup.count == 84)
        #expect(r.urgency.groups.count == 17)
        // Every Apple label maps to a group the urgency table knows.
        #expect(Set(r.mapper.labelToGroup.values).isSubset(of: r.urgency.groups))
        // Every group has an explicit threshold.
        #expect(r.urgency.groups.allSatisfy { r.thresholds.thresholds[$0] != nil })
        #expect(r.urgency.urgency(for: "Siren") == .critical)
        #expect(r.urgency.urgency(for: "Speech") == .low)
    }
}
