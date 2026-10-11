/// The radar sweep only plays right after Start Listening (urgency spec §3):
/// fully visible for 2 s, then fading linearly to nothing at 3 s.
public enum RadarSweep {
    public static let fadeStart = 2.0
    public static let duration = 3.0

    public static func opacity(elapsed: Double) -> Double {
        if elapsed < 0 || elapsed >= duration { return 0 }
        if elapsed < fadeStart { return 1 }
        return (duration - elapsed) / (duration - fadeStart)
    }
}
