import CoreML
import SoundSightCore
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
    /// Raw-axis intensity and energy per `IntensityResult.directionTestBands` band, for the direction test.
    var bands: [(raw: SIMD3<Float>, energy: Float)] = []
    var levelDB: Double = 0
}

/// Every 0.1 s: the room's ambient level, where it comes from, and the Unclassified markers.
struct SceneUpdate: Sendable {
    var now: Double
    var ambientDB: Double
    var ambientProfile: [Double]
    var markers: [MarkerSnapshot]
}

struct TrackerOutput: Sendable {
    var events: [SoundEvent]
    var newEvents: [SoundEvent]
    var now: Double
    /// A 0.1 s direction nudge between classifier windows: refresh arrows only (no alerts).
    var directionOnly = false
}

/// Chunk → classifier + 1 s windows → DOA → joiner → EventTracker, all on one serial queue (spec §3).
/// Classifies with Apple's SoundAnalysis in the foreground and YAMNet on the CPU in the background,
/// where SoundAnalysis fails; a classifier that errors is rebuilt.
final class AudioPipeline: @unchecked Sendable {
    enum ClassifierKind: Sendable { case apple, yamnet }

    private let queue = DispatchQueue(label: "soundsight.pipeline")
    private let resources: ClassificationResources
    private let yamnet: YAMNetResources
    private let yamnetFrontend: YAMNetFrontend
    private let yamnetModel: MLModel?
    private let estimator: DOAEstimator
    private let tracker: EventTracker
    private let state = OSAllocatedUnfairLock(initialState: FOAAxisCalibration.initialGuess)
    private let wantsYAMNet = OSAllocatedUnfairLock(initialState: false)
    private let enabledOptional = OSAllocatedUnfairLock(initialState: Set<String>())
    private let loudnessMarginLock = OSAllocatedUnfairLock(initialState: LoudnessGate.defaultMargin)
    private let deviceToWorld: @Sendable () -> simd_float3x3

    private var sampleRate: Double = 0
    private var samplesSeen: Int64 = 0
    private var accumulator: WindowAccumulator?
    private var joiner: WindowJoiner?
    private var classifier: (any SoundClassifier)?
    private var classifierKind: ClassifierKind?
    private var classifierFailedAt: Int64?
    private var activeThresholds: GroupThresholds
    /// 0.1 s blocks for ambient tracking and instant "Unclassified" arrows.
    private var blockBuffer: [[Float]] = [[], [], [], []]
    private var blockStart: Int64 = 0
    private var ambient = AmbientTracker()
    private var ambientDirection = AmbientDirection()
    private var markerTracker = MarkerTracker()
    /// Sounds are only named when they stand out from the room.
    private var loudnessGate = LoudnessGate()
    private var spikeGate = SpikeGate()
    private var handlingTimeline = HandlingTimeline()
    /// Loud impulses (≥ 20 dB over the room), so a classifier window holding one can name a single gunshot.
    private var impulseTimeline = HandlingTimeline()
    private let gunshotAssist: ImpulseAssist
    private let handlingUntil = OSAllocatedUnfairLock(initialState: Date.distantPast)
    /// Omni level (approximate dB SPL) per DOA window start, for the tracker and the session log.
    private var levels: [Int64: Double] = [:]
    /// Debug (probe session log): raw labels per window start.
    private var rawLabels: [Int64: [String: Double]] = [:]

    var onWindow: (@Sendable (WindowSummary) -> Void)?
    var onTracker: (@Sendable (TrackerOutput) -> Void)?
    var onScene: (@Sendable (SceneUpdate) -> Void)?
    var onError: (@Sendable (String) -> Void)?
    /// Debug: one `;`-separated line per joined window for the probe's session log.
    var onDebugLine: (@Sendable (String) -> Void)?
    /// Debug: one-off notes for the probe's Recent detections (e.g. which classifier is active).
    var onNote: (@Sendable (String) -> Void)?

    init(resources: ClassificationResources, deviceToWorld: @escaping @Sendable () -> simd_float3x3) throws {
        self.resources = resources
        self.deviceToWorld = deviceToWorld
        yamnet = try YAMNetResources.bundled()
        yamnetFrontend = try YAMNetFrontend.bundled()
        // Loaded up front, in the foreground, so switching on lock is instant.
        yamnetModel = try? YAMNetClassifier.loadModel()
        estimator = try DOAEstimator()
        // Named sounds leave the list 2 s after their last detection (arrows hide sooner: 1 s of quiet).
        tracker = EventTracker(urgencyMap: resources.urgency, evictAfter: 2)
        activeThresholds = resources.thresholds
        gunshotAssist = .gunshot(mapper: resources.mapper)
    }

    var calibration: FOAAxisCalibration {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// True while the app is not in the foreground (or when forced from the probe): classify with YAMNet.
    var useYAMNet: Bool {
        get { wantsYAMNet.withLock { $0 } }
        set { wantsYAMNet.withLock { $0 = newValue } }
    }

    /// Optional groups (Footsteps, Water Running, ...) the user turned on in Settings.
    var enabledOptionalGroups: Set<String> {
        get { enabledOptional.withLock { $0 } }
        set { enabledOptional.withLock { $0 = newValue } }
    }

    /// dB a sound must stand out from the room to be named (Settings › Strictness).
    var loudnessMargin: Double {
        get { loudnessMarginLock.withLock { $0 } }
        set { loudnessMarginLock.withLock { $0 = newValue } }
    }

    /// The phone is being touched or bumped until `date`: ignore sounds around then. Safe from any queue.
    func noteHandling(until date: Date) {
        handlingUntil.withLock { $0 = max($0, date) }
    }

    /// Safe to call from any queue.
    func ingest(_ chunk: FOAChunk) {
        queue.async { self.process(chunk) }
    }

    func reset() {
        queue.async {
            self.sampleRate = 0
            self.samplesSeen = 0
            self.accumulator = nil
            self.joiner = nil
            self.classifier = nil
            self.classifierKind = nil
            self.classifierFailedAt = nil
            self.rawLabels = [:]
            self.levels = [:]
            self.resetScene()
            self.tracker.reset()
        }
    }

    private func setUp(sampleRate: Double) {
        self.sampleRate = sampleRate
        samplesSeen = 0
        // The capture clock restarts at 0 here (first chunk, or a route/sample-rate change mid-session):
        // events timed on the old clock would never evict. Alert gates treat the backwards jump as a reset.
        tracker.reset()
        // A new 1 s window every 0.25 s: sounds are named sooner and Low/Medium ones confirmed in 0.25 s.
        let acc = WindowAccumulator.forSampleRate(sampleRate, hopSeconds: 0.25)
        accumulator = acc
        joiner = WindowJoiner(hopLength: acc.hopLength)
        classifier = nil
        classifierKind = nil
        resetScene()
    }

    private func resetScene() {
        blockBuffer = [[], [], [], []]
        blockStart = samplesSeen
        ambient = AmbientTracker()
        ambientDirection = AmbientDirection()
        markerTracker.reset()
        loudnessGate.reset()
        spikeGate = SpikeGate()
        handlingTimeline = HandlingTimeline()
        impulseTimeline = HandlingTimeline()
    }

    /// 0.1 s block: update ambient; a spike above it becomes an Unclassified marker at once,
    /// anything else feeds the background-direction profile.
    private func processBlock(_ block: FOAWindow) {
        let level = UrgencyScore.level(rms: Double(Self.rms(block.w)))
        let now = Double(block.startSample) / sampleRate
        // Touches and bumps: mark the moment (with margin) and skip it entirely.
        if Date() <= handlingUntil.withLock({ $0 }) {
            handlingTimeline.mark(from: now - 0.1, to: now + 0.2)
            _ = spikeGate.feed(level: 0, ambient: ambient.level, bearing: nil, now: now)
            markerTracker.expire(now: now)
            onScene?(SceneUpdate(now: now, ambientDB: ambient.level, ambientProfile: ambientDirection.profile,
                                 markers: markerTracker.snapshot(now: now)))
            return
        }
        handlingTimeline.prune(before: now - 10)
        impulseTimeline.prune(before: now - 10)
        ambient.add(level: level)
        loudnessGate.margin = loudnessMargin
        loudnessGate.addBlock(level: level, ambient: ambient.level, time: now)
        if level >= max(ambient.level + SpikeGate.impulseMargin, AmbientTracker.spikeFloor) {
            impulseTimeline.mark(from: now, to: now + 0.1)
        }
        let toWorld = deviceToWorld()
        var doa = estimator.estimate(estimator.intensity.analyze(block), windowStart: block.startSample,
                                     calibration: calibration, deviceToWorld: toWorld)
        if !ForwardHeading.directionUsable(deviceToWorld: toWorld) { doa.peaks = []; doa.diffuseness = 1 }
        // 10 updates/s for named sounds: a block clearly above the room nudges their directions.
        if level >= ambient.level + 4, doa.diffuseness < 0.8, !doa.peaks.isEmpty, !tracker.events.isEmpty {
            tracker.nudge(peaks: doa.peaks, now: now)
            onTracker?(TrackerOutput(events: tracker.events, newEvents: [], now: now, directionOnly: true))
        }
        let peak = doa.diffuseness < 0.9 ? doa.peaks.max(by: { $0.weight < $1.weight }) : nil
        // Spikes near a named arrow are that sound: no new arrow, and leftovers there are absorbed.
        let named = tracker.events.filter { $0.isConfirmed && $0.arrowVisible(now: now) }.map(\.belief.peakBearing)
        if let spike = spikeGate.feed(level: level, ambient: ambient.level, bearing: peak?.bearing, now: now) {
            markerTracker.spike(bearing: spike.bearing, level: spike.level, now: now, near: named)
        }
        markerTracker.absorb(near: named)
        if !AmbientTracker.isSpike(level: level, ambient: ambient.level) {
            if !doa.peaks.isEmpty { ambientDirection.add(histogram: doa.histogram) }
        }
        markerTracker.expire(now: now)
        onScene?(SceneUpdate(now: now, ambientDB: ambient.level, ambientProfile: ambientDirection.profile,
                             markers: markerTracker.snapshot(now: now)))
    }

    /// Builds the classifier the app currently wants, starting at the current capture sample.
    private func makeClassifier(_ kind: ClassifierKind) {
        classifierKind = kind
        classifierFailedAt = nil
        do {
            let c: any SoundClassifier
            switch kind {
            case .apple:
                c = try SoundAnalysisClassifier(sampleRate: sampleRate, mapper: resources.mapper, startSample: samplesSeen)
                activeThresholds = resources.thresholds
                onNote?("classifier: Apple built-in (SoundAnalysis)")
            case .yamnet:
                guard let yamnetModel else { throw ResourceError.missing("YAMNet.mlmodelc") }
                c = try YAMNetClassifier(sampleRate: sampleRate, model: yamnetModel, frontend: yamnetFrontend,
                                         mapper: yamnet.mapper, startSample: samplesSeen)
                activeThresholds = yamnet.thresholds
                onNote?("classifier: YAMNet on CPU")
            }
            c.onLabels = { [unowned self] start, labels in self.rawLabels[start] = labels }
            c.onFrame = { [unowned self] frame in self.handle(self.joiner?.add(classification: frame) ?? []) }
            c.onError = { [unowned self] error in
                let ns = error as NSError
                let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { " ← \($0.domain) \($0.code): \($0.localizedDescription)" } ?? ""
                self.onError?("Sound classifier error: \(ns.domain) \(ns.code): \(ns.localizedDescription)\(underlying)")
                if self.classifierFailedAt == nil { self.classifierFailedAt = self.samplesSeen }
            }
            classifier = c
        } catch {
            classifier = nil
            classifierFailedAt = samplesSeen
            onError?("Sound classifier unavailable: \(error.localizedDescription)")
        }
    }

    private func process(_ chunk: FOAChunk) {
        if chunk.sampleRate != sampleRate { setUp(sampleRate: chunk.sampleRate) }
        let wanted: ClassifierKind = useYAMNet ? .yamnet : .apple
        // Switch on foreground/background changes; rebuild a failed classifier after 2 s.
        if wanted != classifierKind || classifierFailedAt.map({ samplesSeen - $0 >= Int64(2 * sampleRate) }) == true {
            makeClassifier(wanted)
        }
        classifier?.analyze(chunk.w)
        samplesSeen += Int64(chunk.w.count)
        for (i, channel) in [chunk.w, chunk.x, chunk.y, chunk.z].enumerated() { blockBuffer[i] += channel }
        let blockLength = Int(sampleRate / 10)
        while blockBuffer[0].count >= blockLength {
            let parts = blockBuffer.map { Array($0[0..<blockLength]) }
            blockBuffer = blockBuffer.map { Array($0[blockLength...]) }
            processBlock(FOAWindow(w: parts[0], x: parts[1], y: parts[2], z: parts[3], sampleRate: sampleRate, startSample: blockStart))
            blockStart += Int64(blockLength)
        }
        guard var acc = accumulator else { return }
        let windows = acc.append(w: chunk.w, x: chunk.x, y: chunk.y, z: chunk.z, sampleRate: chunk.sampleRate)
        accumulator = acc
        let cal = calibration
        for window in windows {
            let intensity = estimator.intensity.analyze(window)
            let toWorld = deviceToWorld()
            var doa = estimator.estimate(intensity, windowStart: window.startSample, calibration: cal, deviceToWorld: toWorld)
            // Held upright, the screen plane is vertical: no usable horizontal direction. Keep beliefs as they are.
            if !ForwardHeading.directionUsable(deviceToWorld: toWorld) { doa.peaks = []; doa.diffuseness = 1 }
            let windowTime = Double(window.startSample) / sampleRate
            if handlingTimeline.overlaps(windowTime, windowTime + 1) { doa.peaks = []; doa.diffuseness = 1 }
            levels[window.startSample] = UrgencyScore.level(rms: Double(Self.rms(window.w)))
            let cutoff = window.startSample - Int64(8 * acc.hopLength)
            levels = levels.filter { $0.key >= cutoff }
            rawLabels = rawLabels.filter { $0.key >= cutoff }
            onWindow?(WindowSummary(summedRaw: intensity.summedRaw, diffuseness: intensity.diffuseness,
                                    totalEnergy: intensity.totalEnergy,
                                    channelRMS: [window.w, window.x, window.y, window.z].map(Self.rms), doa: doa,
                                    bands: intensity.bandSums(edges: IntensityResult.directionTestBands),
                                    levelDB: levels[window.startSample] ?? 0))
            handle(joiner?.add(doa: doa) ?? [])
        }
    }

    private func handle(_ joined: [JoinedWindow]) {
        for j in joined {
            let now = Double(j.windowStart) / sampleRate
            let handled = handlingTimeline.overlaps(now, now + 1)
            let shown = resources.visibility.shown(activeThresholds.active(j.classification.groupScores),
                                                   enabled: enabledOptionalGroups)
            // A window overlapping handling keeps Critical/High sounds (a siren must not vanish because the
            // phone was bumped); Low/Medium detections there are dropped.
            var active = handled ? HandlingTimeline.keepDuringHandling(shown, urgencyMap: resources.urgency) : shown
            // Single gunshots: a loud impulse in the window plus a gunshot-type top label (Apple's classifier only).
            if !handled, classifierKind == .apple, active[gunshotAssist.group] == nil,
               let score = j.classification.groupScores[gunshotAssist.group],
               gunshotAssist.activates(rawLabels: rawLabels[j.windowStart] ?? [:], groupScore: score,
                                       impulseInWindow: impulseTimeline.overlaps(now, now + 1)) {
                active[gunshotAssist.group] = score
            }
            // Quiet sounds aren't named; ones already being tracked carry on.
            active = loudnessGate.filter(active, windowStart: now, tracked: tracker.events, evictAfter: tracker.evictAfter)
            let level = j.doa.flatMap { levels[$0.windowStart] }
            let created = tracker.ingest(active: active, doa: j.doa, now: now, levelDB: level)
            // A classified sound claims the Unclassified marker it started as.
            for e in tracker.events where e.lastSeen == now && e.isConfirmed {
                if let named = markerTracker.claim(group: e.group, bearing: e.showsDirection ? e.belief.peakBearing : nil, windowStart: now) {
                    let live = Double(blockStart) / sampleRate
                    onNote?(String(format: "named %@ %.1f s after it started", e.group, live - named.firstSpike))
                }
            }
            onTracker?(TrackerOutput(events: tracker.events, newEvents: created, now: now))
            if let onDebugLine { onDebugLine(debugLine(j, active: active, now: now)) }
        }
    }

    /// t;level_db;diffuseness;doa_peaks;top_labels;group_scores;active;events
    private func debugLine(_ j: JoinedWindow, active: [String: Double], now: Double) -> String {
        func f(_ x: Double) -> String { String(format: "%.2f", x) }
        let level = j.doa.flatMap { levels[$0.windowStart] }.map { String(format: "%.1f", $0) } ?? ""
        let peaks = j.doa?.peaks.map { "\(Int($0.bearing.rounded()))@\(f($0.weight))" }.joined(separator: " ") ?? ""
        let top = (rawLabels[j.windowStart] ?? [:]).sorted { $0.value > $1.value }.prefix(5).map { "\($0.key):\(f($0.value))" }
        let groups = j.classification.groupScores.filter { $0.value >= 0.2 }.sorted { $0.value > $1.value }.map { "\($0.key):\(f($0.value))" }
        let events = tracker.events.map { "\($0.group)@\(Int($0.belief.peakBearing.rounded()))/R\(f($0.belief.concentration))" }
        return [f(now), level, j.doa.map { f($0.diffuseness) } ?? "", peaks, top.joined(separator: " "), groups.joined(separator: " "),
                active.keys.sorted().joined(separator: " "), events.joined(separator: " ")].joined(separator: ";")
    }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }
}
