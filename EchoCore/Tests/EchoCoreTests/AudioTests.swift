import Testing
@testable import EchoCore

struct PCMDeinterleaverTests {
    @Test func interleavedInt16() {
        let samples: [Int16] = [16384, -16384, 0, 32767, -32768, 8192]  // 3 frames × 2 ch
        let out = samples.withUnsafeBytes { raw in
            PCMDeinterleaver.deinterleave(buffers: [raw], layout: .init(sampleType: .int16, channelCount: 2, interleaved: true))
        }
        #expect(out.count == 2)
        #expect(out[0] == [0.5, 0, -1])
        #expect(out[1][0] == -0.5)
        #expect(abs(out[1][1] - 32767.0 / 32768.0) < 1e-6)
        #expect(out[1][2] == 0.25)
    }

    @Test func nonInterleavedFloat() {
        let a: [Float] = [0.1, 0.2]
        let b: [Float] = [-0.1, -0.2]
        let out = a.withUnsafeBytes { ra in
            b.withUnsafeBytes { rb in
                PCMDeinterleaver.deinterleave(buffers: [ra, rb], layout: .init(sampleType: .float32, channelCount: 2, interleaved: false))
            }
        }
        #expect(out == [[0.1, 0.2], [-0.1, -0.2]])
    }

    @Test func missingChannelBufferYieldsEmptyChannel() {
        let a: [Float] = [0.5]
        let out = a.withUnsafeBytes { ra in
            PCMDeinterleaver.deinterleave(buffers: [ra], layout: .init(sampleType: .float32, channelCount: 2, interleaved: false))
        }
        #expect(out == [[0.5], []])
    }
}

struct WindowAccumulatorTests {
    @Test func emitsOverlappingWindowsOnHopGrid() {
        var acc = WindowAccumulator(windowLength: 4, hopLength: 2)
        let ramp = (0..<3).map(Float.init)
        #expect(acc.append(w: ramp, x: ramp, y: ramp, z: ramp, sampleRate: 4).isEmpty)
        let next = (3..<8).map(Float.init)
        let windows = acc.append(w: next, x: next, y: next, z: next, sampleRate: 4)
        #expect(windows.map(\.startSample) == [0, 2, 4])
        #expect(windows[0].w == [0, 1, 2, 3])
        #expect(windows[1].w == [2, 3, 4, 5])
        #expect(windows[2].z == [4, 5, 6, 7])
    }

    @Test func oneSecondWindowsAtAnyRate() {
        let a = WindowAccumulator.forSampleRate(44_100)
        #expect(a.windowLength == 44_100 && a.hopLength == 22_050)
        let b = WindowAccumulator.forSampleRate(48_000)
        #expect(b.windowLength == 48_000 && b.hopLength == 24_000)
    }

    @Test func irregularChunksGiveSameWindowsAsOneChunk() {
        let signal = (0..<200).map(Float.init)
        var whole = WindowAccumulator(windowLength: 40, hopLength: 20)
        let expected = whole.append(w: signal, x: signal, y: signal, z: signal, sampleRate: 40)
        var pieces = WindowAccumulator(windowLength: 40, hopLength: 20)
        var got: [FOAWindow] = []
        var i = 0
        for size in [1, 7, 33, 2, 19, 64, 3, 50, 21] where i < signal.count {
            let part = Array(signal[i..<min(signal.count, i + size)])
            got += pieces.append(w: part, x: part, y: part, z: part, sampleRate: 40)
            i += size
        }
        #expect(got.map(\.startSample) == expected.map(\.startSample))
        #expect(got.map(\.w) == expected.map(\.w))
    }

    @Test func resetRestartsTimeline() {
        var acc = WindowAccumulator(windowLength: 2, hopLength: 1)
        _ = acc.append(w: [1, 2, 3], x: [1, 2, 3], y: [1, 2, 3], z: [1, 2, 3], sampleRate: 1)
        acc.reset()
        let w = acc.append(w: [9, 9], x: [9, 9], y: [9, 9], z: [9, 9], sampleRate: 1)
        #expect(w.map(\.startSample) == [0])
    }
}
