import simd

/// Touching or bumping the phone reaches the mics through its body and sounds loud and close. The
/// motion sensors catch it: a sharp jump in user acceleration between consecutive samples (~60 Hz),
/// or a large acceleration. Smooth turning and slow handling don't count.
public struct HandlingDetector: Sendable {
    /// g between consecutive samples.
    public static let jerkThreshold = 0.04
    /// g.
    public static let accelerationThreshold = 0.15
    private var last: SIMD3<Double>?

    public init() {}

    public mutating func update(userAcceleration a: SIMD3<Double>) -> Bool {
        defer { last = a }
        let jerk = last.map { simd_length(a - $0) } ?? 0
        return jerk > Self.jerkThreshold || simd_length(a) > Self.accelerationThreshold
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
