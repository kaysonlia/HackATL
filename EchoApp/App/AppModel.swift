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

@MainActor
@Observable
final class AppModel {
    private static let calibrationKey = "foaAxisCalibration"

    var status: ListeningStatus = .idle
    var isListening = false
    /// Tracked sounds, most urgent (highest score) first.
    var events: [EventDisplay] = []
    var forwardBearing: Double = 0
    var classifierWarning: String?
    var notificationsNote: String?
    var liveActivityNote: String?
    /// When listening last started; drives the 3 s radar sweep.
    var listeningSince: Date?
    /// Debug: classify with YAMNet even in the foreground (it always runs in the background).
    var forceYAMNet = false {
        didSet { pipeline?.useYAMNet = forceYAMNet || !isForeground }
    }
    /// Set from the scene phase; false while backgrounded or locked.
    var isForeground = true {
        didSet {
            // SoundAnalysis fails in the background; YAMNet on the CPU keeps classifying.
            pipeline?.useYAMNet = forceYAMNet || !isForeground
            guard oldValue != isForeground, isListening else { return }
            // Debug: how much audio and how many classifications arrived while away (background gate).
            probe.logDetection(isForeground
                ? "→ foreground: \(windowsSeen - windowsAtBackground) audio windows, \(classificationsSeen - classificationsAtBackground) classifications while away"
                : "→ background", inBackground: !isForeground, at: Date())
            windowsAtBackground = windowsSeen
            classificationsAtBackground = classificationsSeen
        }
    }
    @ObservationIgnored private var windowsSeen = 0
    @ObservationIgnored private var classificationsSeen = 0
    @ObservationIgnored private var windowsAtBackground = 0
    @ObservationIgnored private var classificationsAtBackground = 0
    var probe = ProbeState()
    /// Extra lines for the status banner.
    var notes: [String] { [classifierWarning, notificationsNote, liveActivityNote].compactMap { $0 } }
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
    @ObservationIgnored private let notifier = UrgentNotifier()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private var pipeline: AudioPipeline?
    @ObservationIgnored private var sourceLevels = SourceLevels(levels: [:])
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.calibrationKey),
           let saved = try? JSONDecoder().decode(FOAAxisCalibration.self, from: data) {
            calibration = saved
        } else {
            calibration = .initialGuess
        }
        do {
            let resources = try ClassificationResources.bundled()
            sourceLevels = resources.sourceLevels
            let motion = motion
            let pipeline = try AudioPipeline(resources: resources) { motion.deviceToWorld() }
            pipeline.calibration = calibration
            pipeline.onWindow = { [weak self] summary in Task { @MainActor in self?.apply(summary) } }
            pipeline.onTracker = { [weak self] output in Task { @MainActor in self?.apply(output) } }
            pipeline.onError = { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.classifierWarning = message
                    self.probe.logDetection("ERROR \(message)", inBackground: !self.isForeground, at: Date())
                }
            }
            pipeline.onNote = { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    self.probe.logDetection(note, inBackground: !self.isForeground, at: Date())
                }
            }
            pipeline.onDebugLine = { [weak self] line in
                Task { @MainActor in
                    guard let self else { return }
                    self.probe.appendSession(line, forward: self.forwardBearing)
                }
            }
            capture.onChunk = { chunk in pipeline.ingest(chunk) }
            self.pipeline = pipeline
        } catch {
            status = .error("Couldn't load the sound tables: \(error.localizedDescription)")
        }
        capture.onFormat = { [weak self] format in Task { @MainActor in self?.probe.format = format } }
        motion.onUpdate = { [weak self] bearing in self?.forwardBearing = bearing }
        liveActivity.onProblem = { [weak self] message in self?.liveActivityNote = message }
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
        notificationsNote = await notifier.requestAuthorization()
            ? nil : "Notifications are off: urgent sounds will only show on the lock-screen bar."
        pipeline?.reset()
        haptics.reset()
        notifier.reset()
        announced = []
        motion.start()
        capture.start()
        isListening = true
        listeningSince = Date()
        liveActivity.start()
        if !capture.foaEnabled {
            status = .directionUnavailable("this device can't capture spatial (FOA) audio. Sounds are still identified.")
        } else if !motion.isAvailable {
            status = .error("Motion sensors unavailable: the radar won't stay anchored as you turn.")
        } else {
            status = .listening
        }
    }

    func stop() {
        notifier.clear()
        liveActivity.stop()
        capture.stop()
        motion.stop()
        isListening = false
        listeningSince = nil
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

    func exportSessionLog() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("echo-session-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try probe.sessionLog().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func apply(_ summary: WindowSummary) {
        windowsSeen += 1
        probe.ingest(summary, calibration: calibration, now: Date())
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        let displays = output.events.map { EventDisplay($0, sourceLevels: sourceLevels) }.sorted { $0.score > $1.score }
        events = displays
        classificationsSeen += 1
        for e in output.newEvents { probe.logDetection(e.group, inBackground: !isForeground, at: Date()) }
        if isForeground {
            let refreshed = Set(output.events.filter { $0.lastSeen == output.now }.map(\.group))
            for d in displays where refreshed.contains(d.group) {
                haptics.alert(group: d.group, score: d.score, now: output.now)
            }
        }
        announceUrgent(displays)
        notifier.consider(displays, forward: forwardBearing, now: output.now, isForeground: isForeground)
        liveActivity.show(displays.first, forward: forwardBearing, paused: false)
    }

    /// VoiceOver announces each event once, when it first reaches Urgent.
    private func announceUrgent(_ displays: [EventDisplay]) {
        announced.formIntersection(displays.map(\.group))
        for d in displays where d.band == .urgent && !announced.contains(d.group) {
            announced.insert(d.group)
            AccessibilityNotification.Announcement("\(d.group), urgent, \(d.directionPhrase(forward: forwardBearing))").post()
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                self.status = .interrupted
                self.liveActivity.show(self.events.first, forward: self.forwardBearing, paused: true)
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                self.status = .listening
                self.liveActivity.show(self.events.first, forward: self.forwardBearing, paused: false)
            }
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
