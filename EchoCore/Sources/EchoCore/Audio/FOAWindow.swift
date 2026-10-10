/// One analysis window of First-Order Ambisonics audio. Channels are the raw FOA
/// components (ACN/SN3D): `w` omni, `x`/`y`/`z` dipoles in the FOA's own axes.
public struct FOAWindow: Sendable {
    public var w: [Float]
    public var x: [Float]
    public var y: [Float]
    public var z: [Float]
    public var sampleRate: Double
    /// Absolute index of the first sample since capture started.
    public var startSample: Int64

    public init(w: [Float], x: [Float], y: [Float], z: [Float], sampleRate: Double, startSample: Int64) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
        self.sampleRate = sampleRate
        self.startSample = startSample
    }
}
