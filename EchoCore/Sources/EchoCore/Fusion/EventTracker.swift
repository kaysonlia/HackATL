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
    /// Smoothed omni level (approximate dB SPL) over the windows where this group was active; nil until measured.
    public var levelDB: Double?
    public var directionLatch = DirectionLatch()
    /// Windows in which this group was active.
    public var hits = 1

    /// Whether the belief is concentrated enough to draw an arrow (with hysteresis).
    public var showsDirection: Bool { directionLatch.isShown }
}

/// Rolling set of active sound events with per-label direction beliefs (spec §3.4).
public final class EventTracker {
    public let urgencyMap: UrgencyMap
    public let evictAfter: Double
    public let emaAlpha: Double
    public let diffusenessCutoff: Double
    /// Groups that never become events (urgency spec §2.5).
    public let ignoredGroups: Set<String>
    /// Belief decay per window for events with no new direction evidence. Slower than the 0.15 applied
    /// with each update, so intermittent sounds (barks) keep their direction between detections.
    public let idleDecay: Double
    private var byGroup: [String: SoundEvent] = [:]

    public init(urgencyMap: UrgencyMap, evictAfter: Double = 3, emaAlpha: Double = 0.5, diffusenessCutoff: Double = 0.8,
                ignoredGroups: Set<String> = ["Silence"], idleDecay: Double = 0.04) {
        self.urgencyMap = urgencyMap
        self.evictAfter = evictAfter
        self.emaAlpha = emaAlpha
        self.diffusenessCutoff = diffusenessCutoff
        self.ignoredGroups = ignoredGroups
        self.idleDecay = idleDecay
    }

    /// Events sorted by urgency (highest first), then confidence.
    public var events: [SoundEvent] {
        byGroup.values.sorted { ($0.urgency, $0.confidence) > ($1.urgency, $1.confidence) }
    }

    /// Feeds one joined window. `active` holds groups at or above threshold; `now` is seconds
    /// on the capture timeline; `levelDB` is the window's omni level, if known.
    /// Returns events that were not being tracked before this window.
    @discardableResult
    public func ingest(active: [String: Double], doa: DOAFrame?, now: Double, levelDB: Double? = nil) -> [SoundEvent] {
        byGroup = byGroup.filter { now - $0.value.lastSeen <= evictAfter }
        let usable = doa.flatMap { $0.diffuseness <= diffusenessCutoff && !$0.peaks.isEmpty ? $0.peaks : nil }
        let active = active.filter { !ignoredGroups.contains($0.key) }
        var created: [SoundEvent] = []
        for (group, score) in active {
            if var e = byGroup[group] {
                e.confidence = emaAlpha * score + (1 - emaAlpha) * e.confidence
                e.lastSeen = now
                e.hits += 1
                if let levelDB { e.levelDB = e.levelDB.map { emaAlpha * levelDB + (1 - emaAlpha) * $0 } ?? levelDB }
                byGroup[group] = e
            } else {
                let e = SoundEvent(group: group, urgency: urgencyMap.urgency(for: group), confidence: score,
                                   belief: AzimuthBelief(), firstSeen: now, lastSeen: now, levelDB: levelDB)
                byGroup[group] = e
                created.append(e)
            }
        }
        for group in byGroup.keys {
            if let peaks = usable, let score = active[group] {
                byGroup[group]!.belief.update(peaks: peaks, confidence: score)
            } else {
                byGroup[group]!.belief.decayTowardUniform(rate: idleDecay)
            }
            byGroup[group]!.directionLatch.update(concentration: byGroup[group]!.belief.concentration)
        }
        return created.map { byGroup[$0.group]! }
    }

    /// 0.1 s direction nudges between classifier windows: lighter decay and evidence than a full window.
    public var nudgeDecay = 0.05
    public var nudgeConfidence = 0.35
    public var nudgeAngle = 60.0
    public var nudgeRecency = 1.0

    /// Refines named sounds' directions from a 0.1 s block (10 updates/s): each sound that already shows a
    /// direction and was detected within the last second takes the block peak nearest to it, if within ±60°,
    /// so a clap or echo elsewhere can't drag it across the radar.
    public func nudge(peaks: [DOAPeak], now: Double) {
        guard !peaks.isEmpty else { return }
        for group in Array(byGroup.keys) {
            guard let e = byGroup[group], e.showsDirection, now - e.lastSeen <= nudgeRecency else { continue }
            let current = e.belief.peakBearing
            func gap(_ p: DOAPeak) -> Double { abs(Circular.difference(p.bearing, current)) }
            guard let near = peaks.min(by: { gap($0) < gap($1) }), gap(near) <= nudgeAngle else { continue }
            byGroup[group]!.belief.update(peaks: [DOAPeak(bearing: near.bearing, weight: 1)],
                                          confidence: nudgeConfidence, decayRate: nudgeDecay)
            byGroup[group]!.directionLatch.update(concentration: byGroup[group]!.belief.concentration)
        }
    }

    public func reset() { byGroup = [:] }
}
