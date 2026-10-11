import AVFoundation
import EchoCore
import Observation
import SwiftUI

enum ListeningStatus: Equatable {
    case idle
    case listening
    case interrupted
    case permissionDenied
    case directionUnavailable(String)
    case error(String)
}

/// What the UI needs for one tracked sound.
struct EventDisplay: Identifiable, Equatable {
    var id: String { group }
    var group: String
    var urgency: Urgency
    var confidence: Double
    /// World bearing of the belief peak; nil until the belief is concentrated enough (R ≥ 0.5).
    var worldBearing: Double?
    var concentration: Double
    var belief: [Double]

    static let minConcentration = 0.5

    init(_ e: SoundEvent) {
        group = e.group
        urgency = e.urgency
        confidence = e.confidence
        concentration = e.belief.concentration
        worldBearing = concentration >= Self.minConcentration ? e.belief.peakBearing : nil
        belief = e.belief.probabilities
    }
}

@MainActor
@Observable
final class AppModel {
    private static let calibrationKey = "foaAxisCalibration"

    var status: ListeningStatus = .idle
    var isListening = false
    var events: [EventDisplay] = []
    var forwardBearing: Double = 0
    var classifierWarning: String?
    var probe = ProbeState()
    var calibration: FOAAxisCalibration {
        didSet {
            pipeline?.calibration = calibration
            if let data = try? JSONEncoder().encode(calibration) {
                UserDefaults.standard.set(data, forKey: Self.calibrationKey)
            }
        }
    }

    @ObservationIgnored private let capture = FOACaptureSession()
    @ObservationIgnored private let motion = MotionProvider()
    @ObservationIgnored private let haptics = HapticsManager()
    @ObservationIgnored private var pipeline: AudioPipeline?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.calibrationKey),
           let saved = try? JSONDecoder().decode(FOAAxisCalibration.self, from: data) {
            calibration = saved
        } else {
            calibration = .initialGuess
        }
        do {
            let motion = motion
            let pipeline = try AudioPipeline(resources: .bundled()) { motion.deviceToWorld() }
            pipeline.calibration = calibration
            pipeline.onWindow = { [weak self] summary in Task { @MainActor in self?.apply(summary) } }
            pipeline.onTracker = { [weak self] output in Task { @MainActor in self?.apply(output) } }
            pipeline.onError = { [weak self] message in Task { @MainActor in self?.classifierWarning = message } }
            capture.onChunk = { chunk in pipeline.ingest(chunk) }
            self.pipeline = pipeline
        } catch {
            status = .error("Couldn't load the sound tables: \(error.localizedDescription)")
        }
        capture.onFormat = { [weak self] format in Task { @MainActor in self?.probe.format = format } }
        motion.onUpdate = { [weak self] bearing in self?.forwardBearing = bearing }
        observeSession()
    }

    func start() async {
        guard !isListening, pipeline != nil else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            status = .permissionDenied
            return
        }
        do {
            try capture.configure()
        } catch {
            status = .error("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        pipeline?.reset()
        motion.start()
        capture.start()
        isListening = true
        if !capture.foaEnabled {
            status = .directionUnavailable("this device can't capture spatial (FOA) audio. Sounds are still identified.")
        } else if !motion.isAvailable {
            status = .error("Motion sensors unavailable: the radar won't stay anchored as you turn.")
        } else {
            status = .listening
        }
    }

    func stop() {
        capture.stop()
        motion.stop()
        isListening = false
        events = []
        status = .idle
    }

    func recordProbe(seconds: Double) {
        probe.recordingUntil = Date().addingTimeInterval(seconds)
    }

    func fitProbe() {
        probe.fit = CalibrationFitter.fit(probe.samples)
    }

    func exportProbeCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foa-probe-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try probe.csv().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func apply(_ summary: WindowSummary) {
        probe.ingest(summary, calibration: calibration, now: Date())
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        events = output.events.map(EventDisplay.init)
        for e in output.events where e.lastSeen == output.now {
            haptics.alert(group: e.group, urgency: e.urgency, now: output.now)
        }
        for e in output.newEvents where e.urgency == .critical {
            AccessibilityNotification.Announcement("\(e.group), critical").post()
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isListening == true { self?.status = .interrupted } }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isListening == true { self?.status = .listening } }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                self.status = .error("Audio capture stopped unexpectedly. Restarting…")
                self.capture.start()
            }
        })
    }
}
