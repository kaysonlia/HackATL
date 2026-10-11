import Foundation
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
    /// Windows in which the classifier detected this group.
    var hits: Int

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
        hits = e.hits
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

/// A sudden sound on the radar: "Classifying…" (blue) until the classifier names it, then that sound's
/// name and color until its own direction estimate takes over; "Unclassified" if nothing names it in 5 s.
struct MarkerDisplay: Identifiable, Equatable {
    enum Kind: Equatable { case classifying, unclassified, classified }

    let id: Int
    var worldBearing: Double
    var kind: Kind
    /// The classified group's name; empty otherwise.
    var group: String
    /// Urgency score once classified; nil draws the blue.
    var score: Double?
    /// 1 until the marker's last second, then fading to 0.
    var opacity: Double

    /// `events` decide hand-off: a classified marker disappears once its event shows an arrow.
    static func from(_ snapshots: [MarkerSnapshot], events: [EventDisplay]) -> [MarkerDisplay] {
        snapshots.compactMap { s in
            let m = s.marker
            switch s.state {
            case .classifying:
                return MarkerDisplay(id: m.id, worldBearing: m.bearing, kind: .classifying, group: "", score: nil, opacity: s.opacity)
            case .unclassified:
                return MarkerDisplay(id: m.id, worldBearing: m.bearing, kind: .unclassified, group: "", score: nil, opacity: s.opacity)
            case .claimed(let group):
                let event = events.first { $0.group == group }
                if event?.worldBearing != nil { return nil }
                return MarkerDisplay(id: m.id, worldBearing: m.bearing, kind: .classified, group: group, score: event?.score, opacity: s.opacity)
            }
        }
    }

    /// "Classifying." → ".." → "..." cycling three times a second.
    func label(at date: Date) -> String {
        switch kind {
        case .classifying: "Classifying" + String(repeating: ".", count: Int(date.timeIntervalSinceReferenceDate * 3) % 3 + 1)
        case .unclassified: "Unclassified"
        case .classified: group
        }
    }
}
