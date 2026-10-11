import Foundation

/// A sound group currently being tracked.
public struct SoundEvent: Sendable, Identifiable {
    public var id: String { group }
    public var group: String
    public var urgency: Urgency
    public var confidence: Double
    public var belief: AzimuthBelief
    public var firstSeen: Double
    public var lastSeen: Double
}

/// Rolling set of active sound events with per-label direction beliefs (spec §3.4).
public final class EventTracker {
    public let urgencyMap: UrgencyMap
    public let evictAfter: Double
    public let emaAlpha: Double
    public let diffusenessCutoff: Double
    private var byGroup: [String: SoundEvent] = [:]

    public init(urgencyMap: UrgencyMap, evictAfter: Double = 3, emaAlpha: Double = 0.5, diffusenessCutoff: Double = 0.8) {
        self.urgencyMap = urgencyMap
        self.evictAfter = evictAfter
        self.emaAlpha = emaAlpha
        self.diffusenessCutoff = diffusenessCutoff
    }

    /// Events sorted by urgency (highest first), then confidence.
    public var events: [SoundEvent] {
        byGroup.values.sorted { ($0.urgency, $0.confidence) > ($1.urgency, $1.confidence) }
    }

    /// Feeds one joined window. `active` holds groups at or above threshold; `now` is seconds
    /// on the capture timeline. Returns events that were not being tracked before this window.
    @discardableResult
    public func ingest(active: [String: Double], doa: DOAFrame?, now: Double) -> [SoundEvent] {
        byGroup = byGroup.filter { now - $0.value.lastSeen <= evictAfter }
        let usable = doa.flatMap { $0.diffuseness <= diffusenessCutoff && !$0.peaks.isEmpty ? $0.peaks : nil }
        var created: [SoundEvent] = []
        for (group, score) in active {
            if var e = byGroup[group] {
                e.confidence = emaAlpha * score + (1 - emaAlpha) * e.confidence
                e.lastSeen = now
                byGroup[group] = e
            } else {
                let e = SoundEvent(group: group, urgency: urgencyMap.urgency(for: group), confidence: score,
                                   belief: AzimuthBelief(), firstSeen: now, lastSeen: now)
                byGroup[group] = e
                created.append(e)
            }
        }
        for group in byGroup.keys {
            if let peaks = usable, let score = active[group] {
                byGroup[group]!.belief.update(peaks: peaks, confidence: score)
            } else {
                byGroup[group]!.belief.decayTowardUniform()
            }
        }
        return created.map { byGroup[$0.group]! }
    }

    public func reset() { byGroup = [:] }
}
