# SoundSight iOS (FOA 360°) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SoundSight hackathon demo for iPhone 16 Pro Max: on-device sound classification with four urgency tiers, and a 360° world-anchored radar driven by First-Order Ambisonics (FOA) direction finding, with haptics and VoiceOver.

**Architecture:** Pure logic (PCM conversion, windowing, FOA intensity, direction of arrival, axis calibration, label mapping, window joining, motion conventions, beliefs, event tracking, alert rules) lives in the `EchoCore` Swift package and is unit-tested on the Mac with `swift test`. A thin SwiftUI app (`EchoApp`, generated with XcodeGen) owns AVFoundation capture, SoundAnalysis, CoreMotion, Core Haptics and the UI. The FOA probe (Tasks 5–6) is a hard gate: no work past Task 6 starts until the probe passes on the phone.

**Tech Stack:** Swift 6.2 / Xcode 26.2, iOS 26.0, SwiftUI + Observation, AVFoundation (`AVCaptureSession` FOA), SoundAnalysis, CoreMotion, Core Haptics, Accelerate (vDSP), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-10-soundsight-ios-foa-design.md` (read it first). Classifier data: `docs/superpowers/spikes/2026-10-10-classifier/`.

**Scope:** Spec build steps 0–6 (Tasks 1–15 here). Spec step 7 (custom Create ML classifier) gets its own plan once this one is finished. On-device tuning is deferred (spec §5).

**Deliberate refinements of the spec** (same behavior, better testability):
- The JSON tables (`apple_to_group.json`, `thresholds.json`, `urgency_map.json`) live in `EchoCore/Sources/EchoCore/Resources/` instead of `EchoApp/Resources/`, so unit tests can check them.
- The `SoundClassifier` protocol takes mono `[Float]` blocks (`analyze(_:)`) rather than `AVAudioPCMBuffer` plus a sample time; the classifier tracks its own frame position.
- `FOAAxisCalibration` is a signed permutation without the optional yaw offset. Task 6 records the mean signed error so an offset can be added during deferred tuning if needed.
- The probe gate also requires samples from at least 6 of the 8 directions (Review Focus 3).
- If FOA is unsupported the capture falls back to mono, which gives the spec's classification-only mode.

## Global Constraints

- iOS deployment target **26.0**; iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait; Swift language mode **6**.
- `EchoCore` platforms: `.iOS(.v26)`, `.macOS(.v15)`; swift-tools-version **6.2**; tests use **Swift Testing** (`import Testing`), not XCTest.
- No third-party dependencies. Apple frameworks only; XcodeGen is a developer tool, not a dependency.
- FOA channel order from capture is **ACN: 0 = W, 1 = Y, 2 = Z, 3 = X** (SN3D). `FOAWindow`/`FOAChunk` store them as `w, x, y, z`.
- Bearing convention everywhere: degrees in [0, 360), **0° = +y (top edge / forward), 90° = +x (right), clockwise seen from above**. Device frame = CoreMotion's (x right, y top edge, z out of the screen).
- Windows: **1.0 s with 50% overlap** at the capture sample rate (48 kHz expected); window starts are multiples of the hop from capture start.
- Classification: Apple `SNClassifySoundRequest(.version1)`, `windowDuration = 1.0 s`, `overlapFactor = 0.5`, fed the W channel. Groups and urgency tiers are the 42 starting groups (`urgency_map.json`), thresholds from `thresholds.json`.
- Tracker constants: evict **3 s** after last seen; confidence EMA α = **0.5**; skip belief updates when diffuseness > **0.8**; draw arrows only when belief concentration R ≥ **0.5**; haptic cooldown **5 s** per group.
- Bundle identifier `com.hackatl.soundsight`. Signing comes from the git-ignored `EchoApp/Config/Signing.xcconfig`; never commit a team ID.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Work on branch `ios-foa-design` (already created; the spec is committed there).

## Review Focus

1. **A sample rate other than 48 kHz** (the HAL may deliver 44.1 kHz): windows must still be exactly 1 s / 0.5 s hop, and the FFT band must still cover 200–8000 Hz. Pinned in Task 2 (`oneSecondWindowsAtAnyRate`) and Task 3 (`binRangeAt48k` checks 44.1 kHz and 16 kHz).
2. **Irregular capture buffer sizes** (AVFoundation picks chunk lengths): windows must be identical to feeding one long buffer. Pinned in Task 2 (`irregularChunksGiveSameWindowsAsOneChunk`).
3. **Calibration recorded at only a few directions**: several axis mappings fit equally well, so the gate must not report a pass. Pinned in Task 4 (`gateNeedsSixDirections`).
4. **SoundAnalysis windows drifting off the hop grid**: directions must still pair with the nearest classifier window instead of silently disappearing. Pinned in Task 9 (`classifierWindowsDriftingOffGridStillMostlyJoin`).
5. **Phone lying face-down** on a table: it must count as "flat", with forward = top edge, not flip to upright. Pinned in Task 10 (`faceDownCountsAsFlat`).

## File Structure

```
HackATL/
├── project.yml                                   XcodeGen spec (Task 1)
├── .gitignore                                    (Task 1)
├── README.md                                     build/run/test instructions (Task 1)
├── EchoCore/
│   ├── Package.swift                             (Task 1; resources added in Task 8)
│   ├── Sources/EchoCore/
│   │   ├── DSP/Circular.swift                    bearings, circular stats (Task 1)
│   │   ├── Audio/FOAWindow.swift                 one 1 s FOA window (Task 2)
│   │   ├── Audio/PCMDeinterleaver.swift          raw PCM → per-channel Float (Task 2)
│   │   ├── Audio/WindowAccumulator.swift         chunks → overlapping windows (Task 2)
│   │   ├── DSP/IntensityAnalyzer.swift           STFT → per-bin intensity, diffuseness (Task 3)
│   │   ├── DSP/FOAAxisCalibration.swift          raw FOA axes → device axes; probe fitter (Task 4)
│   │   ├── DSP/DOAEstimator.swift                world-frame histogram → peaks (Task 7)
│   │   ├── Classification/Urgency.swift          (Task 8)
│   │   ├── Classification/UrgencyMap.swift       (Task 8)
│   │   ├── Classification/LabelMapper.swift      noisy-OR label → group (Task 8)
│   │   ├── Classification/GroupThresholds.swift  (Task 8)
│   │   ├── Classification/ClassificationResources.swift  bundled JSON loader (Task 8)
│   │   ├── Classification/WindowJoiner.swift     pairs classifier + DOA windows (Task 9)
│   │   ├── Motion/RotationConvention.swift       resolves CMAttitude matrix direction (Task 10)
│   │   ├── Motion/ForwardHeading.swift           flat/upright forward + radar angle (Task 10)
│   │   ├── Fusion/AzimuthBelief.swift            per-label 72-bin belief (Task 11)
│   │   ├── Fusion/EventTracker.swift             active events, eviction, sorting (Task 11)
│   │   ├── Alerts/HapticGate.swift               tier + cooldown rule (Task 12)
│   │   ├── Alerts/DirectionPhrase.swift          VoiceOver clock phrases (Task 12)
│   │   └── Resources/{apple_to_group,thresholds,urgency_map}.json   (Task 8)
│   └── Tests/EchoCoreTests/                      one test file per source area; Support/FOASynth.swift
└── EchoApp/
    ├── Config/App.xcconfig, Config/Signing.xcconfig.example     (Task 1)
    ├── App/SoundSightApp.swift                       (Task 1, replaced in Task 5)
    ├── App/AppModel.swift                        probe model (Task 5) → full model (Task 13)
    ├── Capture/FOABufferAdapter.swift            CMSampleBuffer → FOAChunk (Task 5)
    ├── Capture/FOACaptureSession.swift           AVCaptureSession FOA / mono fallback (Task 5)
    ├── Capture/AudioPipeline.swift               probe pipeline (Task 5) → full pipeline (Task 13)
    ├── Probe/ProbeState.swift, Probe/ProbeView.swift            (Task 5)
    ├── UI/StatusBanner.swift, UI/RadarGeometry.swift            (Task 5)
    ├── UI/MainView.swift                         (Task 5 → Task 13 → Task 14)
    ├── Classification/SoundAnalysisClassifier.swift             (Task 13)
    ├── Motion/MotionProvider.swift                              (Task 13)
    ├── Haptics/HapticsManager.swift                             (Task 13)
    ├── UI/UrgencyStyle.swift, UI/EventListView.swift            (Task 13)
    └── UI/RadarView.swift                                       (Task 14)
```

**Commands used throughout** (run from the repo root):
- Core tests: `swift test --package-path EchoCore`
- App build check (no signing): `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
- Install on the phone (human): open `SoundSight.xcodeproj`, choose the iPhone 16 Pro Max as the destination, press Run.

---

### Task 1: Scaffold the repo, EchoCore package and app shell

**Files:**
- Create: `project.yml`, `.gitignore`, `EchoApp/Config/App.xcconfig`, `EchoApp/Config/Signing.xcconfig.example`, `EchoApp/App/SoundSightApp.swift`
- Create: `EchoCore/Package.swift`, `EchoCore/Sources/EchoCore/DSP/Circular.swift`
- Test: `EchoCore/Tests/EchoCoreTests/CircularTests.swift`
- Modify: `README.md` (replace the one-line placeholder)

**Interfaces:**
- Produces: `Circular.wrap360(_:)`, `Circular.difference(_:_:)`, `Circular.vonMises(_:kappa:)`, `Circular.bearing(_: SIMD3<Float>) -> Double`, `Circular.unitVector(bearing:elevation:) -> SIMD3<Float>`, `Circular.mean(_:weights:) -> Double?`, `Circular.median(_:) -> Double?`. Every later task uses these.

- [ ] **Step 1: Check tools**

Run: `xcodebuild -version && swift --version && xcodegen --version`
Expected: Xcode 26.2+, Swift 6.2+, an XcodeGen version. If `xcodegen` is missing, stop and ask the human to run `! brew install xcodegen`.

- [ ] **Step 2: Create the package manifest**

`EchoCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "EchoCore", targets: ["EchoCore"])],
    targets: [
        .target(name: "EchoCore"),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"]),
    ]
)
```

- [ ] **Step 3: Write the failing test**

`EchoCore/Tests/EchoCoreTests/CircularTests.swift`:

```swift
import Testing
import simd
@testable import EchoCore

struct CircularTests {
    @Test func wrapsIntoRange() {
        #expect(Circular.wrap360(370) == 10)
        #expect(Circular.wrap360(-10) == 350)
        #expect(Circular.wrap360(-1e-15) < 360)
        #expect(Circular.wrap360(720) == 0)
    }

    @Test func differenceIsShortestSigned() {
        #expect(Circular.difference(10, 350) == 20)
        #expect(Circular.difference(350, 10) == -20)
        #expect(Circular.difference(180, 0) == 180)
    }

    @Test func bearingConvention() {
        #expect(abs(Circular.bearing(SIMD3(0, 1, 0)) - 0) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(1, 0, 0)) - 90) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(0, -1, 0)) - 180) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(-1, 0, 0)) - 270) < 1e-6)
    }

    @Test func unitVectorRoundTrips() {
        for b in stride(from: 0.0, to: 360, by: 15) {
            let v = Circular.unitVector(bearing: b, elevation: 30)
            #expect(abs(Circular.difference(Circular.bearing(v), b)) < 1e-3)
            #expect(abs(simd_length(v) - 1) < 1e-5)
        }
    }

    @Test func circularMeanAcrossZero() {
        let m = Circular.mean([350, 10], weights: [1, 1])!
        #expect(abs(Circular.difference(m, 0)) < 1e-9)
        #expect(Circular.mean([0, 180], weights: [1, 1]) == nil)
    }

    @Test func vonMisesPeaksAtZero() {
        #expect(Circular.vonMises(0, kappa: 6) == 1)
        #expect(Circular.vonMises(90, kappa: 6) < 0.01)
    }

    @Test func medianOddEven() {
        #expect(Circular.median([3, 1, 2]) == 2)
        #expect(Circular.median([4, 1, 2, 3]) == 2.5)
        #expect(Circular.median([]) == nil)
    }
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'Circular' in scope` (SwiftPM may also complain that the `EchoCore` target has no sources).

- [ ] **Step 5: Implement `Circular`**

`EchoCore/Sources/EchoCore/DSP/Circular.swift`:

```swift
import Foundation
import simd

/// Angle helpers. Bearings are degrees in [0, 360): 0° = +y (device top / world "north"),
/// 90° = +x (right), increasing clockwise when viewed from +z (above).
public enum Circular {
    /// Wraps any angle in degrees into [0, 360).
    public static func wrap360(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        let w = r < 0 ? r + 360 : r
        return w >= 360 ? 0 : w
    }

    /// Smallest signed difference `a − b` in degrees, in (−180, 180].
    public static func difference(_ a: Double, _ b: Double) -> Double {
        let d = wrap360(a - b)
        return d > 180 ? d - 360 : d
    }

    /// Unnormalized von Mises kernel: 1 at Δ = 0, falling off with |Δ|.
    public static func vonMises(_ deltaDegrees: Double, kappa: Double) -> Double {
        exp(kappa * (cos(deltaDegrees * .pi / 180) - 1))
    }

    /// Bearing of the horizontal (x, y) part of `v`.
    public static func bearing(_ v: SIMD3<Float>) -> Double {
        wrap360(atan2(Double(v.x), Double(v.y)) * 180 / .pi)
    }

    /// Unit vector for a bearing and elevation (degrees), same convention as `bearing`.
    public static func unitVector(bearing: Double, elevation: Double = 0) -> SIMD3<Float> {
        let b = bearing * .pi / 180
        let e = elevation * .pi / 180
        return SIMD3(Float(cos(e) * sin(b)), Float(cos(e) * cos(b)), Float(sin(e)))
    }

    /// Weighted circular mean (degrees) of `angles`; nil when the weights cancel out.
    public static func mean(_ angles: [Double], weights: [Double]) -> Double? {
        var s = 0.0, c = 0.0
        for (a, w) in zip(angles, weights) {
            s += w * sin(a * .pi / 180)
            c += w * cos(a * .pi / 180)
        }
        guard s * s + c * c > 1e-18 else { return nil }
        return wrap360(atan2(s, c) * 180 / .pi)
    }

    /// Median of `values` (nil when empty).
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 7 tests in 1 suite passed`.

- [ ] **Step 7: Create the XcodeGen project and app shell**

`project.yml`:

```yaml
name: SoundSight
options:
  bundleIdPrefix: com.hackatl
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  EchoCore:
    path: EchoCore
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  SoundSight:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: EchoApp
        excludes:
          - "Config/**"
          - "Info.plist"
    dependencies:
      - package: EchoCore
    configFiles:
      Debug: EchoApp/Config/App.xcconfig
      Release: EchoApp/Config/App.xcconfig
    info:
      path: EchoApp/Info.plist
      properties:
        CFBundleDisplayName: SoundSight
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSMicrophoneUsageDescription: SoundSight listens to the sounds around you to identify them and show where they come from. Audio never leaves your iPhone.
        NSMotionUsageDescription: SoundSight uses motion sensors to keep sound directions fixed as you turn.
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hackatl.soundsight
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
```

`EchoApp/Config/App.xcconfig`:

```text
// Shared app settings. Personal signing lives in the git-ignored Signing.xcconfig
// (copy Signing.xcconfig.example and set your team ID).
CODE_SIGN_STYLE = Automatic
#include? "Signing.xcconfig"
```

`EchoApp/Config/Signing.xcconfig.example`:

```text
// Copy to Signing.xcconfig (git-ignored) and set your Apple Developer team ID.
// Find it in Xcode → Settings → Accounts, or developer.apple.com → Membership.
DEVELOPMENT_TEAM = ABCDE12345
```

`EchoApp/App/SoundSightApp.swift`:

```swift
import SwiftUI

@main
struct SoundSightApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SoundSight")
                .font(.largeTitle.bold())
        }
    }
}
```

`.gitignore`:

```text
# Generated by XcodeGen (run `xcodegen generate`)
SoundSight.xcodeproj/
EchoApp/Info.plist

# Personal signing settings
EchoApp/Config/Signing.xcconfig

# Build products
.build/
DerivedData/
.swiftpm/
xcuserdata/
*.xcuserstate
.DS_Store
```

`README.md` (replace the whole file):

````markdown
# SoundSight for iPhone

Real-time, on-device sound awareness for deaf and hard-of-hearing users: an iOS app for the **iPhone 16 Pro Max**. It classifies environmental sounds, ranks their urgency, and shows where each one is coming from on a full 360° radar, using the phone's microphone array as First-Order Ambisonics (FOA).

Design: [`docs/superpowers/specs/2026-10-10-soundsight-ios-foa-design.md`](docs/superpowers/specs/2026-10-10-soundsight-ios-foa-design.md)

## Requirements

- iPhone 16 Pro Max on iOS 26 (FOA capture doesn't work in the Simulator)
- Xcode 26.2 or newer, macOS 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple Developer account (a free personal team works; its builds expire after 7 days)

## Build and run

```sh
cp EchoApp/Config/Signing.xcconfig.example EchoApp/Config/Signing.xcconfig   # then set DEVELOPMENT_TEAM
xcodegen generate
open SoundSight.xcodeproj
```

Select your iPhone as the run destination and press Run. Re-run `xcodegen generate` after adding or removing files.

## Tests

The DSP, classification-mapping and fusion logic lives in the `EchoCore` Swift package and is tested on the Mac:

```sh
swift test --package-path EchoCore
```

## Layout

| Path | What |
|---|---|
| `EchoCore/` | Pure Swift logic: FOA intensity, direction finding, axis calibration, label mapping, event tracking |
| `EchoApp/` | iOS app: capture, SoundAnalysis, motion, haptics, SwiftUI, FOA probe |
| `docs/superpowers/` | Spec, spike results and implementation plans |
````

- [ ] **Step 8: Build the app for a generic iOS device**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
Expected: `⚙️  Generating plists...` / `Created project at …`, then the build finishes with no `error:` lines. If XcodeGen rejects `scheme: {}`, replace it with a top-level `schemes:` entry `SoundSight: { build: { targets: { SoundSight: all } } }` and rerun.

- [ ] **Step 9: Human check: install on the iPhone**

Ask the human to `cp EchoApp/Config/Signing.xcconfig.example EchoApp/Config/Signing.xcconfig`, set their team ID, run `xcodegen generate`, open `SoundSight.xcodeproj`, and Run on the iPhone 16 Pro Max.
Expected: the app launches and shows "SoundSight". Wait for confirmation before committing.

- [ ] **Step 10: Commit**

```bash
git add project.yml .gitignore README.md EchoApp EchoCore
git commit -m "Scaffold SoundSight iOS app and EchoCore package" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: FOA windows, PCM conversion and window accumulation

**Files:**
- Create: `EchoCore/Sources/EchoCore/Audio/FOAWindow.swift`, `EchoCore/Sources/EchoCore/Audio/PCMDeinterleaver.swift`, `EchoCore/Sources/EchoCore/Audio/WindowAccumulator.swift`
- Test: `EchoCore/Tests/EchoCoreTests/AudioTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct FOAWindow { var w, x, y, z: [Float]; var sampleRate: Double; var startSample: Int64 }` (memberwise `init(w:x:y:z:sampleRate:startSample:)`).
  - `struct PCMLayout { enum SampleType { case float32, int16, int32 }; init(sampleType:channelCount:interleaved:) }`.
  - `PCMDeinterleaver.deinterleave(buffers: [UnsafeRawBufferPointer], layout: PCMLayout) -> [[Float]]`.
  - `struct WindowAccumulator { init(windowLength:hopLength:); static func forSampleRate(_:) -> WindowAccumulator; let windowLength, hopLength: Int; mutating func append(w:x:y:z:sampleRate:) -> [FOAWindow]; mutating func reset() }`.

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/AudioTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'PCMDeinterleaver' in scope` and `cannot find 'WindowAccumulator' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/Audio/FOAWindow.swift`:

```swift
/// One analysis window of First-Order Ambisonics audio. Channels are the raw FOA
/// components (ACN/SN3D): `w` omni, `x`/`y`/`z` dipoles in the FOA's own axes.
public struct FOAWindow: Sendable {
    public var w: [Float]
    public var x: [Float]
    public var y: [Float]
    public var z: [Float]
    public var sampleRate: Double
    /// Absolute index of the first sample since capture started.
    public var startSample: Int64

    public init(w: [Float], x: [Float], y: [Float], z: [Float], sampleRate: Double, startSample: Int64) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
        self.sampleRate = sampleRate
        self.startSample = startSample
    }
}
```

`EchoCore/Sources/EchoCore/Audio/PCMDeinterleaver.swift`:

```swift
/// Describes linear PCM as delivered by Core Audio.
public struct PCMLayout: Sendable, Equatable {
    public enum SampleType: Sendable, Equatable { case float32, int16, int32 }

    public var sampleType: SampleType
    public var channelCount: Int
    public var interleaved: Bool

    public init(sampleType: SampleType, channelCount: Int, interleaved: Bool) {
        self.sampleType = sampleType
        self.channelCount = channelCount
        self.interleaved = interleaved
    }

    var bytesPerSample: Int {
        switch sampleType {
        case .float32, .int32: 4
        case .int16: 2
        }
    }
}

public enum PCMDeinterleaver {
    /// Converts raw PCM into one Float array per channel, scaled to [-1, 1].
    /// - Parameter buffers: one buffer when `layout.interleaved`, otherwise one per channel.
    public static func deinterleave(buffers: [UnsafeRawBufferPointer], layout: PCMLayout) -> [[Float]] {
        let bps = layout.bytesPerSample
        if layout.interleaved {
            guard let buf = buffers.first else { return Array(repeating: [], count: layout.channelCount) }
            let frames = buf.count / (bps * layout.channelCount)
            return (0..<layout.channelCount).map { ch in
                (0..<frames).map { f in read(buf, offset: (f * layout.channelCount + ch) * bps, layout.sampleType) }
            }
        }
        return (0..<layout.channelCount).map { ch in
            guard ch < buffers.count else { return [] }
            let buf = buffers[ch]
            return (0..<(buf.count / bps)).map { f in read(buf, offset: f * bps, layout.sampleType) }
        }
    }

    private static func read(_ buf: UnsafeRawBufferPointer, offset: Int, _ type: PCMLayout.SampleType) -> Float {
        switch type {
        case .float32: buf.loadUnaligned(fromByteOffset: offset, as: Float.self)
        case .int16: Float(buf.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
        case .int32: Float(buf.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2_147_483_648
        }
    }
}
```

`EchoCore/Sources/EchoCore/Audio/WindowAccumulator.swift`:

```swift
/// Buffers incoming FOA chunks and emits fixed-length overlapping windows whose
/// start samples are multiples of `hopLength` from capture start.
public struct WindowAccumulator: Sendable {
    public let windowLength: Int
    public let hopLength: Int
    private var w: [Float] = []
    private var x: [Float] = []
    private var y: [Float] = []
    private var z: [Float] = []
    private var bufferStart: Int64 = 0

    public init(windowLength: Int, hopLength: Int) {
        precondition(windowLength > 0 && hopLength > 0 && hopLength <= windowLength)
        self.windowLength = windowLength
        self.hopLength = hopLength
    }

    /// Appends equal-length channel chunks; returns every window that became complete.
    public mutating func append(w: [Float], x: [Float], y: [Float], z: [Float], sampleRate: Double) -> [FOAWindow] {
        precondition(w.count == x.count && x.count == y.count && y.count == z.count, "channel lengths differ")
        self.w += w
        self.x += x
        self.y += y
        self.z += z
        var out: [FOAWindow] = []
        while self.w.count >= windowLength {
            out.append(FOAWindow(
                w: Array(self.w[0..<windowLength]), x: Array(self.x[0..<windowLength]),
                y: Array(self.y[0..<windowLength]), z: Array(self.z[0..<windowLength]),
                sampleRate: sampleRate, startSample: bufferStart))
            self.w.removeFirst(hopLength)
            self.x.removeFirst(hopLength)
            self.y.removeFirst(hopLength)
            self.z.removeFirst(hopLength)
            bufferStart += Int64(hopLength)
        }
        return out
    }

    /// 1 s windows with 50% overlap at any sample rate (spec §3: same cadence as the reference design).
    public static func forSampleRate(_ sampleRate: Double) -> WindowAccumulator {
        let window = max(2, Int(sampleRate.rounded()))
        return WindowAccumulator(windowLength: window, hopLength: window / 2)
    }

    public mutating func reset() {
        w = []
        x = []
        y = []
        z = []
        bufferStart = 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 14 tests in 3 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add FOA windows, PCM deinterleaving and window accumulation" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: FOA intensity analysis and synthetic FOA test signals

**Files:**
- Create: `EchoCore/Sources/EchoCore/DSP/IntensityAnalyzer.swift`
- Create (test support): `EchoCore/Tests/EchoCoreTests/Support/FOASynth.swift`
- Test: `EchoCore/Tests/EchoCoreTests/IntensityAnalyzerTests.swift`

**Interfaces:**
- Consumes: `FOAWindow` (Task 2), `Circular` (Task 1).
- Produces:
  - `struct IntensityConfig` (fftSize 1024, hopSize 512, minHz 200, maxHz 8000, noiseFloorPercentile 0.2, absoluteEnergyFloor 1e-9).
  - `struct BinIntensity { var raw: SIMD3<Float>; var energy: Float }`.
  - `struct IntensityResult { var bins: [BinIntensity]; var diffuseness: Float; var summedRaw: SIMD3<Float>; var totalEnergy: Float }`.
  - `final class IntensityAnalyzer { init(config:) throws; func binRange(sampleRate:) -> ClosedRange<Int>; func analyze(_: FOAWindow) -> IntensityResult }`.
  - Test helpers: `SeededRNG(seed:)`, `FOASynth.whiteNoise/tones/planeWave/mix/diffuseNoise/silence` (used again in Tasks 4 and 7).

The math (spec §3.3): for SN3D first order, a plane wave from unit direction **u** gives W = s and (X, Y, Z) = s·**u**. Per STFT bin the active intensity **I** = Re(W*·[X, Y, Z]) points at the source, and energy E = ½(|W|² + |X|² + |Y|² + |Z|²). For one plane wave |Σ**I**| = ΣE, so diffuseness 1 − |Σ**I**|/ΣE is 0; uncorrelated sound from all directions cancels in Σ**I**, so it tends toward 1.

- [ ] **Step 1: Write the test support and failing tests**

`EchoCore/Tests/EchoCoreTests/Support/FOASynth.swift`:

```swift
import Foundation
@testable import EchoCore

/// Deterministic SplitMix64 generator so synthetic tests are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds synthetic SN3D first-order ambisonic signals. With `.identity` calibration the
/// raw FOA axes equal the device axes, so `bearing`/`elevation` are device-frame angles.
enum FOASynth {
    static let sampleRate = 48_000.0
    static let windowLength = 48_000

    static func whiteNoise(count: Int = windowLength, amplitude: Float = 0.1, rng: inout SeededRNG) -> [Float] {
        (0..<count).map { _ in Float.random(in: -amplitude...amplitude, using: &rng) }
    }

    /// Sum of `toneCount` random-phase sinusoids with frequencies drawn from `band` (Hz).
    static func tones(count: Int = windowLength, band: ClosedRange<Double>, toneCount: Int = 40,
                      amplitude: Float = 0.02, rng: inout SeededRNG) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for _ in 0..<toneCount {
            let f = Double.random(in: band, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            for n in 0..<count { out[n] += amplitude * Float(sin(2 * .pi * f * Double(n) / sampleRate + phase)) }
        }
        return out
    }

    static func planeWave(_ s: [Float], bearing: Double, elevation: Double = 0, startSample: Int64 = 0) -> FOAWindow {
        let u = Circular.unitVector(bearing: bearing, elevation: elevation)
        return FOAWindow(w: s, x: s.map { $0 * u.x }, y: s.map { $0 * u.y }, z: s.map { $0 * u.z },
                         sampleRate: sampleRate, startSample: startSample)
    }

    static func mix(_ a: FOAWindow, _ b: FOAWindow) -> FOAWindow {
        func add(_ p: [Float], _ q: [Float]) -> [Float] { zip(p, q).map { $0 + $1 } }
        return FOAWindow(w: add(a.w, b.w), x: add(a.x, b.x), y: add(a.y, b.y), z: add(a.z, b.z),
                         sampleRate: a.sampleRate, startSample: a.startSample)
    }

    /// Approximates a diffuse field: many uncorrelated noise plane waves from random directions.
    static func diffuseNoise(sources: Int = 48, totalAmplitude: Float, rng: inout SeededRNG) -> FOAWindow {
        let per = totalAmplitude / Float(Double(sources).squareRoot())
        var acc = planeWave([Float](repeating: 0, count: windowLength), bearing: 0)
        for _ in 0..<sources {
            let s = whiteNoise(amplitude: per, rng: &rng)
            acc = mix(acc, planeWave(s, bearing: Double.random(in: 0..<360, using: &rng),
                                     elevation: Double.random(in: -60...60, using: &rng)))
        }
        return acc
    }

    static let silence = planeWave([Float](repeating: 0, count: windowLength), bearing: 0)
}
```

`EchoCore/Tests/EchoCoreTests/IntensityAnalyzerTests.swift`:

```swift
import Testing
@testable import EchoCore

struct IntensityAnalyzerTests {
    let analyzer = try! IntensityAnalyzer()

    @Test func binRangeAt48k() {
        #expect(analyzer.binRange(sampleRate: 48_000) == 5...170)
        #expect(analyzer.binRange(sampleRate: 44_100) == 5...185)
        #expect(analyzer.binRange(sampleRate: 16_000) == 13...512)
    }

    @Test func planeWavePointsAtSourceAndIsNotDiffuse() {
        var rng = SeededRNG(seed: 1)
        for bearing in stride(from: 0.0, to: 360, by: 40) {
            let r = analyzer.analyze(FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: bearing))
            #expect(abs(Circular.difference(Circular.bearing(r.summedRaw), bearing)) < 1)
            #expect(r.diffuseness < 0.05)
            #expect(!r.bins.isEmpty)
        }
    }

    @Test func silenceProducesNoBins() {
        let r = analyzer.analyze(FOASynth.silence)
        #expect(r.bins.isEmpty)
        #expect(r.diffuseness == 1)
        #expect(r.totalEnergy == 0)
    }

    @Test func diffuseFieldIsDiffuse() {
        var rng = SeededRNG(seed: 2)
        let r = analyzer.analyze(FOASynth.diffuseNoise(totalAmplitude: 0.1, rng: &rng))
        #expect(r.diffuseness > 0.6)
    }

    @Test func shortWindowYieldsNoFrames() {
        let r = analyzer.analyze(FOASynth.planeWave([Float](repeating: 0.1, count: 512), bearing: 0))
        #expect(r.bins.isEmpty)
        #expect(r.diffuseness == 1)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'IntensityAnalyzer' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/DSP/IntensityAnalyzer.swift`:

```swift
import Accelerate
import simd

public struct IntensityConfig: Sendable {
    public var fftSize = 1024
    public var hopSize = 512
    public var minHz = 200.0
    public var maxHz = 8000.0
    /// Bins at or below this percentile of the window's bin energies are dropped.
    public var noiseFloorPercentile = 0.2
    /// Bins at or below this absolute energy are always dropped (digital silence).
    public var absoluteEnergyFloor: Float = 1e-9

    public init() {}
}

/// Active intensity of one STFT bin, in raw FOA axes: (Re(W*X), Re(W*Y), Re(W*Z)).
public struct BinIntensity: Sendable {
    public var raw: SIMD3<Float>
    public var energy: Float
}

public struct IntensityResult: Sendable {
    /// Bins that passed the band and noise-floor filters.
    public var bins: [BinIntensity]
    /// 1 − |Σ I| / Σ E over kept bins: 0 for a single plane wave, → 1 for a diffuse field.
    public var diffuseness: Float
    /// Σ I over kept bins (raw FOA axes). Its direction is the energy-weighted arrival direction.
    public var summedRaw: SIMD3<Float>
    public var totalEnergy: Float
}

/// Turns an FOA window into per-bin active-intensity vectors.
public final class IntensityAnalyzer {
    public let config: IntensityConfig
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]

    public init(config: IntensityConfig = .init()) throws {
        self.config = config
        dft = try vDSP.DiscreteFourierTransform(
            count: config.fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: config.fftSize, isHalfWindow: false)
    }

    /// Inclusive FFT bin range kept for a sample rate.
    public func binRange(sampleRate: Double) -> ClosedRange<Int> {
        let n = Double(config.fftSize)
        let lo = max(1, Int((config.minHz * n / sampleRate).rounded(.up)))
        let hi = min(config.fftSize / 2, Int((config.maxHz * n / sampleRate).rounded(.down)))
        return lo...max(lo, hi)
    }

    public func analyze(_ win: FOAWindow) -> IntensityResult {
        let n = config.fftSize
        let range = binRange(sampleRate: win.sampleRate)
        let zeros = [Float](repeating: 0, count: n)
        var all: [BinIntensity] = []
        var start = 0
        while start + n <= win.w.count {
            let spectra = [win.w, win.x, win.y, win.z].map { ch -> (re: [Float], im: [Float]) in
                let frame = vDSP.multiply(ch[start..<(start + n)], window)
                let out = dft.transform(real: frame, imaginary: zeros)
                return (out.real, out.imaginary)
            }
            let (wr, wi) = spectra[0]
            for k in range {
                let i = SIMD3<Float>(
                    wr[k] * spectra[1].re[k] + wi[k] * spectra[1].im[k],
                    wr[k] * spectra[2].re[k] + wi[k] * spectra[2].im[k],
                    wr[k] * spectra[3].re[k] + wi[k] * spectra[3].im[k])
                var e = wr[k] * wr[k] + wi[k] * wi[k]
                for c in 1...3 { e += spectra[c].re[k] * spectra[c].re[k] + spectra[c].im[k] * spectra[c].im[k] }
                all.append(BinIntensity(raw: i, energy: 0.5 * e))
            }
            start += config.hopSize
        }
        guard !all.isEmpty else { return IntensityResult(bins: [], diffuseness: 1, summedRaw: .zero, totalEnergy: 0) }
        let sorted = all.map(\.energy).sorted()
        let pIndex = min(sorted.count - 1, Int(Double(sorted.count) * config.noiseFloorPercentile))
        let floor = max(sorted[pIndex], config.absoluteEnergyFloor)
        let kept = all.filter { $0.energy > floor }
        let sum = kept.reduce(SIMD3<Float>.zero) { $0 + $1.raw }
        let energy = kept.reduce(Float(0)) { $0 + $1.energy }
        let diffuseness = energy > 0 ? max(0, min(1, 1 - simd_length(sum) / energy)) : 1
        return IntensityResult(bins: kept, diffuseness: diffuseness, summedRaw: sum, totalEnergy: energy)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 19 tests in 4 suites passed` (the synthetic tests take a few seconds in debug builds).

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add FOA active-intensity analysis with synthetic signal tests" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: FOA axis calibration and the probe fitter

**Files:**
- Create: `EchoCore/Sources/EchoCore/DSP/FOAAxisCalibration.swift`
- Test: `EchoCore/Tests/EchoCoreTests/CalibrationTests.swift`

**Interfaces:**
- Consumes: `Circular` (Task 1), `SeededRNG` (Task 3 test support).
- Produces:
  - `struct FOAAxisCalibration: Codable, Equatable { var rows: [[Float]]; var matrix: simd_float3x3; func toDevice(_:) -> SIMD3<Float>; static let identity; static let initialGuess; static func allProperSignedPermutations() -> [FOAAxisCalibration] }`.
  - `struct CalibrationSample: Codable { var trueBearing: Double; var raw: SIMD3<Float> }`.
  - `struct CalibrationFit { calibration, medianAbsError, frontBackHitRate, meanSignedError, sampleCount, distinctAngles; var passesGate: Bool; static let minDistinctAngles = 6 }`.
  - `CalibrationFitter.evaluate(_:samples:) -> CalibrationFit?`, `CalibrationFitter.fit(_:) -> CalibrationFit?`.

Why only 24 candidates: the mapping from FOA axes to device axes is a rotation made of axis swaps and sign flips. Requiring determinant +1 (a real rotation, not a mirror) leaves 24 signed permutations. With the phone flat, the fitter only sees bearings, which fixes the device x and y rows; the z row is then forced by the determinant.

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/CalibrationTests.swift`:

```swift
import Foundation
import Testing
import simd
@testable import EchoCore

struct CalibrationTests {
    @Test func twentyFourProperPermutations() {
        let all = FOAAxisCalibration.allProperSignedPermutations()
        #expect(all.count == 24)
        #expect(Set(all.map(\.rows)).count == 24)
        #expect(all.allSatisfy { simd_determinant($0.matrix) == 1 })
        #expect(all.contains(FOAAxisCalibration.initialGuess))
    }

    @Test func initialGuessMapsFOAFrontToBackCamera() {
        // FOA front (+X) should land on device −z (the back-camera direction).
        #expect(FOAAxisCalibration.initialGuess.toDevice(SIMD3(1, 0, 0)) == SIMD3(0, 0, -1))
    }

    private func samples(truth: FOAAxisCalibration, noiseDegrees: Double, rng: inout SeededRNG) -> [CalibrationSample] {
        stride(from: 0.0, to: 360, by: 45).flatMap { b in
            (0..<5).map { _ in
                let jitter = Double.random(in: -noiseDegrees...noiseDegrees, using: &rng)
                let device = Circular.unitVector(bearing: b + jitter)
                return CalibrationSample(trueBearing: b, raw: truth.matrix.transpose * device)
            }
        }
    }

    @Test func fitRecoversEveryCalibration() {
        var rng = SeededRNG(seed: 3)
        for truth in FOAAxisCalibration.allProperSignedPermutations() {
            let fit = CalibrationFitter.fit(samples(truth: truth, noiseDegrees: 10, rng: &rng))!
            #expect(fit.calibration == truth)
            #expect(fit.medianAbsError < 10)
            #expect(fit.frontBackHitRate == 1)
            #expect(fit.passesGate)
        }
    }

    @Test func gateFailsOnNoise() {
        var rng = SeededRNG(seed: 4)
        let junk = (0..<40).map { _ in
            CalibrationSample(trueBearing: Double(Int.random(in: 0..<8, using: &rng)) * 45,
                              raw: SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng),
                                         Float.random(in: -1...1, using: &rng)))
        }
        #expect(CalibrationFitter.fit(junk)!.passesGate == false)
    }

    @Test func gateNeedsSixDirections() {
        var rng = SeededRNG(seed: 5)
        let all = samples(truth: .initialGuess, noiseDegrees: 5, rng: &rng)
        let three = all.filter { [0.0, 45, 90].contains($0.trueBearing) }
        let fit = CalibrationFitter.fit(three)!
        #expect(fit.distinctAngles == 3)
        #expect(fit.medianAbsError < 10)
        #expect(fit.passesGate == false)
        #expect(CalibrationFitter.fit(all)!.distinctAngles == 8)
    }

    @Test func emptySamplesGiveNoFit() {
        #expect(CalibrationFitter.fit([]) == nil)
    }

    @Test func calibrationRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(FOAAxisCalibration.initialGuess)
        #expect(try JSONDecoder().decode(FOAAxisCalibration.self, from: data) == .initialGuess)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'FOAAxisCalibration' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/DSP/FOAAxisCalibration.swift`:

```swift
import simd

/// Maps raw FOA dipole axes (X, Y, Z) onto the device frame
/// (x → right edge, y → top edge, z → out of the screen), as a proper signed permutation.
public struct FOAAxisCalibration: Codable, Sendable, Equatable {
    /// Row-major 3×3 matrix: device = rows · raw.
    public var rows: [[Float]]

    public init(rows: [[Float]]) {
        precondition(rows.count == 3 && rows.allSatisfy { $0.count == 3 })
        self.rows = rows
    }

    public var matrix: simd_float3x3 {
        simd_float3x3(rows: rows.map { SIMD3($0[0], $0[1], $0[2]) })
    }

    public func toDevice(_ raw: SIMD3<Float>) -> SIMD3<Float> { matrix * raw }

    /// Raw axes are already device axes (used by synthetic tests).
    public static let identity = FOAAxisCalibration(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    /// Pre-probe guess: FOA front (X) = back-camera direction (−z), left (Y) = −x, up (Z) = +y,
    /// i.e. the ambisonic scene of a portrait video. Replaced by the probe's fitted calibration.
    public static let initialGuess = FOAAxisCalibration(rows: [[0, -1, 0], [0, 0, 1], [-1, 0, 0]])

    /// All 24 signed permutation matrices with determinant +1.
    public static func allProperSignedPermutations() -> [FOAAxisCalibration] {
        let perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var out: [FOAAxisCalibration] = []
        for p in perms {
            for signs in 0..<8 {
                var rows = [[Float]](repeating: [0, 0, 0], count: 3)
                for r in 0..<3 { rows[r][p[r]] = (signs >> r) & 1 == 0 ? 1 : -1 }
                let cal = FOAAxisCalibration(rows: rows)
                if simd_determinant(cal.matrix) > 0 { out.append(cal) }
            }
        }
        return out
    }
}

/// One probe measurement: summed raw intensity while a source played at a known device bearing.
public struct CalibrationSample: Codable, Sendable {
    public var trueBearing: Double
    public var raw: SIMD3<Float>

    public init(trueBearing: Double, raw: SIMD3<Float>) {
        self.trueBearing = trueBearing
        self.raw = raw
    }
}

public struct CalibrationFit: Sendable {
    public var calibration: FOAAxisCalibration
    public var medianAbsError: Double
    /// Fraction of samples with |error| < 90° (front/back correct).
    public var frontBackHitRate: Double
    /// Mean signed error: a large value suggests a constant yaw offset.
    public var meanSignedError: Double
    public var sampleCount: Int
    /// Number of different true bearings the samples cover.
    public var distinctAngles: Int

    /// Minimum directions recorded before the gate can pass: with fewer, several axis mappings
    /// fit equally well and a wrong one could "pass".
    public static let minDistinctAngles = 6

    /// Step 1 gate from the spec: median ≤ 30° and front/back ≥ 90%, over at least 6 directions.
    public var passesGate: Bool {
        distinctAngles >= Self.minDistinctAngles && medianAbsError <= 30 && frontBackHitRate >= 0.9
    }
}

public enum CalibrationFitter {
    /// Scores one calibration against samples taken with the phone flat.
    public static func evaluate(_ cal: FOAAxisCalibration, samples: [CalibrationSample]) -> CalibrationFit? {
        guard !samples.isEmpty else { return nil }
        let errors = samples.map { Circular.difference(Circular.bearing(cal.toDevice($0.raw)), $0.trueBearing) }
        let abs = errors.map(Swift.abs)
        return CalibrationFit(
            calibration: cal,
            medianAbsError: Circular.median(abs)!,
            frontBackHitRate: Double(abs.filter { $0 < 90 }.count) / Double(abs.count),
            meanSignedError: errors.reduce(0, +) / Double(errors.count),
            sampleCount: samples.count,
            distinctAngles: Set(samples.map(\.trueBearing)).count)
    }

    /// Brute-forces the 24 proper signed permutations; returns the lowest median error.
    public static func fit(_ samples: [CalibrationSample]) -> CalibrationFit? {
        FOAAxisCalibration.allProperSignedPermutations()
            .compactMap { evaluate($0, samples: samples) }
            .min { ($0.medianAbsError, Swift.abs($0.meanSignedError)) < ($1.medianAbsError, Swift.abs($1.meanSignedError)) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 26 tests in 5 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add FOA axis calibration and brute-force probe fitter" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: FOA capture and the probe app

The first on-device code. It captures FOA, shows live per-channel levels and a raw direction dial, records calibration samples at known angles, fits the axis mapping, and exports CSV. Some files written here are replaced in Task 13 (`AppModel`, `AudioPipeline`) and Task 14 (`MainView`); that is intentional.

**Files:**
- Create: `EchoApp/Capture/FOABufferAdapter.swift`, `EchoApp/Capture/FOACaptureSession.swift`, `EchoApp/Capture/AudioPipeline.swift`
- Create: `EchoApp/Probe/ProbeState.swift`, `EchoApp/Probe/ProbeView.swift`
- Create: `EchoApp/UI/StatusBanner.swift`, `EchoApp/UI/RadarGeometry.swift`, `EchoApp/UI/MainView.swift`
- Create: `EchoApp/App/AppModel.swift`
- Modify: `EchoApp/App/SoundSightApp.swift` (replace)

**Interfaces:**
- Consumes: `PCMLayout`, `PCMDeinterleaver`, `WindowAccumulator`, `IntensityAnalyzer`, `FOAAxisCalibration`, `CalibrationSample`, `CalibrationFit`, `CalibrationFitter`, `Circular`.
- Produces (app-internal, used by Tasks 13–14):
  - `struct FOAChunk { var w, x, y, z: [Float]; var sampleRate: Double }`; `FOABufferAdapter.chunk(from:) -> FOAChunk?`, `FOABufferAdapter.describe(_:) -> String`.
  - `final class FOACaptureSession { let session: AVCaptureSession; private(set) var foaEnabled: Bool; var onChunk, onFormat; func configure() throws; func start(); func stop() }`.
  - `enum ListeningStatus { idle, listening, interrupted, permissionDenied, directionUnavailable(String), error(String) }`.
  - `struct ProbeState` (`ingest(_:calibration:now:)`, `samples`, `fit`, `csv()`, `angles`).
  - `func radarPoint(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint`.
  - `StatusBanner(status:classifierWarning:)`, `ProbeView(model:)`, `ProbeDial(bearing:)`.

- [ ] **Step 1: Write the capture layer**

`EchoApp/Capture/FOABufferAdapter.swift`:

```swift
import AVFoundation
import EchoCore

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
```

`EchoApp/Capture/FOACaptureSession.swift`:

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
    private let sessionQueue = DispatchQueue(label: "echo.capture.session")
    private let bufferQueue = DispatchQueue(label: "echo.capture.buffers")
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

`EchoApp/Capture/AudioPipeline.swift` (probe stage):

```swift
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
```

- [ ] **Step 2: Write the probe state and screens**

`EchoApp/Probe/ProbeState.swift`:

```swift
import EchoCore
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

`EchoApp/Probe/ProbeView.swift`:

```swift
import EchoCore
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

`EchoApp/UI/RadarGeometry.swift`:

```swift
import SwiftUI

/// Point at `radius` from `center`, `degrees` clockwise from straight up.
func radarPoint(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: center.x + radius * sin(r), y: center.y - radius * cos(r))
}
```

`EchoApp/UI/StatusBanner.swift`:

```swift
import SwiftUI
import UIKit

struct StatusBanner: View {
    let status: ListeningStatus
    let classifierWarning: String?

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
            if let classifierWarning {
                banner(classifierWarning, systemImage: "waveform.badge.exclamationmark")
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

- [ ] **Step 3: Write the probe-stage model, main screen and app entry**

`EchoApp/App/AppModel.swift`:

```swift
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

/// Probe-stage app model. Task 13 replaces it with the full model.
@MainActor
@Observable
final class AppModel {
    private static let calibrationKey = "foaAxisCalibration"

    var status: ListeningStatus = .idle
    var isListening = false
    var classifierWarning: String?
    var probe = ProbeState()
    var calibration: FOAAxisCalibration {
        didSet {
            if let data = try? JSONEncoder().encode(calibration) {
                UserDefaults.standard.set(data, forKey: Self.calibrationKey)
            }
        }
    }

    @ObservationIgnored private let capture = FOACaptureSession()
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
            let pipeline = try AudioPipeline()
            pipeline.onWindow = { [weak self] summary in Task { @MainActor in self?.apply(summary) } }
            capture.onChunk = { chunk in pipeline.ingest(chunk) }
            self.pipeline = pipeline
        } catch {
            status = .error("Couldn't set up audio analysis: \(error.localizedDescription)")
        }
        capture.onFormat = { [weak self] format in Task { @MainActor in self?.probe.format = format } }
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
        capture.start()
        isListening = true
        status = capture.foaEnabled
            ? .listening
            : .directionUnavailable("this device can't capture spatial (FOA) audio.")
    }

    func stop() {
        capture.stop()
        isListening = false
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

`EchoApp/UI/MainView.swift`:

```swift
import SwiftUI

/// Probe-stage main screen. Task 13 adds the event list; Task 14 the radar.
struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusBanner(status: model.status, classifierWarning: model.classifierWarning)
                Spacer()
                Button("Open FOA Probe") { showProbe = true }
                Button {
                    if model.isListening { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.isListening ? "Stop Listening" : "Start Listening").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("SoundSight")
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
        }
    }
}
```

`EchoApp/App/SoundSightApp.swift` (replace):

```swift
import SwiftUI

@main
struct SoundSightApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup { MainView(model: model) }
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
Expected: no `error:` lines. Swift 6 concurrency warnings must also be zero; fix any that appear before continuing.

- [ ] **Step 5: Run core tests (no regressions)**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 26 tests in 5 suites passed`.

- [ ] **Step 6: Human check on the iPhone**

Ask the human to Run on the phone, tap **Start Listening** (allow the microphone), then **Open FOA Probe**, and report:
1. The **Format** line (expected: `48000 Hz · 4 ch · …`). If it shows `1 ch`, FOA isn't active; record that, since it's a gate failure.
2. Whether the four RMS values move when they talk, and whether X/Y/Z differ when they speak from different sides.
3. Whether the dial roughly follows a sound moved around the phone (it may be rotated or mirrored; Task 6 calibrates that).
Wait for the report before committing.

- [ ] **Step 7: Commit**

```bash
git add EchoApp
git commit -m "Add FOA capture and on-device probe with calibration recorder" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: GATE — run the FOA probe protocol on the iPhone

**This task is performed by the human with the agent's guidance. No code is written. Do not start Task 7 until this gate passes.**

**Files:**
- Create: `docs/superpowers/spikes/2026-10-10-foa-probe/README.md` (results), `docs/superpowers/spikes/2026-10-10-foa-probe/*.csv` (exported data)

- [ ] **Step 1: Give the human the protocol** (spec §6)

1. Quiet room. Phone **flat** on a table, screen up, top edge pointing at 0°. Mark 8 positions around it (0°, 45°, …, 315°, clockwise, 0° = straight past the top edge) at about 1.5 m.
2. A speaker at table height plays pink noise (any "pink noise" video or app), then a siren clip, then a knock clip.
3. In the probe: **Start Listening** → choose the true direction → **Record 10 s** while the sound plays from that position. Repeat for all 8 positions.
4. **Fit calibration** → note median error, front/back %, mean signed error, and GATE PASSED/FAILED.
5. If passed, tap **Use this calibration**. **Prepare CSV** → **Share CSV** (AirDrop to the Mac).
6. Repeat once with the phone **upright in portrait**, back camera facing 0°, without fitting again: check that the dial follows the sound when the speaker moves left/right around the phone.
7. Also note the Format line and whether anything required a camera.

- [ ] **Step 2: Record the results**

Write `docs/superpowers/spikes/2026-10-10-foa-probe/README.md` with: date, iOS version, format line, fitted calibration rows, median error, front/back hit rate, mean signed error, distinct angles, gate result, upright observation. Copy the CSV(s) next to it.

- [ ] **Step 3: Decide**

- **PASS** (median ≤ 30°, front/back ≥ 90%, ≥ 6 directions): continue to Task 7.
- **FAIL**: stop. Report the numbers to the human and propose the stereo fallback (spec §2 "Fallback": AVAudioSession stereo + a rotational belief). Do not continue with this plan.
- If the mean signed error is large (> 20°) while the median is fine, note it: a constant yaw offset may need adding to `FOAAxisCalibration` later (deferred tuning).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/spikes/2026-10-10-foa-probe
git commit -m "Record FOA probe gate results" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Direction-of-arrival estimator

**Files:**
- Create: `EchoCore/Sources/EchoCore/DSP/DOAEstimator.swift`
- Test: `EchoCore/Tests/EchoCoreTests/DOAEstimatorTests.swift`

**Interfaces:**
- Consumes: `IntensityAnalyzer`, `IntensityResult`, `IntensityConfig` (Task 3); `FOAAxisCalibration` (Task 4); `FOAWindow` (Task 2); `Circular`; test helpers `FOASynth`, `SeededRNG`.
- Produces:
  - `struct DOAConfig` (72 bins, κ 8 smoothing, ≤ 3 peaks, ≥ 25% of max, ≥ 30° apart).
  - `struct DOAPeak: Equatable { var bearing: Double; var weight: Double; init(bearing:weight:) }` (world bearing; weights in one frame sum to 1).
  - `struct DOAFrame { var windowStart: Int64; var peaks: [DOAPeak]; var diffuseness: Double; var histogram: [Double]; init(windowStart:peaks:diffuseness:histogram:) }`.
  - `final class DOAEstimator { let intensity: IntensityAnalyzer; init(intensity:config:) throws; func estimate(_: FOAWindow, calibration:deviceToWorld:) -> DOAFrame; func estimate(_: IntensityResult, windowStart:calibration:deviceToWorld:) -> DOAFrame }`.
  - Test helper `yawRotation(clockwise:) -> simd_float3x3` (top-level in the test file; Task 10 reuses it).

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/DOAEstimatorTests.swift`:

```swift
import Testing
import simd
@testable import EchoCore

/// deviceToWorld for a phone lying flat, turned clockwise (seen from above) by `degrees`.
func yawRotation(clockwise degrees: Double) -> simd_float3x3 {
    let r = Float(degrees * .pi / 180)
    return simd_float3x3(columns: (SIMD3(cos(r), -sin(r), 0), SIMD3(sin(r), cos(r), 0), SIMD3(0, 0, 1)))
}

struct DOAEstimatorTests {
    let estimator = try! DOAEstimator()
    let flat = matrix_identity_float3x3

    @Test func singleSourceEveryDirection() {
        var rng = SeededRNG(seed: 10)
        for bearing in stride(from: 0.0, to: 360, by: 5) {
            let w = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: bearing)
            let f = estimator.estimate(w, calibration: .identity, deviceToWorld: flat)
            #expect(f.peaks.count == 1)
            #expect(abs(Circular.difference(f.peaks[0].bearing, bearing)) < 5)
            #expect(f.diffuseness < 0.05)
        }
    }

    @Test func elevatedSourceKeepsAzimuth() {
        var rng = SeededRNG(seed: 11)
        let f = estimator.estimate(FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 200, elevation: 60),
                                   calibration: .identity, deviceToWorld: flat)
        #expect(abs(Circular.difference(f.peaks[0].bearing, 200)) < 5)
    }

    @Test func twoSourcesWithDifferentSpectra() {
        var rng = SeededRNG(seed: 12)
        let low = FOASynth.planeWave(FOASynth.tones(band: 300...1500, rng: &rng), bearing: 0)
        let high = FOASynth.planeWave(FOASynth.tones(band: 3000...7000, rng: &rng), bearing: 120)
        let f = estimator.estimate(FOASynth.mix(low, high), calibration: .identity, deviceToWorld: flat)
        #expect(f.peaks.count == 2)
        #expect(f.peaks.contains { abs(Circular.difference($0.bearing, 0)) < 10 })
        #expect(f.peaks.contains { abs(Circular.difference($0.bearing, 120)) < 10 })
        #expect(abs(f.peaks.map(\.weight).reduce(0, +) - 1) < 1e-9)
    }

    @Test func diffuseNoiseAt6dBSNR() {
        var rng = SeededRNG(seed: 13)
        let source = FOASynth.planeWave(FOASynth.whiteNoise(amplitude: 0.1, rng: &rng), bearing: 60)
        let clean = estimator.estimate(source, calibration: .identity, deviceToWorld: flat)
        // 6 dB SNR: diffuse field amplitude is half the source amplitude.
        let noisy = estimator.estimate(FOASynth.mix(source, FOASynth.diffuseNoise(totalAmplitude: 0.05, rng: &rng)),
                                       calibration: .identity, deviceToWorld: flat)
        #expect(abs(Circular.difference(noisy.peaks[0].bearing, 60)) < 15)
        #expect(noisy.diffuseness > clean.diffuseness)
    }

    @Test func silenceHasNoPeaks() {
        let f = estimator.estimate(FOASynth.silence, calibration: .identity, deviceToWorld: flat)
        #expect(f.peaks.isEmpty)
        #expect(f.diffuseness == 1)
    }

    @Test func rotatesIntoWorldFrame() {
        var rng = SeededRNG(seed: 14)
        // Source 30° right of the phone's top; phone turned 90° clockwise → world bearing 120°.
        let w = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 30)
        let f = estimator.estimate(w, calibration: .identity, deviceToWorld: yawRotation(clockwise: 90))
        #expect(abs(Circular.difference(f.peaks[0].bearing, 120)) < 5)
    }

    @Test func appliesAxisCalibration() {
        var rng = SeededRNG(seed: 15)
        let cal = FOAAxisCalibration.initialGuess
        // Encode in device frame, then express in raw FOA axes: raw = Cᵀ · device.
        let dev = FOASynth.planeWave(FOASynth.whiteNoise(rng: &rng), bearing: 250)
        let m = cal.matrix.transpose
        func raw(_ i: Int, _ n: Int) -> Float {
            let v = m * SIMD3(dev.x[n], dev.y[n], dev.z[n])
            return v[i]
        }
        let count = dev.w.count
        let foa = FOAWindow(w: dev.w, x: (0..<count).map { raw(0, $0) }, y: (0..<count).map { raw(1, $0) },
                            z: (0..<count).map { raw(2, $0) }, sampleRate: dev.sampleRate, startSample: 0)
        let f = estimator.estimate(foa, calibration: cal, deviceToWorld: flat)
        #expect(abs(Circular.difference(f.peaks[0].bearing, 250)) < 5)
    }

    @Test func passesWindowStartThrough() {
        let f = estimator.estimate(FOASynth.planeWave([Float](repeating: 0, count: 48_000), bearing: 0, startSample: 24_000),
                                   calibration: .identity, deviceToWorld: flat)
        #expect(f.windowStart == 24_000)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'DOAEstimator' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/DSP/DOAEstimator.swift`:

```swift
import simd

public struct DOAConfig: Sendable {
    public var binCount = 72  // 5° bins
    public var smoothingKappa = 8.0
    public var maxPeaks = 3
    public var minPeakFraction = 0.25
    public var minPeakSeparation = 30.0

    public init() {}

    public var binWidth: Double { 360 / Double(binCount) }
}

/// A direction-of-arrival peak in the world frame.
public struct DOAPeak: Sendable, Equatable {
    public var bearing: Double
    /// Share of the frame's total peak height, in (0, 1]; the weights of one frame sum to 1.
    public var weight: Double

    public init(bearing: Double, weight: Double) {
        self.bearing = bearing
        self.weight = weight
    }
}

public struct DOAFrame: Sendable {
    public var windowStart: Int64
    public var peaks: [DOAPeak]
    public var diffuseness: Double
    /// Smoothed world-frame histogram (`binCount` bins), for debugging and the probe.
    public var histogram: [Double]

    public init(windowStart: Int64, peaks: [DOAPeak], diffuseness: Double, histogram: [Double]) {
        self.windowStart = windowStart
        self.peaks = peaks
        self.diffuseness = diffuseness
        self.histogram = histogram
    }
}

/// FOA window → world-frame direction peaks (spec §3.3).
public final class DOAEstimator {
    public let config: DOAConfig
    public let intensity: IntensityAnalyzer
    private let kernel: [Double]

    public init(intensity: IntensityConfig = .init(), config: DOAConfig = .init()) throws {
        self.config = config
        self.intensity = try IntensityAnalyzer(config: intensity)
        kernel = (0..<config.binCount).map { Circular.vonMises(Double($0) * config.binWidth, kappa: config.smoothingKappa) }
    }

    public func estimate(_ window: FOAWindow, calibration: FOAAxisCalibration, deviceToWorld: simd_float3x3) -> DOAFrame {
        estimate(intensity.analyze(window), windowStart: window.startSample, calibration: calibration, deviceToWorld: deviceToWorld)
    }

    public func estimate(_ result: IntensityResult, windowStart: Int64, calibration: FOAAxisCalibration,
                         deviceToWorld: simd_float3x3) -> DOAFrame {
        let n = config.binCount
        let toWorld = deviceToWorld * calibration.matrix
        var raw = [Double](repeating: 0, count: n)
        for bin in result.bins {
            let v = toWorld * bin.raw
            let h = Double(simd_length(SIMD2(v.x, v.y)))
            guard h > 0 else { continue }
            raw[Int(Circular.bearing(v) / config.binWidth) % n] += h
        }
        var smooth = [Double](repeating: 0, count: n)
        for i in 0..<n where raw[i] > 0 {
            for j in 0..<n { smooth[j] += raw[i] * kernel[(j - i + n) % n] }
        }
        return DOAFrame(windowStart: windowStart, peaks: peaks(in: smooth), diffuseness: Double(result.diffuseness), histogram: smooth)
    }

    private func peaks(in s: [Double]) -> [DOAPeak] {
        let n = s.count
        guard let top = s.max(), top > 0 else { return [] }
        let candidates = (0..<n)
            .filter { s[$0] >= s[($0 - 1 + n) % n] && s[$0] > s[($0 + 1) % n] && s[$0] >= config.minPeakFraction * top }
            .sorted { s[$0] > s[$1] }
        var chosen: [(bearing: Double, height: Double)] = []
        for i in candidates where chosen.count < config.maxPeaks {
            let neighborhood = (-2...2).map { (i + $0 + n) % n }
            let bearing = Circular.mean(neighborhood.map { (Double($0) + 0.5) * config.binWidth },
                                        weights: neighborhood.map { s[$0] }) ?? (Double(i) + 0.5) * config.binWidth
            if chosen.allSatisfy({ abs(Circular.difference($0.bearing, bearing)) >= config.minPeakSeparation }) {
                chosen.append((bearing, s[i]))
            }
        }
        let total = chosen.reduce(0) { $0 + $1.height }
        return chosen.map { DOAPeak(bearing: $0.bearing, weight: $0.height / total) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 34 tests in 6 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add world-frame FOA direction-of-arrival estimator" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Classification tables (urgency, label mapping, thresholds)

**Files:**
- Create: `EchoCore/Sources/EchoCore/Classification/Urgency.swift`, `UrgencyMap.swift`, `LabelMapper.swift`, `GroupThresholds.swift`, `ClassificationResources.swift`
- Create (resources): `EchoCore/Sources/EchoCore/Resources/apple_to_group.json`, `thresholds.json` (copied from the spike), `urgency_map.json` (hand-written)
- Modify: `EchoCore/Package.swift` (declare resources)
- Test: `EchoCore/Tests/EchoCoreTests/ClassificationTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `enum Urgency: Int, Comparable, CaseIterable { case low, medium, high, critical; init?(tier:) }`.
  - `enum ResourceError: Error { case missing(String), malformed(String) }`.
  - `struct UrgencyMap { init(tiers:); init(json:) throws; func urgency(for:) -> Urgency; var groups: Set<String> }`.
  - `struct LabelMapper { let labelToGroup: [String: String]; init(labelToGroup:topK:); init(json:topK:) throws; func groupScores(_: [String: Double]) -> [String: Double] }`.
  - `struct GroupThresholds { let thresholds: [String: Double]; init(thresholds:defaultThreshold:); init(json:defaultThreshold:) throws; func threshold(for:) -> Double; func active(_:) -> [String: Double] }`.
  - `struct ClassificationResources { let mapper, thresholds, urgency; static func bundled() throws -> ClassificationResources }`.

- [ ] **Step 1: Add the resource files**

```bash
mkdir -p EchoCore/Sources/EchoCore/Resources
cp docs/superpowers/spikes/2026-10-10-classifier/apple_to_group.json EchoCore/Sources/EchoCore/Resources/
cp docs/superpowers/spikes/2026-10-10-classifier/thresholds.json EchoCore/Sources/EchoCore/Resources/
curl -sL https://example.com/urgency_map.json \
  -o EchoCore/Sources/EchoCore/Resources/urgency_map.json
python3 -c "import json; d=json.load(open('EchoCore/Sources/EchoCore/Resources/urgency_map.json')); print(sum(len(v) for k,v in d.items() if not k.startswith('_')))"
```
Expected: the last command prints `42`. If the download fails, copy `urgency_map.json` from the team's notes.

- [ ] **Step 2: Declare the resources**

`EchoCore/Package.swift` (replace):

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "EchoCore", targets: ["EchoCore"])],
    targets: [
        .target(name: "EchoCore", resources: [.process("Resources")]),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"]),
    ]
)
```

- [ ] **Step 3: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/ClassificationTests.swift`:

```swift
import Foundation
import Testing
@testable import EchoCore

struct ClassificationTests {
    @Test func urgencyOrderingAndParsing() {
        #expect(Urgency.low < .medium && Urgency.medium < .high && Urgency.high < .critical)
        #expect(Urgency(tier: "critical") == .critical)
        #expect(Urgency(tier: "nope") == nil)
    }

    @Test func noisyOrMatchesWorkedExample() {
        let m = LabelMapper(labelToGroup: ["music": "Music", "classical": "Music", "guitar": "Music", "drum": "Music", "dog_bark": "Dog"])
        // Music=0.5, Classical=0.7 → 1 − 0.5·0.3 = 0.85 (worked example).
        #expect(abs(m.groupScores(["music": 0.5, "classical": 0.7])["Music"]! - 0.85) < 1e-12)
        // Only the top 3 members count: 0.1 is ignored.
        let top3 = m.groupScores(["music": 0.5, "classical": 0.5, "guitar": 0.5, "drum": 0.1])["Music"]!
        #expect(abs(top3 - (1 - 0.125)) < 1e-12)
        // Single member passes through; unknown labels ignored; values clamped.
        #expect(m.groupScores(["dog_bark": 1.4, "unknown": 0.9]) == ["Dog": 1])
        #expect(m.groupScores([:]).isEmpty)
    }

    @Test func thresholdsFilterAndDefault() {
        let t = GroupThresholds(thresholds: ["Siren": 0.5], defaultThreshold: 0.9)
        #expect(t.active(["Siren": 0.5, "Dog": 0.89, "Speech": 0.95]) == ["Siren": 0.5, "Speech": 0.95])
        #expect(t.threshold(for: "Anything") == 0.9)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try GroupThresholds(json: Data("{\"x\":1}".utf8)) }
        #expect(throws: (any Error).self) { try LabelMapper(json: Data("[1,2]".utf8)) }
        #expect(throws: (any Error).self) { try UrgencyMap(json: Data("{\"URGENT\": [\"Siren\"]}".utf8)) }
    }

    @Test func bundledResourcesAreConsistent() throws {
        let r = try ClassificationResources.bundled()
        #expect(r.mapper.labelToGroup.count == 303)
        #expect(r.urgency.groups.count == 42)
        // Every Apple label maps to a group the urgency table knows.
        #expect(Set(r.mapper.labelToGroup.values).isSubset(of: r.urgency.groups))
        // Every group has an explicit threshold.
        #expect(r.urgency.groups.allSatisfy { r.thresholds.thresholds[$0] != nil })
        #expect(r.urgency.urgency(for: "Siren") == .critical)
        #expect(r.urgency.urgency(for: "Speech") == .low)
    }
}
```

- [ ] **Step 4: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'LabelMapper' in scope` (and the other new types).

- [ ] **Step 5: Implement**

`EchoCore/Sources/EchoCore/Classification/Urgency.swift`:

```swift
/// Four urgency tiers, ordered from least to most urgent.
public enum Urgency: Int, Comparable, Sendable, CaseIterable {
    case low, medium, high, critical

    public init?(tier: String) {
        switch tier.uppercased() {
        case "LOW": self = .low
        case "MEDIUM": self = .medium
        case "HIGH": self = .high
        case "CRITICAL": self = .critical
        default: return nil
        }
    }

    public static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }
}
```

`EchoCore/Sources/EchoCore/Classification/UrgencyMap.swift`:

```swift
import Foundation

public enum ResourceError: Error, Equatable {
    case missing(String)
    case malformed(String)
}

/// Group name → urgency tier, loaded from `urgency_map.json`
/// (`{"CRITICAL": [groups], "HIGH": [...], ...}`; keys starting with `_` are comments).
public struct UrgencyMap: Sendable {
    private let tiers: [String: Urgency]

    public init(tiers: [String: Urgency]) { self.tiers = tiers }

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ResourceError.malformed("urgency_map root is not an object")
        }
        var tiers: [String: Urgency] = [:]
        for (key, value) in root where !key.hasPrefix("_") {
            guard let urgency = Urgency(tier: key), let groups = value as? [String] else {
                throw ResourceError.malformed("urgency_map key \(key)")
            }
            for g in groups { tiers[g] = urgency }
        }
        self.tiers = tiers
    }

    /// Unknown groups default to `.low`.
    public func urgency(for group: String) -> Urgency { tiers[group] ?? .low }

    public var groups: Set<String> { Set(tiers.keys) }
}
```

`EchoCore/Sources/EchoCore/Classification/LabelMapper.swift`:

```swift
import Foundation

/// Pools classifier labels into sound groups with top-k noisy-OR (spec §3.2):
/// score(G) = 1 − ∏(1 − pᵢ) over the k strongest member labels of G.
public struct LabelMapper: Sendable {
    public let labelToGroup: [String: String]
    public let topK: Int

    public init(labelToGroup: [String: String], topK: Int = 3) {
        self.labelToGroup = labelToGroup
        self.topK = topK
    }

    /// `json` is a flat object `{"label": "Group", ...}` (e.g. `apple_to_group.json`).
    public init(json: Data, topK: Int = 3) throws {
        guard let map = try JSONSerialization.jsonObject(with: json) as? [String: String] else {
            throw ResourceError.malformed("label map is not a string→string object")
        }
        self.init(labelToGroup: map, topK: topK)
    }

    /// Unknown labels are ignored; confidences are clamped to [0, 1].
    public func groupScores(_ labelConfidences: [String: Double]) -> [String: Double] {
        var members: [String: [Double]] = [:]
        for (label, p) in labelConfidences {
            guard let g = labelToGroup[label] else { continue }
            members[g, default: []].append(min(1, max(0, p)))
        }
        return members.mapValues { ps in
            1 - ps.sorted(by: >).prefix(topK).reduce(1) { $0 * (1 - $1) }
        }
    }
}
```

`EchoCore/Sources/EchoCore/Classification/GroupThresholds.swift`:

```swift
import Foundation

/// Per-group activation thresholds (`thresholds.json`: `{"thresholds": {"Group": 0.77, ...}}`).
public struct GroupThresholds: Sendable {
    public let thresholds: [String: Double]
    public let defaultThreshold: Double

    public init(thresholds: [String: Double], defaultThreshold: Double = 0.9) {
        self.thresholds = thresholds
        self.defaultThreshold = defaultThreshold
    }

    public init(json: Data, defaultThreshold: Double = 0.9) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let map = root["thresholds"] as? [String: Double] else {
            throw ResourceError.malformed("thresholds.json needs a \"thresholds\" object of numbers")
        }
        self.init(thresholds: map, defaultThreshold: defaultThreshold)
    }

    public func threshold(for group: String) -> Double { thresholds[group] ?? defaultThreshold }

    /// Groups whose score reaches their threshold.
    public func active(_ scores: [String: Double]) -> [String: Double] {
        scores.filter { $0.value >= threshold(for: $0.key) }
    }
}
```

`EchoCore/Sources/EchoCore/Classification/ClassificationResources.swift`:

```swift
import Foundation

/// The bundled classification tables: Apple label map, per-group thresholds and urgency tiers.
public struct ClassificationResources: Sendable {
    public let mapper: LabelMapper
    public let thresholds: GroupThresholds
    public let urgency: UrgencyMap

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
            urgency: try UrgencyMap(json: load("urgency_map")))
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 39 tests in 7 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add EchoCore
git commit -m "Add classification tables: urgency, noisy-OR label mapping, thresholds" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Window joiner (classification ↔ direction)

**Files:**
- Create: `EchoCore/Sources/EchoCore/Classification/WindowJoiner.swift`
- Test: `EchoCore/Tests/EchoCoreTests/WindowJoinerTests.swift`

**Interfaces:**
- Consumes: `DOAFrame` (Task 7).
- Produces:
  - `struct ClassificationFrame { var windowStart: Int64; var groupScores: [String: Double]; init(windowStart:groupScores:) }`.
  - `struct JoinedWindow { var windowStart: Int64; var classification: ClassificationFrame; var doa: DOAFrame? }`.
  - `struct WindowJoiner { init(hopLength:maxLagWindows: = 2); mutating func add(classification:) -> [JoinedWindow]; mutating func add(doa:) -> [JoinedWindow]; mutating func reset() }`.

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/WindowJoinerTests.swift`:

```swift
import Testing
@testable import EchoCore

struct WindowJoinerTests {
    func doa(_ start: Int64) -> DOAFrame { DOAFrame(windowStart: start, peaks: [], diffuseness: 0, histogram: []) }
    func cls(_ start: Int64) -> ClassificationFrame { ClassificationFrame(windowStart: start, groupScores: ["Dog": 1]) }

    @Test func joinsInEitherOrder() {
        var j = WindowJoiner(hopLength: 24_000)
        #expect(j.add(doa: doa(0)).isEmpty)
        let a = j.add(classification: cls(0))
        #expect(a.count == 1 && a[0].doa != nil)
        #expect(j.add(classification: cls(24_000)).isEmpty)
        let b = j.add(doa: doa(24_000))
        #expect(b.count == 1 && b[0].windowStart == 24_000)
    }

    @Test func toleratesSmallTimestampDrift() {
        var j = WindowJoiner(hopLength: 24_000)
        _ = j.add(doa: doa(48_000))
        #expect(j.add(classification: cls(48_010)).first?.doa?.windowStart == 48_000)
    }

    @Test func emitsClassificationWithoutDOAAfterLag() {
        var j = WindowJoiner(hopLength: 24_000, maxLagWindows: 2)
        #expect(j.add(classification: cls(0)).isEmpty)
        #expect(j.add(doa: doa(24_000)).isEmpty)
        #expect(j.add(doa: doa(48_000)).isEmpty)
        let out = j.add(doa: doa(72_000))
        #expect(out.count == 1 && out[0].windowStart == 0 && out[0].doa == nil)
    }

    @Test func classifierWindowsDriftingOffGridStillMostlyJoin() {
        // If SoundAnalysis ever used 0.975 s windows, its starts would drift 600 samples per hop.
        var j = WindowJoiner(hopLength: 24_000)
        var joined: [JoinedWindow] = []
        for n in 0..<40 {
            joined += j.add(doa: doa(Int64(n) * 24_000))
            joined += j.add(classification: cls(Int64(n) * 23_400))
        }
        let withDOA = joined.filter { $0.doa != nil }
        #expect(Double(withDOA.count) >= 0.9 * 40)
        // Every pairing is within half a hop in time.
        #expect(withDOA.allSatisfy { abs($0.windowStart - $0.doa!.windowStart) <= 12_000 })
    }

    @Test func dropsOrphanDOA() {
        var j = WindowJoiner(hopLength: 24_000, maxLagWindows: 1)
        _ = j.add(doa: doa(0))
        _ = j.add(classification: cls(48_000))
        // The DOA for window 0 expired, so a late classification for 0 waits alone, then expires.
        #expect(j.add(classification: cls(0)).first?.doa == nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'WindowJoiner' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/Classification/WindowJoiner.swift`:

```swift
/// Group scores for one classifier window.
public struct ClassificationFrame: Sendable {
    public var windowStart: Int64
    public var groupScores: [String: Double]

    public init(windowStart: Int64, groupScores: [String: Double]) {
        self.windowStart = windowStart
        self.groupScores = groupScores
    }
}

public struct JoinedWindow: Sendable {
    public var windowStart: Int64
    public var classification: ClassificationFrame
    public var doa: DOAFrame?
}

/// Pairs classification and DOA frames that describe the same window. Frames are matched on
/// their start sample rounded to the hop grid. A classification whose DOA has not arrived
/// within `maxLagWindows` newer windows is emitted alone; a DOA frame with no classification is dropped.
public struct WindowJoiner: Sendable {
    public let hopLength: Int
    public let maxLagWindows: Int
    private var pendingClassification: [Int64: ClassificationFrame] = [:]
    private var pendingDOA: [Int64: DOAFrame] = [:]
    private var newestKey: Int64 = .min

    public init(hopLength: Int, maxLagWindows: Int = 2) {
        self.hopLength = hopLength
        self.maxLagWindows = maxLagWindows
    }

    private func key(_ start: Int64) -> Int64 {
        Int64((Double(start) / Double(hopLength)).rounded())
    }

    public mutating func add(classification: ClassificationFrame) -> [JoinedWindow] {
        let k = key(classification.windowStart)
        var out: [JoinedWindow] = []
        if let doa = pendingDOA.removeValue(forKey: k) {
            out.append(JoinedWindow(windowStart: classification.windowStart, classification: classification, doa: doa))
        } else {
            pendingClassification[k] = classification
        }
        return out + expire(newest: k)
    }

    public mutating func add(doa: DOAFrame) -> [JoinedWindow] {
        let k = key(doa.windowStart)
        var out: [JoinedWindow] = []
        if let c = pendingClassification.removeValue(forKey: k) {
            out.append(JoinedWindow(windowStart: c.windowStart, classification: c, doa: doa))
        } else {
            pendingDOA[k] = doa
        }
        return out + expire(newest: k)
    }

    public mutating func reset() {
        pendingClassification = [:]
        pendingDOA = [:]
        newestKey = .min
    }

    private mutating func expire(newest k: Int64) -> [JoinedWindow] {
        newestKey = max(newestKey, k)
        let cutoff = newestKey - Int64(maxLagWindows)
        let stale = pendingClassification.keys.filter { $0 < cutoff }.sorted()
        let out = stale.map { s -> JoinedWindow in
            let c = pendingClassification.removeValue(forKey: s)!
            return JoinedWindow(windowStart: c.windowStart, classification: c, doa: nil)
        }
        pendingDOA = pendingDOA.filter { $0.key >= cutoff }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 44 tests in 8 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add window joiner pairing classifier and DOA frames" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Motion conventions and forward heading

**Files:**
- Create: `EchoCore/Sources/EchoCore/Motion/RotationConvention.swift`, `EchoCore/Sources/EchoCore/Motion/ForwardHeading.swift`
- Test: `EchoCore/Tests/EchoCoreTests/MotionTests.swift`

**Interfaces:**
- Consumes: `Circular`; test helper `yawRotation(clockwise:)` (Task 7 test file).
- Produces:
  - `enum RotationConvention: Equatable { case worldToDevice, deviceToWorld; static func resolve(m:gravity:) -> RotationConvention?; func deviceToWorld(_:) -> simd_float3x3 }`.
  - `struct ForwardHeading { enum Posture { flat, upright }; private(set) var posture; mutating func update(deviceToWorld:) -> Double; static func radarAngle(worldBearing:forward:) -> Double }`.
  - Test helper `tilt(_ degrees:) -> simd_float3x3`.

Why a runtime convention check: the CoreMotion header only says `rotationMatrix` "represents the device's attitude", not whether it maps world→device or device→world. Getting it wrong mirrors yaw (the radar would spin the wrong way). With the phone tilted, only one interpretation predicts the measured gravity vector. The app resolves it once and stores it (Task 13).

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/MotionTests.swift`:

```swift
import Testing
import simd
@testable import EchoCore

/// deviceToWorld for a phone tilted up about its x axis by `degrees` (0 = flat, 90 = upright portrait).
func tilt(_ degrees: Double) -> simd_float3x3 {
    let t = Float(degrees * .pi / 180)
    return simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, cos(t), sin(t)), SIMD3(0, -sin(t), cos(t))))
}

struct RotationConventionTests {
    let truth = yawRotation(clockwise: 40) * tilt(50)  // a tilted, turned phone

    @Test func resolvesWorldToDevice() {
        let m = truth.transpose  // CoreMotion hands us world→device
        let g = m * SIMD3<Float>(0, 0, -1)
        let c = RotationConvention.resolve(m: m, gravity: g)
        #expect(c == .worldToDevice)
        #expect(simd_almost_equal_elements(c!.deviceToWorld(m), truth, 1e-5))
    }

    @Test func resolvesDeviceToWorld() {
        let m = truth  // CoreMotion hands us device→world
        let g = m.transpose * SIMD3<Float>(0, 0, -1)
        let c = RotationConvention.resolve(m: m, gravity: g)
        #expect(c == .deviceToWorld)
        #expect(simd_almost_equal_elements(c!.deviceToWorld(m), truth, 1e-5))
    }

    @Test func undecidableWhenFlat() {
        let m = yawRotation(clockwise: 70)
        #expect(RotationConvention.resolve(m: m, gravity: SIMD3(0, 0, -1)) == nil)
        #expect(RotationConvention.resolve(m: m, gravity: .zero) == nil)
    }
}

struct ForwardHeadingTests {
    @Test func flatUsesTopEdge() {
        var h = ForwardHeading()
        let ahead = h.update(deviceToWorld: matrix_identity_float3x3)
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90))
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
        #expect(h.posture == .flat)
    }

    @Test func uprightUsesBackCamera() {
        var h = ForwardHeading()
        // Upright portrait, back camera facing world bearing 0 → forward 0.
        let ahead = h.update(deviceToWorld: tilt(90))
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        #expect(h.posture == .upright)
        // Same posture turned 90° clockwise.
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90) * tilt(90))
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
    }

    @Test func faceDownCountsAsFlat() {
        // Flipped over about the long (y) axis: screen faces the floor, top edge still points ahead.
        let faceDown = simd_float3x3(columns: (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)))
        var h = ForwardHeading()
        let ahead = h.update(deviceToWorld: faceDown)
        #expect(h.posture == .flat)
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90) * faceDown)
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
    }

    @Test func hysteresis() {
        var h = ForwardHeading()
        _ = h.update(deviceToWorld: tilt(50)); #expect(h.posture == .flat)
        _ = h.update(deviceToWorld: tilt(60)); #expect(h.posture == .upright)
        _ = h.update(deviceToWorld: tilt(40)); #expect(h.posture == .upright)
        _ = h.update(deviceToWorld: tilt(30)); #expect(h.posture == .flat)
    }

    @Test func radarAngleIsRelativeToForward() {
        #expect(ForwardHeading.radarAngle(worldBearing: 120, forward: 90) == 30)
        #expect(ForwardHeading.radarAngle(worldBearing: 10, forward: 350) == 20)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'RotationConvention' in scope` and `cannot find 'ForwardHeading' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/Motion/RotationConvention.swift`:

```swift
import simd

/// CoreMotion documents `CMAttitude.rotationMatrix` only as "the device's attitude", not which way
/// it maps vectors. We resolve it at runtime from gravity (spec §3.5): with the phone tilted, only
/// one interpretation predicts the measured device-frame gravity.
public enum RotationConvention: Sendable, Equatable {
    /// v_device = M · v_world, so deviceToWorld = Mᵀ.
    case worldToDevice
    /// v_world = M · v_device, so deviceToWorld = M.
    case deviceToWorld

    /// - Parameters:
    ///   - m: `CMAttitude.rotationMatrix` with rows (m11 m12 m13), (m21 …), (m31 …).
    ///   - gravity: `CMDeviceMotion.gravity` (device frame, pointing down).
    /// - Returns: nil while the phone is too close to flat (or upside down) to tell.
    public static func resolve(m: simd_float3x3, gravity: SIMD3<Float>) -> RotationConvention? {
        guard simd_length(gravity) > 0.5 else { return nil }
        let g = simd_normalize(gravity)
        guard abs(g.z) < 0.95 else { return nil }
        let down = SIMD3<Float>(0, 0, -1)
        let a = simd_distance(m * down, g)
        let b = simd_distance(m.transpose * down, g)
        guard abs(a - b) > 0.1 else { return nil }
        return a < b ? .worldToDevice : .deviceToWorld
    }

    public func deviceToWorld(_ m: simd_float3x3) -> simd_float3x3 {
        switch self {
        case .worldToDevice: m.transpose
        case .deviceToWorld: m
        }
    }
}
```

`EchoCore/Sources/EchoCore/Motion/ForwardHeading.swift`:

```swift
import Foundation
import simd

/// Tracks which way the user is "facing" with the phone (spec §3.5): the top edge when the
/// phone is near flat, the back camera when it is upright. Hysteresis (switch to upright past
/// 55° of tilt, back to flat under 35°) stops the reference from flickering near 45°.
public struct ForwardHeading: Sendable {
    public enum Posture: Sendable, Equatable { case flat, upright }

    public private(set) var posture: Posture = .flat

    public init() {}

    /// Returns the world bearing (degrees) of the forward direction.
    public mutating func update(deviceToWorld d: simd_float3x3) -> Double {
        let screenUp = abs(Double((d * SIMD3<Float>(0, 0, 1)).z))
        switch posture {
        case .flat where screenUp < cos(55 * Double.pi / 180): posture = .upright
        case .upright where screenUp > cos(35 * Double.pi / 180): posture = .flat
        default: break
        }
        let forward: SIMD3<Float> = posture == .flat ? SIMD3(0, 1, 0) : SIMD3(0, 0, -1)
        return Circular.bearing(d * forward)
    }

    /// Angle to draw a world bearing at on the radar (0° = up / forward).
    public static func radarAngle(worldBearing: Double, forward: Double) -> Double {
        Circular.wrap360(worldBearing - forward)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 52 tests in 10 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add rotation-convention resolution and forward heading" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Azimuth belief and event tracker

**Files:**
- Create: `EchoCore/Sources/EchoCore/Fusion/AzimuthBelief.swift`, `EchoCore/Sources/EchoCore/Fusion/EventTracker.swift`
- Test: `EchoCore/Tests/EchoCoreTests/FusionTests.swift`

**Interfaces:**
- Consumes: `DOAPeak`, `DOAFrame` (Task 7); `Urgency`, `UrgencyMap` (Task 8); `Circular`.
- Produces:
  - `struct AzimuthBelief { static let binCount = 72, binWidth = 5.0; static func binCenter(_:) -> Double; private(set) var probabilities: [Double]; mutating func decayTowardUniform(); mutating func update(peaks:confidence:); var concentration: Double; var peakBearing: Double }`.
  - `struct SoundEvent: Identifiable { group, urgency, confidence, belief, firstSeen, lastSeen }`.
  - `final class EventTracker { init(urgencyMap:evictAfter:emaAlpha:diffusenessCutoff:); var events: [SoundEvent]; @discardableResult func ingest(active:doa:now:) -> [SoundEvent]; func reset() }`.

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/FusionTests.swift`:

```swift
import Testing
@testable import EchoCore

struct AzimuthBeliefTests {
    @Test func startsUniform() {
        let b = AzimuthBelief()
        #expect(b.concentration < 1e-9)
        #expect(abs(b.probabilities.reduce(0, +) - 1) < 1e-9)
    }

    @Test func convergesOnConsistentEvidence() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 93, weight: 1)], confidence: 1) }
        #expect(abs(Circular.difference(b.peakBearing, 93)) < 5)
        #expect(b.concentration >= 0.5)
    }

    @Test func convergesAcrossZero() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 358, weight: 1)], confidence: 0.8) }
        #expect(abs(Circular.difference(b.peakBearing, 358)) < 5)
    }

    @Test func decaysWithoutEvidence() {
        var b = AzimuthBelief()
        for _ in 0..<6 { b.update(peaks: [DOAPeak(bearing: 200, weight: 1)], confidence: 1) }
        for _ in 0..<30 { b.decayTowardUniform() }
        #expect(b.concentration < 0.05)
    }

    @Test func emptyPeaksOnlyDecay() {
        var a = AzimuthBelief(), b = AzimuthBelief()
        a.update(peaks: [DOAPeak(bearing: 10, weight: 1)], confidence: 1)
        b.update(peaks: [DOAPeak(bearing: 10, weight: 1)], confidence: 1)
        a.update(peaks: [], confidence: 1)
        b.decayTowardUniform()
        #expect(a.probabilities == b.probabilities)
    }

    @Test func zeroConfidenceDoesNotMoveBelief() {
        var b = AzimuthBelief()
        b.update(peaks: [DOAPeak(bearing: 45, weight: 1)], confidence: 0)
        #expect(b.concentration < 1e-9)
    }
}

struct EventTrackerTests {
    let urgency = UrgencyMap(tiers: ["Siren": .critical, "Dog": .medium, "Speech": .low])
    func doa(_ bearing: Double, diffuseness: Double = 0.1) -> DOAFrame {
        DOAFrame(windowStart: 0, peaks: [DOAPeak(bearing: bearing, weight: 1)], diffuseness: diffuseness, histogram: [])
    }

    @Test func createsRefreshesAndEvicts() {
        let t = EventTracker(urgencyMap: urgency)
        #expect(t.ingest(active: ["Dog": 0.9], doa: nil, now: 0).map(\.group) == ["Dog"])
        #expect(t.ingest(active: ["Dog": 0.5], doa: nil, now: 0.5).isEmpty)
        #expect(abs(t.events[0].confidence - 0.7) < 1e-12)
        #expect(t.events[0].firstSeen == 0 && t.events[0].lastSeen == 0.5)
        t.ingest(active: [:], doa: nil, now: 3.5)
        #expect(t.events.count == 1)  // exactly 3 s since lastSeen: kept
        t.ingest(active: [:], doa: nil, now: 3.6)
        #expect(t.events.isEmpty)
    }

    @Test func sortsByUrgencyThenConfidence() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Speech": 0.99, "Dog": 0.6, "Siren": 0.5], doa: nil, now: 0)
        #expect(t.events.map(\.group) == ["Siren", "Dog", "Speech"])
        #expect(t.events[0].urgency == .critical)
    }

    @Test func activeLabelsLearnDirectionIndependently() {
        let t = EventTracker(urgencyMap: urgency)
        for i in 0..<6 { t.ingest(active: ["Siren": 1], doa: doa(270), now: Double(i) * 0.5) }
        for i in 6..<12 { t.ingest(active: ["Siren": 1, "Dog": 1], doa: nil, now: Double(i) * 0.5) }
        for i in 12..<18 { t.ingest(active: ["Dog": 1], doa: doa(45), now: Double(i) * 0.5) }
        let dog = t.events.first { $0.group == "Dog" }!
        #expect(abs(Circular.difference(dog.belief.peakBearing, 45)) < 5)
        #expect(dog.belief.concentration >= 0.5)
    }

    @Test func diffuseFramesDoNotUpdateBelief() {
        let t = EventTracker(urgencyMap: urgency)
        for i in 0..<6 { t.ingest(active: ["Dog": 1], doa: doa(90, diffuseness: 0.95), now: Double(i)) }
        #expect(t.events[0].belief.concentration < 1e-9)
    }

    @Test func unknownGroupDefaultsToLow() {
        let t = EventTracker(urgencyMap: urgency)
        t.ingest(active: ["Mystery": 0.9], doa: nil, now: 0)
        #expect(t.events[0].urgency == .low)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'AzimuthBelief' in scope` and `cannot find 'EventTracker' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/Fusion/AzimuthBelief.swift`:

```swift
import Foundation

/// Per-label world-frame direction belief over 72 × 5° bins (spec §3.4).
public struct AzimuthBelief: Sendable {
    public static let binCount = 72
    public static let binWidth = 360.0 / Double(binCount)

    public private(set) var probabilities: [Double]
    public var decay = 0.15
    public var epsilon = 0.05
    public var kappa = 6.0

    public init() {
        probabilities = Array(repeating: 1 / Double(Self.binCount), count: Self.binCount)
    }

    public static func binCenter(_ i: Int) -> Double { (Double(i) + 0.5) * binWidth }

    /// Blends toward uniform: p ← (1 − λ)·p + λ·uniform.
    public mutating func decayTowardUniform() {
        let u = 1 / Double(Self.binCount)
        probabilities = probabilities.map { (1 - decay) * $0 + decay * u }
    }

    /// Decays, then multiplies by ε + confidence·Σ wₖ·vonMises(θ − peakₖ, κ) and renormalizes.
    public mutating func update(peaks: [DOAPeak], confidence: Double) {
        decayTowardUniform()
        guard !peaks.isEmpty else { return }
        let c = min(1, max(0, confidence))
        for i in 0..<Self.binCount {
            let theta = Self.binCenter(i)
            let like = peaks.reduce(epsilon) { $0 + c * $1.weight * Circular.vonMises(theta - $1.bearing, kappa: kappa) }
            probabilities[i] *= like
        }
        let sum = probabilities.reduce(0, +)
        probabilities = probabilities.map { $0 / sum }
    }

    /// Mean resultant length R ∈ [0, 1]: 0 = no idea, 1 = certain.
    public var concentration: Double {
        var s = 0.0, c = 0.0
        for (i, p) in probabilities.enumerated() {
            s += p * sin(Self.binCenter(i) * .pi / 180)
            c += p * cos(Self.binCenter(i) * .pi / 180)
        }
        return (s * s + c * c).squareRoot()
    }

    /// Most likely bearing: the argmax bin refined by a circular mean over ±3 bins.
    public var peakBearing: Double {
        let n = Self.binCount
        let i = probabilities.indices.max { probabilities[$0] < probabilities[$1] }!
        let near = (-3...3).map { (i + $0 + n) % n }
        return Circular.mean(near.map(Self.binCenter), weights: near.map { probabilities[$0] }) ?? Self.binCenter(i)
    }
}
```

`EchoCore/Sources/EchoCore/Fusion/EventTracker.swift`:

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
}

/// Rolling set of active sound events with per-label direction beliefs (spec §3.4).
public final class EventTracker {
    public let urgencyMap: UrgencyMap
    public let evictAfter: Double
    public let emaAlpha: Double
    public let diffusenessCutoff: Double
    private var byGroup: [String: SoundEvent] = [:]

    public init(urgencyMap: UrgencyMap, evictAfter: Double = 3, emaAlpha: Double = 0.5, diffusenessCutoff: Double = 0.8) {
        self.urgencyMap = urgencyMap
        self.evictAfter = evictAfter
        self.emaAlpha = emaAlpha
        self.diffusenessCutoff = diffusenessCutoff
    }

    /// Events sorted by urgency (highest first), then confidence.
    public var events: [SoundEvent] {
        byGroup.values.sorted { ($0.urgency, $0.confidence) > ($1.urgency, $1.confidence) }
    }

    /// Feeds one joined window. `active` holds groups at or above threshold; `now` is seconds
    /// on the capture timeline. Returns events that were not being tracked before this window.
    @discardableResult
    public func ingest(active: [String: Double], doa: DOAFrame?, now: Double) -> [SoundEvent] {
        byGroup = byGroup.filter { now - $0.value.lastSeen <= evictAfter }
        let usable = doa.flatMap { $0.diffuseness <= diffusenessCutoff && !$0.peaks.isEmpty ? $0.peaks : nil }
        var created: [SoundEvent] = []
        for (group, score) in active {
            if var e = byGroup[group] {
                e.confidence = emaAlpha * score + (1 - emaAlpha) * e.confidence
                e.lastSeen = now
                byGroup[group] = e
            } else {
                let e = SoundEvent(group: group, urgency: urgencyMap.urgency(for: group), confidence: score,
                                   belief: AzimuthBelief(), firstSeen: now, lastSeen: now)
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 63 tests in 12 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add per-label azimuth belief and event tracker" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Alert rules (haptic gate, VoiceOver phrases)

**Files:**
- Create: `EchoCore/Sources/EchoCore/Alerts/HapticGate.swift`, `EchoCore/Sources/EchoCore/Alerts/DirectionPhrase.swift`
- Test: `EchoCore/Tests/EchoCoreTests/AlertTests.swift`

**Interfaces:**
- Consumes: `Urgency` (Task 8), `Circular`.
- Produces: `struct HapticGate { init(cooldown:); mutating func shouldFire(group:urgency:now:) -> Bool }`; `enum DirectionPhrase { static func clockHour(radarAngle:) -> Int; static func describe(radarAngle:) -> String }`.

Note: the spec's example phrase "behind you, to the left (4 o'clock)" mixes up sides. 4 o'clock is behind and to the **right**. This task uses the correct clock mapping (12 = front, 3 = right, 6 = behind, 9 = left).

- [ ] **Step 1: Write the failing tests**

`EchoCore/Tests/EchoCoreTests/AlertTests.swift`:

```swift
import Testing
@testable import EchoCore

struct AlertTests {
    @Test func hapticGateCooldownAndTiers() {
        var g = HapticGate(cooldown: 5)
        let fired = [
            g.shouldFire(group: "Speech", urgency: .low, now: 0),
            g.shouldFire(group: "Siren", urgency: .critical, now: 0),
            g.shouldFire(group: "Siren", urgency: .critical, now: 4.9),
            g.shouldFire(group: "Dog", urgency: .medium, now: 4.9),
            g.shouldFire(group: "Siren", urgency: .critical, now: 5),
        ]
        #expect(fired == [false, true, false, true, true])
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

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path EchoCore`
Expected: build FAILS with `cannot find 'HapticGate' in scope` and `cannot find 'DirectionPhrase' in scope`.

- [ ] **Step 3: Implement**

`EchoCore/Sources/EchoCore/Alerts/HapticGate.swift`:

```swift
/// Decides when an event may buzz: MEDIUM and above only, at most once per group per cooldown.
public struct HapticGate: Sendable {
    public let cooldown: Double
    private var lastFired: [String: Double] = [:]

    public init(cooldown: Double = 5) { self.cooldown = cooldown }

    public mutating func shouldFire(group: String, urgency: Urgency, now: Double) -> Bool {
        guard urgency >= .medium else { return false }
        if let last = lastFired[group], now - last < cooldown { return false }
        lastFired[group] = now
        return true
    }
}
```

`EchoCore/Sources/EchoCore/Alerts/DirectionPhrase.swift`:

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path EchoCore`
Expected: `Test run with 65 tests in 13 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add EchoCore
git commit -m "Add haptic gate and VoiceOver direction phrases" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Wire classification, direction, motion and haptics end to end

**Files:**
- Create: `EchoApp/Classification/SoundAnalysisClassifier.swift`, `EchoApp/Motion/MotionProvider.swift`, `EchoApp/Haptics/HapticsManager.swift`, `EchoApp/UI/UrgencyStyle.swift`, `EchoApp/UI/EventListView.swift`
- Modify (replace): `EchoApp/Capture/AudioPipeline.swift`, `EchoApp/App/AppModel.swift`, `EchoApp/UI/MainView.swift`

**Interfaces:**
- Consumes: everything in EchoCore; `FOAChunk`, `FOACaptureSession`, `ProbeState`, `StatusBanner`, `ProbeView` (Task 5).
- Produces (used by Task 14):
  - `struct EventDisplay: Identifiable, Equatable { group, urgency, confidence, worldBearing: Double?, concentration, belief: [Double]; static let minConcentration = 0.5 }`.
  - `AppModel.events: [EventDisplay]`, `AppModel.forwardBearing: Double`, `AppModel.isListening`, `AppModel.status`, `AppModel.classifierWarning`.
  - `extension Urgency { var color: Color; var label: String }`.
  - `EventListView(events:forward:)`.
  - `protocol SoundClassifier: AnyObject { var onFrame: ((ClassificationFrame) -> Void)?; var onError: ((Error) -> Void)?; func analyze(_ mono: [Float]) }`, implemented by `SoundAnalysisClassifier(sampleRate:mapper:)`.
- Pipeline contract: `WindowSummary` now also carries `doa: DOAFrame`; `TrackerOutput { events, newEvents, now }`. Haptics fire for every event refreshed in the current window, rate-limited by `HapticGate`. New CRITICAL events post a VoiceOver announcement.

- [ ] **Step 1: Write the app services**

`EchoApp/Classification/SoundAnalysisClassifier.swift`:

```swift
import AVFoundation
import EchoCore
import SoundAnalysis

/// A classifier fed mono audio that reports sound group scores per window (spec §3.2).
/// Lets another model (e.g. a TFLite YAMNet) be swapped in without touching the pipeline.
protocol SoundClassifier: AnyObject {
    var onFrame: ((ClassificationFrame) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Appends the next block of mono samples (continuous with the previous call).
    func analyze(_ mono: [Float])
}

/// Apple's built-in sound classifier over the omni (W) channel.
/// Not thread-safe: call `analyze` from one serial queue; results arrive synchronously on it.
final class SoundAnalysisClassifier: NSObject, SoundClassifier, SNResultsObserving, @unchecked Sendable {
    private let analyzer: SNAudioStreamAnalyzer
    private let format: AVAudioFormat
    private let mapper: LabelMapper
    private let sampleRate: Double
    private var framePosition: AVAudioFramePosition = 0

    var onFrame: ((ClassificationFrame) -> Void)?
    var onError: ((Error) -> Void)?

    init(sampleRate: Double, mapper: LabelMapper) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ResourceError.malformed("unsupported sample rate \(sampleRate)")
        }
        self.format = format
        self.sampleRate = sampleRate
        self.mapper = mapper
        analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(sampleRate))
        request.overlapFactor = 0.5
        super.init()
        try analyzer.add(request, withObserver: self)
    }

    func analyze(_ mono: [Float]) {
        guard !mono.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count)),
              let dest = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { dest.update(from: $0.baseAddress!, count: mono.count) }
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(mono.count)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var labels: [String: Double] = [:]
        for c in result.classifications { labels[c.identifier] = c.confidence }
        let start = Int64((result.timeRange.start.seconds * sampleRate).rounded())
        onFrame?(ClassificationFrame(windowStart: start, groupScores: mapper.groupScores(labels)))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) { onError?(error) }
}
```

`EchoApp/Motion/MotionProvider.swift`:

```swift
import CoreMotion
import EchoCore
import os
import simd

/// CoreMotion attitude → device-to-world rotation and the user's forward heading (spec §3.5).
@MainActor
final class MotionProvider {
    private static let conventionKey = "rotationConvention"
    private let manager = CMMotionManager()
    private var heading = ForwardHeading()
    private var convention: RotationConvention?
    private let latest = OSAllocatedUnfairLock(initialState: matrix_identity_float3x3)

    /// World bearing (degrees) the user is facing with the phone.
    private(set) var forwardBearing: Double = 0
    var onUpdate: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    init() {
        switch UserDefaults.standard.string(forKey: Self.conventionKey) {
        case "worldToDevice": convention = .worldToDevice
        case "deviceToWorld": convention = .deviceToWorld
        default: convention = nil
        }
    }

    /// Thread-safe snapshot for the audio pipeline.
    nonisolated func deviceToWorld() -> simd_float3x3 { latest.withLock { $0 } }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let r = motion.attitude.rotationMatrix
            let m = simd_float3x3(rows: [
                SIMD3(Float(r.m11), Float(r.m12), Float(r.m13)),
                SIMD3(Float(r.m21), Float(r.m22), Float(r.m23)),
                SIMD3(Float(r.m31), Float(r.m32), Float(r.m33)),
            ])
            let g = SIMD3(Float(motion.gravity.x), Float(motion.gravity.y), Float(motion.gravity.z))
            MainActor.assumeIsolated { self?.handle(m: m, gravity: g) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    private func handle(m: simd_float3x3, gravity: SIMD3<Float>) {
        if convention == nil, let resolved = RotationConvention.resolve(m: m, gravity: gravity) {
            convention = resolved
            UserDefaults.standard.set(resolved == .worldToDevice ? "worldToDevice" : "deviceToWorld", forKey: Self.conventionKey)
        }
        let d = (convention ?? .worldToDevice).deviceToWorld(m)
        latest.withLock { $0 = d }
        forwardBearing = heading.update(deviceToWorld: d)
        onUpdate?(forwardBearing)
    }
}
```

`EchoApp/Haptics/HapticsManager.swift`:

```swift
import CoreHaptics
import EchoCore

/// Urgency-tiered Core Haptics patterns with a per-group cooldown (spec §3.7).
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

    func alert(group: String, urgency: Urgency, now: Double) {
        guard gate.shouldFire(group: group, urgency: urgency, now: now), let engine else { return }
        let events = Self.events(for: urgency)
        guard !events.isEmpty, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    static func events(for urgency: Urgency) -> [CHHapticEvent] {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        return switch urgency {
        case .critical: [tap(0, 1, 1), tap(0.15, 1, 1), tap(0.30, 1, 1)]
        case .high: [tap(0, 0.8, 0.7), tap(0.25, 0.8, 0.7)]
        case .medium: [tap(0, 0.5, 0.5)]
        case .low: []
        }
    }
}
```

- [ ] **Step 2: Replace the pipeline and the model**

`EchoApp/Capture/AudioPipeline.swift` (replace):

```swift
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
```

`EchoApp/App/AppModel.swift` (replace):

```swift
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
```

- [ ] **Step 3: Add the event list**

`EchoApp/UI/UrgencyStyle.swift`:

```swift
import EchoCore
import SwiftUI

extension Urgency {
    /// Tier colors: CRITICAL red, HIGH orange, MEDIUM yellow, LOW blue.
    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        }
    }

    var label: String {
        switch self {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
```

`EchoApp/UI/EventListView.swift`:

```swift
import EchoCore
import SwiftUI

struct EventListView: View {
    let events: [EventDisplay]
    let forward: Double

    var body: some View {
        if events.isEmpty {
            Text("No sounds detected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            VStack(spacing: 8) {
                ForEach(events) { row($0) }
            }
        }
    }

    private func direction(_ e: EventDisplay) -> String {
        guard let world = e.worldBearing else { return "direction unknown" }
        return DirectionPhrase.describe(radarAngle: ForwardHeading.radarAngle(worldBearing: world, forward: forward))
    }

    private func row(_ e: EventDisplay) -> some View {
        HStack(spacing: 12) {
            Circle().fill(e.urgency.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.group).font(.headline)
                Text(direction(e)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(e.urgency.label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(e.urgency.color.opacity(0.25), in: Capsule())
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.group), \(e.urgency.label), \(direction(e))")
    }
}
```

`EchoApp/UI/MainView.swift` (replace):

```swift
import SwiftUI

/// Main screen with the live event list. Task 14 adds the radar.
struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(status: model.status, classifierWarning: model.classifierWarning)
                    EventListView(events: model.events, forward: model.forwardBearing)
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

- [ ] **Step 4: Build and run core tests**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet && swift test --package-path EchoCore`
Expected: no `error:` or concurrency warnings; `Test run with 65 tests in 13 suites passed`.

- [ ] **Step 5: Human check on the iPhone**

Ask the human to Run on the phone and **Start Listening**, then:
1. Play a siren clip from a speaker about 1.5 m away. Expected: a **Siren / Critical** row appears within about 1 s, with a triple haptic pulse. After a few seconds it shows a direction phrase instead of "direction unknown".
2. Play a knock and a dog bark. Expected: **Knock / Medium** and **Dog / Medium** rows with a single tap each.
3. Tilt the phone once (pick it up). This lets `MotionProvider` resolve and store the rotation convention.
4. Long-press the "SoundSight" title. Expected: the probe still opens and its dial still works.
Wait for the report before committing. If no rows ever appear, check the probe's Format line and ask whether `classifierWarning` showed a banner.

- [ ] **Step 6: Commit**

```bash
git add EchoApp
git commit -m "Wire SoundAnalysis, DOA, motion and haptics into the live pipeline" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 360° radar and final main screen

**Files:**
- Create: `EchoApp/UI/RadarView.swift`
- Modify (replace): `EchoApp/UI/MainView.swift`

**Interfaces:**
- Consumes: `EventDisplay`, `AppModel.forwardBearing` (Task 13); `radarPoint` (Task 5); `ForwardHeading.radarAngle`, `AzimuthBelief.binCenter/binWidth`, `DirectionPhrase` (EchoCore); `Urgency.color/label` (Task 13).
- Produces: `RadarView(events:forward:isListening:)`; the final `MainView`.

The radar redraws at display rate through `TimelineView(.animation)`. Every belief bin and arrow is drawn at `ForwardHeading.radarAngle(worldBearing:forward:)`, so turning the phone counter-rotates the picture and sources stay put in the world.

- [ ] **Step 1: Write the radar**

`EchoApp/UI/RadarView.swift`:

```swift
import EchoCore
import SwiftUI

/// 360° radar: belief halos, peak arrows and labels, counter-rotated by the forward heading (spec §3.6).
struct RadarView: View {
    let events: [EventDisplay]
    let forward: Double
    let isListening: Bool

    var body: some View {
        TimelineView(.animation(paused: !isListening)) { context in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 28
                drawGrid(&ctx, c, radius)
                if isListening {
                    let a = (context.date.timeIntervalSinceReferenceDate * 90).truncatingRemainder(dividingBy: 360)
                    var sweep = Path()
                    sweep.move(to: c)
                    sweep.addLine(to: radarPoint(c, radius, a))
                    ctx.stroke(sweep, with: .color(.accentColor.opacity(0.4)), lineWidth: 2)
                }
                for e in events.reversed() { drawEvent(&ctx, e, c, radius) }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
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

    private func drawEvent(_ ctx: inout GraphicsContext, _ e: EventDisplay, _ c: CGPoint, _ radius: CGFloat) {
        let color = e.urgency.color
        if let maxP = e.belief.max(), maxP > 0 {
            for (i, p) in e.belief.enumerated() where p > 0.2 * maxP {
                let a = ForwardHeading.radarAngle(worldBearing: AzimuthBelief.binCenter(i), forward: forward)
                var seg = Path()
                seg.move(to: radarPoint(c, radius * 0.92, a - AzimuthBelief.binWidth / 2))
                seg.addLine(to: radarPoint(c, radius * 0.92, a))
                seg.addLine(to: radarPoint(c, radius * 0.92, a + AzimuthBelief.binWidth / 2))
                ctx.stroke(seg, with: .color(color.opacity(e.concentration * p / maxP)), lineWidth: 10)
            }
        }
        guard let world = e.worldBearing else { return }
        let a = ForwardHeading.radarAngle(worldBearing: world, forward: forward)
        var arrow = Path()
        arrow.move(to: c)
        arrow.addLine(to: radarPoint(c, radius * 0.8, a))
        ctx.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.draw(Text(e.group).font(.caption.bold()).foregroundStyle(color), at: radarPoint(c, radius * 0.6, a))
    }

    private var accessibilitySummary: String {
        guard !events.isEmpty else { return isListening ? "Radar. No sounds detected." : "Radar. Not listening." }
        return "Radar. " + events.map { e in
            let where_ = e.worldBearing.map { DirectionPhrase.describe(radarAngle: ForwardHeading.radarAngle(worldBearing: $0, forward: forward)) } ?? "direction unknown"
            return "\(e.group), \(e.urgency.label), \(where_)"
        }.joined(separator: ". ")
    }
}
```

- [ ] **Step 2: Replace the main screen**

`EchoApp/UI/MainView.swift` (replace):

```swift
import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(status: model.status, classifierWarning: model.classifierWarning)
                    RadarView(events: model.events, forward: model.forwardBearing, isListening: model.isListening)
                        .aspectRatio(1, contentMode: .fit)
                    EventListView(events: model.events, forward: model.forwardBearing)
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

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
Expected: no `error:` or concurrency warnings.

- [ ] **Step 4: Human check: spec success criteria**

Ask the human to run these on the phone and report pass/fail for each:
1. **Criterion 1:** siren, knock and dog clips each get the right group and urgency within about 1 s.
2. **Criterion 2:** with the phone flat, play the siren from front, right, back and left. The arrow points within about ±30° of the true direction each time, without rotating the phone.
3. **Criterion 3:** keep the speaker fixed and slowly turn the phone 90°. The arrow stays pointing at the speaker (the radar counter-rotates).
4. **Criterion 4:** siren → triple pulse; glass or skidding (HIGH) → double pulse; dog → single tap; speech → none.
5. **Upright:** hold the phone upright (back camera forward), siren behind you → the arrow points to BACK.
6. **VoiceOver:** enable it (Settings → Accessibility) and swipe to an event row. It reads e.g. "Siren, Critical, behind you to the right (4 o'clock)".
If criterion 3 fails with the radar spinning the wrong way, ask the human to delete and reinstall the app (this clears the stored rotation convention), tilt the phone during the first seconds of listening, and retest.

- [ ] **Step 5: Commit**

```bash
git add EchoApp
git commit -m "Add world-anchored 360-degree radar to the main screen" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Final verification and hand-off

**Files:**
- Modify: `README.md` (add a "Using the app" section)

- [ ] **Step 1: Clean build and full test run**

Run:
```bash
rm -rf SoundSight.xcodeproj && xcodegen generate
xcodebuild -project SoundSight.xcodeproj -scheme SoundSight -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO clean build -quiet
swift test --package-path EchoCore
git status --short
```
Expected: build succeeds with no warnings; `Test run with 65 tests in 13 suites passed`; `git status` shows no untracked generated files (`SoundSight.xcodeproj/` and `EchoApp/Info.plist` are ignored).

- [ ] **Step 2: Add usage notes to the README**

Append to `README.md`:

```markdown
## Using the app

1. Tap **Start Listening** and allow microphone access.
2. Sounds appear as rows (newest most urgent first) and on the radar, colored by urgency: red critical, orange high, yellow medium, blue low.
3. An arrow appears once the app is confident about a sound's direction. FRONT is where the phone's top edge points (lying flat) or where its back camera points (held upright). Arrows stay fixed in the room as you turn.
4. Critical sounds give a triple vibration, high a double, medium a single tap.
5. Long-press the **SoundSight** title for the FOA probe (calibration and diagnostics).
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document app usage" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Finish the branch**

Use superpowers:finishing-a-development-branch to choose between a PR, a merge or keeping the branch. Then tell the human the next plan is spec step 7 (custom Create ML classifier).
