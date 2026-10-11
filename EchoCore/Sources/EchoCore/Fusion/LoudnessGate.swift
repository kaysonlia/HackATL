/// Only sounds that stand out from the room get named. A classifier window counts when its loudest
/// 0.1 s block is `margin` dB over the ambient level at that moment, and at least `floor` dB; the
/// loudest block (not the 1 s average) lets short bangs through. A sound already being tracked carries
/// on regardless, since the ambient level rises to meet a long siren after about 8 s.
public struct LoudnessGate: Sendable {
    /// dB over ambient; adjustable in Settings within `marginRange`.
    public var margin = LoudnessGate.defaultMargin
    public static let defaultMargin = 6.0
    public static let marginRange: ClosedRange<Double> = 0...20
    public var floor = AmbientTracker.spikeFloor
    public var blockLength = 0.1
    public var windowLength = 1.0
    /// Block history kept; windows run 1–2 s behind the live blocks.
    public var keep = 10.0
    private var blocks: [(time: Double, loud: Bool)] = []

    public init() {}

    /// One 0.1 s block's omni level and the room's ambient level then, at capture time `time` (s).
    public mutating func addBlock(level: Double, ambient: Double, time: Double) {
        if let last = blocks.last, time < last.time { blocks = [] }  // clock restarted
        blocks.append((time, level >= max(ambient + margin, floor)))
        blocks.removeAll { time - $0.time > keep }
    }

    /// Whether any block in the window [windowStart, windowStart + windowLength) stood out.
    public func passes(windowStart: Double) -> Bool {
        let end = windowStart + windowLength
        return blocks.contains { $0.loud && $0.time + blockLength > windowStart && $0.time < end }
    }

    /// `active` without new sounds from a window that didn't stand out. `tracked` sounds seen within
    /// `evictAfter` seconds of the window are kept.
    public func filter(_ active: [String: Double], windowStart: Double, tracked: [SoundEvent],
                       evictAfter: Double) -> [String: Double] {
        if passes(windowStart: windowStart) { return active }
        let ongoing = Set(tracked.filter { windowStart - $0.lastSeen <= evictAfter }.map(\.group))
        return active.filter { ongoing.contains($0.key) }
    }

    public mutating func reset() { blocks = [] }
}
