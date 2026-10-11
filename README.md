# SoundSightAI

Real-time, on-device sound awareness for deaf and hard-of-hearing users. SoundSightAI is an iOS app for the **iPhone 16 Pro Max**. It classifies environmental sounds, ranks their urgency, and shows where each one is coming from on a full 360° radar, using the phone's microphone array as First-Order Ambisonics (FOA).

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
