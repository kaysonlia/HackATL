import EchoCore
import Foundation
import os
import simd

/// Per-window direction data, also used by the probe.
struct WindowSummary: Sendable {
    var summedRaw: SIMD3<Float>
    var diffuseness: Float
    var totalEnergy: Float
    var channelRMS: [Float]  // W, X, Y, Z
    var doa: DOAFrame
}

struct TrackerOutput: Sendable {
    var events: [SoundEvent]
    var newEvents: [SoundEvent]
    var now: Double
}

/// Chunk → SoundAnalysis + 1 s windows → DOA → joiner → EventTracker, all on one serial queue (spec §3).
final class AudioPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "echo.pipeline")
    private let resources: ClassificationResources
    private let estimator: DOAEstimator
    private let tracker: EventTracker
    private let state = OSAllocatedUnfairLock(initialState: FOAAxisCalibration.initialGuess)
    private let deviceToWorld: @Sendable () -> simd_float3x3

    private var sampleRate: Double = 0
    private var accumulator: WindowAccumulator?
    private var joiner: WindowJoiner?
    private var classifier: (any SoundClassifier)?

    var onWindow: (@Sendable (WindowSummary) -> Void)?
    var onTracker: (@Sendable (TrackerOutput) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    init(resources: ClassificationResources, deviceToWorld: @escaping @Sendable () -> simd_float3x3) throws {
        self.resources = resources
        self.deviceToWorld = deviceToWorld
        estimator = try DOAEstimator()
        tracker = EventTracker(urgencyMap: resources.urgency)
    }

    var calibration: FOAAxisCalibration {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// Safe to call from any queue.
    func ingest(_ chunk: FOAChunk) {
        queue.async { self.process(chunk) }
    }

    func reset() {
        queue.async {
            self.sampleRate = 0
            self.accumulator = nil
            self.joiner = nil
            self.classifier = nil
            self.tracker.reset()
        }
    }

    private func setUp(sampleRate: Double) {
        self.sampleRate = sampleRate
        let acc = WindowAccumulator.forSampleRate(sampleRate)
        accumulator = acc
        joiner = WindowJoiner(hopLength: acc.hopLength)
        do {
            let c: any SoundClassifier = try SoundAnalysisClassifier(sampleRate: sampleRate, mapper: resources.mapper)
            c.onFrame = { [unowned self] frame in self.handle(self.joiner?.add(classification: frame) ?? []) }
            c.onError = { [onError] error in onError?("Sound classifier error: \(error.localizedDescription)") }
            classifier = c
        } catch {
            onError?("Sound classifier unavailable: \(error.localizedDescription)")
        }
    }

    private func process(_ chunk: FOAChunk) {
        if chunk.sampleRate != sampleRate { setUp(sampleRate: chunk.sampleRate) }
        classifier?.analyze(chunk.w)
        guard var acc = accumulator else { return }
        let windows = acc.append(w: chunk.w, x: chunk.x, y: chunk.y, z: chunk.z, sampleRate: chunk.sampleRate)
        accumulator = acc
        let cal = calibration
        for window in windows {
            let intensity = estimator.intensity.analyze(window)
            let doa = estimator.estimate(intensity, windowStart: window.startSample, calibration: cal, deviceToWorld: deviceToWorld())
            onWindow?(WindowSummary(summedRaw: intensity.summedRaw, diffuseness: intensity.diffuseness,
                                    totalEnergy: intensity.totalEnergy,
                                    channelRMS: [window.w, window.x, window.y, window.z].map(Self.rms), doa: doa))
            handle(joiner?.add(doa: doa) ?? [])
        }
    }

    private func handle(_ joined: [JoinedWindow]) {
        for j in joined {
            let now = Double(j.windowStart) / sampleRate
            let active = resources.thresholds.active(j.classification.groupScores)
            let created = tracker.ingest(active: active, doa: j.doa, now: now)
            onTracker?(TrackerOutput(events: tracker.events, newEvents: created, now: now))
        }
    }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }
}
