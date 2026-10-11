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

/// Spikes become markers at once; a later classification of the same sound (close in time and
/// direction) claims the marker so the arrow turns into that sound. Unclaimed markers stay
/// "Unclassified" and fade 2.5 s after their last spike.
public struct MarkerTracker: Sendable {
    public var mergeAngle = 30.0
    public var fadeAfter = 2.5
    public var claimAngle = 45.0
    /// A classification window [start, start + 1 s] claims spikes from 0.5 s before it to its end.
    public var claimLead = 0.5
    public var windowLength = 1.0

    public private(set) var markers: [SoundMarker] = []
    private var nextID = 0

    public init() {}

    public mutating func spike(bearing: Double, level: Double, now: Double) {
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

    public mutating func expire(now: Double) {
        markers.removeAll { now - $0.lastSpike > fadeAfter }
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
