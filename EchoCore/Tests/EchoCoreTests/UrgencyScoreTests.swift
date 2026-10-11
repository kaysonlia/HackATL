import Foundation
import Testing
@testable import EchoCore

struct UrgencyScoreTests {
    func score(_ u: Urgency, _ sourceLevel: Double, _ level: Double) -> Double {
        UrgencyScore.score(urgency: u, level: level, sourceLevel: sourceLevel)
    }

    @Test func referenceCases() {
        #expect(abs(score(.critical, 120, 114) - 1.0) < 0.005)   // siren at 2 m
        #expect(abs(score(.critical, 120, 100) - 0.805) < 0.005) // siren at 10 m
        #expect(abs(score(.critical, 110, 70) - 0.506) < 0.005)  // car alarm at 100 m
        #expect(abs(score(.medium, 90, 80) - 0.446) < 0.005)     // dog at 3 m
        #expect(score(.low, 60, 130) <= 0.15 + 1e-12)            // speech can never leave green
    }

    @Test func levelFromRMS() {
        #expect(UrgencyScore.level(rms: 1) == 120)
        #expect(abs(UrgencyScore.level(rms: 0.01) - 80) < 1e-9)
        #expect(UrgencyScore.level(rms: 0) == 0)
        #expect(UrgencyScore.level(rms: 1e-9) == 0)
    }

    @Test func distanceAndFactorsClamp() {
        #expect(UrgencyScore.distance(level: 200, sourceLevel: 60) == 0.5)
        #expect(UrgencyScore.distance(level: 0, sourceLevel: 120) == 100)
        #expect(abs(UrgencyScore.distance(level: 70, sourceLevel: 90) - 10) < 1e-9)
        #expect(UrgencyScore.closeness(distance: 1) == 1)
        #expect(abs(UrgencyScore.closeness(distance: 50)) < 1e-12)
        #expect(UrgencyScore.closeness(distance: 100) == 0)
        #expect(UrgencyScore.loudness(level: 30) == 0)
        #expect(UrgencyScore.loudness(level: 100) == 1)
        // RMS 0 → level 0 → farthest and quietest: only the 0.35 floor remains.
        #expect(abs(score(.critical, 120, 0) - 0.35) < 1e-12)
    }

    @Test func bandsAndHue() {
        #expect(UrgencyBand(score: 0.75) == .urgent)
        #expect(UrgencyBand(score: 0.7499) == .moderate)
        #expect(UrgencyBand(score: 0.4) == .moderate)
        #expect(UrgencyBand(score: 0.3999) == .low)
        #expect(UrgencyBand.urgent.label == "Urgent")
        #expect(UrgencyScore.hueDegrees(0) == 120)
        #expect(UrgencyScore.hueDegrees(0.5) == 60)
        #expect(UrgencyScore.hueDegrees(1) == 0)
        #expect(UrgencyScore.hueDegrees(1.3) == 0)
    }

    @Test func distanceText() {
        #expect(UrgencyScore.formatDistance(0.5) == "< 1 m")
        #expect(UrgencyScore.formatDistance(3.2) == "~3 m")
        #expect(UrgencyScore.formatDistance(9.6) == "~10 m")
        #expect(UrgencyScore.formatDistance(17) == "~20 m")
        #expect(UrgencyScore.formatDistance(100) == "~100 m")
    }

    @Test func sourceLevelsCoverEveryGroup() throws {
        let r = try ClassificationResources.bundled()
        #expect(r.urgency.groups.allSatisfy { r.sourceLevels.levels[$0] != nil })
        #expect(r.sourceLevels.level(for: "Siren") == 120)
        #expect(r.sourceLevels.level(for: "Unknown") == 70)
        #expect(throws: (any Error).self) { try SourceLevels(json: Data("{\"Siren\": 120}".utf8)) }
    }
}
