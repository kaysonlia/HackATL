# SoundSight for iPhone 16 Pro Max — 360° sound awareness via First-Order Ambisonics

**Date:** 2026-10-10 · **Status:** Draft for review

## 1. Intent

**What the user asked for:** Build SoundSight step by step for the iPhone 16 Pro Max, using its microphone array for 360° detection.

**Agreed scope (HackATL hackathon demo):** A working on-device demo that classifies environmental sounds, assigns urgency, and shows where each sound is coming from on a full 360° radar, with urgency-tiered haptics. Profiles, pinned alerts, history and background monitoring are stretch goals.

**Success criteria**
1. On a physical iPhone 16 Pro Max (iOS 26), a siren, knock or dog clip played from a speaker about 1.5 m away is labeled with the correct sound group and urgency within about 1 s.
2. The radar arrow for that sound points within ±30° (median) of the true direction for any of 8 directions around the phone, with no rotation required.
3. The arrow stays fixed in the world while the user rotates the phone.
4. CRITICAL/HIGH sounds trigger distinct haptic patterns.

**Assumptions to verify on hardware (probe, step 1):** iOS delivers live 4-channel FOA buffers from the built-in mic array to an audio-only `AVCaptureSession`; the FOA field is accurate enough to meet criterion 2; the FOA axis orientation relative to the device can be determined and is fixed.

## 2. Key decisions

| Decision | Choice | Why |
|---|---|---|
| Localization | FOA active-intensity direction of arrival | One window gives a full 3-D direction with no front/back mirror ambiguity. A stereo pair would need rotation to converge. |
| Gating | On-device FOA probe before any other app work | FOA quality on iPhone is unverified. Failing fast avoids building on a bad assumption. |
| Fallback | None built up front. If the probe fails, stop and revisit (AVAudioSession stereo + a rotational belief) | YAGNI for a hackathon. |
| Classifier | Apple SoundAnalysis (`SNClassifySoundRequest(.version1)`) behind a `SoundClassifier` protocol | Classifier spike: best accuracy (77.9% top-1 vs 67.0%/61.9%), zero added size or dependencies, native `AVAudioPCMBuffer` input. See `docs/superpowers/spikes/2026-10-10-classifier/`. |
| Label taxonomy | the 42 starting groups and `urgency_map.json`, unchanged | A practical, tested taxonomy. All 303 Apple labels are mapped (`apple_to_group.json`). |
| Device posture | Any (flat, upright, tilted) | The 3-D FOA vector is rotated into the world frame with CoreMotion attitude, then projected onto the horizontal plane. |
| Project generation | XcodeGen (`project.yml`) | A readable, mergeable project definition for a team. |
| Code split | `SoundSightCore` Swift package (pure logic) + thin `SoundSightApp` target | DSP, mapping and fusion are tested on the Mac with `swift test` in seconds. |
| Platform | iOS 26.0 minimum, Swift 6, SwiftUI | The FOA audio-data-output layout tag is iOS 26. iPhone 16 Pro Max only. |

## 3. Architecture

```
AVCaptureSession (audio only, built-in mic, multichannelAudioMode = .firstOrderAmbisonics)
 └─ AVCaptureAudioDataOutput (spatialAudioChannelLayoutTag = HOA_ACN_SN3D | 4)
      │  CMSampleBuffer → FOABufferAdapter → FOAChunk {w, y, z, x : [Float], sampleTime}
      ▼
 AudioPipeline (serial DispatchQueue; ring buffer; 1.0 s windows, 0.5 s hop)
  ├─ SoundClassifier ── SoundAnalysisClassifier: SNAudioStreamAnalyzer fed the W channel
  │     → [AppleLabel: conf] → LabelMapper (noisy-OR into 42 groups) → GroupThresholds → UrgencyMap
  ├─ DOAEstimator (SoundSightCore) ── STFT → per-bin intensity → device→world rotation → azimuth histogram → peaks
  └─ MotionProvider ── CMMotionManager deviceMotion (xArbitraryCorrectedZVertical, 60 Hz)
      ▼  joined per window by window start sample
 EventTracker (SoundSightCore) ── per group: smoothed confidence, urgency, AzimuthBelief, lastSeen
      ▼  @Observable AppModel (main actor)
 SwiftUI: RadarView (Canvas + TimelineView, 60 fps) · EventList · Controls · ProbeView (debug)
 HapticsManager (Core Haptics) · VoiceOver announcements
```

### 3.1 Capture (`SoundSightApp/Capture`)
- `AVCaptureDevice.default(for: .audio)` → `AVCaptureDeviceInput`. Require `isMultichannelAudioModeSupported(.firstOrderAmbisonics)`, then set `multichannelAudioMode = .firstOrderAmbisonics`.
- One `AVCaptureAudioDataOutput` with `spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4` and a delegate on a dedicated serial queue.
- `FOABufferAdapter` reads each buffer's `AudioStreamBasicDescription` and converts whatever arrives (Int16/Float32, interleaved or not) into Float32 per channel in **ACN order: 0 = W, 1 = Y, 2 = Z, 3 = X**. The sample rate is taken from the format; 48 kHz is expected.
- Interruptions (`AVCaptureSession.wasInterruptedNotification` / `interruptionEndedNotification`, runtime errors) pause the pipeline and resume automatically.

### 3.2 Classification (`SoundSightApp/Classification` + `SoundSightCore/Classification`)
- `protocol SoundClassifier { func analyze(_ mono: AVAudioPCMBuffer, at sampleTime: Int64); var onResult: (ClassificationFrame) -> Void }`.
- `SoundAnalysisClassifier`: `SNAudioStreamAnalyzer` (mono Float32 at the capture rate) with `SNClassifySoundRequest(classifierIdentifier: .version1)`, `windowDuration = 1.0 s`, `overlapFactor = 0.5`. Each `SNClassificationResult.timeRange` gives the window start sample.
- `LabelMapper` (SoundSightCore): Apple label → group via `apple_to_group.json`; group score = top-3 noisy-OR `1 − ∏(1 − pᵢ)`.
- `GroupThresholds` (SoundSightCore): per-group thresholds from `thresholds.json` (spike output, tunable). A group is **active** when score ≥ threshold.
- `UrgencyMap` (SoundSightCore): `urgency_map.json` (CRITICAL / HIGH / MEDIUM / LOW). "Car Alarm", "TV/Radio" and "Fart" have no Apple label and never fire until the step 7 custom classifier adds Car Alarm.

### 3.3 Direction of arrival (`SoundSightCore/DSP`)
For each 1 s window (from the same ring buffer and sample grid as classification):
1. **STFT** (vDSP): 1024-sample Hann frames, 512 hop; keep bins in 200–8000 Hz.
2. **Per-bin intensity** (SN3D first order: for a plane wave from unit direction **u**, W = s and (X, Y, Z) = s·**u**):
   **I** = Re(W* · [X, Y, Z]), energy E = ½(|W|² + |X|² + |Y|² + |Z|²).
   Drop bins whose E is below a noise floor (the 20th percentile of the window's bin energies).
3. **FOA → device frame**: **v**_dev = `FOAAxisCalibration` · **I**, a fixed signed 3×3 permutation (plus optional yaw offset) measured by the probe. Device frame = CoreMotion's (x right, y toward the top edge, z out of the screen).
4. **Device → world**: **v**_world = R(attitude) · **v**_dev. Azimuth θ = atan2(v_y, v_x); weight = horizontal magnitude ‖(v_x, v_y)‖.
5. **Histogram**: 72 bins × 5°, weight-accumulated, then circularly smoothed (von Mises kernel, κ = 8).
6. **Peaks**: up to 3 local maxima ≥ 25% of the global maximum and ≥ 30° apart. Output `DOAFrame { windowStart, peaks: [(azimuth, weight)], diffuseness }`, with diffuseness = 1 − ‖Σ**I**‖ / Σ E.

### 3.4 Fusion (`SoundSightCore/Fusion`)
- **`AzimuthBelief`**: 72 bins (5°) in the world frame, starting uniform. Each update decays toward uniform, `p ← (1 − λ)·p + λ·uniform` with λ = 0.15, then multiplies by `ε + Σ wₖ·vonMises(θ − peakₖ, κ = 6)` (ε = 0.05) and renormalizes. **Concentration** = mean resultant length R ∈ [0, 1].
- **`EventTracker`**: one `SoundEvent` per active group with label, urgency, smoothed confidence (EMA α = 0.5), belief, `firstSeen` and `lastSeen`. A window's DOA peaks update the belief of every group active in that window. The update is skipped when window diffuseness > 0.8. Events are evicted 3 s after `lastSeen` and sorted by urgency, then confidence.
- **Matching directions to sounds**: confidence-weighted. Simultaneous sources may blur together; this is accepted for the demo.

### 3.5 Motion (`SoundSightApp/Motion`)
- `CMMotionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)` at 60 Hz. Publishes the latest rotation matrix (used by the DOA step) and the device **forward heading**.
- **Forward**: the horizontal projection of device +y when the phone is near flat (tilt < 45° from horizontal), otherwise of device −z (where the back camera points). Hysteresis of ±10° stops the reference from flipping back and forth at 45°.
- **Radar angle** of a world azimuth θ = θ − forwardHeading, so "up" on the radar is where the user is facing or pointing the phone.

### 3.6 UI (`SoundSightApp/UI`, SwiftUI)
- **MainView**: title bar, `RadarView`, active event list, Start/Stop button, and a status banner (for "Direction unavailable", "Mic permission needed" or "Interrupted").
- **RadarView**: `Canvas` inside `TimelineView(.animation)`; range rings; FRONT / BACK / LEFT / RIGHT labels; sweep while listening. For each event, a belief halo (bin arcs with alpha ∝ belief), a peak arrow and a chip, all in urgency colors (CRITICAL red, HIGH orange, MEDIUM yellow, LOW blue). Arrow and chip appear only when concentration R ≥ 0.5; otherwise the chip sits in a "direction unknown" row.
- **ProbeView** (debug, opened by long-pressing the title): per-channel RMS, live raw azimuth/elevation dial (before calibration), diffuseness, a calibration recorder and CSV export via the share sheet.
- **Accessibility**: each event has an accessibility label, e.g. "Siren, critical, behind you, to the left (4 o'clock)". New CRITICAL events post a VoiceOver announcement. Dynamic Type for text.
- **Permissions**: `NSMicrophoneUsageDescription`, `NSMotionUsageDescription`; a denied-permission screen links to Settings.

### 3.7 Haptics (`SoundSightApp/Haptics`)
`CHHapticEngine` patterns: CRITICAL = 3 transients (intensity 1.0, sharpness 1.0) at 0 / 0.15 / 0.30 s; HIGH = 2 transients (0.8) at 0 / 0.25 s; MEDIUM = 1 transient (0.5); LOW = none. Each label has a 5 s cooldown.


### 3.8 Custom ML classification system (step 7, after the main system)
Extends coverage beyond Apple's 303 built-in labels. It is built only after steps 0–6 work end to end.
- **Initial classes**: `car_alarm`, `smoke_alarm_chirp`, `appliance_beep` (microwave/oven/washer), `crosswalk_signal`, plus a `background` negative class. The class list lives in `custom_to_group.json`, so adding a class later means a new folder of clips plus one map entry.
- **Data**: at least 10 (target 30+) mono clips of ≥ 16 kHz per class. Sources:
  1. Recorded on the 16 Pro Max with a **Sample Recorder** in the debug view, which saves the FOA W channel as WAV. These are the preferred source because they match the app's mic processing.
  2. FSD50K/Freesound clips, with each clip's license checked and recorded in `Training/data/LICENSES.csv`.
  Raw clips are git-ignored; the manifest is committed.
- **Training**: `Training/train.swift`, a macOS script using the CreateML framework: `MLSoundClassifier(trainingData: .labeledDirectories(at:))` with an 80/20 split by recording session. It writes `SoundSightCustomSounds.mlmodel` and a metrics report. The same workflow also works in the Create ML app.
- **Runtime**: a second `SNClassifySoundRequest(mlModel:)` on the **same** `SNAudioStreamAnalyzer` as the built-in request, with the same window and overlap. `CustomSoundClassifier` conforms to `SoundClassifier`. Its labels map to sound groups through `custom_to_group.json` (`car_alarm` → Car Alarm, `smoke_alarm_chirp` → Smoke/Fire Alarm, `appliance_beep` → Alarm/Buzzer/Beep, `crosswalk_signal` → Alarm/Buzzer/Beep; `background` → ignored).
- **Merge**: a `ClassifierMerger` (SoundSightCore) takes the max per group across classifiers for the same window. Thresholds for the custom groups are separate keys in `thresholds.json` (`custom:<label>`), starting at 0.7.
- **Fallback**: if the model fails to load, the app logs a warning and continues with the built-in classifier only.

## 4. Repository layout

```
HackATL/
├── project.yml                     XcodeGen → SoundSight.xcodeproj (generated; git-ignored)
├── SoundSightCore/                       Swift package (iOS 26, macOS 15)
│   ├── Package.swift
│   ├── Sources/SoundSightCore/{DSP,Classification,Fusion}/
│   └── Tests/SoundSightCoreTests/
├── SoundSightApp/
│   ├── App/  Capture/  Classification/  Motion/  Haptics/  UI/  Probe/
│   ├── Resources/{apple_to_group.json, custom_to_group.json, thresholds.json, urgency_map.json, SoundSightCustomSounds.mlmodel}
│   └── Info.plist
├── Training/                       step 7: train.swift (CreateML, macOS), data/ (git-ignored clips), data/LICENSES.csv
├── docs/superpowers/{specs,spikes,plans}/
└── README.md
```

## 5. Build steps

| # | Step | Exit criterion |
|---|---|---|
| 0 | **Scaffold**: XcodeGen project, SoundSightCore package, app shell, README build instructions | App installs and launches on the 16 Pro Max; `swift test` passes |
| 1 | **FOA probe (gate)**: capture path + ProbeView + calibration CSV; run the protocol in §6 | **Median azimuth error ≤ 30° and front/back correct ≥ 90%** (phone flat). `FOAAxisCalibration` determined. If this fails: stop and revisit the fallback. |
| 2 | **DOA estimator** in SoundSightCore | Synthetic tests (§7) pass; error < 5° on a clean plane wave |
| 3 | **Classification**: SoundAnalysis wrapper, LabelMapper, GroupThresholds, UrgencyMap | Unit tests pass; a siren clip on device → Siren / CRITICAL |
| 4 | **Motion + world frame** | A fixed source keeps its world azimuth within ±15° while the phone yaws 90° |
| 5 | **Fusion**: AzimuthBelief + EventTracker | Unit tests pass |
| 6 | **UI + haptics + accessibility**, end-to-end wiring | Success criteria 1–4 met on device |
| 7 | **Custom ML classification system** (after steps 0–6 are complete; §3.8): sample recorder, Create ML training script, second classifier request, group merge | Held-out accuracy ≥ 85% on custom classes; a car-alarm clip on device → Car Alarm / CRITICAL; no regression on the step 6 demo checklist |
| — | *Deferred, later work*: **on-device tuning**: per-window diagnostics CSV, quiet/target recording sessions, threshold and localization-constant re-fit, optional in-app tuning panel, battery/thermal measurement | — |
| — | *Stretch*: pinned alerts, 24 h history, scene profiles, background monitoring (audio-only `AVCaptureSession` in background must be verified first) | — |

## 6. FOA probe protocol (step 1 gate)

- **Setup**: phone flat on a table in a quiet room, top edge = 0°. A Bluetooth or wired speaker at about 1.5 m, at roughly table height, plays pink-noise bursts, then a siren clip, then a knock clip.
- **Directions**: 0°, 45°, …, 315° (8 positions), 10 s each. In ProbeView the tester taps the current true angle; the app logs per-window mean intensity (raw FOA axes), diffuseness and RMS to CSV.
- **Analysis**: find the signed axis permutation and yaw offset that minimize circular error (6 axis orders × 8 sign combinations = 48 candidates, brute force), then report median |error| and the front/back hit rate (|error| < 90°) on held-out sounds.
- **Repeat** once with the phone upright in portrait (back camera facing 0°) to confirm the axis mapping holds in 3-D.
- **Also record**: whether FOA mode works without a video input, the delivered sample format and rate, and the session start latency.
- **Gate**: pass when median ≤ 30° and front/back ≥ 90% with the phone flat. Otherwise stop and present the stereo fallback (plan B) to the user before any further work.

## 7. Testing

**SoundSightCore unit tests (Mac, `swift test`)**
- *DSP*: synthetic SN3D plane waves (noise or tone source) encoded at known azimuth and elevation → estimated azimuth error < 5° across 0–355°; two sources at 0° and 120° with different spectra → two peaks within 10°; added diffuse noise (SNR 6 dB) → error < 15° and diffuseness increases; silent input → no peaks; elevation 60° → azimuth still correct.
- *Rotation*: device → world transforms for identity, 90° yaw and phone upright.
- *Classification*: noisy-OR math (standard noisy-OR cases); every Apple label maps to a known group; thresholds load; urgency lookup.
- *Custom classifier (step 7)*: every custom label maps to a known group or is explicitly ignored; `ClassifierMerger` takes the per-group max and handles a missing classifier; training report shows held-out accuracy ≥ 85%.
- *Fusion*: belief peak is within 5° of the true angle with R ≥ 0.5 after 6 consistent updates; decays back toward uniform without evidence; events are created, refreshed and evicted at 3 s; urgency sort; per-label independence (tracker and belief behaviour).

**On device**: the §6 probe protocol (regression after iOS updates) and the demo checklist: siren / knock / dog from front, back, left and right, with the phone flat and upright; rotate the phone 90° with the source fixed; check haptic tiers; check VoiceOver labels.

## 8. Error handling

| Condition | Behavior |
|---|---|
| Mic or motion permission denied | Explainer screen with a Settings link |
| FOA unsupported / session fails to start | Classification-only mode + "Direction unavailable" banner |
| Interruption (call, Siri, another app takes the mic) | Pause, show banner, resume on interruption end |
| Diffuse or quiet field (diffuseness > 0.8) | No belief update; arrows fade as beliefs decay |
| Motion unavailable | Device-frame radar (no world anchoring), banner |
| Haptic engine reset | Restart engine on `resetHandler` |

## 9. Risks

1. **FOA quality or behavior** (accuracy, axis frame, needing a video input, latency). Mitigated by the step 1 gate.
2. **SoundAnalysis calibration on real mic audio** differs from ESC-50. Mitigated by tunable `thresholds.json` and the deferred on-device tuning work; the TFLite model can be swapped in behind the protocol.
3. **Simultaneous sources** blur together. Accepted for the demo.
4. **Thermal/battery** while continuously capturing at 48 kHz × 4 channels plus FFTs. Measure during the deferred tuning work; reduce the band or window rate if needed.

## 10. Out of scope (demo)
On-device tuning (deferred to later work), distance (near/far) estimation, on-device training of custom sounds, scene profiles, pinned alerts, 24 h history, background monitoring, App Store distribution, iPhone models other than the 16 Pro Max.
