# Background listening gate: 2026-10-10

**Question:** Does SoundSight keep detecting sounds while the iPhone is locked? This is plan `2026-10-10-soundsight-ios-urgency-background.md`, Task 1.

**Device:** iPhone 16 Pro Max, iOS 26.6.2, free Personal Team build. The background audio mode is enabled (`UIBackgroundModes: audio`).

## What happened, in order

| # | Build | Result | Evidence |
|---|---|---|---|
| 1 | App owns `AVAudioSession` (`.playAndRecord`, `.mixWithOthers`) | **Direction finding died**: no DOA peaks and diffuseness 1.0 in every window. The session config disabled FOA capture. | 3 session logs, 123/123 windows |
| 2 | Automatic audio session restored | DOA back (40/40 windows with peaks). A siren while locked produced **no detection**, and the app showed "Sound classifier error". | probe |
| 3 | Diagnostics | `com.apple.SoundAnalysis 2` (operation failed) in the background; the capture kept running (108 audio windows while away, 0 classifications). | probe |
| 4 | Create ML sound classifier (ESC-50) through `SNClassifySoundRequest(mlModel:)`, CPU only | Still SNError 2. | probe |
| 5 | Same model run directly through Core ML, CPU only | `Failed to evaluate model 0 in pipeline ← model 1` 39 times. Model 0 is Apple's `audioFeaturePrint` stage, the same feature extractor SoundAnalysis uses. 3 of 63 windows classified. | `text-…` share |
| 6 | **YAMNet on CPU** (converted Core ML network + Swift log-mel frontend), used only while not in the foreground | **PASS.** 97/98 and 165/165 windows classified while locked, no errors; Siren detected in the background. | `diagnostics-yamnet.log` |

## Root cause

- Apple's sound feature extractor (`audioFeaturePrint`) can't run while the app is in the background. Both SoundAnalysis's built-in classifier and Create ML sound classifiers are built on it.
- `SNClassifySoundRequest` exposes no compute-unit control.
- Audio capture itself survives the lock.

## Result: PASS, with a hybrid classifier

| When | Classifier | Accuracy (ESC-50 spike) |
|---|---|---|
| App in the foreground | Apple SoundAnalysis | ~78% |
| Locked / background | YAMNet on the CPU | ~62% |

**Known gaps (tuning):**
- **Weak siren recall:** YAMNet caught the siren only intermittently while locked.
- **False alarms:** it produced some false urgent events (Glass Shatter, Gunshot/Explosion). Background notifications need a confirmation rule before they ship.
- **Shared audio:** the automatic audio session probably pauses other apps' audio while listening.
