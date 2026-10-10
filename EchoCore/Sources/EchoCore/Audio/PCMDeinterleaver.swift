/// Describes linear PCM as delivered by Core Audio.
public struct PCMLayout: Sendable, Equatable {
    public enum SampleType: Sendable, Equatable { case float32, int16, int32 }

    public var sampleType: SampleType
    public var channelCount: Int
    public var interleaved: Bool

    public init(sampleType: SampleType, channelCount: Int, interleaved: Bool) {
        self.sampleType = sampleType
        self.channelCount = channelCount
        self.interleaved = interleaved
    }

    var bytesPerSample: Int {
        switch sampleType {
        case .float32, .int32: 4
        case .int16: 2
        }
    }
}

public enum PCMDeinterleaver {
    /// Converts raw PCM into one Float array per channel, scaled to [-1, 1].
    /// - Parameter buffers: one buffer when `layout.interleaved`, otherwise one per channel.
    public static func deinterleave(buffers: [UnsafeRawBufferPointer], layout: PCMLayout) -> [[Float]] {
        let bps = layout.bytesPerSample
        if layout.interleaved {
            guard let buf = buffers.first else { return Array(repeating: [], count: layout.channelCount) }
            let frames = buf.count / (bps * layout.channelCount)
            return (0..<layout.channelCount).map { ch in
                (0..<frames).map { f in read(buf, offset: (f * layout.channelCount + ch) * bps, layout.sampleType) }
            }
        }
        return (0..<layout.channelCount).map { ch in
            guard ch < buffers.count else { return [] }
            let buf = buffers[ch]
            return (0..<(buf.count / bps)).map { f in read(buf, offset: f * bps, layout.sampleType) }
        }
    }

    private static func read(_ buf: UnsafeRawBufferPointer, offset: Int, _ type: PCMLayout.SampleType) -> Float {
        switch type {
        case .float32: buf.loadUnaligned(fromByteOffset: offset, as: Float.self)
        case .int16: Float(buf.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
        case .int32: Float(buf.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2_147_483_648
        }
    }
}
