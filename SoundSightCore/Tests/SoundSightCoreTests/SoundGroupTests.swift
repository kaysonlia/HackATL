import Testing
@testable import SoundSightCore

/// SoundSight's regrouping: 13 groups always shown, 4 optional (off by default), everything else unmapped.
struct SoundGroupTests {
    static let optional: Set<String> = ["Footsteps", "Water Running", "Power Tool", "Cough/Sneeze"]

    @Test func seventeenGroupsInFourTiers() throws {
        let r = try ClassificationResources.bundled()
        #expect(r.urgency.groups.count == 17)
        #expect(r.urgency.urgency(for: "Siren") == .critical)
        #expect(r.urgency.urgency(for: "Traffic Warning") == .high)
        #expect(r.urgency.urgency(for: "Door") == .medium)
        #expect(r.urgency.urgency(for: "Speech") == .low)
        #expect(Set(r.visibility.optional) == Self.optional)
    }

    @Test func uselessSoundsAreUnmapped() throws {
        let apple = try ClassificationResources.bundled().mapper.labelToGroup
        for label in ["typing", "keys_jangling", "camera", "music", "tap", "slap_smack", "airplane", "laughter", "chewing"] {
            #expect(apple[label] == nil, "\(label) should be hidden")
        }
        let yam = try YAMNetResources.bundled().mapper.labelToGroup
        #expect(yam["378"] == nil)  // Typing
        #expect(yam["387"] == nil)  // Dial tone isn't a ringing phone
    }

    @Test func misfiledLabelsMoved() throws {
        let apple = try ClassificationResources.bundled().mapper.labelToGroup
        #expect(apple["foghorn"] == "Traffic Warning")
        #expect(apple["bicycle_bell"] == "Traffic Warning")
        #expect(apple["boom"] == "Gunshot/Explosion")
        #expect(apple["door_slam"] == "Door")
        #expect(apple["knock"] == "Door")
        #expect(apple["screaming"] == "Screaming/Shouting")
        let yam = try YAMNetResources.bundled().mapper.labelToGroup
        #expect(yam["304"] == "Siren")  // Car alarm
        #expect(yam["198"] == "Traffic Warning")  // Bicycle bell
    }

    @Test func everyGroupHasTablesInBothClassifiers() throws {
        let r = try ClassificationResources.bundled()
        let y = try YAMNetResources.bundled()
        #expect(Set(r.mapper.labelToGroup.values) == r.urgency.groups)
        #expect(Set(y.mapper.labelToGroup.values) == r.urgency.groups)
        #expect(r.urgency.groups.allSatisfy { r.thresholds.thresholds[$0] != nil && y.thresholds.thresholds[$0] != nil })
        #expect(r.urgency.groups.allSatisfy { r.sourceLevels.levels[$0] != nil })
    }

    @Test func optionalGroupsHiddenUntilEnabled() {
        let v = GroupVisibility(optional: ["Footsteps", "Power Tool"])
        let scores = ["Siren": 0.9, "Footsteps": 0.8, "Power Tool": 0.95]
        #expect(v.shown(scores, enabled: []) == ["Siren": 0.9])
        #expect(v.shown(scores, enabled: ["Power Tool"]) == ["Siren": 0.9, "Power Tool": 0.95])
    }
}

/// Device 2026-10-11: sounds kept reading "Crash/Glass Breaking". Its Apple threshold was the 0.30 clamp
/// floor and it included `thump_thud`, a generic impact label that fires mostly on claps and footsteps.
struct CrashGroupTests {
    @Test func genericImpactsDontCountAsCrash() throws {
        let apple = try ClassificationResources.bundled().mapper.labelToGroup
        #expect(apple["thump_thud"] == nil)
        #expect(apple["glass_breaking"] == "Crash/Glass Breaking")
        let yam = try YAMNetResources.bundled().mapper.labelToGroup
        #expect(yam["454"] == nil)  // Thump, thud
    }

    @Test func appleThresholdsHaveAFloorOfPointFour() throws {
        let t = try ClassificationResources.bundled().thresholds
        #expect(t.thresholds.values.allSatisfy { $0 >= 0.4 })
    }
}
