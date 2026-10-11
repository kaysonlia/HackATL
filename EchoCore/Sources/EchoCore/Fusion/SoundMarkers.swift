/// A sudden sound shown immediately as an "Unclassified" arrow, before (or without) a classification.
public struct SoundMarker: Sendable, Identifiable, Equatable {
    public let id: Int
    /// World bearing of the latest spike.
    public var bearing: Double
    public var levelDB: Double
    public var firstSpike: Double
    public var lastSpike: Double
    /// The group the classifier named for this sound; nil while unclassified.
    public var claimedBy: String?
}

public enum MarkerState: Sendable, Equatable {
    /// Shown as "Classifying…" while the classifier may still name it.
    case classifying
    /// Nothing named it within `classifyingFor` seconds.
    case unclassified
    case claimed(String)
}

/// A marker with what to draw, for the UI.
public struct MarkerSnapshot: Sendable, Equatable {
    public var marker: SoundMarker
    public var state: MarkerState
    /// 1 until the marker's last second, then fading to 0.
    public var opacity: Double
}

/// Spikes become markers at once; a later classification of the same sound (close in time and
/// direction) claims the marker so the arrow turns into that sound. An unclaimed marker reads
/// "Classifying…" while the sound continues plus 1.5 s for the classifier (at most 5 s), then
/// "Unclassified" for 1 s after the sound stops. A claimed marker goes 1 s after its last spike, by
/// which time the sound's own arrow has taken over. Spikes near a named arrow belong to it.
public struct MarkerTracker: Sendable {
    public var mergeAngle = 45.0
    /// Spikes this close to a named arrow are that sound, not a new one.
    public var suppressAngle = 40.0
    public var classifyingFor = 5.0
    /// Time after the last spike for the classifier to name the sound.
    public var classifyAfterLast = 1.5
    public var unclassifiedHold = 1.0
    public var claimedHold = 1.0
    public var claimAngle = 45.0
    /// A classification window [start, start + 1 s] claims spikes from 0.5 s before it to its end.
    public var claimLead = 0.5
    public var windowLength = 1.0

    public private(set) var markers: [SoundMarker] = []
    private var nextID = 0

    public init() {}

    /// `near`: bearings of named arrows currently shown; a spike close to one is that sound.
    public mutating func spike(bearing: Double, level: Double, now: Double, near named: [Double] = []) {
        if named.contains(where: { abs(Circular.difference($0, bearing)) <= suppressAngle }) { return }
        let near = markers.indices.filter { abs(Circular.difference(markers[$0].bearing, bearing)) <= mergeAngle }
        if let i = near.min(by: { abs(Circular.difference(markers[$0].bearing, bearing)) < abs(Circular.difference(markers[$1].bearing, bearing)) }) {
            markers[i].bearing = bearing
            markers[i].levelDB = level
            markers[i].lastSpike = now
        } else {
            markers.append(SoundMarker(id: nextID, bearing: bearing, levelDB: level, firstSpike: now, lastSpike: now, claimedBy: nil))
            nextID += 1
        }
    }

    func classifyingUntil(_ m: SoundMarker) -> Double {
        min(m.firstSpike + classifyingFor, m.lastSpike + classifyAfterLast)
    }

    public func state(of m: SoundMarker, now: Double) -> MarkerState {
        if let group = m.claimedBy { return .claimed(group) }
        return now < classifyingUntil(m) ? .classifying : .unclassified
    }

    /// When the marker disappears.
    public func endTime(of m: SoundMarker) -> Double {
        m.claimedBy != nil ? m.lastSpike + claimedHold : max(classifyingUntil(m), m.lastSpike) + unclassifiedHold
    }

    /// Named arrows replace markers near them.
    public mutating func absorb(near named: [Double]) {
        let angle = suppressAngle
        markers.removeAll { m in named.contains { abs(Circular.difference($0, m.bearing)) <= angle } }
    }

    public func opacity(of m: SoundMarker, now: Double) -> Double {
        min(1, max(0, endTime(of: m) - now))
    }

    public func snapshot(now: Double) -> [MarkerSnapshot] {
        markers.map { MarkerSnapshot(marker: $0, state: state(of: $0, now: now), opacity: opacity(of: $0, now: now)) }
    }

    public mutating func expire(now: Double) {
        let tracker = self
        markers.removeAll { now > tracker.endTime(of: $0) }
    }

    /// A shown group was detected in the classification window starting at `windowStart`;
    /// `bearing` is its direction if the tracker knows it.
    public mutating func claim(group: String, bearing: Double?, windowStart: Double) {
        let lo = windowStart - claimLead, hi = windowStart + windowLength
        let candidates = markers.indices.filter { i in
            let m = markers[i]
            guard m.claimedBy == nil || m.claimedBy == group, m.lastSpike >= lo, m.firstSpike <= hi else { return false }
            guard let bearing else { return true }
            return abs(Circular.difference(m.bearing, bearing)) <= claimAngle
        }
        let pick: Int? = if let bearing {
            candidates.min { abs(Circular.difference(markers[$0].bearing, bearing)) < abs(Circular.difference(markers[$1].bearing, bearing)) }
        } else {
            candidates.max { markers[$0].lastSpike < markers[$1].lastSpike }
        }
        if let pick { markers[pick].claimedBy = group }
    }

    public mutating func reset() {
        markers = []
    }
}
