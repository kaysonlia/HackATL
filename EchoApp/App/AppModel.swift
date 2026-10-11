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
    /// Room background level (approximate dB SPL); nil when not listening.
    var ambientDB: Double?
    /// Where the background noise comes from: weight per 5° world bin (max 1).
    var ambientProfile: [Double] = []
    /// Sudden sounds: Unclassified arrows, or the sound they turned into.
    var markers: [MarkerDisplay] = []
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
    var notes: [String] {
        let loudRoom = (ambientDB ?? 0) >= 80 ? "Very loud room: some sounds may be missed." : nil
        return [classifierWarning, notificationsNote, liveActivityNote, loudRoom].compactMap { $0 }
    }
    var calibration: FOAAxisCalibration {
        didSet {
            pipeline?.calibration = effectiveCalibration
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
    @ObservationIgnored private var baseSourceLevels = SourceLevels(levels: [:])
    private static let demoModeKey = "demoMode"
    /// Assume sounds come from a speaker (lower typical loudness) so played clips show real-world urgency.
    var demoMode = UserDefaults.standard.bool(forKey: AppModel.demoModeKey) {
        didSet { UserDefaults.standard.set(demoMode, forKey: Self.demoModeKey) }
    }
    private var sourceLevels: SourceLevels { demoMode ? baseSourceLevels.adjusted(by: -45) : baseSourceLevels }
    private static let optionalGroupsKey = "enabledOptionalGroups"
    /// Groups hidden by default that Settings can turn on.
    private(set) var optionalGroups: [String] = []
    /// Optional groups the user turned on; persisted.
    var enabledOptionalGroups: Set<String> = Set(UserDefaults.standard.stringArray(forKey: AppModel.optionalGroupsKey) ?? []) {
        didSet {
            pipeline?.enabledOptionalGroups = enabledOptionalGroups
            UserDefaults.standard.set(enabledOptionalGroups.sorted(), forKey: Self.optionalGroupsKey)
        }
    }
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
            baseSourceLevels = resources.sourceLevels
            optionalGroups = resources.visibility.optional
            let motion = motion
            let pipeline = try AudioPipeline(resources: resources) { motion.deviceToWorld() }
            pipeline.calibration = effectiveCalibration
            pipeline.enabledOptionalGroups = enabledOptionalGroups
            pipeline.onWindow = { [weak self] summary in Task { @MainActor in self?.apply(summary) } }
            pipeline.onTracker = { [weak self] output in Task { @MainActor in self?.apply(output) } }
            pipeline.onScene = { [weak self] scene in Task { @MainActor in self?.apply(scene) } }
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
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observers.append(NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let o = UIDevice.current.orientation
                if o.isPortrait || o.isLandscape { self.lastUpright = o }
                if self.isListening {
                    self.orientationCompensation.observe(Self.upright(o))
                    self.pipeline?.calibration = self.effectiveCalibration
                }
                self.probe.logDetection("orientation → \(Self.name(o)) (last upright \(Self.name(self.lastUpright)))", inBackground: !self.isForeground, at: Date())
            }
        })
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
        probe.logDetection("start: \(capture.connectionNote), orientation \(Self.name(UIDevice.current.orientation)), last upright \(Self.name(lastUpright))",
                           inBackground: !isForeground, at: Date())
        orientationCompensation.reset()
        pipeline?.calibration = effectiveCalibration
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
        ambientDB = nil
        ambientProfile = []
        markers = []
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

    private func apply(_ scene: SceneUpdate) {
        guard isListening else { return }
        ambientDB = scene.ambientDB
        ambientProfile = scene.ambientProfile
        markers = MarkerDisplay.from(scene.markers, events: events)
    }

    private func apply(_ summary: WindowSummary) {
        windowsSeen += 1
        probe.ingest(summary, calibration: effectiveCalibration, now: Date())
        // Debug: once a second, the raw (device-frame) bearing with the phone's orientation.
        if windowsSeen % 2 == 0, summary.totalEnergy > 0 {
            ProbeState.appendToDiagnosticsFile(String(format: "%@  dial %@ diff %.2f rmsW %.4f orient %@ lastUpright %@ corr %.0f",
                Date().formatted(date: .omitted, time: .standard), probe.rawBearing.map { String(format: "%3.0f°", $0) } ?? "–",
                summary.diffuseness, summary.channelRMS.first ?? 0, Self.name(UIDevice.current.orientation), Self.name(lastUpright),
                orientationCompensation.correction))
        }
    }

    @ObservationIgnored private var lastUpright: UIDeviceOrientation = .unknown
    /// iOS rotates FOA capture to the phone's upright orientation (tracked from Start); undo it.
    @ObservationIgnored private var orientationCompensation = FOAOrientationCompensation()

    /// The fitted (portrait-frame) calibration turned to match the orientation iOS applies to FOA.
    private var effectiveCalibration: FOAAxisCalibration {
        calibration.rotated(clockwise: orientationCompensation.correction)
    }

    static func upright(_ o: UIDeviceOrientation) -> UprightOrientation? {
        switch o {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: nil
        }
    }

    static func name(_ o: UIDeviceOrientation) -> String {
        switch o {
        case .portrait: "portrait"
        case .portraitUpsideDown: "upsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        case .faceUp: "faceUp"
        case .faceDown: "faceDown"
        default: "unknown"
        }
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        let displays = output.events.map { EventDisplay($0, sourceLevels: sourceLevels) }.sorted { $0.score > $1.score }
        events = displays
        if output.directionOnly { return }
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
