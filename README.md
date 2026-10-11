# SoundSight

Real-time, on-device sound awareness for deaf and hard-of-hearing users. SoundSight is an iOS app for the **iPhone 16 Pro Max**. It classifies environmental sounds, ranks their urgency, and shows where each one is coming from on a full 360° radar, using the phone's microphone array as First-Order Ambisonics (FOA).

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
| `EchoCore/` | Pure Swift logic: FOA intensity, direction finding, axis calibration and orientation correction, label mapping, YAMNet frontend, urgency score, event tracking, ambient level and new-sound markers |
| `EchoApp/` | iOS app: capture, SoundAnalysis and YAMNet classifiers, motion, haptics, notifications, SwiftUI, Settings, FOA probe |
| `EchoShared/` | Code shared by the app and the Live Activity (urgency colors, activity attributes) |
| `EchoLiveActivity/` | Widget extension: lock-screen bar and Dynamic Island |
| `docs/superpowers/` | Specs, spike and device-test results, implementation plans |

## Using SoundSight

Tap **Start Listening**. iOS asks for microphone, motion and notification access.

### The screen

- **Radar:** each sound appears in the direction it comes from, and the radar stays fixed to the room as you turn. **FRONT** is the phone's top edge.
- **Keep the phone flat (screen up)**, on a table or face-up in your hand like a compass:
  - Only the screen plane carries usable direction; the axis through the phone's thickness is biased.
  - Held upright, direction updates pause and a banner says so.
- **Arrows:**
  - A sudden sound shows a blue **"Classifying…"** arrow within about 0.1–0.2 s. The sound must last at least 0.2 s from one direction, or be a single impulse 20 dB over the room.
  - When the sound is recognized (typically about 0.9 s after it starts), the arrow turns into its name and urgency color.
  - If it isn't recognized while it lasts plus 1 s (at most 5 s), it reads **"Unclassified"** for 1 s and goes.
  - Named sounds update their direction 10 times a second, and their arrows hide 1 s after sound stops coming from there.
  - New sounds near a named arrow join it, and the radar draws one named arrow per spot.
- **Touching the phone:** taps, bumps and screen touches are detected with the motion sensors and ignored for a quarter-second.
- **Urgency gradient:** each sound gets a score from 0 to 1, combining its group, how loud it is, and a rough distance. The distance compares the heard level with the sound's typical level at 1 m (`EchoCore/Sources/EchoCore/Resources/source_levels.json`). Green means low, yellow moderate, red urgent. The card under the radar shows the most urgent sound with its volume, distance and direction.
- **Ambient ring:** a light-blue ring that grows thicker and stronger as the room gets louder. It is thicker on the side the background noise comes from. The `Ambient NN dB · Quiet/Moderate/Loud/Very loud` line sits under the radar. Above 80 dB a banner warns that sounds may be missed.
- **Volume figures are approximate:** the microphone is uncalibrated.

### Sound groups

| Urgency | Groups |
|---|---|
| Critical | Siren, Smoke Alarm, Gunshot/Explosion |
| High | Traffic Warning, Screaming/Shouting, Crash/Glass Breaking |
| Medium | Vehicle, Door, Phone Ringing, Baby/Crying, Dog, Beeping/Timer |
| Low | Speech |

- **Off by default:** Footsteps, Water Running, Power Tool and Cough/Sneeze. Turn them on in **Settings** (the gear icon).
- **When sounds appear:** Low and Medium sounds appear after two detections (0.25 s apart); Critical and High sounds appear on the first.
- **Only louder sounds:** a sound is only named if its loudest 0.1 s is at least 6 dB above the room's background (adjustable from 0 to 20 dB in Settings › Strictness) and at least 45 dB. Once named, it stays named while it continues, even after the background level catches up with a long siren.
- **Never shown:** typing, keys, music, appliances, animals other than dogs, and similar background sounds.
- **More detail:** `docs/superpowers/spikes/2026-10-10-regroup/`.

### Alerts

- **Haptics** (app open), set by score:

  | Score | Haptic |
  |---|---|
  | ≥ 0.75 | triple pulse |
  | ≥ 0.5 | double |
  | ≥ 0.3 | single |

- **Single gunshots:** a 0.15 s bang fills little of the classifier's 1 s window, so with the app open a loud impulse (≥ 20 dB over the room) plus a gunshot-type top label counts at a score of 0.5 instead of 0.84. This caught 18 of 20 test bangs. The locked-phone classifier (YAMNet) doesn't use this rule, because it confuses other loud impulses too often.
- **VoiceOver** announces urgent sounds with a clock direction, e.g. "behind you to the right (4 o'clock)".

### While locked

- **Listening continues:** once you tap Start Listening, SoundSight keeps listening when you lock the phone or switch apps, and the orange mic indicator stays on.
- **Classifier:** iOS stops Apple's sound classifier in the background, so YAMNet (run on the CPU) takes over. It is less accurate.
- **Lock-screen bar:** a Live Activity shows the most urgent sound with a direction arrow, on the lock screen and in the Dynamic Island. Turn it off in Settings › SoundSight › Live Activities.
- **Urgent notification:** an urgent sound posts one notification, at most one every 10 s. It needs two detections first, and each new one replaces the last instead of stacking.

### Demo mode

Clips played from a laptop or phone are much quieter than real sirens, so they look far away and less urgent. **Settings › Demo mode** assumes speaker playback: play clips near full volume and a nearby siren shows red. Turn it off for real-world use.

### FOA probe (debug)

Long-press the **SoundSight** title to open the probe. It provides:
- the live 4-channel format and levels;
- a raw direction dial;
- calibration recording and fitting;
- a classifier switch (force YAMNet);
- a per-window session log (Share log);
- recent detections, marked `(background)` when detected while locked.

Diagnostics are also written to `Documents/diagnostics.log` in the app container. Copy it to the Mac with:

```sh
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.hackatl.soundsight --source Documents/diagnostics.log --destination diagnostics.log
```

### Device findings worth knowing

- **iOS rotates FOA capture to the phone's upright orientation.** It only tracks changes made after capture starts, and defaults to the camera sensor's landscape. The app corrects for this (`FOAOrientationCompensation`).
- **Taking control of the `AVAudioSession` disables FOA**, so the capture session configures the audio session itself.
- **Apple's sound feature extractor fails in the background.** This affects both SoundAnalysis and Create ML sound classifiers, hence the YAMNet fallback.

