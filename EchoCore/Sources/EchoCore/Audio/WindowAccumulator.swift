/// Buffers incoming FOA chunks and emits fixed-length overlapping windows whose
/// start samples are multiples of `hopLength` from capture start.
public struct WindowAccumulator: Sendable {
    public let windowLength: Int
    public let hopLength: Int
    private var w: [Float] = []
    private var x: [Float] = []
    private var y: [Float] = []
    private var z: [Float] = []
    private var bufferStart: Int64 = 0

    public init(windowLength: Int, hopLength: Int) {
        precondition(windowLength > 0 && hopLength > 0 && hopLength <= windowLength)
        self.windowLength = windowLength
        self.hopLength = hopLength
    }

    /// Appends equal-length channel chunks; returns every window that became complete.
    public mutating func append(w: [Float], x: [Float], y: [Float], z: [Float], sampleRate: Double) -> [FOAWindow] {
        precondition(w.count == x.count && x.count == y.count && y.count == z.count, "channel lengths differ")
        self.w += w
        self.x += x
        self.y += y
        self.z += z
        var out: [FOAWindow] = []
        while self.w.count >= windowLength {
            out.append(FOAWindow(
                w: Array(self.w[0..<windowLength]), x: Array(self.x[0..<windowLength]),
                y: Array(self.y[0..<windowLength]), z: Array(self.z[0..<windowLength]),
                sampleRate: sampleRate, startSample: bufferStart))
            self.w.removeFirst(hopLength)
            self.x.removeFirst(hopLength)
            self.y.removeFirst(hopLength)
            self.z.removeFirst(hopLength)
            bufferStart += Int64(hopLength)
        }
        return out
    }

    /// 1 s windows with 50% overlap at any sample rate (spec §3: same cadence as the reference design).
    /// 1 s windows starting every `hopSeconds` (0.5 s by default).
    public static func forSampleRate(_ sampleRate: Double, hopSeconds: Double = 0.5) -> WindowAccumulator {
        let window = max(2, Int(sampleRate.rounded()))
        return WindowAccumulator(windowLength: window, hopLength: max(1, Int((sampleRate * hopSeconds).rounded())))
    }

    public mutating func reset() {
        w = []
        x = []
        y = []
        z = []
        bufferStart = 0
    }
}
