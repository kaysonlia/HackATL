# SoundSight iOS: urgency gradient, background listening and lock-screen bar

**Date:** 2026-10-10
**Builds on:** `2026-10-10-soundsight-ios-foa-design.md` (the base spec) and its plan (Tasks 1–15).
**Status:** approved in conversation, pending written review.

## 1. Goal

Make the app useful when the phone is not in your hand:

- One continuous **urgency score** per sound, built from classification, loudness and approximate distance. It is shown as a green → yellow → red gradient.
- A cleaner main screen. Under the radar, the most urgent sound's **class, volume and distance** are shown as text.
- **Always-on listening** in the background, with a **Live Activity** on the lock screen and in the Dynamic Island, like Spotify's now-playing bar.
- One **notification** for urgent sounds, which **never stacks**.

What the user asked for:

- Urgency combines loudness, approximate distance and classification.
- Red means very dangerous and loud or close. Yellow means medium, like a car alarm some way off. Green means indistinct chatter.
- Class and volume appear as text below the compass.
- Haptics follow the score.
- Listening stays on in the background, with a pop-up on the lock screen.
- Urgent sounds also send a notification, and notifications don't stack.
- The colored area is tighter.
- The radar sweep only plays for a few seconds after Start Listening, then fades away.

What I assumed:

- The constants below (dB offset, source levels, score weights) are starting values for the deferred tuning pass.
- In the foreground, the app's own haptics and screen do the alerting, so no notification is sent there.

## 2. Urgency score (EchoCore, pure and tested)

### 2.1 Loudness

- Each 1 s analysis window already computes the omni (W) RMS.
- Level in dB is: L = 20·log10(RMS) + **120** (dB offset). 120 is a rough guess at the dB SPL of digital full scale on the iPhone mic.
- RMS = 0 maps to 0 dB.
- Each event keeps an EMA of L (α 0.5) over the windows where it is active.
- This is shown as "84 dB". It is approximate, because the mic is not calibrated.

### 2.2 Approximate distance

- Each of the 42 groups has a typical level at 1 m, L_ref (§2.5). The distance estimate is d = 10^((L_ref − L)/20) m, clamped to [0.5, 100].
- This is shown as "~3 m", rounded to 1 significant figure. Below 1 m it shows "< 1 m".
- It assumes the source is as loud as is typical for its kind, so it is often off by up to 2×. That is fine for a demo.

### 2.3 Score

| Factor | Formula | Meaning |
|---|---|---|
| Class weight c | CRITICAL 1.0, HIGH 0.75, MEDIUM 0.5, LOW 0.15 | from `urgency_map.json` |
| Closeness p | clamp(1 − log10(d/2)/log10(25), 0, 1) | 1 at ≤ 2 m, 0 at ≥ 50 m |
| Loudness ℓ | clamp((L − 40)/50, 0, 1) | 0 at ≤ 40 dB, 1 at ≥ 90 dB |
| **Score u** | **c · (0.35 + 0.65 · (0.6·p + 0.4·ℓ))** | in [0, 1] |

Reference cases (unit tests):

| Case | L_ref | L | u | Color |
|---|---|---|---|---|
| Siren at 2 m | 120 | 114 | 1.00 | red |
| Siren at 10 m | 120 | 100 | ≈ 0.81 | red-orange |
| Car alarm at 100 m | 110 | 70 | ≈ 0.51 | yellow |
| Dog at 3 m | 90 | 80 | ≈ 0.45 | yellow-green |
| Speech, any distance | 60 | — | ≤ 0.15 | green |

### 2.4 Gradient and bands

- **Color:** hue = 120° · (1 − u), with saturation 0.9 and brightness 0.95. So u = 0 is green, 0.5 is yellow and 1 is red. Every event visual uses it: halo, arrow, list dot, readout card and Live Activity.
- **Band words** keep the meaning available without color:

  | Band | Score |
  |---|---|
  | **Urgent** | u ≥ 0.75 |
  | **Moderate** | 0.4 ≤ u < 0.75 |
  | **Low** | u < 0.4 |

  The band word appears in text and in VoiceOver labels.
- The **Urgent** threshold (0.75) also drives notifications, the VoiceOver announcement and the triple haptic.

### 2.5 Typical level at 1 m (`source_levels.json`, dB SPL)

| Tier | Group: L_ref |
|---|---|
| CRITICAL | Siren 120, Smoke/Fire Alarm 95, Vehicle Horn 110, Car Alarm 110, Gunshot/Explosion 140 |
| HIGH | Screaming 100, Glass Shatter 100, Skidding/Tire Squeal 100, Reversing Beeps 97, Slam/Bang/Crash 100, Shouting/Yelling 88, Motorcycle 95 |
| MEDIUM | Doorbell 80, Phone Ring 75, Alarm/Buzzer/Beep 85, Knock 75, Baby Cry 90, Crying 75, Dog 90, Vehicle 85, Aircraft 130, Train 110, Power Tool 100 |
| LOW | Speech 60, Footsteps 60, Door 75, Water 65, Crowd/Applause/Laughter 75, Music 75, Appliance/Kitchen 70, Body Sounds 50, Cough/Sneeze 70, Fart 55, Whistle 90, Insect Buzz 45, Typing/Keyboard 55, Keys Jangling 60, Camera Shutter 55, TV/Radio 65, Ambient Nature 55, Silence 0, Other 70 |

- A test checks that every group in `urgency_map.json` has a level.
- The **Silence** group never becomes an event. The pipeline drops it before the tracker, so a quiet room shows "No sounds detected", not a "Silence" row.

## 3. Main screen

```
┌────────────────────────────────┐
│ status banner                  │
│            FRONT               │
│     ╭─────────────────╮        │
│ LEFT│   ↗ Siren        │RIGHT  │  radar: tight halo + arrow in gradient color
│     ╰─────────────────╯        │
│            BACK                │
│ ┌────────────────────────────┐ │
│ │ ● SIREN            Urgent  │ │  focus card: the most urgent event
│ │ 84 dB · ~3 m away          │ │
│ │ behind you to the right (4 o'clock)│
│ │ ▕green━━━━yellow━━━━━●red▏ │ │  gradient bar, marker at u
│ └────────────────────────────┘ │
│  ● Dog     62 dB · ~8 m · left │  remaining events, sorted by u
│  ● Speech  55 dB · ~2 m · front│
│ [ Start / Stop Listening ]     │
└────────────────────────────────┘
```

- **Sorting:** by u, descending. The focus card shows the first event. With no events, it reads "Listening…" or "Not listening".
- **Tighter halo:** only bins within **±15° of the belief peak** with **p ≥ 50% of the peak bin** are drawn, at opacity concentration · p/max. Previously it was every bin above 20% of max.
- **Radar sweep:** shown only for the **first 3 s** after Start Listening. It is fully opaque until 2 s and fades linearly to 0 by 3 s. After that the animation timeline pauses, and the radar redraws only when the model changes.
- **Tier pills** are replaced by the band word. The tier still feeds the score.
- **Haptics** happen in the foreground only, per group with a 5 s cooldown:

  | Score | Haptic |
  |---|---|
  | u ≥ 0.75 | triple pulse |
  | u ≥ 0.5 | double pulse |
  | u ≥ 0.3 | single tap |
  | below 0.3 | none |

  This replaces the tier-based rule in the base spec §3.7.
- **VoiceOver:** "Siren, critical" becomes "Siren, urgent, behind you to the right (4 o'clock)". It is announced once when an event first reaches u ≥ 0.75.

## 4. Background listening

- **Info.plist:** add `UIBackgroundModes: [audio]`.
- **Audio session:** activated as `.playAndRecord` with `.mixWithOthers` and `.defaultToSpeaker` before the capture session starts, so other apps' audio keeps playing.
- **Why this should work:** the AVFoundation headers prohibit only the *camera* in the background, so audio-only `AVCaptureSession` capture should continue once started in the foreground.
- **Verified first (gate):** the first implementation task builds just this and checks it on the device:
  1. Start listening, lock the phone for 60 s, and play a siren.
  2. Afterwards the in-app event history must show it.
  3. Check that the FOA format line is unchanged.
- **If FOA stops in the background:**
  - Classification continues from a mono `AVAudioEngine` tap while backgrounded.
  - The direction is shown as the last known one, marked stale.
  - The plan records which case happened.
- **Motion and haptics:** CoreMotion keeps updating while the app runs. Core Haptics doesn't play in the background; the notification provides vibration.
- **Status:** the iOS orange mic indicator is always visible while listening. That is expected and not something we hide.

## 5. Live Activity (lock screen + Dynamic Island)

- **Target:** new widget extension `EchoLiveActivity`, generated by XcodeGen and embedded in the app. `NSSupportsLiveActivities = YES`.
- **Signing:** local updates need no push or App Groups, so a free Personal Team can sign it.
- **Shared code:** `EchoShared/EchoActivityAttributes.swift` is compiled into both targets. It is kept out of EchoCore, which must also build on macOS for tests.
- `ContentState`:

  | Field | Meaning |
  |---|---|
  | `group: String?` | nil means "Listening…" |
  | `score` | |
  | `levelDB` | |
  | `distanceM` | |
  | `radarAngle: Double?` | relative to the phone's forward direction; nil when the direction is unknown |
  | `band` | |

- **Layout:**

  | Place | Shows |
  |---|---|
  | Lock screen | the banner from the design: dot, class, arrow, "84 dB · ~3 m", gradient bar |
  | Dynamic Island, compact | gradient dot (leading), arrow (trailing) |
  | Dynamic Island, minimal | dot |
  | Dynamic Island, expanded | the lock-screen layout |

- **Lifecycle:**
  - Requested on Start Listening and ended (immediate dismissal) on Stop.
  - If the system ends it (8 h limit) while still listening, a new one is requested.
  - If Live Activities are disabled in Settings, listening works anyway and the status banner says so.
- **Update throttle** (pure function in EchoCore, tested). An update is sent when:
  - the focus event's group changes, or it appears or disappears; or
  - |Δu| ≥ 0.05; or
  - |Δangle| ≥ 15°; or
  - |ΔdB| ≥ 3.

  Updates are always at least **1 s** apart, and each sets `staleDate` = now + 10 s.
- **No alert configuration:** the Live Activity never uses `alertConfiguration`. The notification (§6) handles alerting, so one urgent sound produces one buzz.

## 6. Urgent notification (never stacks)

- **When:** a local `UNNotificationRequest` is sent when an event reaches **u ≥ 0.75** and the app is **not in the foreground**.
- **Content:**
  - Title "Siren: behind you to the right"
  - Body "84 dB · ~3 m away"
  - Default sound (vibration)
  - Interruption level `.active`. `.timeSensitive` needs an entitlement a free team can't get.
- **No stacking:** every request uses the same identifier, **`echo.urgent`**. A new one replaces the delivered one, so at most one SoundSight notification is ever on the lock screen or in Notification Center.
- **Rate limit** (pure `NotificationPolicy` in EchoCore, tested):
  - At most one notification per **10 s** overall.
  - The same group again only after **30 s**, unless its score rises by ≥ 0.15 since the last one for it.
  - Suppressed ones are dropped; the Live Activity still shows the latest.
- **Cleanup:** stopping listening removes the delivered `echo.urgent` notification.
- **Permission:** requested on the first Start Listening. If it's denied, the status banner says urgent sounds will only show on the lock-screen bar.

## 7. Error handling

| Condition | Behavior |
|---|---|
| Background capture interrupted (call, Siri, another recording app) | Existing interruption handling; Live Activity shows "Paused"; resumes on interruption end |
| Live Activities disabled / request throws | Keep listening; banner: "Lock-screen bar is off in Settings" |
| Notifications denied | Keep listening; banner note as §6 |
| Event with unknown direction | Card and Live Activity say "direction unknown"; arrow hidden |
| Level RMS = 0 | L = 0 dB, d clamps to 100 m, ℓ = 0 |

## 8. Testing

**Unit-tested in EchoCore (Swift Testing, TDD):**
- `UrgencyScore`: the formula, the reference cases in §2.3, clamps, band edges and gradient hue at 0, 0.5 and 1.
- `SourceLevels`: covers all groups.
- Level EMA in `EventTracker`, and Silence is dropped.
- `HapticGate`: by score.
- `RadarSweep.opacity(elapsed:)`: 1 at 0–2 s, linear to 0 at 3 s, 0 after.
- Halo bin selection: ±15° and ≥ 50% of the peak.
- `LiveActivityThrottle`.
- `NotificationPolicy`: global gap, per-group cooldown, score-rise override, foreground suppression.

**Human checks on the device:**
1. **Background gate (§4):** listening survives a lock.
2. **Gradient:** close siren → red card, car-alarm clip played quietly far off → yellow, chatter → green.
3. **Sweep:** shows for about 3 s, then fades.
4. **Lock-screen bar:** appears, updates and shows the arrow.
5. **Notifications:** three urgent sounds in a row with the phone locked leave **one** notification.
6. **Stop:** ends the bar and clears the notification.

## 9. Out of scope

- Calibrating the dB offset or source levels (that is the deferred tuning pass).
- Push-driven Live Activity updates.
- Time-sensitive notifications.
- The custom Create ML classifier (base spec step 7).
- A history screen.
