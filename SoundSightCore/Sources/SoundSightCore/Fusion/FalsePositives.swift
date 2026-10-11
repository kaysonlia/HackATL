import simd

/// Touching or bumping the phone reaches the mics through its body and sounds loud and close. The
/// motion sensors catch it: a jolt (a sharp jump in user acceleration between ~60 Hz samples, or a large
/// acceleration) after the phone has been still for 0.5 s starts a handling episode of at most 1.5 s.
/// Continuous motion (walking, carrying) is not handling, so it never blanks the classifier.
public struct HandlingDetector: Sendable {
    /// g between consecutive samples.
    public static let jerkThreshold = 0.04
    /// g.
    public static let accelerationThreshold = 0.15
    /// Below this the phone counts as still (g).
    public static let calmThreshold = 0.05
    /// Still samples needed before a jolt counts (0.5 s).
    public static let calmSamplesNeeded = 30
    /// Longest handling episode in samples (1.5 s); motion after that is carrying, not handling.
    public static let episodeSamples = 90

    private var last: SIMD3<Double>?
    private var calmRun = 0
    private var episodeAge: Int?

    public init() {}

    public mutating func update(userAcceleration a: SIMD3<Double>) -> Bool {
        defer {
            last = a
            calmRun = simd_length(a) < Self.calmThreshold ? calmRun + 1 : 0
        }
        if let age = episodeAge { episodeAge = age + 1 > Self.episodeSamples ? nil : age + 1 }
        let jerk = last.map { simd_length(a - $0) } ?? 0
        guard jerk > Self.jerkThreshold || simd_length(a) > Self.accelerationThreshold else { return false }
        if episodeAge != nil { return true }
        guard calmRun >= Self.calmSamplesNeeded else { return false }
        episodeAge = 0
        return true
    }
}

/// Stretches of the capture timeline (seconds) when the phone was being handled, so classifier windows
/// that overlap them can be ignored.
public struct HandlingTimeline: Sendable {
    private var intervals: [ClosedRange<Double>] = []

    public init() {}

    public mutating func mark(from start: Double, to end: Double) {
        if let last = intervals.last, start <= last.upperBound {
            intervals[intervals.count - 1] = last.lowerBound...max(last.upperBound, end)
        } else {
            intervals.append(start...end)
        }
    }

    public func overlaps(_ start: Double, _ end: Double) -> Bool {
        intervals.contains { $0.lowerBound < end && start < $0.upperBound }
    }

    public mutating func prune(before t: Double) {
        intervals.removeAll { $0.upperBound < t }
    }

    /// Classifier detections kept for a window that overlaps handling: Critical and High sounds always
    /// count (a siren must not vanish because the phone was bumped); Low and Medium ones are dropped.
    public static func keepDuringHandling(_ active: [String: Double], urgencyMap: UrgencyMap) -> [String: Double] {
        active.filter { urgencyMap.urgency(for: $0.key) >= .high }
    }
}

/// Decides which 0.1 s spikes get an instant arrow: a sound that lasts two blocks in a row from about
/// the same direction (horn, bark, shout), or a single very loud impulse (gunshot, bang). Quick quiet
/// clicks and taps get none.
public struct SpikeGate: Sendable {
    public struct Spike: Sendable, Equatable {
        public var bearing: Double
        public var level: Double
    }

    /// A single block this far above ambient passes on its own.
    public static let impulseMargin = 20.0
    public var maxGap = 0.15
    public var sameDirection = 30.0
    private var pending: (bearing: Double, time: Double)?

    public init() {}

    /// `bearing` is nil when the block has no usable direction.
    public mutating func feed(level: Double, ambient: Double, bearing: Double?, now: Double) -> Spike? {
        guard let bearing, AmbientTracker.isSpike(level: level, ambient: ambient) else {
            pending = nil
            return nil
        }
        defer { pending = (bearing, now) }
        if level >= ambient + Self.impulseMargin { return Spike(bearing: bearing, level: level) }
        if let p = pending, now - p.time <= maxGap, abs(Circular.difference(p.bearing, bearing)) <= sameDirection {
            return Spike(bearing: bearing, level: level)
        }
        return nil
    }
}

extension SoundEvent {
    /// Critical and High sounds show on their first detection; Low and Medium need two, which filters
    /// one-window misfires (e.g. a false Door).
    public var isConfirmed: Bool { urgency >= .high || hits >= 2 }
}

/// Lets short loud sounds through that a 1 s classifier window dilutes. A single gunshot (~0.15 s) is
/// named by Apple's classifier (top label firecracker/gunshot) but scores 0.44–0.91, under the 0.841
/// Gunshot threshold. When the window held a loud impulse (≥ 20 dB over the room), a gunshot-family
/// top label and a group score ≥ 0.5 count. Spike test: 18/20 single bangs caught; 13/120 equally loud
/// other impulses (claps, cans, glass) slip through, fewer in practice since those are rarely that loud.
public struct ImpulseAssist: Sendable {
    public let group: String
    public let labels: Set<String>
    public var floor = 0.5

    public init(group: String, labels: Set<String>) {
        self.group = group
        self.labels = labels
    }

    /// The Gunshot/Explosion rule over Apple's labels.
    public static func gunshot(mapper: LabelMapper) -> ImpulseAssist {
        let group = "Gunshot/Explosion"
        return ImpulseAssist(group: group, labels: Set(mapper.labelToGroup.filter { $0.value == group }.keys))
    }

    public func activates(rawLabels: [String: Double], groupScore: Double, impulseInWindow: Bool) -> Bool {
        guard impulseInWindow, groupScore >= floor,
              let top = rawLabels.max(by: { $0.value < $1.value }) else { return false }
        return labels.contains(top.key)
    }
}
