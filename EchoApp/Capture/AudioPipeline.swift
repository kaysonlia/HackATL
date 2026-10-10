import EchoCore
import Foundation
import os
import simd

/// Per-window direction data for the probe.
struct WindowSummary: Sendable {
    var summedRaw: SIMD3<Float>
    var diffuseness: Float
    var totalEnergy: Float
    var channelRMS: [Float]  // W, X, Y, Z
}

/// Probe-stage pipeline: chunk → 1 s windows → FOA intensity, on one serial queue.
/// Task 13 replaces this with the full classification + DOA + tracking pipeline.
final class AudioPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "echo.pipeline")
    private let analyzer: IntensityAnalyzer
    private var sampleRate: Double = 0
    private var accumulator: WindowAccumulator?

    var onWindow: (@Sendable (WindowSummary) -> Void)?

    init() throws {
        analyzer = try IntensityAnalyzer()
    }

    /// Safe to call from any queue.
    func ingest(_ chunk: FOAChunk) {
        queue.async { self.process(chunk) }
    }

    func reset() {
        queue.async {
            self.sampleRate = 0
            self.accumulator = nil
        }
    }

    private func process(_ chunk: FOAChunk) {
        if chunk.sampleRate != sampleRate {
            sampleRate = chunk.sampleRate
            accumulator = .forSampleRate(chunk.sampleRate)
        }
        guard var acc = accumulator else { return }
        let windows = acc.append(w: chunk.w, x: chunk.x, y: chunk.y, z: chunk.z, sampleRate: chunk.sampleRate)
        accumulator = acc
        for window in windows {
            let r = analyzer.analyze(window)
            onWindow?(WindowSummary(summedRaw: r.summedRaw, diffuseness: r.diffuseness, totalEnergy: r.totalEnergy,
                                    channelRMS: [window.w, window.x, window.y, window.z].map(Self.rms)))
        }
    }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }
}
