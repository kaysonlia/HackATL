import EchoCore

/// What the UI needs for one tracked sound.
struct EventDisplay: Identifiable, Equatable {
    var id: String { group }
    var group: String
    var urgency: Urgency
    var confidence: Double
    /// World bearing of the belief peak; nil while the tracker's direction latch is off
    /// (shown at R ≥ 0.5, hidden below 0.3).
    var worldBearing: Double?
    /// Belief peak even when diffuse, for the halo.
    var peakBearing: Double
    var concentration: Double
    var belief: [Double]
    var levelDB: Double?
    /// Approximate metres; nil until the level is measured.
    var distance: Double?
    var score: Double
    var band: UrgencyBand

    init(_ e: SoundEvent, sourceLevels: SourceLevels) {
        group = e.group
        urgency = e.urgency
        confidence = e.confidence
        concentration = e.belief.concentration
        peakBearing = e.belief.peakBearing
        worldBearing = e.showsDirection ? peakBearing : nil
        belief = e.belief.probabilities
        levelDB = e.levelDB
        let source = sourceLevels.level(for: e.group)
        distance = e.levelDB.map { UrgencyScore.distance(level: $0, sourceLevel: source) }
        score = UrgencyScore.score(urgency: e.urgency, level: e.levelDB ?? 0, sourceLevel: source)
        band = UrgencyBand(score: score)
    }

    /// "84 dB · ~3 m"; nil before the first level arrives.
    var levelText: String? {
        guard let levelDB, let distance else { return nil }
        return "\(Int(levelDB.rounded())) dB · \(UrgencyScore.formatDistance(distance))"
    }

    func radarAngle(forward: Double) -> Double? {
        worldBearing.map { ForwardHeading.radarAngle(worldBearing: $0, forward: forward) }
    }

    /// "behind you to the right (4 o'clock)" or "direction unknown".
    func directionPhrase(forward: Double) -> String {
        radarAngle(forward: forward).map { DirectionPhrase.describe(radarAngle: $0) } ?? "direction unknown"
    }

    /// "back-right" or "direction unknown".
    func shortDirection(forward: Double) -> String {
        radarAngle(forward: forward).map { DirectionPhrase.short(radarAngle: $0) } ?? "direction unknown"
    }
}
