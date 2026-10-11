# SoundSight iOS: Urgency Gradient, Background Listening and Lock-Screen Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four fixed urgency tiers with a continuous urgency score shown as a green → yellow → red gradient. The score combines classification, loudness and approximate distance. Put the most urgent sound's class, volume and distance under the radar, keep listening in the background, and show a Live Activity bar on the lock screen and in the Dynamic Island. Send one urgent notification that never stacks.

**Architecture:**
- **SoundSightCore (pure, tested):** the score, bands and gradient hue, the per-group source levels, the tracker's level smoothing, score-based haptics, the notification and Live Activity rate limits, and the radar sweep and halo rules. All of these are tested with `swift test`.
- **App (thin wiring):** background audio, the SwiftUI focus card and radar changes, a `UserNotifications` wrapper and an `ActivityKit` controller.
- **Widget extension (`SoundSightLiveActivity`):** renders the bar. It shares `SoundSightShared/`, which holds the attributes and gradient color, with the app.

**Tech Stack:** Swift 6.2 / Xcode 26.2, iOS 26.0, SwiftUI + Observation, AVFoundation, ActivityKit + WidgetKit, UserNotifications, Core Haptics, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-10-soundsight-ios-urgency-background-design.md`. It builds on the base spec `docs/superpowers/specs/2026-10-10-soundsight-ios-foa-design.md`.

**Starts after:** plan `docs/superpowers/plans/2026-10-10-soundsight-ios-foa.md` is finished (Tasks 1–15, with the radar of Task 14 committed). The code below replaces that plan's `AppModel`, `RadarView`, `MainView`, `EventListView` and `UrgencyStyle`.

**Deliberate refinements of the spec:**
- **`ContentState`:**
  - It carries a pre-formatted `detail` string ("84 dB · ~3 m") instead of separate `levelDB`/`distanceM` fields. The display is the same, and the widget stays free of logic.
  - It adds `paused`, for spec §7's "Live Activity shows Paused".
- **Live Activity throttle:** it adds an **8 s keep-alive**, so the bar (`staleDate` = now + 10 s) never turns stale while listening in silence.
- **Clocks:**
  - The haptic gate and notification policy use the capture timeline. That timeline restarts at 0 on every Start, so both are reset on Start.
  - The Live Activity throttle uses system uptime.
- **Notifications:** if the most urgent event is blocked by its own group cooldown, the next urgent event may notify. There is still only ever one notification, under one identifier.
- **Background check:** the "in-app event history" used by the background gate is a **Recent detections** list in the FOA probe. It marks each event `(background)` when detected while not in the foreground.
- **If the background gate fails** (no detections while locked), work stops and the result is reported. The spec §4 mono-`AVAudioEngine` fallback can't be verified in advance, so it gets designed against the observed failure.
- **Device checks:** the checks for Tasks 5–7 are batched into one session in Task 8.

## Global Constraints

- **Build settings:** iOS deployment target **26.0**; iPhone only; portrait; Swift language mode **6**. `SoundSightCore` must keep building and testing on **macOS 15**, so ActivityKit, UIKit and SwiftUI code never goes into `SoundSightCore`.
- **Dependencies:** no third-party dependencies.
- **Score:**

  | Constant | Value |
  |---|---|
  | dB offset | **+120** (dBFS → approximate dB SPL) |
  | Class weights | CRITICAL **1.0**, HIGH **0.75**, MEDIUM **0.5**, LOW **0.15** |
  | Closeness | 1 at ≤ **2 m**, 0 at ≥ **50 m** (log) |
  | Loudness | 0 at ≤ **40 dB**, 1 at ≥ **90 dB** |
  | Score u | **c · (0.35 + 0.65 · (0.6·p + 0.4·ℓ))** |
  | Distance | **10^((L_ref − L)/20)** clamped to **[0.5, 100] m** |

- **Bands:** **Urgent ≥ 0.75**, **Moderate ≥ 0.4**, otherwise **Low**. The gradient hue is **120°·(1 − u)**, with saturation 0.9 and brightness 0.95.
- **Haptics** (foreground only, **5 s** per-group cooldown):

  | Score | Haptic |
  |---|---|
  | u ≥ 0.75 | triple |
  | u ≥ 0.5 | double |
  | u ≥ 0.3 | single |

- **Notification:**
  - Identifier **`soundsight.urgent`** on every request.
  - Only when **not in the foreground** and **u ≥ 0.75**.
  - At most one every **10 s**; the same group only after **30 s**, unless its score rose by **≥ 0.15**.
  - Interruption level `.active`, default sound.
- **Live Activity updates:**
  - At least **1 s** apart.
  - Sent on a group or paused change, |Δu| ≥ **0.05**, |Δangle| ≥ **15°**, or |ΔdB| ≥ **3**, plus the 8 s keep-alive.
  - `staleDate` = now + **10 s**. Ended with `.immediate` on Stop.
  - Re-requested only when the system **ends** it, not when the user dismisses it.
- **Radar:**
  - Sweep: opacity 1 for the first **2 s** after Start, then linear to 0 at **3 s**.
  - Halo: only bins within **±15°** of the belief peak with p ≥ **50%** of the strongest bin.
- **Silence:** the group `Silence` never becomes an event.
- **Bundle IDs and signing:** bundle IDs are `com.hackatl.soundsight` and `com.hackatl.soundsight.liveactivity`. Both targets sign with the git-ignored `SoundSightApp/Config/Signing.xcconfig`; never commit a team ID.
- **Commits:** every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Branch:** `ios-foa-design`.

## Review Focus

1. **Stop, then Start again.** The capture timeline restarts at 0, so a haptic gate or notification policy carried over from the last session would mute every alert until the clock caught up. `HapticsManager.reset()` and `UrgentNotifier.reset()` on Start pin this (Tasks 5 and 6), and the Task 8 device check covers it.
2. **A sound classified before its first level is measured** (a classification with no joined DOA window). The score must fall back to c · 0.35 and the text must say "Measuring volume…" instead of crashing or showing 0 dB. Pinned in Task 2 (`distanceAndFactorsClamp` checks level 0 → 0.35).
3. **Several urgent sounds while locked.** Exactly one notification, never a pile. Pinned in Task 3 (`notificationGlobalGap`, `notificationGroupCooldownAndRise`) and the Task 8 device check.
4. **A belief peak near 0°/360°.** The halo must wrap and not lose half its bins. Pinned in Task 4 (`haloDropsWeakBinsAndEmptyBelief`: a uniform belief around 2.5° gives exactly 7 bins).
5. **The user swipes the bar away, or Live Activities are off in Settings.** No re-request loop, and a banner note. Covered by `LiveActivityController.ended` (only `.ended` re-requests) and the Task 8 device check.

## File Structure

```
HackATL/
├── project.yml                                   + UIBackgroundModes (T1), SoundSightShared (T5), extension target (T7)
├── .gitignore                                    + SoundSightLiveActivity/Info.plist (T7)
├── SoundSightCore/
│   ├── Sources/SoundSightCore/
│   │   ├── Urgency/UrgencyScore.swift            score, band, hue, distance text (T2)
│   │   ├── Urgency/SourceLevels.swift            typical level per group (T2)
│   │   ├── Resources/source_levels.json          (T2)
│   │   ├── Classification/ClassificationResources.swift  + sourceLevels (T2)
│   │   ├── Fusion/EventTracker.swift             + levelDB EMA, ignores Silence (T3)
│   │   ├── Alerts/NotificationPolicy.swift       never-stacking notification rules (T3)
│   │   ├── Display/RadarSweep.swift              3 s sweep fade (T4)
│   │   ├── Display/Halo.swift                    tight halo bins (T4)
│   │   ├── Display/LiveActivityThrottle.swift    bar update rate limit (T4)
│   │   ├── Alerts/DirectionPhrase.swift          + short sector words (T4)
│   │   └── Alerts/HapticGate.swift               patterns by score (T5)
│   └── Tests/SoundSightCoreTests/
│       ├── UrgencyScoreTests.swift (T2)  EventTrackerLevelTests.swift (T3)
│       ├── NotificationPolicyTests.swift (T3)  DisplayTests.swift (T4)  AlertTests.swift (T5)
├── SoundSightShared/                                   compiled into app and extension
│   ├── UrgencyColor.swift                        Color.urgency(_:), UrgencyBar (T5)
│   └── SoundSightActivityAttributes.swift              Live Activity attributes (T7)
├── SoundSightApp/
│   ├── App/SoundSightApp.swift                       scene phase → isForeground (T1)
│   ├── App/AppModel.swift                        (T1, T5, T6, T7)
│   ├── App/EventDisplay.swift                    score, level, distance, phrases (T5)
│   ├── Capture/FOACaptureSession.swift           own audio session for background (T1)
│   ├── Capture/AudioPipeline.swift               per-window level → tracker (T5)
│   ├── Probe/ProbeState.swift, ProbeView.swift   Recent detections (T1)
│   ├── Haptics/HapticsManager.swift              by score, reset (T5)
│   ├── Alerts/UrgentNotifier.swift               (T6)
│   ├── Alerts/LiveActivityController.swift       (T7)
│   └── UI/RadarView.swift, FocusCard.swift, EventListView.swift, MainView.swift, StatusBanner.swift (T5)
└── SoundSightLiveActivity/SoundSightLiveActivityWidget.swift lock-screen banner + Dynamic Island (T7)
```

---

### Task 1: Background capture, gated on the device

**Files:**
- Modify (replace): `project.yml`, `SoundSightApp/Capture/FOACaptureSession.swift`, `SoundSightApp/Probe/ProbeState.swift`, `SoundSightApp/Probe/ProbeView.swift`, `SoundSightApp/App/AppModel.swift`, `SoundSightApp/App/SoundSightApp.swift`
- Create: `docs/superpowers/spikes/2026-10-10-background-gate/README.md`

**Interfaces:**
- Consumes: base plan's `FOACaptureSession`, `ProbeState`, `AppModel`, `TrackerOutput.newEvents`.
- Produces:
  - `AppModel.isForeground: Bool`, set from the scene phase.
  - `ProbeState.recentDetections: [String]` and `ProbeState.logDetection(_:inBackground:at:)`.
  - Background audio (`UIBackgroundModes: [audio]`), with the app owning the `AVAudioSession` (`.playAndRecord`, `[.mixWithOthers, .defaultToSpeaker]`).

App-layer task: verified by the iOS build and the on-device gate. This is the same ruling as base plan Task 5; there is no app test target.

- [ ] **Step 1: Write the files**

`project.yml` (replace):

```yaml
name: SoundSight
options:
  bundleIdPrefix: com.hackatl
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  SoundSightCore:
    path: SoundSightCore
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  SoundSight:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: SoundSightApp
        excludes:
          - "Config/**"
          - "Info.plist"
    dependencies:
      - package: SoundSightCore
    configFiles:
      Debug: SoundSightApp/Config/App.xcconfig
      Release: SoundSightApp/Config/App.xcconfig
    info:
      path: SoundSightApp/Info.plist
      properties:
        CFBundleDisplayName: SoundSight
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSMicrophoneUsageDescription: SoundSight listens to the sounds around you to identify them and show where they come from. Audio never leaves your iPhone.
        NSMotionUsageDescription: SoundSight uses motion sensors to keep sound directions fixed as you turn.
        UIBackgroundModes: [audio]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hackatl.soundsight
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
```

`SoundSightApp/Capture/FOACaptureSession.swift` (replace):

```swift
import AVFoundation

enum CaptureError: LocalizedError {
    case noMicrophone
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No built-in microphone was found."
        case .cannotAddInput: "The microphone input couldn't be added to the capture session."
        case .cannotAddOutput: "The audio output couldn't be added to the capture session."
        }
    }
}

/// Audio-only AVCaptureSession delivering 4-channel FOA buffers, or mono when FOA is unsupported (spec §3.1, §8).
final class FOACaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "soundsight.capture.session")
    private let bufferQueue = DispatchQueue(label: "soundsight.capture.buffers")
    private var configured = false
    /// False when the device can't capture FOA and the session fell back to mono.
    private(set) var foaEnabled = false

    /// Called on the buffer queue for every converted chunk.
    var onChunk: (@Sendable (FOAChunk) -> Void)?
    /// Called once, on the buffer queue, with the first buffer's format.
    var onFormat: (@Sendable (String) -> Void)?
    private var reportedFormat = false

    /// Builds the session once. Checks `canAdd…` first because AVFoundation raises an
    /// uncatchable NSInvalidArgumentException on commit for invalid configurations.
    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        let foa = input.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
        // Own the audio session so capture keeps running in the background (UIBackgroundModes: audio)
        // and other apps' audio keeps playing (urgency spec §4).
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)
        if foa { input.multichannelAudioMode = .firstOrderAmbisonics }
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)
        // FOA mode requires the 4-channel layout tag; any other mode requires the default tag.
        if foa { output.spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4 }
        output.setSampleBufferDelegate(self, queue: bufferQueue)
        foaEnabled = foa
        configured = true
    }

    func start() { sessionQueue.async { self.session.startRunning() } }
    func stop() { sessionQueue.async { self.session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !reportedFormat {
            reportedFormat = true
            onFormat?(FOABufferAdapter.describe(sampleBuffer))
        }
        if let chunk = FOABufferAdapter.chunk(from: sampleBuffer) { onChunk?(chunk) }
    }
}
```

`SoundSightApp/Probe/ProbeState.swift` (replace):

```swift
import SoundSightCore
import Foundation
import simd

/// Live readouts and calibration recording for the FOA probe (spec §6).
struct ProbeState {
    static let angles: [Double] = stride(from: 0.0, to: 360, by: 45).map { $0 }
    static let maxDiffuseness: Float = 0.9

    var format = "–"
    var channelRMS: [Float] = [0, 0, 0, 0]
    var rawBearing: Double?
    var rawElevation: Double?
    var diffuseness: Float = 1
    var selectedAngle: Double = 0
    var recordingUntil: Date?
    private(set) var samples: [CalibrationSample] = []
    private(set) var csvRows: [String] = []
    var fit: CalibrationFit?
    /// Newest first: "12:03:04  Siren  (background)". Lets the background gate be checked after unlocking.
    private(set) var recentDetections: [String] = []

    var isRecording: Bool { recordingUntil != nil }

    func count(at angle: Double) -> Int { samples.filter { $0.trueBearing == angle }.count }

    mutating func ingest(_ s: WindowSummary, calibration: FOAAxisCalibration, now: Date) {
        channelRMS = s.channelRMS
        diffuseness = s.diffuseness
        let device = calibration.toDevice(s.summedRaw)
        let length = simd_length(device)
        if length > 0 {
            rawBearing = Circular.bearing(device)
            rawElevation = asin(Double(device.z / length)) * 180 / .pi
        } else {
            rawBearing = nil
            rawElevation = nil
        }
        guard let until = recordingUntil else { return }
        if now >= until {
            recordingUntil = nil
            return
        }
        guard s.totalEnergy > 0, simd_length(s.summedRaw) > 0, s.diffuseness < Self.maxDiffuseness else { return }
        samples.append(CalibrationSample(trueBearing: selectedAngle, raw: s.summedRaw))
        csvRows.append([String(selectedAngle), String(s.summedRaw.x), String(s.summedRaw.y), String(s.summedRaw.z),
                        String(s.diffuseness), String(s.totalEnergy), String(now.timeIntervalSince1970)].joined(separator: ","))
    }

    mutating func logDetection(_ group: String, inBackground: Bool, at date: Date) {
        let time = date.formatted(date: .omitted, time: .standard)
        recentDetections.insert("\(time)  \(group)\(inBackground ? "  (background)" : "")", at: 0)
        if recentDetections.count > 20 { recentDetections.removeLast() }
    }

    mutating func clearSamples() {
        samples = []
        csvRows = []
        fit = nil
    }

    func csv() -> String {
        (["true_bearing,raw_x,raw_y,raw_z,diffuseness,energy,unix_time"] + csvRows).joined(separator: "\n") + "\n"
    }
}
```

`SoundSightApp/Probe/ProbeView.swift` (replace):

```swift
import SoundSightCore
import SwiftUI

/// Debug screen for the step 1 FOA gate (spec §6).
struct ProbeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Stream") {
                    LabeledContent("Format", value: model.probe.format)
                    ForEach(0..<4, id: \.self) { i in
                        LabeledContent("RMS \(["W", "X", "Y", "Z"][i])", value: String(format: "%.4f", model.probe.channelRMS[i]))
                    }
                    LabeledContent("Diffuseness", value: String(format: "%.2f", model.probe.diffuseness))
                }
                Section("Direction (device frame, current calibration)") {
                    ProbeDial(bearing: model.probe.rawBearing).frame(height: 180)
                    LabeledContent("Bearing", value: model.probe.rawBearing.map { String(format: "%.0f°", $0) } ?? "–")
                    LabeledContent("Elevation", value: model.probe.rawElevation.map { String(format: "%.0f°", $0) } ?? "–")
                }
                Section("Calibration (phone flat, top edge = 0°)") {
                    Picker("True direction", selection: $model.probe.selectedAngle) {
                        ForEach(ProbeState.angles, id: \.self) { Text("\(Int($0))°").tag($0) }
                    }
                    Button(model.probe.isRecording ? "Recording…" : "Record 10 s at \(Int(model.probe.selectedAngle))°") {
                        model.recordProbe(seconds: 10)
                    }
                    .disabled(model.probe.isRecording || !model.isListening)
                    ForEach(ProbeState.angles, id: \.self) { a in
                        LabeledContent("\(Int(a))°", value: "\(model.probe.count(at: a)) windows")
                    }
                    Button("Fit calibration") { model.fitProbe() }
                        .disabled(model.probe.samples.isEmpty)
                    if let fit = model.probe.fit {
                        LabeledContent("Median error", value: String(format: "%.1f°", fit.medianAbsError))
                        LabeledContent("Front/back correct", value: String(format: "%.0f%%", fit.frontBackHitRate * 100))
                        LabeledContent("Mean signed error", value: String(format: "%.1f°", fit.meanSignedError))
                        Text(fit.passesGate ? "GATE PASSED" : "GATE FAILED")
                            .bold()
                            .foregroundStyle(fit.passesGate ? .green : .red)
                        Button("Use this calibration") { model.calibration = fit.calibration }
                    }
                    LabeledContent("Current", value: model.calibration.rows.map { $0.map { String(Int($0)) }.joined(separator: " ") }.joined(separator: " | "))
                    Button("Reset to initial guess") { model.calibration = .initialGuess }
                    Button("Clear samples", role: .destructive) { model.probe.clearSamples() }
                }
                Section("Recent detections") {
                    if model.probe.recentDetections.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                    ForEach(Array(model.probe.recentDetections.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
                }
                Section("Export") {
                    Button("Prepare CSV") { csvURL = model.exportProbeCSV() }
                    if let csvURL { ShareLink("Share CSV", item: csvURL) }
                }
            }
            .navigationTitle("FOA Probe")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Compass-style dial: 0° at the top (phone's top edge), clockwise.
struct ProbeDial: View {
    let bearing: Double?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 8
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.secondary), lineWidth: 1)
            for a in stride(from: 0.0, to: 360, by: 45) {
                var tick = Path()
                tick.move(to: radarPoint(c, r * 0.9, a))
                tick.addLine(to: radarPoint(c, r, a))
                ctx.stroke(tick, with: .color(.secondary), lineWidth: 1)
            }
            guard let bearing else { return }
            var needle = Path()
            needle.move(to: c)
            needle.addLine(to: radarPoint(c, r * 0.85, bearing))
            ctx.stroke(needle, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .accessibilityLabel(bearing.map { "Direction \(Int($0)) degrees" } ?? "No direction")
    }
}
```

`SoundSightApp/App/AppModel.swift` (replace):

```swift
import AVFoundation
import SoundSightCore
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
    /// Set from the scene phase; false while backgrounded or locked.
    var isForeground = true
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
        for e in output.newEvents { probe.logDetection(e.group, inBackground: !isForeground, at: Date()) }
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
```

`SoundSightApp/App/SoundSightApp.swift` (replace):

```swift
import SwiftUI

@main
struct SoundSightApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { MainView(model: model) }
            .onChange(of: scenePhase, initial: true) { _, phase in model.isForeground = phase == .active }
    }
}
```

- [ ] **Step 2: Build and run the core tests**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet && swift test --package-path SoundSightCore`
Expected: no `error:` or warnings; `Test run with 65 tests in 13 suites passed`.

- [ ] **Step 3: GATE — background listening on the iPhone (human)**

Ask the human to Run on the phone, then:
1. Start music in another app, open SoundSight and tap **Start Listening**. Expected: the music keeps playing.
2. Long-press the "SoundSight" title to open the probe. Expected: the **Format** line still reads `48000 Hz · 4 ch · …`, the same as in the FOA gate. Close the probe.
3. Lock the phone and wait 60 s. Play a siren clip for about 5 s from 1–2 m away, wait 10 s, then unlock.
4. Open the probe. Expected: **Recent detections** lists `Siren` (or another alarm group) marked `(background)`, with a time from while the phone was locked.

Outcomes:
- **PASS** (steps 2 and 4 hold): continue.
- **Format line is no longer 4 ch:** the app-owned audio session broke FOA. Delete these four lines from `FOACaptureSession.configure()`:
  ```swift
  let audio = AVAudioSession.sharedInstance()
  try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
  try audio.setActive(true)
  session.automaticallyConfiguresApplicationAudioSession = false
  ```
  Then rebuild and repeat steps 2–4. Ledger the ruling: other apps' audio will pause while listening.
- **No `(background)` detections:** stop. Report to the human and propose either foreground-only listening or a background design built on what was observed (spec §4 fallback). Do not continue.

- [ ] **Step 4: Record the gate**

Write `docs/superpowers/spikes/2026-10-10-background-gate/README.md` with: the date, the iOS version, the Format line before and after locking, whether music kept playing, the Recent detections lines, and PASS or FAIL.

- [ ] **Step 5: Commit**

```bash
git add project.yml SoundSightApp docs/superpowers/spikes/2026-10-10-background-gate
git commit -m "Keep listening in the background and log detections in the probe" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Urgency score, bands, gradient hue and source levels

**Files:**
- Create: `SoundSightCore/Sources/SoundSightCore/Urgency/UrgencyScore.swift`, `SoundSightCore/Sources/SoundSightCore/Urgency/SourceLevels.swift`, `SoundSightCore/Sources/SoundSightCore/Resources/source_levels.json`
- Modify (replace): `SoundSightCore/Sources/SoundSightCore/Classification/ClassificationResources.swift`
- Test: `SoundSightCore/Tests/SoundSightCoreTests/UrgencyScoreTests.swift`

**Interfaces:**
- Consumes: `Urgency`, `UrgencyMap`, `ResourceError`, `ClassificationResources` (base plan Task 8).
- Produces:
  - `enum UrgencyScore` with:
    - `dbOffset = 120` and `urgentThreshold = 0.75`.
    - `classWeight(_:)`, `level(rms:)`, `distance(level:sourceLevel:)`, `closeness(distance:)`, `loudness(level:)`.
    - `score(urgency:level:sourceLevel:) -> Double`.
    - `hueDegrees(_:) -> Double` and `formatDistance(_:) -> String`.
  - `enum UrgencyBand: Equatable { low, moderate, urgent; init(score:); var label: String }`.
  - `struct SourceLevels { let levels: [String: Double]; init(levels:defaultLevel:); init(json:defaultLevel:) throws; func level(for:) -> Double }`.
  - `ClassificationResources.sourceLevels: SourceLevels`.

- [ ] **Step 1: Write the failing tests**

`SoundSightCore/Tests/SoundSightCoreTests/UrgencyScoreTests.swift`:

```swift
import Foundation
import Testing
@testable import SoundSightCore

struct UrgencyScoreTests {
    func score(_ u: Urgency, _ sourceLevel: Double, _ level: Double) -> Double {
        UrgencyScore.score(urgency: u, level: level, sourceLevel: sourceLevel)
    }

    @Test func referenceCases() {
        #expect(abs(score(.critical, 120, 114) - 1.0) < 0.005)   // siren at 2 m
        #expect(abs(score(.critical, 120, 100) - 0.805) < 0.005) // siren at 10 m
        #expect(abs(score(.critical, 110, 70) - 0.506) < 0.005)  // car alarm at 100 m
        #expect(abs(score(.medium, 90, 80) - 0.446) < 0.005)     // dog at 3 m
        #expect(score(.low, 60, 130) <= 0.15 + 1e-12)            // speech can never leave green
    }

    @Test func levelFromRMS() {
        #expect(UrgencyScore.level(rms: 1) == 120)
        #expect(abs(UrgencyScore.level(rms: 0.01) - 80) < 1e-9)
        #expect(UrgencyScore.level(rms: 0) == 0)
        #expect(UrgencyScore.level(rms: 1e-9) == 0)
    }

    @Test func distanceAndFactorsClamp() {
        #expect(UrgencyScore.distance(level: 200, sourceLevel: 60) == 0.5)
        #expect(UrgencyScore.distance(level: 0, sourceLevel: 120) == 100)
        #expect(abs(UrgencyScore.distance(level: 70, sourceLevel: 90) - 10) < 1e-9)
        #expect(UrgencyScore.closeness(distance: 1) == 1)
        #expect(abs(UrgencyScore.closeness(distance: 50)) < 1e-12)
        #expect(UrgencyScore.closeness(distance: 100) == 0)
        #expect(UrgencyScore.loudness(level: 30) == 0)
        #expect(UrgencyScore.loudness(level: 100) == 1)
        // RMS 0 → level 0 → farthest and quietest: only the 0.35 floor remains.
        #expect(abs(score(.critical, 120, 0) - 0.35) < 1e-12)
    }

    @Test func bandsAndHue() {
        #expect(UrgencyBand(score: 0.75) == .urgent)
        #expect(UrgencyBand(score: 0.7499) == .moderate)
        #expect(UrgencyBand(score: 0.4) == .moderate)
        #expect(UrgencyBand(score: 0.3999) == .low)
        #expect(UrgencyBand.urgent.label == "Urgent")
        #expect(UrgencyScore.hueDegrees(0) == 120)
        #expect(UrgencyScore.hueDegrees(0.5) == 60)
        #expect(UrgencyScore.hueDegrees(1) == 0)
        #expect(UrgencyScore.hueDegrees(1.3) == 0)
    }

    @Test func distanceText() {
        #expect(UrgencyScore.formatDistance(0.5) == "< 1 m")
        #expect(UrgencyScore.formatDistance(3.2) == "~3 m")
        #expect(UrgencyScore.formatDistance(9.6) == "~10 m")
        #expect(UrgencyScore.formatDistance(17) == "~20 m")
        #expect(UrgencyScore.formatDistance(100) == "~100 m")
    }

    @Test func sourceLevelsCoverEveryGroup() throws {
        let r = try ClassificationResources.bundled()
        #expect(r.urgency.groups.allSatisfy { r.sourceLevels.levels[$0] != nil })
        #expect(r.sourceLevels.level(for: "Siren") == 120)
        #expect(r.sourceLevels.level(for: "Unknown") == 70)
        #expect(throws: (any Error).self) { try SourceLevels(json: Data("{\"Siren\": 120}".utf8)) }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path SoundSightCore`
Expected: build FAILS with `cannot find 'UrgencyScore' in scope`.

- [ ] **Step 3: Implement**

`SoundSightCore/Sources/SoundSightCore/Urgency/UrgencyScore.swift`:

```swift
import Foundation

/// Continuous urgency in [0, 1] from class tier, loudness and approximate distance (urgency spec §2).
public enum UrgencyScore {
    /// Added to dBFS to approximate dB SPL. The iPhone mic is uncalibrated; refine in the tuning pass.
    public static let dbOffset = 120.0
    /// Scores at or above this are "Urgent": notification, VoiceOver announcement, triple haptic.
    public static let urgentThreshold = 0.75

    public static func classWeight(_ urgency: Urgency) -> Double {
        switch urgency {
        case .critical: 1.0
        case .high: 0.75
        case .medium: 0.5
        case .low: 0.15
        }
    }

    /// Omni-channel RMS → approximate dB SPL, floored at 0 (silence).
    public static func level(rms: Double) -> Double {
        rms > 0 ? max(0, 20 * log10(rms) + dbOffset) : 0
    }

    /// Metres at which a source with typical 1 m level `sourceLevel` is heard at `level`, clamped to [0.5, 100].
    public static func distance(level: Double, sourceLevel: Double) -> Double {
        min(100, max(0.5, pow(10, (sourceLevel - level) / 20)))
    }

    /// 1 at ≤ 2 m, 0 at ≥ 50 m, log-linear between.
    public static func closeness(distance: Double) -> Double {
        clamp(1 - log10(distance / 2) / log10(25))
    }

    /// 0 at ≤ 40 dB, 1 at ≥ 90 dB.
    public static func loudness(level: Double) -> Double {
        clamp((level - 40) / 50)
    }

    /// u = c · (0.35 + 0.65 · (0.6·closeness + 0.4·loudness)).
    public static func score(urgency: Urgency, level: Double, sourceLevel: Double) -> Double {
        let p = closeness(distance: distance(level: level, sourceLevel: sourceLevel))
        return classWeight(urgency) * (0.35 + 0.65 * (0.6 * p + 0.4 * loudness(level: level)))
    }

    /// Gradient hue in degrees: 120 (green) at 0, 60 (yellow) at 0.5, 0 (red) at 1.
    public static func hueDegrees(_ score: Double) -> Double {
        120 * (1 - clamp(score))
    }

    /// "< 1 m", "~3 m", "~20 m", "~100 m": one significant figure.
    public static func formatDistance(_ meters: Double) -> String {
        guard meters >= 1 else { return "< 1 m" }
        let magnitude = pow(10, floor(log10(meters)))
        return "~\(Int((meters / magnitude).rounded() * magnitude)) m"
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// Words for score ranges, so meaning never depends on color alone.
public enum UrgencyBand: Sendable, Equatable {
    case low, moderate, urgent

    public init(score: Double) {
        self = score >= UrgencyScore.urgentThreshold ? .urgent : score >= 0.4 ? .moderate : .low
    }

    public var label: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .urgent: "Urgent"
        }
    }
}
```

`SoundSightCore/Sources/SoundSightCore/Urgency/SourceLevels.swift`:

```swift
import Foundation

/// Typical level (dB SPL at 1 m) of each group, for the distance estimate
/// (`source_levels.json`: `{"levels": {"Group": 120, ...}}`).
public struct SourceLevels: Sendable {
    public let levels: [String: Double]
    public let defaultLevel: Double

    public init(levels: [String: Double], defaultLevel: Double = 70) {
        self.levels = levels
        self.defaultLevel = defaultLevel
    }

    public init(json: Data, defaultLevel: Double = 70) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let map = root["levels"] as? [String: Double] else {
            throw ResourceError.malformed("source_levels.json needs a \"levels\" object of numbers")
        }
        self.init(levels: map, defaultLevel: defaultLevel)
    }

    public func level(for group: String) -> Double { levels[group] ?? defaultLevel }
}
```

`SoundSightCore/Sources/SoundSightCore/Resources/source_levels.json`:

```json
{
  "_comment": "Typical level in dB SPL at 1 m per sound group, for the urgency distance estimate. Starting values; tune on device.",
  "levels": {
    "Siren": 120, "Smoke/Fire Alarm": 95, "Vehicle Horn": 110, "Car Alarm": 110, "Gunshot/Explosion": 140,
    "Screaming": 100, "Glass Shatter": 100, "Skidding/Tire Squeal": 100, "Reversing Beeps": 97,
    "Slam/Bang/Crash": 100, "Shouting/Yelling": 88, "Motorcycle": 95,
    "Doorbell": 80, "Phone Ring": 75, "Alarm/Buzzer/Beep": 85, "Knock": 75, "Baby Cry": 90, "Crying": 75,
    "Dog": 90, "Vehicle": 85, "Aircraft": 130, "Train": 110, "Power Tool": 100,
    "Speech": 60, "Footsteps": 60, "Door": 75, "Water": 65, "Crowd/Applause/Laughter": 75, "Music": 75,
    "Appliance/Kitchen": 70, "Body Sounds": 50, "Cough/Sneeze": 70, "Fart": 55, "Whistle": 90,
    "Insect Buzz": 45, "Typing/Keyboard": 55, "Keys Jangling": 60, "Camera Shutter": 55, "TV/Radio": 65,
    "Ambient Nature": 55, "Silence": 0, "Other": 70
  }
}
```

`SoundSightCore/Sources/SoundSightCore/Classification/ClassificationResources.swift` (replace):

```swift
import Foundation

/// The bundled classification tables: Apple label map, per-group thresholds, urgency tiers and source levels.
public struct ClassificationResources: Sendable {
    public let mapper: LabelMapper
    public let thresholds: GroupThresholds
    public let urgency: UrgencyMap
    public let sourceLevels: SourceLevels

    public static func bundled() throws -> ClassificationResources {
        func load(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                throw ResourceError.missing("\(name).json")
            }
            return try Data(contentsOf: url)
        }
        return ClassificationResources(
            mapper: try LabelMapper(json: load("apple_to_group")),
            thresholds: try GroupThresholds(json: load("thresholds")),
            urgency: try UrgencyMap(json: load("urgency_map")),
            sourceLevels: try SourceLevels(json: load("source_levels")))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path SoundSightCore`
Expected: `Test run with 71 tests in 14 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add SoundSightCore
git commit -m "Add continuous urgency score from class, loudness and approximate distance" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Tracker loudness, Silence filter and notification policy

**Files:**
- Modify (replace): `SoundSightCore/Sources/SoundSightCore/Fusion/EventTracker.swift`
- Create: `SoundSightCore/Sources/SoundSightCore/Alerts/NotificationPolicy.swift`
- Test: `SoundSightCore/Tests/SoundSightCoreTests/EventTrackerLevelTests.swift`, `SoundSightCore/Tests/SoundSightCoreTests/NotificationPolicyTests.swift`

**Interfaces:**
- Consumes: `EventTracker`, `SoundEvent` (base plan Task 11); `UrgencyScore.urgentThreshold` (Task 2).
- Produces:
  - `SoundEvent.levelDB: Double?`.
  - `EventTracker.init(urgencyMap:evictAfter:emaAlpha:diffusenessCutoff:ignoredGroups: = ["Silence"])`.
  - `EventTracker.ingest(active:doa:now:levelDB: Double? = nil)`. Existing callers still compile.
  - `struct NotificationPolicy { static let identifier = "soundsight.urgent"; mutating func shouldNotify(group:score:now:isForeground:) -> Bool }`.

- [ ] **Step 1: Write the failing tests**

`SoundSightCore/Tests/SoundSightCoreTests/EventTrackerLevelTests.swift`:

```swift
import Testing
@testable import SoundSightCore

struct EventTrackerLevelTests {
    let urgency = UrgencyMap(tiers: ["Dog": .medium])

    @Test func levelIsSmoothedWhileActive() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0, levelDB: 80)
        #expect(t.events[0].levelDB == 80)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0.5, levelDB: 60)
        #expect(t.events[0].levelDB == 70)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 1, levelDB: nil)
        #expect(t.events[0].levelDB == 70)
        t.ingest(active: [:], doa: nil, now: 1.5, levelDB: 20)  // not active: level unchanged
        #expect(t.events[0].levelDB == 70)
    }

    @Test func levelStartsNilWhenUnknown() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Dog": 0.9], doa: nil, now: 0)
        #expect(t.events[0].levelDB == nil)
    }

    @Test func silenceNeverBecomesAnEvent() {
        let t = EventTracker(urgencyMap: urgency)
        let created = t.ingest(active: ["Silence": 0.99, "Dog": 0.9], doa: nil, now: 0)
        #expect(created.map(\.group) == ["Dog"])
        #expect(t.events.map(\.group) == ["Dog"])
    }
}
```

`SoundSightCore/Tests/SoundSightCoreTests/NotificationPolicyTests.swift`:

```swift
import Testing
@testable import SoundSightCore

struct NotificationPolicyTests {
    @Test func notificationsNeverInForegroundOrBelowUrgent() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: true),
            p.shouldNotify(group: "Siren", score: 0.74, now: 0, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.75, now: 0, isForeground: false),
        ]
        #expect(sent == [false, false, true])
        #expect(NotificationPolicy.identifier == "soundsight.urgent")
    }

    @Test func notificationGlobalGap() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.9, now: 0, isForeground: false),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 9.9, isForeground: false),
            p.shouldNotify(group: "Gunshot/Explosion", score: 1, now: 10, isForeground: false),
        ]
        #expect(sent == [true, false, true])
    }

    @Test func notificationGroupCooldownAndRise() {
        var p = NotificationPolicy()
        let sent = [
            p.shouldNotify(group: "Siren", score: 0.8, now: 0, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.85, now: 15, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.96, now: 15, isForeground: false),  // rose by ≥ 0.15
            p.shouldNotify(group: "Siren", score: 0.95, now: 44, isForeground: false),
            p.shouldNotify(group: "Siren", score: 0.8, now: 45, isForeground: false),   // 30 s after the last
        ]
        #expect(sent == [true, false, true, false, true])
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path SoundSightCore`
Expected: build FAILS with `extra argument 'levelDB' in call` and `cannot find 'NotificationPolicy' in scope`.

- [ ] **Step 3: Implement**

`SoundSightCore/Sources/SoundSightCore/Fusion/EventTracker.swift` (replace):

```swift
import Foundation

/// A sound group currently being tracked.
public struct SoundEvent: Sendable, Identifiable {
    public var id: String { group }
    public var group: String
    public var urgency: Urgency
    public var confidence: Double
    public var belief: AzimuthBelief
    public var firstSeen: Double
    public var lastSeen: Double
    /// Smoothed omni level (approximate dB SPL) over the windows where this group was active; nil until measured.
    public var levelDB: Double?
}

/// Rolling set of active sound events with per-label direction beliefs (spec §3.4).
public final class EventTracker {
    public let urgencyMap: UrgencyMap
    public let evictAfter: Double
    public let emaAlpha: Double
    public let diffusenessCutoff: Double
    /// Groups that never become events (urgency spec §2.5).
    public let ignoredGroups: Set<String>
    private var byGroup: [String: SoundEvent] = [:]

    public init(urgencyMap: UrgencyMap, evictAfter: Double = 3, emaAlpha: Double = 0.5, diffusenessCutoff: Double = 0.8,
                ignoredGroups: Set<String> = ["Silence"]) {
        self.urgencyMap = urgencyMap
        self.evictAfter = evictAfter
        self.emaAlpha = emaAlpha
        self.diffusenessCutoff = diffusenessCutoff
        self.ignoredGroups = ignoredGroups
    }

    /// Events sorted by urgency (highest first), then confidence.
    public var events: [SoundEvent] {
        byGroup.values.sorted { ($0.urgency, $0.confidence) > ($1.urgency, $1.confidence) }
    }

    /// Feeds one joined window. `active` holds groups at or above threshold; `now` is seconds
    /// on the capture timeline; `levelDB` is the window's omni level, if known.
    /// Returns events that were not being tracked before this window.
    @discardableResult
    public func ingest(active: [String: Double], doa: DOAFrame?, now: Double, levelDB: Double? = nil) -> [SoundEvent] {
        byGroup = byGroup.filter { now - $0.value.lastSeen <= evictAfter }
        let usable = doa.flatMap { $0.diffuseness <= diffusenessCutoff && !$0.peaks.isEmpty ? $0.peaks : nil }
        let active = active.filter { !ignoredGroups.contains($0.key) }
        var created: [SoundEvent] = []
        for (group, score) in active {
            if var e = byGroup[group] {
                e.confidence = emaAlpha * score + (1 - emaAlpha) * e.confidence
                e.lastSeen = now
                if let levelDB { e.levelDB = e.levelDB.map { emaAlpha * levelDB + (1 - emaAlpha) * $0 } ?? levelDB }
                byGroup[group] = e
            } else {
                let e = SoundEvent(group: group, urgency: urgencyMap.urgency(for: group), confidence: score,
                                   belief: AzimuthBelief(), firstSeen: now, lastSeen: now, levelDB: levelDB)
                byGroup[group] = e
                created.append(e)
            }
        }
        for group in byGroup.keys {
            if let peaks = usable, let score = active[group] {
                byGroup[group]!.belief.update(peaks: peaks, confidence: score)
            } else {
                byGroup[group]!.belief.decayTowardUniform()
            }
        }
        return created.map { byGroup[$0.group]! }
    }

    public func reset() { byGroup = [:] }
}
```

`SoundSightCore/Sources/SoundSightCore/Alerts/NotificationPolicy.swift`:

```swift
/// When to post the urgent notification (urgency spec §6). Every notification reuses one
/// identifier, so a new one replaces the last instead of stacking.
public struct NotificationPolicy: Sendable {
    public static let identifier = "soundsight.urgent"

    public var minGap = 10.0
    public var groupCooldown = 30.0
    public var scoreRise = 0.15
    private var lastAny: Double?
    private var lastByGroup: [String: (time: Double, score: Double)] = [:]

    public init() {}

    /// True if a notification should be posted now; records it when so.
    public mutating func shouldNotify(group: String, score: Double, now: Double, isForeground: Bool) -> Bool {
        guard !isForeground, score >= UrgencyScore.urgentThreshold else { return false }
        if let lastAny, now - lastAny < minGap { return false }
        if let last = lastByGroup[group], now - last.time < groupCooldown, score < last.score + scoreRise { return false }
        lastAny = now
        lastByGroup[group] = (now, score)
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path SoundSightCore`
Expected: `Test run with 77 tests in 16 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add SoundSightCore
git commit -m "Track per-event loudness, ignore Silence, add never-stacking notification policy" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Radar sweep, tight halo, Live Activity throttle, short directions

**Files:**
- Create: `SoundSightCore/Sources/SoundSightCore/Display/RadarSweep.swift`, `SoundSightCore/Sources/SoundSightCore/Display/Halo.swift`, `SoundSightCore/Sources/SoundSightCore/Display/LiveActivityThrottle.swift`
- Modify (replace): `SoundSightCore/Sources/SoundSightCore/Alerts/DirectionPhrase.swift`
- Test: `SoundSightCore/Tests/SoundSightCoreTests/DisplayTests.swift`

**Interfaces:**
- Consumes: `Circular`, `AzimuthBelief`, `DOAPeak` (base plan).
- Produces:
  - `enum RadarSweep { fadeStart = 2, duration = 3; static func opacity(elapsed:) -> Double }`.
  - `struct HaloBin: Equatable { index, strength }` and `enum Halo { static func bins(_:around:halfWidth: = 15, minFraction: = 0.5) -> [HaloBin] }`.
  - `struct LiveActivitySnapshot: Equatable { group: String?, score, levelDB, radarAngle: Double?, paused }`.
  - `struct LiveActivityThrottle { minInterval = 1, keepAlive = 8; mutating func shouldSend(_:now:) -> Bool }`.
  - `DirectionPhrase.short(radarAngle:) -> String`.

- [ ] **Step 1: Write the failing tests**

`SoundSightCore/Tests/SoundSightCoreTests/DisplayTests.swift`:

```swift
import Testing
@testable import SoundSightCore

struct DisplayTests {
    @Test func sweepFadesOutAfterThreeSeconds() {
        #expect(RadarSweep.opacity(elapsed: 0) == 1)
        #expect(RadarSweep.opacity(elapsed: 1.99) == 1)
        #expect(abs(RadarSweep.opacity(elapsed: 2.5) - 0.5) < 1e-12)
        #expect(RadarSweep.opacity(elapsed: 3) == 0)
        #expect(RadarSweep.opacity(elapsed: 60) == 0)
        #expect(RadarSweep.opacity(elapsed: -1) == 0)
    }

    @Test func haloStaysWithinFifteenDegreesOfPeak() {
        var b = AzimuthBelief()
        b.update(peaks: [DOAPeak(bearing: 93, weight: 1)], confidence: 0.3)  // broad belief
        let bins = Halo.bins(b.probabilities, around: b.peakBearing)
        #expect(!bins.isEmpty)
        #expect(bins.allSatisfy { abs(Circular.difference(AzimuthBelief.binCenter($0.index), b.peakBearing)) <= 15 })
        #expect(bins.contains { $0.strength == 1 })
        #expect(bins.allSatisfy { $0.strength >= 0.5 })
    }

    @Test func haloDropsWeakBinsAndEmptyBelief() {
        var p = [Double](repeating: 0.001, count: 72)
        p[18] = 1; p[19] = 0.6; p[17] = 0.4
        #expect(Halo.bins(p, around: 92.5).map(\.index) == [18, 19])
        #expect(Halo.bins([Double](repeating: 0, count: 72), around: 0).isEmpty)
        // Uniform belief: exactly the 7 bins whose centers lie within ±15° of the peak.
        #expect(Halo.bins([Double](repeating: 1.0 / 72, count: 72), around: 2.5).count == 7)
    }

    @Test func throttleSendsFirstThenRateLimits() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: "Siren", score: 0.9, levelDB: 80, radarAngle: 10)
        var b = a; b.group = "Dog"
        let sent = [t.shouldSend(a, now: 0), t.shouldSend(b, now: 0.5), t.shouldSend(b, now: 1)]
        #expect(sent == [true, false, true])
    }

    @Test func throttleIgnoresSmallChanges() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: "Siren", score: 0.9, levelDB: 80, radarAngle: 355)
        var small = a; small.score = 0.94; small.levelDB = 82; small.radarAngle = 5
        var angle = a; angle.radarAngle = 20
        var dB = a; dB.levelDB = 83
        var paused = a; paused.paused = true
        var lost = a; lost.radarAngle = nil
        let sent = [
            t.shouldSend(a, now: 0), t.shouldSend(small, now: 2), t.shouldSend(angle, now: 3),
            t.shouldSend(dB, now: 4), t.shouldSend(paused, now: 5), t.shouldSend(lost, now: 6),
        ]
        #expect(sent == [true, false, true, true, true, true])
    }

    @Test func throttleKeepAlive() {
        var t = LiveActivityThrottle()
        let a = LiveActivitySnapshot(group: nil, score: 0, levelDB: 0, radarAngle: nil)
        let sent = [t.shouldSend(a, now: 0), t.shouldSend(a, now: 7.9), t.shouldSend(a, now: 8)]
        #expect(sent == [true, false, true])
    }

    @Test func shortDirections() {
        #expect(DirectionPhrase.short(radarAngle: 0) == "front")
        #expect(DirectionPhrase.short(radarAngle: 350) == "front")
        #expect(DirectionPhrase.short(radarAngle: 45) == "front-right")
        #expect(DirectionPhrase.short(radarAngle: 100) == "right")
        #expect(DirectionPhrase.short(radarAngle: 200) == "back")
        #expect(DirectionPhrase.short(radarAngle: 280) == "left")
        #expect(DirectionPhrase.short(radarAngle: 330) == "front-left")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path SoundSightCore`
Expected: build FAILS with `cannot find 'RadarSweep' in scope` (and `Halo`, `LiveActivityThrottle`, `LiveActivitySnapshot`, `short`).

- [ ] **Step 3: Implement**

`SoundSightCore/Sources/SoundSightCore/Display/RadarSweep.swift`:

```swift
/// The radar sweep only plays right after Start Listening (urgency spec §3):
/// fully visible for 2 s, then fading linearly to nothing at 3 s.
public enum RadarSweep {
    public static let fadeStart = 2.0
    public static let duration = 3.0

    public static func opacity(elapsed: Double) -> Double {
        if elapsed < 0 || elapsed >= duration { return 0 }
        if elapsed < fadeStart { return 1 }
        return (duration - elapsed) / (duration - fadeStart)
    }
}
```

`SoundSightCore/Sources/SoundSightCore/Display/Halo.swift`:

```swift
/// One belief bin to draw in the radar halo.
public struct HaloBin: Sendable, Equatable {
    public var index: Int
    /// Probability relative to the strongest bin, in (0, 1].
    public var strength: Double

    public init(index: Int, strength: Double) {
        self.index = index
        self.strength = strength
    }
}

/// Keeps the colored halo tight (urgency spec §3): only bins within `halfWidth` degrees of the
/// belief peak whose probability is at least `minFraction` of the strongest bin.
public enum Halo {
    public static func bins(_ probabilities: [Double], around peak: Double,
                            halfWidth: Double = 15, minFraction: Double = 0.5) -> [HaloBin] {
        guard let top = probabilities.max(), top > 0 else { return [] }
        let width = 360 / Double(probabilities.count)
        return probabilities.indices.compactMap { i in
            let center = (Double(i) + 0.5) * width
            let p = probabilities[i]
            guard abs(Circular.difference(center, peak)) <= halfWidth, p >= minFraction * top else { return nil }
            return HaloBin(index: i, strength: p / top)
        }
    }
}
```

`SoundSightCore/Sources/SoundSightCore/Display/LiveActivityThrottle.swift`:

```swift
/// What the lock-screen bar shows, reduced to the fields that decide whether to update it.
public struct LiveActivitySnapshot: Sendable, Equatable {
    public var group: String?
    public var score: Double
    public var levelDB: Double
    public var radarAngle: Double?
    public var paused: Bool

    public init(group: String?, score: Double, levelDB: Double, radarAngle: Double?, paused: Bool = false) {
        self.group = group
        self.score = score
        self.levelDB = levelDB
        self.radarAngle = radarAngle
        self.paused = paused
    }
}

/// Rate-limits Live Activity updates (urgency spec §5): at least `minInterval` apart, and only
/// when something visible changed, plus a keep-alive so the bar never goes stale while listening.
public struct LiveActivityThrottle: Sendable {
    public var minInterval = 1.0
    public var keepAlive = 8.0
    private var last: LiveActivitySnapshot?
    private var lastTime = -Double.infinity

    public init() {}

    /// True if this snapshot should be sent now; records it when so.
    public mutating func shouldSend(_ s: LiveActivitySnapshot, now: Double) -> Bool {
        if let last {
            guard now - lastTime >= minInterval else { return false }
            guard Self.differs(s, last) || now - lastTime >= keepAlive else { return false }
        }
        last = s
        lastTime = now
        return true
    }

    static func differs(_ a: LiveActivitySnapshot, _ b: LiveActivitySnapshot) -> Bool {
        if a.group != b.group || a.paused != b.paused { return true }
        if abs(a.score - b.score) >= 0.05 || abs(a.levelDB - b.levelDB) >= 3 { return true }
        switch (a.radarAngle, b.radarAngle) {
        case (nil, nil): return false
        case let (x?, y?): return abs(Circular.difference(x, y)) >= 15
        default: return true
        }
    }
}
```

`SoundSightCore/Sources/SoundSightCore/Alerts/DirectionPhrase.swift` (replace):

```swift
/// Spoken description of a radar angle for VoiceOver (spec §3.6), e.g. "behind you to the right (4 o'clock)".
public enum DirectionPhrase {
    public static func clockHour(radarAngle: Double) -> Int {
        let h = Int((Circular.wrap360(radarAngle) / 30).rounded()) % 12
        return h == 0 ? 12 : h
    }

    public static func describe(radarAngle: Double) -> String {
        let hour = clockHour(radarAngle: radarAngle)
        let phrase = switch hour {
        case 12: "in front of you"
        case 1, 2: "ahead to your right"
        case 3: "to your right"
        case 4, 5: "behind you to the right"
        case 6: "behind you"
        case 7, 8: "behind you to the left"
        case 9: "to your left"
        default: "ahead to your left"
        }
        return "\(phrase) (\(hour) o'clock)"
    }

    /// Short sector word for list rows: "front", "front-right", "right", … (45° sectors).
    public static func short(radarAngle: Double) -> String {
        let words = ["front", "front-right", "right", "back-right", "back", "back-left", "left", "front-left"]
        return words[Int((Circular.wrap360(radarAngle) + 22.5) / 45) % 8]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path SoundSightCore`
Expected: `Test run with 84 tests in 17 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add SoundSightCore
git commit -m "Add radar sweep fade, tight halo selection, Live Activity throttle and short directions" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Gradient GUI, focus card and score-based haptics

**Files:**
- Modify (replace): `SoundSightCore/Sources/SoundSightCore/Alerts/HapticGate.swift`, `SoundSightCore/Tests/SoundSightCoreTests/AlertTests.swift`
- Create: `SoundSightShared/UrgencyColor.swift`, `SoundSightApp/App/EventDisplay.swift`, `SoundSightApp/UI/FocusCard.swift`
- Modify (replace): `project.yml`, `SoundSightApp/App/AppModel.swift`, `SoundSightApp/Capture/AudioPipeline.swift`, `SoundSightApp/Haptics/HapticsManager.swift`, `SoundSightApp/UI/RadarView.swift`, `SoundSightApp/UI/EventListView.swift`, `SoundSightApp/UI/MainView.swift`, `SoundSightApp/UI/StatusBanner.swift`
- Delete: `SoundSightApp/UI/UrgencyStyle.swift`. The gradient replaces `Urgency.color`/`label`.

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - **SoundSightCore:**
    - `enum HapticPattern { single, double, triple; init?(score:) }`.
    - `HapticGate.shouldFire(group:score:now:) -> HapticPattern?`. It replaces `shouldFire(group:urgency:now:)`.
  - **Shared:** `Color.urgency(_ score: Double) -> Color` and `UrgencyBar(score: Double?)`, in `SoundSightShared`.
  - **EventDisplay:**
    - Fields `score`, `band`, `levelDB`, `distance`, `peakBearing` and `levelText: String?`.
    - Methods `radarAngle(forward:)`, `directionPhrase(forward:)` and `shortDirection(forward:)`.
    - `init(_:sourceLevels:)`.
  - **AppModel:**
    - `events` sorted by score.
    - `listeningSince: Date?` and `notes: [String]`.
  - **Views:**
    - `StatusBanner(status:notes:)`.
    - `RadarView(events:forward:listeningSince:)`.
    - `FocusCard(event:forward:isListening:)`.
  - **`HapticsManager`:** `alert(group:score:now:)` and `reset()`.

- [ ] **Step 1: Write the failing test (SoundSightCore)**

`SoundSightCore/Tests/SoundSightCoreTests/AlertTests.swift` (replace):

```swift
import Testing
@testable import SoundSightCore

struct AlertTests {
    @Test func hapticPatternsFollowScore() {
        #expect(HapticPattern(score: 0.75) == .triple)
        #expect(HapticPattern(score: 0.6) == .double)
        #expect(HapticPattern(score: 0.3) == .single)
        #expect(HapticPattern(score: 0.29) == nil)
    }

    @Test func hapticGateCooldown() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Speech", score: 0.1, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 0),
            g.shouldFire(group: "Siren", score: 0.9, now: 4.9),
            g.shouldFire(group: "Dog", score: 0.45, now: 4.9),
            g.shouldFire(group: "Siren", score: 0.6, now: 5),
        ]
        #expect(fired == [nil, .triple, nil, .single, .double])
    }

    @Test func directionPhrases() {
        #expect(DirectionPhrase.describe(radarAngle: 0) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 120) == "behind you to the right (4 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 270) == "to your left (9 o'clock)")
        #expect(DirectionPhrase.describe(radarAngle: 350) == "in front of you (12 o'clock)")
        #expect(DirectionPhrase.clockHour(radarAngle: 184) == 6)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path SoundSightCore`
Expected: build FAILS with `cannot find 'HapticPattern' in scope`.

- [ ] **Step 3: Implement the haptic gate**

`SoundSightCore/Sources/SoundSightCore/Alerts/HapticGate.swift` (replace):

```swift
/// Haptic pattern for an urgency score (urgency spec §3): ≥ 0.75 triple, ≥ 0.5 double, ≥ 0.3 single.
public enum HapticPattern: Int, Sendable, Equatable {
    case single = 1, double, triple

    public init?(score: Double) {
        if score >= UrgencyScore.urgentThreshold {
            self = .triple
        } else if score >= 0.5 {
            self = .double
        } else if score >= 0.3 {
            self = .single
        } else {
            return nil
        }
    }
}

/// Decides when an event may buzz: only scores with a pattern, at most once per group per cooldown.
public struct HapticGate: Sendable {
    public let cooldown: Double
    private var lastFired: [String: Double] = [:]

    public init(cooldown: Double = 5) { self.cooldown = cooldown }

    public mutating func shouldFire(group: String, score: Double, now: Double) -> HapticPattern? {
        guard let pattern = HapticPattern(score: score) else { return nil }
        if let last = lastFired[group], now - last < cooldown { return nil }
        lastFired[group] = now
        return pattern
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path SoundSightCore`
Expected: `Test run with 85 tests in 17 suites passed`.

- [ ] **Step 5: Write the app files**

Delete the old tier styling first:

```bash
git rm SoundSightApp/UI/UrgencyStyle.swift
mkdir -p SoundSightShared
```

`project.yml` (replace):

```yaml
name: SoundSight
options:
  bundleIdPrefix: com.hackatl
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  SoundSightCore:
    path: SoundSightCore
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  SoundSight:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: SoundSightApp
        excludes:
          - "Config/**"
          - "Info.plist"
      - path: SoundSightShared
    dependencies:
      - package: SoundSightCore
    configFiles:
      Debug: SoundSightApp/Config/App.xcconfig
      Release: SoundSightApp/Config/App.xcconfig
    info:
      path: SoundSightApp/Info.plist
      properties:
        CFBundleDisplayName: SoundSight
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSMicrophoneUsageDescription: SoundSight listens to the sounds around you to identify them and show where they come from. Audio never leaves your iPhone.
        NSMotionUsageDescription: SoundSight uses motion sensors to keep sound directions fixed as you turn.
        UIBackgroundModes: [audio]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hackatl.soundsight
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
```

`SoundSightShared/UrgencyColor.swift`:

```swift
import SoundSightCore
import SwiftUI

extension Color {
    /// Urgency gradient: green (0) → yellow (0.5) → red (1) (urgency spec §2.4).
    static func urgency(_ score: Double) -> Color {
        Color(hue: UrgencyScore.hueDegrees(score) / 360, saturation: 0.9, brightness: 0.95)
    }
}

/// Green → yellow → red bar with a marker at `score`; no marker when nil.
struct UrgencyBar: View {
    let score: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [.urgency(0), .urgency(0.5), .urgency(1)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                if let score {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .offset(x: (geo.size.width - 14) * min(1, max(0, score)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
```

`SoundSightApp/App/EventDisplay.swift`:

```swift
import SoundSightCore

/// What the UI needs for one tracked sound.
struct EventDisplay: Identifiable, Equatable {
    /// Arrows are drawn only once the belief is this concentrated (R ≥ 0.5).
    static let minConcentration = 0.5

    var id: String { group }
    var group: String
    var urgency: Urgency
    var confidence: Double
    /// World bearing of the belief peak; nil until the belief is concentrated enough.
    var worldBearing: Double?
    /// Belief peak even when diffuse, for the halo.
    var peakBearing: Double
    var concentration: Double
    var belief: [Double]
    var levelDB: Double?
    /// Approximate metres; nil until the level is measured.
    var distance: Double?
    var score: Double
    var band: UrgencyBand

    init(_ e: SoundEvent, sourceLevels: SourceLevels) {
        group = e.group
        urgency = e.urgency
        confidence = e.confidence
        concentration = e.belief.concentration
        peakBearing = e.belief.peakBearing
        worldBearing = concentration >= Self.minConcentration ? peakBearing : nil
        belief = e.belief.probabilities
        levelDB = e.levelDB
        let source = sourceLevels.level(for: e.group)
        distance = e.levelDB.map { UrgencyScore.distance(level: $0, sourceLevel: source) }
        score = UrgencyScore.score(urgency: e.urgency, level: e.levelDB ?? 0, sourceLevel: source)
        band = UrgencyBand(score: score)
    }

    /// "84 dB · ~3 m"; nil before the first level arrives.
    var levelText: String? {
        guard let levelDB, let distance else { return nil }
        return "\(Int(levelDB.rounded())) dB · \(UrgencyScore.formatDistance(distance))"
    }

    func radarAngle(forward: Double) -> Double? {
        worldBearing.map { ForwardHeading.radarAngle(worldBearing: $0, forward: forward) }
    }

    /// "behind you to the right (4 o'clock)" or "direction unknown".
    func directionPhrase(forward: Double) -> String {
        radarAngle(forward: forward).map { DirectionPhrase.describe(radarAngle: $0) } ?? "direction unknown"
    }

    /// "back-right" or "direction unknown".
    func shortDirection(forward: Double) -> String {
        radarAngle(forward: forward).map { DirectionPhrase.short(radarAngle: $0) } ?? "direction unknown"
    }
}
```

`SoundSightApp/App/AppModel.swift` (replace):

```swift
import AVFoundation
import SoundSightCore
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
    /// When listening last started; drives the 3 s radar sweep.
    var listeningSince: Date?
    /// Set from the scene phase; false while backgrounded or locked.
    var isForeground = true
    var probe = ProbeState()
    var calibration: FOAAxisCalibration {
        didSet {
            pipeline?.calibration = calibration
            if let data = try? JSONEncoder().encode(calibration) {
                UserDefaults.standard.set(data, forKey: Self.calibrationKey)
            }
        }
    }

    /// Extra lines for the status banner.
    var notes: [String] { [classifierWarning].compactMap { $0 } }

    @ObservationIgnored private let capture = FOACaptureSession()
    @ObservationIgnored private let motion = MotionProvider()
    @ObservationIgnored private let haptics = HapticsManager()
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
        haptics.reset()
        announced = []
        motion.start()
        capture.start()
        isListening = true
        listeningSince = Date()
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

    private func apply(_ summary: WindowSummary) {
        probe.ingest(summary, calibration: calibration, now: Date())
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        let displays = output.events.map { EventDisplay($0, sourceLevels: sourceLevels) }.sorted { $0.score > $1.score }
        events = displays
        for e in output.newEvents { probe.logDetection(e.group, inBackground: !isForeground, at: Date()) }
        if isForeground {
            let refreshed = Set(output.events.filter { $0.lastSeen == output.now }.map(\.group))
            for d in displays where refreshed.contains(d.group) {
                haptics.alert(group: d.group, score: d.score, now: output.now)
            }
        }
        announceUrgent(displays)
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
```

`SoundSightApp/Capture/AudioPipeline.swift` (replace):

```swift
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
}

struct TrackerOutput: Sendable {
    var events: [SoundEvent]
    var newEvents: [SoundEvent]
    var now: Double
}

/// Chunk → SoundAnalysis + 1 s windows → DOA → joiner → EventTracker, all on one serial queue (spec §3).
final class AudioPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "soundsight.pipeline")
    private let resources: ClassificationResources
    private let estimator: DOAEstimator
    private let tracker: EventTracker
    private let state = OSAllocatedUnfairLock(initialState: FOAAxisCalibration.initialGuess)
    private let deviceToWorld: @Sendable () -> simd_float3x3

    private var sampleRate: Double = 0
    private var accumulator: WindowAccumulator?
    private var joiner: WindowJoiner?
    private var classifier: (any SoundClassifier)?
    /// Omni level (approximate dB SPL) per DOA window start, until its classification joins.
    private var levels: [Int64: Double] = [:]

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
            self.levels = [:]
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
            let rms = [window.w, window.x, window.y, window.z].map(Self.rms)
            levels[window.startSample] = UrgencyScore.level(rms: Double(rms[0]))
            let cutoff = window.startSample - Int64(8 * acc.hopLength)
            levels = levels.filter { $0.key >= cutoff }
            onWindow?(WindowSummary(summedRaw: intensity.summedRaw, diffuseness: intensity.diffuseness,
                                    totalEnergy: intensity.totalEnergy, channelRMS: rms, doa: doa))
            handle(joiner?.add(doa: doa) ?? [])
        }
    }

    private func handle(_ joined: [JoinedWindow]) {
        for j in joined {
            let now = Double(j.windowStart) / sampleRate
            let active = resources.thresholds.active(j.classification.groupScores)
            let level = j.doa.flatMap { levels.removeValue(forKey: $0.windowStart) }
            let created = tracker.ingest(active: active, doa: j.doa, now: now, levelDB: level)
            onTracker?(TrackerOutput(events: tracker.events, newEvents: created, now: now))
        }
    }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }
}
```

`SoundSightApp/Haptics/HapticsManager.swift` (replace):

```swift
import CoreHaptics
import SoundSightCore

/// Score-tiered Core Haptics patterns with a per-group cooldown (urgency spec §3). Foreground only:
/// Core Haptics doesn't play in the background, where the urgent notification vibrates instead.
@MainActor
final class HapticsManager {
    private var engine: CHHapticEngine?
    private var gate = HapticGate(cooldown: 5)

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    /// Clears cooldowns; call when listening restarts (the capture timeline restarts at 0).
    func reset() { gate = HapticGate(cooldown: 5) }

    func alert(group: String, score: Double, now: Double) {
        guard let engine, let pattern = gate.shouldFire(group: group, score: score, now: now),
              let haptic = try? CHHapticPattern(events: Self.events(for: pattern), parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: haptic).start(atTime: CHHapticTimeImmediate)
    }

    static func events(for pattern: HapticPattern) -> [CHHapticEvent] {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        return switch pattern {
        case .triple: [tap(0, 1, 1), tap(0.15, 1, 1), tap(0.30, 1, 1)]
        case .double: [tap(0, 0.8, 0.7), tap(0.25, 0.8, 0.7)]
        case .single: [tap(0, 0.5, 0.5)]
        }
    }
}
```

`SoundSightApp/UI/RadarView.swift` (replace):

```swift
import SoundSightCore
import SwiftUI

/// 360° radar: a tight belief halo, arrows and labels in the urgency gradient, counter-rotated by the
/// forward heading (spec §3.6). The sweep only plays for 3 s after Start Listening (urgency spec §3).
struct RadarView: View {
    let events: [EventDisplay]
    let forward: Double
    let listeningSince: Date?

    var body: some View {
        TimelineView(.animation(paused: !isSweeping)) { context in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 28
                drawGrid(&ctx, c, radius)
                if let listeningSince {
                    drawSweep(&ctx, c, radius, elapsed: context.date.timeIntervalSince(listeningSince))
                }
                for e in events.reversed() { drawEvent(&ctx, e, c, radius) }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var isSweeping: Bool {
        guard let listeningSince else { return false }
        return Date().timeIntervalSince(listeningSince) < RadarSweep.duration
    }

    private func drawGrid(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat) {
        for f in [1.0 / 3, 2.0 / 3, 1.0] {
            let r = radius * f
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        for (label, angle) in [("FRONT", 0.0), ("RIGHT", 90), ("BACK", 180), ("LEFT", 270)] {
            ctx.draw(Text(label).font(.caption2.bold()).foregroundStyle(.secondary), at: radarPoint(c, radius + 16, angle))
        }
    }

    private func drawSweep(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat, elapsed: Double) {
        let alpha = RadarSweep.opacity(elapsed: elapsed)
        guard alpha > 0 else { return }
        let a = (elapsed * 120).truncatingRemainder(dividingBy: 360)  // one turn per 3 s
        var sweep = Path()
        sweep.move(to: c)
        sweep.addLine(to: radarPoint(c, radius, a))
        ctx.stroke(sweep, with: .color(.accentColor.opacity(0.6 * alpha)), lineWidth: 2)
    }

    private func drawEvent(_ ctx: inout GraphicsContext, _ e: EventDisplay, _ c: CGPoint, _ radius: CGFloat) {
        let color = Color.urgency(e.score)
        for bin in Halo.bins(e.belief, around: e.peakBearing) {
            let a = ForwardHeading.radarAngle(worldBearing: AzimuthBelief.binCenter(bin.index), forward: forward)
            var seg = Path()
            seg.move(to: radarPoint(c, radius * 0.92, a - AzimuthBelief.binWidth / 2))
            seg.addLine(to: radarPoint(c, radius * 0.92, a))
            seg.addLine(to: radarPoint(c, radius * 0.92, a + AzimuthBelief.binWidth / 2))
            ctx.stroke(seg, with: .color(color.opacity(e.concentration * bin.strength)), lineWidth: 10)
        }
        guard let a = e.radarAngle(forward: forward) else { return }
        var arrow = Path()
        arrow.move(to: c)
        arrow.addLine(to: radarPoint(c, radius * 0.8, a))
        ctx.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.draw(Text(e.group).font(.caption.bold()).foregroundStyle(color), at: radarPoint(c, radius * 0.6, a))
    }

    private var accessibilitySummary: String {
        guard !events.isEmpty else { return listeningSince == nil ? "Radar. Not listening." : "Radar. No sounds detected." }
        return "Radar. " + events.map { "\($0.group), \($0.band.label), \($0.directionPhrase(forward: forward))" }.joined(separator: ". ")
    }
}
```

`SoundSightApp/UI/FocusCard.swift`:

```swift
import SoundSightCore
import SwiftUI

/// The most urgent sound, in large text under the radar: class, volume, distance, direction and the gradient bar.
struct FocusCard: View {
    let event: EventDisplay?
    let forward: Double
    let isListening: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = event {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color.urgency(e.score)).frame(width: 14, height: 14)
                    Text(e.group.uppercased())
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text(e.band.label).font(.headline).foregroundStyle(Color.urgency(e.score))
                }
                Text(e.levelText.map { "\($0) away" } ?? "Measuring volume…")
                    .font(.title3.monospacedDigit())
                Text(e.directionPhrase(forward: forward))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                UrgencyBar(score: e.score)
            } else {
                Text(isListening ? "Listening…" : "Not listening")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                UrgencyBar(score: nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let e = event else { return isListening ? "Listening. No sounds detected." : "Not listening." }
        return "\(e.group), \(e.band.label), \(e.levelText ?? "volume unknown"), \(e.directionPhrase(forward: forward))"
    }
}
```

`SoundSightApp/UI/EventListView.swift` (replace):

```swift
import SoundSightCore
import SwiftUI

/// The other tracked sounds, under the focus card.
struct EventListView: View {
    let events: [EventDisplay]
    let forward: Double

    var body: some View {
        VStack(spacing: 8) {
            ForEach(events) { row($0) }
        }
    }

    private func row(_ e: EventDisplay) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.urgency(e.score)).frame(width: 12, height: 12)
            Text(e.group).font(.headline)
            Spacer()
            Text("\(e.levelText ?? "measuring…") · \(e.shortDirection(forward: forward))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.group), \(e.band.label), \(e.levelText ?? "volume unknown"), \(e.directionPhrase(forward: forward))")
    }
}
```

`SoundSightApp/UI/MainView.swift` (replace):

```swift
import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(status: model.status, notes: model.notes)
                    RadarView(events: model.events, forward: model.forwardBearing, listeningSince: model.listeningSince)
                        .aspectRatio(1, contentMode: .fit)
                    FocusCard(event: model.events.first, forward: model.forwardBearing, isListening: model.isListening)
                    EventListView(events: Array(model.events.dropFirst()), forward: model.forwardBearing)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if model.isListening { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.isListening ? "Stop Listening" : "Start Listening").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SoundSight")
                        .font(.headline)
                        .onLongPressGesture { showProbe = true }
                        .accessibilityHint("Long-press to open the FOA probe")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
        }
    }
}
```

`SoundSightApp/UI/StatusBanner.swift` (replace):

```swift
import SwiftUI
import UIKit

struct StatusBanner: View {
    let status: ListeningStatus
    /// Extra notices (classifier, notifications, lock-screen bar).
    let notes: [String]

    var body: some View {
        VStack(spacing: 8) {
            switch status {
            case .idle, .listening:
                EmptyView()
            case .interrupted:
                banner("Paused: another app is using the microphone.", systemImage: "pause.circle")
            case .permissionDenied:
                banner("SoundSight needs microphone access to hear sounds around you.", systemImage: "mic.slash") {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            case .directionUnavailable(let message):
                banner("Direction unavailable: \(message)", systemImage: "location.slash")
            case .error(let message):
                banner(message, systemImage: "exclamationmark.triangle")
            }
            ForEach(notes, id: \.self) { note in
                banner(note, systemImage: "info.circle")
            }
        }
    }

    private func banner(_ text: String, systemImage: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 6: Build**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
Expected: no `error:` or warnings.

- [ ] **Step 7: Commit**

The device check comes in Task 8.

```bash
git add SoundSightCore SoundSightShared SoundSightApp project.yml
git commit -m "Show urgency as a gradient with a focus card, tight halo, short sweep and score haptics" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: One urgent notification that never stacks

**Files:**
- Create: `SoundSightApp/Alerts/UrgentNotifier.swift`
- Modify (replace): `SoundSightApp/App/AppModel.swift`

**Interfaces:**
- Consumes: `NotificationPolicy` (Task 3); `EventDisplay`, `AppModel` (Task 5).
- Produces:
  - `UrgentNotifier` with `requestAuthorization() async -> Bool`, `reset()`, `consider(_:forward:now:isForeground:)` and `clear()`.
  - `AppModel.notificationsNote`.

- [ ] **Step 1: Write the files**

`SoundSightApp/Alerts/UrgentNotifier.swift`:

```swift
import SoundSightCore
import UserNotifications

/// The single urgent notification (urgency spec §6). Every request uses the same identifier, so a new
/// alert replaces the delivered one instead of stacking. Rate-limited by `NotificationPolicy`.
@MainActor
final class UrgentNotifier {
    private let center = UNUserNotificationCenter.current()
    private var policy = NotificationPolicy()

    /// Prompts the first time; afterwards returns the current setting.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Clears rate limits; call when listening restarts (the capture timeline restarts at 0).
    func reset() { policy = NotificationPolicy() }

    /// Posts for the most urgent event the policy lets through, if any. `events` is sorted by score.
    func consider(_ events: [EventDisplay], forward: Double, now: Double, isForeground: Bool) {
        for e in events where e.band == .urgent {
            guard policy.shouldNotify(group: e.group, score: e.score, now: now, isForeground: isForeground) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(e.group): \(e.directionPhrase(forward: forward))"
            content.body = e.levelText.map { "\($0) away" } ?? "Urgent sound nearby"
            content.sound = .default
            content.interruptionLevel = .active
            center.add(UNNotificationRequest(identifier: NotificationPolicy.identifier, content: content, trigger: nil),
                       withCompletionHandler: nil)
            return
        }
    }

    /// Removes the delivered notification, e.g. when listening stops.
    func clear() {
        center.removeDeliveredNotifications(withIdentifiers: [NotificationPolicy.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [NotificationPolicy.identifier])
    }
}
```

`SoundSightApp/App/AppModel.swift` (replace):

```swift
import AVFoundation
import SoundSightCore
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
    /// When listening last started; drives the 3 s radar sweep.
    var listeningSince: Date?
    /// Set from the scene phase; false while backgrounded or locked.
    var isForeground = true
    var probe = ProbeState()
    var calibration: FOAAxisCalibration {
        didSet {
            pipeline?.calibration = calibration
            if let data = try? JSONEncoder().encode(calibration) {
                UserDefaults.standard.set(data, forKey: Self.calibrationKey)
            }
        }
    }

    /// Extra lines for the status banner.
    var notes: [String] { [classifierWarning, notificationsNote].compactMap { $0 } }

    @ObservationIgnored private let capture = FOACaptureSession()
    @ObservationIgnored private let motion = MotionProvider()
    @ObservationIgnored private let haptics = HapticsManager()
    @ObservationIgnored private let notifier = UrgentNotifier()
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
        notifier.clear()
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

    private func apply(_ summary: WindowSummary) {
        probe.ingest(summary, calibration: calibration, now: Date())
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        let displays = output.events.map { EventDisplay($0, sourceLevels: sourceLevels) }.sorted { $0.score > $1.score }
        events = displays
        for e in output.newEvents { probe.logDetection(e.group, inBackground: !isForeground, at: Date()) }
        if isForeground {
            let refreshed = Set(output.events.filter { $0.lastSeen == output.now }.map(\.group))
            for d in displays where refreshed.contains(d.group) {
                haptics.alert(group: d.group, score: d.score, now: output.now)
            }
        }
        announceUrgent(displays)
        notifier.consider(displays, forward: forwardBearing, now: output.now, isForeground: isForeground)
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
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
Expected: no `error:` or warnings.

- [ ] **Step 3: Commit**

```bash
git add SoundSightApp
git commit -m "Send one replaceable urgent notification while in the background" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Live Activity on the lock screen and Dynamic Island

**Files:**
- Create: `SoundSightShared/SoundSightActivityAttributes.swift`, `SoundSightLiveActivity/SoundSightLiveActivityWidget.swift`, `SoundSightApp/Alerts/LiveActivityController.swift`
- Modify (replace): `project.yml`, `SoundSightApp/App/AppModel.swift`, `.gitignore`

**Interfaces:**
- Consumes: `LiveActivityThrottle`, `LiveActivitySnapshot` (Task 4); `UrgencyBar`, `Color.urgency`, `EventDisplay` (Task 5).
- Produces:
  - `SoundSightActivityAttributes.ContentState { group, score, detail, radarAngle, band, paused; static let idle }`.
  - `LiveActivityController` with `start()`, `stop()`, `show(_:forward:paused:)` and `onProblem`.
  - The `SoundSightLiveActivity` widget extension target (`com.hackatl.soundsight.liveactivity`), embedded in the app.
  - `AppModel.liveActivityNote`.

Signing note: local Live Activity updates need neither push notifications nor App Groups, so the free Personal Team can sign the extension. A signed device build was verified while writing this plan.

- [ ] **Step 1: Write the files**

```bash
mkdir -p SoundSightLiveActivity SoundSightApp/Alerts
```

`project.yml` (replace):

```yaml
name: SoundSight
options:
  bundleIdPrefix: com.hackatl
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  SoundSightCore:
    path: SoundSightCore
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  SoundSight:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: SoundSightApp
        excludes:
          - "Config/**"
          - "Info.plist"
      - path: SoundSightShared
    dependencies:
      - package: SoundSightCore
      - target: SoundSightLiveActivity
    configFiles:
      Debug: SoundSightApp/Config/App.xcconfig
      Release: SoundSightApp/Config/App.xcconfig
    info:
      path: SoundSightApp/Info.plist
      properties:
        CFBundleDisplayName: SoundSight
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSMicrophoneUsageDescription: SoundSight listens to the sounds around you to identify them and show where they come from. Audio never leaves your iPhone.
        NSMotionUsageDescription: SoundSight uses motion sensors to keep sound directions fixed as you turn.
        UIBackgroundModes: [audio]
        NSSupportsLiveActivities: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hackatl.soundsight
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
  SoundSightLiveActivity:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: SoundSightLiveActivity
        excludes:
          - "Info.plist"
      - path: SoundSightShared
    dependencies:
      - package: SoundSightCore
    configFiles:
      Debug: SoundSightApp/Config/App.xcconfig
      Release: SoundSightApp/Config/App.xcconfig
    info:
      path: SoundSightLiveActivity/Info.plist
      properties:
        CFBundleDisplayName: SoundSight
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hackatl.soundsight.liveactivity
        TARGETED_DEVICE_FAMILY: "1"
```

`.gitignore` (replace):

```gitignore
# Generated by XcodeGen (run `xcodegen generate`)
SoundSight.xcodeproj/
SoundSightApp/Info.plist
SoundSightLiveActivity/Info.plist

# Personal signing settings
SoundSightApp/Config/Signing.xcconfig

# Build products
.build/
DerivedData/
.swiftpm/
xcuserdata/
*.xcuserstate
.DS_Store
```

`SoundSightShared/SoundSightActivityAttributes.swift`:

```swift
import ActivityKit
import Foundation

/// The lock-screen / Dynamic Island bar (urgency spec §5). Compiled into the app and the widget extension.
struct SoundSightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Most urgent sound; nil shows "Listening…".
        var group: String?
        var score: Double
        /// Pre-formatted "84 dB · ~3 m", empty when unknown.
        var detail: String
        /// Degrees clockwise from the phone's forward direction; nil when the direction is unknown.
        var radarAngle: Double?
        /// "Urgent", "Moderate" or "Low"; empty when there is no sound.
        var band: String
        var paused: Bool

        static let idle = ContentState(group: nil, score: 0, detail: "", radarAngle: nil, band: "", paused: false)
    }
}
```

`SoundSightLiveActivity/SoundSightLiveActivityWidget.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SoundSightWidgets: WidgetBundle {
    var body: some Widget { SoundSightLiveActivityWidget() }
}

/// Lock-screen banner and Dynamic Island for the most urgent sound (urgency spec §5).
struct SoundSightLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoundSightActivityAttributes.self) { context in
            LiveBanner(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { LiveBanner(state: context.state) }
            } compactLeading: {
                StatusDot(state: context.state)
            } compactTrailing: {
                DirectionArrow(state: context.state).font(.caption.bold())
            } minimal: {
                StatusDot(state: context.state)
            }
        }
    }
}

struct LiveBanner: View {
    let state: SoundSightActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusDot(state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    if !state.detail.isEmpty {
                        Text(state.detail).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                DirectionArrow(state: state).font(.title2.bold())
            }
            if state.group != nil { UrgencyBar(score: state.score) }
        }
    }

    private var title: String {
        if state.paused { return "Paused" }
        guard let group = state.group else { return "Listening…" }
        return state.band.isEmpty ? group : "\(group) · \(state.band)"
    }
}

struct StatusDot: View {
    let state: SoundSightActivityAttributes.ContentState

    var body: some View {
        Circle()
            .fill(state.group == nil ? Color.gray : Color.urgency(state.score))
            .frame(width: 12, height: 12)
    }
}

/// Arrow toward the sound, relative to the phone's forward direction.
struct DirectionArrow: View {
    let state: SoundSightActivityAttributes.ContentState

    var body: some View {
        if state.group == nil {
            Image(systemName: "ear").foregroundStyle(.white.opacity(0.8))
        } else if let angle = state.radarAngle {
            Image(systemName: "location.north.fill")
                .rotationEffect(.degrees(angle))
                .foregroundStyle(Color.urgency(state.score))
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.white.opacity(0.8))
        }
    }
}
```

`SoundSightApp/Alerts/LiveActivityController.swift`:

```swift
import ActivityKit
import SoundSightCore
import Foundation

/// Owns the lock-screen / Dynamic Island bar while listening (urgency spec §5).
@MainActor
final class LiveActivityController {
    private var activity: Activity<SoundSightActivityAttributes>?
    private var throttle = LiveActivityThrottle()
    private var wanted = false
    private var watcher: Task<Void, Never>?
    /// Called with a message when the bar can't be shown, or nil once it is.
    var onProblem: ((String?) -> Void)?

    func start() {
        wanted = true
        throttle = LiveActivityThrottle()
        request()
    }

    func stop() {
        wanted = false
        watcher?.cancel()
        watcher = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Shows the most urgent event (or "Listening…"), rate-limited by `LiveActivityThrottle`.
    func show(_ focus: EventDisplay?, forward: Double, paused: Bool) {
        guard let activity else { return }
        let angle = focus?.radarAngle(forward: forward)
        let snapshot = LiveActivitySnapshot(group: focus?.group, score: focus?.score ?? 0, levelDB: focus?.levelDB ?? 0,
                                            radarAngle: angle, paused: paused)
        guard throttle.shouldSend(snapshot, now: ProcessInfo.processInfo.systemUptime) else { return }
        let state = SoundSightActivityAttributes.ContentState(group: focus?.group, score: focus?.score ?? 0, detail: focus?.levelText ?? "",
                                                        radarAngle: angle, band: focus?.band.label ?? "", paused: paused)
        Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))) }
    }

    private func request() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            onProblem?("The lock-screen bar is turned off in Settings › SoundSight › Live Activities.")
            return
        }
        do {
            let a = try Activity.request(attributes: SoundSightActivityAttributes(), content: ActivityContent(state: .idle, staleDate: nil))
            activity = a
            onProblem?(nil)
            watcher?.cancel()
            watcher = Task { [weak self] in
                for await state in a.activityStateUpdates where state == .ended {
                    self?.ended(a.id)
                }
            }
        } catch {
            onProblem?("Lock-screen bar unavailable: \(error.localizedDescription)")
        }
    }

    /// The system ended the bar (8-hour limit): start a new one if still listening.
    /// A swipe-away by the user is `.dismissed` and is respected.
    private func ended(_ id: String) {
        guard wanted, activity?.id == id else { return }
        activity = nil
        request()
    }
}
```

`SoundSightApp/App/AppModel.swift` (replace):

```swift
import AVFoundation
import SoundSightCore
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
    /// Set from the scene phase; false while backgrounded or locked.
    var isForeground = true
    var probe = ProbeState()
    var calibration: FOAAxisCalibration {
        didSet {
            pipeline?.calibration = calibration
            if let data = try? JSONEncoder().encode(calibration) {
                UserDefaults.standard.set(data, forKey: Self.calibrationKey)
            }
        }
    }

    /// Extra lines for the status banner.
    var notes: [String] { [classifierWarning, notificationsNote, liveActivityNote].compactMap { $0 } }

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
            pipeline.onError = { [weak self] message in Task { @MainActor in self?.classifierWarning = message } }
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
        capture.stop()
        motion.stop()
        notifier.clear()
        liveActivity.stop()
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

    private func apply(_ summary: WindowSummary) {
        probe.ingest(summary, calibration: calibration, now: Date())
    }

    private func apply(_ output: TrackerOutput) {
        guard isListening else { return }
        let displays = output.events.map { EventDisplay($0, sourceLevels: sourceLevels) }.sorted { $0.score > $1.score }
        events = displays
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
```

- [ ] **Step 2: Build and check that the extension is embedded**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build -quiet && ls .build/xcode/Build/Products/Debug-iphoneos/SoundSight.app/PlugIns`
Expected: no `error:` or warnings; prints `SoundSightLiveActivity.appex`.

- [ ] **Step 3: Commit**

```bash
git add project.yml .gitignore SoundSightShared SoundSightLiveActivity SoundSightApp
git commit -m "Add lock-screen and Dynamic Island Live Activity for the most urgent sound" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Device check, README and final verification

**Files:**
- Modify: `README.md` (append a section)

- [ ] **Step 1: Human check on the iPhone**

Ask the human to Run on the phone (allow notifications when asked), tap **Start Listening**, and report pass or fail for each item:

1. **Sweep:** the radar sweep turns for about 3 s, fades out, and does not come back.
2. **Gradient:**
   - A siren played loud about 1 m away gives a **red** focus card marked **Urgent**.
   - The same clip played quietly across the room gives **yellow or orange**.
   - People talking gives **green** and **Low**.
3. **Focus card:** shows the class in large text, then `NN dB · ~N m away`, the direction phrase and the gradient bar with its marker. List rows show `NN dB · ~N m · <short direction>`.
4. **Halo:** the colored arc around a steady source is narrow, about 30° wide or less.
5. **Haptics** (app open): Urgent gives a triple pulse, Moderate a double or single, speech none.
6. **Restart:** tap **Stop**, then **Start**, and play the siren. The haptic still fires right away (Review Focus 1).
7. **Lock-screen bar:**
   - After Start, lock the phone. The bar shows "Listening…".
   - Play the siren. The bar shows the class and band, `NN dB · ~N m`, a colored arrow and the gradient bar.
   - The Dynamic Island shows a colored dot and an arrow.
8. **No stacking:** with the phone locked, play the siren three times, 5 s apart. Exactly **one** SoundSight notification is on the lock screen.
9. **Stop:** tapping Stop removes the bar and the notification.
10. **Swipe-away:** while listening, swipe the bar away on the lock screen. It stays gone and is not re-created.

If item 7 shows no bar, check **Settings › SoundSight › Live Activities**. The status banner should say it's off.

- [ ] **Step 2: Append to the README**

```bash
cat >> README.md <<'EOF'

## Urgency, background and lock screen

- **Urgency gradient:** every sound gets a score from 0 to 1, built from its class (its urgency tier), its loudness and an approximate distance. The distance comes from comparing the heard level with that sound's typical level at 1 m (`SoundSightCore/Sources/SoundSightCore/Resources/source_levels.json`). Green is low, yellow moderate and red urgent. dB values and distances are approximate: the mic is uncalibrated.
- **Background:** once you tap Start Listening, SoundSight keeps listening when you lock the phone or switch apps. The orange mic indicator stays on.
- **Lock-screen bar:** a Live Activity shows the most urgent sound with its direction arrow, on the lock screen and in the Dynamic Island. Turn it off in Settings › SoundSight › Live Activities.
- **Urgent notification:** while the phone is locked or SoundSight is in the background, urgent sounds post one notification that replaces the previous one instead of stacking (at most one every 10 s).
EOF
```

- [ ] **Step 3: Final verification**

Run: `swift test --package-path SoundSightCore && xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet && git status --short`
Expected: `Test run with 85 tests in 17 suites passed`; the build is clean; `git status` lists only `README.md`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document urgency gradient, background listening and lock-screen bar" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
