import AVFoundation
import SoundSightCore

/// One delivered buffer of FOA audio, split into raw ambisonic channels.
struct FOAChunk: Sendable {
    var w: [Float]
    var x: [Float]
    var y: [Float]
    var z: [Float]
    var sampleRate: Double
}

/// Converts capture sample buffers (FOA in ACN order W, Y, Z, X, or mono) into `FOAChunk`s.
enum FOABufferAdapter {
    /// Human-readable stream format, for the probe screen.
    static func describe(_ sampleBuffer: CMSampleBuffer) -> String {
        guard let fd = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return "unknown" }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        return "\(Int(asbd.mSampleRate)) Hz · \(asbd.mChannelsPerFrame) ch · \(asbd.mBitsPerChannel)-bit \(isFloat ? "float" : "int") · \(interleaved ? "interleaved" : "planar")"
    }

    static func chunk(from sampleBuffer: CMSampleBuffer) -> FOAChunk? {
        guard let fd = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mChannelsPerFrame == 4 || asbd.mChannelsPerFrame == 1 else { return nil }
        let channelCount = Int(asbd.mChannelsPerFrame)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let type: PCMLayout.SampleType
        switch (isFloat, asbd.mBitsPerChannel) {
        case (true, 32): type = .float32
        case (false, 16): type = .int16
        case (false, 32): type = .int32
        default: return nil
        }
        let layout = PCMLayout(sampleType: type, channelCount: channelCount,
                               interleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)
        let channels: [[Float]]
        do {
            channels = try sampleBuffer.withAudioBufferList { list, _ in
                PCMDeinterleaver.deinterleave(
                    buffers: list.map { UnsafeRawBufferPointer(start: $0.mData, count: Int($0.mDataByteSize)) },
                    layout: layout)
            }
        } catch {
            return nil
        }
        guard channels.count == channelCount else { return nil }
        if channelCount == 1 {
            // Mono fallback (no FOA): classification still works; DOA sees no directional energy.
            let silent = [Float](repeating: 0, count: channels[0].count)
            return FOAChunk(w: channels[0], x: silent, y: silent, z: silent, sampleRate: asbd.mSampleRate)
        }
        // ACN order: 0 = W, 1 = Y, 2 = Z, 3 = X.
        return FOAChunk(w: channels[0], x: channels[3], y: channels[1], z: channels[2], sampleRate: asbd.mSampleRate)
    }
}
