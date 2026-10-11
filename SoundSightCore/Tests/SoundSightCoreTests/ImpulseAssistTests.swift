import Testing
@testable import SoundSightCore

/// A 0.15 s gunshot fills little of a 1 s classifier window, so Apple's classifier names it (top label
/// firecracker/gunshot) but scores it 0.44–0.91 against a 0.841 threshold. With a loud impulse heard in
/// the window, a gunshot-family top label and a score ≥ 0.5 count (spike test: 18/20 single bangs,
/// 13/120 equally loud other impulses).
struct ImpulseAssistTests {
    let assist = ImpulseAssist(group: "Gunshot/Explosion", labels: ["gunshot_gunfire", "firecracker", "fireworks", "boom"])

    @Test func singleBangCountsWithImpulse() {
        let raw = ["firecracker": 0.55, "gunshot_gunfire": 0.2, "door": 0.1]
        #expect(assist.activates(rawLabels: raw, groupScore: 0.62, impulseInWindow: true))
    }

    @Test func needsTheImpulse() {
        let raw = ["firecracker": 0.55, "door": 0.1]
        #expect(!assist.activates(rawLabels: raw, groupScore: 0.62, impulseInWindow: false))
    }

    @Test func needsAGunshotTypeTopLabel() {
        let raw = ["applause": 0.7, "firecracker": 0.5]  // a clap the classifier half-suspects
        #expect(!assist.activates(rawLabels: raw, groupScore: 0.6, impulseInWindow: true))
    }

    @Test func needsAScoreOfAtLeastHalf() {
        let raw = ["firecracker": 0.4]
        #expect(!assist.activates(rawLabels: raw, groupScore: 0.45, impulseInWindow: true))
    }

    @Test func bundledAppleMapGivesTheGunshotLabels() throws {
        let r = try ClassificationResources.bundled()
        let a = ImpulseAssist.gunshot(mapper: r.mapper)
        #expect(a.labels.contains("firecracker") && a.labels.contains("gunshot_gunfire"))
        #expect(a.group == "Gunshot/Explosion")
    }
}
