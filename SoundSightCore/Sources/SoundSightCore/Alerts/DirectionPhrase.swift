/// Spoken description of a radar angle for VoiceOver (spec §3.6), e.g. "behind you to the right (4 o'clock)".
public enum DirectionPhrase {
    public static func clockHour(radarAngle: Double) -> Int {
        let h = Int((Circular.wrap360(radarAngle) / 30).rounded()) % 12
        return h == 0 ? 12 : h
    }

    public static func describe(radarAngle: Double) -> String {
        let hour = clockHour(radarAngle: radarAngle)
        let phrase = switch hour {
        case 12: "in front of you"
        case 1, 2: "ahead to your right"
        case 3: "to your right"
        case 4, 5: "behind you to the right"
        case 6: "behind you"
        case 7, 8: "behind you to the left"
        case 9: "to your left"
        default: "ahead to your left"
        }
        return "\(phrase) (\(hour) o'clock)"
    }

    /// Short sector word for list rows: "front", "front-right", "right", … (45° sectors).
    public static func short(radarAngle: Double) -> String {
        let words = ["front", "front-right", "right", "back-right", "back", "back-left", "left", "front-left"]
        return words[Int((Circular.wrap360(radarAngle) + 22.5) / 45) % 8]
    }
}
